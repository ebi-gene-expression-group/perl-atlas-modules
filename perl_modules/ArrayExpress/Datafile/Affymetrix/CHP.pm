#!/usr/bin/env perl
#
# Module to parse Affymetrix binary data files.
#
# Tim Rayner 2004, ArrayExpress team, European Bioinformatics Institute
#
# $Id: CHP.pm 2025 2008-04-15 23:10:14Z tfrayner $
#

=pod

=begin html

    <div><a name="top"></a>
      <table class="layout">
	  <tr>
	    <td class="whitetitle" width="100">
              <a href="../../../../index.html">
                <img src="../../../T2M_logo.png"
                     border="0" height="50" alt="Tab2MAGE logo"></td>
              </a>
	    <td class="pagetitle">Module detail: CHP.pm</td>
	  </tr>
      </table>
    </div>

=end html

=head1 NAME

ArrayExpress::Datafile::Affymetrix::CHP - GDAC CHP data file
parsing.

=head1 SYNOPSIS

 use base qw( ArrayExpress::Datafile::Affymetrix::CHP );

=head1 DESCRIPTION

Abstract superclass for parsing and export of data from Affymetrix CHP
files. 

Please see the L<ArrayExpress::Datafile::Affymetrix::Parser>
documentation for methods common to all the Affymetrix file classes.

=head1 METHODS

=over 2

=item C<parse_header()>

This method will take the C<input> attribute and parse only the header
metadata.

=item C<export($fh, $cdf)>

This method takes a filehandle and prints the parsed expression data
out to it. The method also requires a pre-parsed CDF object to be
passed to it. The QuantitationTypeDimension and DesignElementDimension
of the resulting matrix are given by the C<get_qtd> and C<get_ded>
methods, respectively.

=item C<get_ded($cdf, $chip_type)>

This method takes a pre-parsed CDF object, and an optional string
argument representing the chip type (e.g., "HG-U133A"). The method
uses these arguments to generate a reference to an array of
CompositeSequence identifiers, arranged in the order that the
B<export> method outputs them (i.e., a DesignElementDimension). The
chip type can be derived in a number of ways; if EXP files are
available, for instance, the $exp->get_chip_type() method should
return an appropriate string. If this argument is not supplied then
the chip_type() methods for the CHP and CDF objects are inspected.

=pod

=back

=head1 AUTHOR

Tim Rayner (rayner@ebi.ac.uk), ArrayExpress team, EBI, 2005.

Acknowledgements go to the ArrayExpress curation team for feature
requests, bug reports and other valuable comments.

=begin html

<hr>
<a href="http://sourceforge.net">
  <img src="http://sourceforge.net/sflogo.php?group_id=120325&amp;type=2" 
       width="125" 
       height="37" 
       border="0" 
       alt="SourceForge.net Logo" />
</a>

=end html

=cut

package ArrayExpress::Datafile::Affymetrix::CHP;
use base 'ArrayExpress::Datafile::Affymetrix::Parser';

use strict;
use warnings;

use Readonly;
use Carp;
use Scalar::Util qw( openhandle );
use IO::File;
use Class::Std;

use ArrayExpress::Datafile::Binary qw(
    get_integer
);

my %affy_qtd_chp               : ATTR( :get<affy_qtd_chp> );
my %affy_qtd_chp_comparison    : ATTR( :get<affy_qtd_chp_comparison> );
my %affy_qtd_chp_snp           : ATTR( :get<affy_qtd_chp_snp> );
my %affy_qtd_chp_snp100        : ATTR( :get<affy_qtd_chp_snp100> );

sub BUILD {

    my ( $self, $id, $args ) = @_;

    # Standard CHP QTDs.
    $affy_qtd_chp{ident $self} = [
	qw(
	   ProbeSetName
	   CHPPairs
	   CHPPairsUsed
	   CHPSignal
	   CHPDetection
	   CHPDetectionPvalue
       )
    ];

    $affy_qtd_chp_comparison{ident $self} = [
	qw(
	   ProbeSetName
	   CHPPairs
	   CHPPairsUsed
	   CHPSignal
	   CHPDetection
	   CHPDetectionPvalue
	   CHPCommonPairs
	   CHPSignalLogRatio
	   CHPSignalLogRatioLow
	   CHPSignalLogRatioHigh
	   CHPChange
	   CHPChangePvalue
       )
    ];

    $affy_qtd_chp_snp{ident $self} = [
	qw(
	   ProbeSetName
	   CHPAllele
	   CHPAllelePvalue
	   CHPAlleleRAS1
	   CHPAlleleRAS2
       )
    ];

    $affy_qtd_chp_snp100{ident $self} = [
	qw(
	   ProbeSetName
	   CHPAllele
	   CHPAllelePvalue
	   CHPAllelePvalueAA
	   CHPAllelePvalueAB
	   CHPAllelePvalueBB
	   CHPAllelePvalueNoCall
       )
    ];

    return;
}

sub START {

    my ( $self, $id, $args ) = @_;

    $self->set_required_magic(1701733703);

    return;
}

sub parse {

    my ( $self ) = @_;

    my $fh = $self->parse_header();

    $self->parse_chp($fh);

    return;
}

sub parse_header {

    my ( $self ) = @_;

    my $fh = $self->get_filehandle();

    binmode($fh);
    sysseek( $fh, 0, 0 )
        or croak(
        qq{Error rewinding filehandle for "magic" integer check : $!\n});

    $self->set_magic( get_integer($fh) );

    unless ($self->get_magic() == $self->get_required_magic()) {
	croak("Error: Incorrect parser class used for CHP type ("
		  . $self->get_magic() . ")");
    }

    $self->parse_chp_header($fh);

    return $fh;    # Filehandle now set for reading main data body.
}

sub export {    # CONFIRMED BY DIFF

    my ( $self, $fh, $cdf ) = @_;

    openhandle($fh) or confess( 'Bad parameters passed to method' );
    $cdf->isa('ArrayExpress::Datafile::Affymetrix::Parser')
        or confess( 'Bad parameters passed to method' );

    # Basic sanity check here. If the parse hasn't been run yet, do so.
    unless ( scalar @{ $cdf->get_probeset_ids() } ) {
	$cdf->parse();
    }

    my $data      = $self->get_data();
    my $probesets = $cdf->get_probeset_ids();
    my @qtd       = @{ $self->get_headings() };

    my @detection = ( q{Present}, q{Marginal}, q{Absent}, q{No Call}, );
    my @change = (
        q{null},
        q{Increase},
        q{Decrease},
        q{Marginal Increase},
        q{Marginal Decrease},
        q{No change},
        q{No call},
    );
    my @allele = (
        q{NoCall}, q{NoCall}, q{NoCall}, q{NoCall}, q{NoCall}, q{NoCall},
        q{AA},     q{BB},     q{AB},     q{AB_A},   q{AB_B},   q{NoCall},
    );

    for ( my $i = 0; $i <= $#{$data}; $i++ ) {

        my @line_array;

        carp(     "WARNING: No CDF data for CHP unit "
                . ( $i + 1 )
                . ". Incorrect CDF file used?\n" )
            unless $probesets->[$i];
        push( @line_array, ( $probesets->[$i] || q{} ) );  # ProbeSetName

        # Skip the first item (ProbeSetName).
        foreach my $qt ( @qtd[ 1 .. $#qtd ] ) {

            my $value = $data->[$i]{$qt};

            QTYPE:
            {    # some reformatting required

                ( $qt eq 'CHPDetection' )
                    && do { $value = $detection[$value] || q{null}; last QTYPE; };

                ( $qt eq 'CHPSignal' )
                    && do { $value = sprintf( "%.1f", $value ); last QTYPE; };

                ( $qt eq 'CHPDetectionPvalue' )
                    && do { $value = sprintf( "%.5f", $value ); last QTYPE; };

                ( $qt eq 'CHPSignalLogRatio' )
                    && do { $value = sprintf( "%.1f", $value ); last QTYPE; };

                ( $qt eq 'CHPSignalLogRatioLow' )
                    && do { $value = sprintf( "%.1f", $value ); last QTYPE; };

                ( $qt eq 'CHPSignalLogRatioHigh' )
                    && do { $value = sprintf( "%.1f", $value ); last QTYPE; };

                ( $qt eq 'CHPChange' )
                    && do { $value = $change[$value] || q{null}; last QTYPE; };

                ( $qt eq 'CHPChangePvalue' )
                    && do { $value = sprintf( "%.5f", $value ); last QTYPE; };

                ( $qt eq 'CHPAllele' )
                    && do { $value = $allele[$value] || q{null}; last QTYPE; };

                ( $qt eq 'CHPAllelePvalue' )
                    && do { $value = sprintf( "%.6f", $value ); last QTYPE; };

                ( $qt eq 'CHPAlleleRAS1' )
                    && do { $value = sprintf( "%.4f", $value ); last QTYPE; };

                ( $qt eq 'CHPAlleleRAS2' )
                    && do { $value = sprintf( "%.4f", $value ); last QTYPE; };

                ( $qt eq 'CHPAllelePvalueAA' )
                    && do { $value = sprintf( "%.6f", $value ); last QTYPE; };

                ( $qt eq 'CHPAllelePvalueAB' )
                    && do { $value = sprintf( "%.6f", $value ); last QTYPE; };

                ( $qt eq 'CHPAllelePvalueBB' )
                    && do { $value = sprintf( "%.6f", $value ); last QTYPE; };

                ( $qt eq 'CHPAllelePvalueNoCall' )
                    && do { $value = sprintf( "%.6f", $value ); last QTYPE; };

            }

            # Safety net
            unless ( defined($value) ) { $value = q{} }

            push( @line_array, $value );

        }

        print $fh ( join( "\t", @line_array ), "\n" );

    }

    return;
}

sub get_ded {

    my ( $self, $cdf, $chip_type ) = @_;

    $cdf->isa('ArrayExpress::Datafile::Affymetrix::CDF')
        or confess( 'Bad parameters passed to method' );
    ref $chip_type and confess( 'Bad parameters passed to method' );

    # If no chip type passed, try and figure it out on our own
    $chip_type ||= $self->get_chip_type() || $cdf->get_chip_type();

    # Basic sanity check here.
    croak("Error: No chip type information available to CHP->get_ded()\n")
        unless $chip_type;

    # If the parse hasn't been run yet, do so.
    unless ( scalar @{ $cdf->get_probeset_ids() } ) {
	$cdf->parse();
    }

    my $data      = $self->get_data();
    my $probesets = $cdf->get_probeset_ids();

    my @composite_sequences;

    for ( my $i = 0; $i <= $#{$data}; $i++ ) {
        carp(     "WARNING: No CDF data for CHP unit "
                . ( $i + 1 )
                . ". Incorrect CDF file used?\n" )
            unless $probesets->[$i];
        push( @composite_sequences,
            "Affymetrix:CompositeSequence:$chip_type:"
                . ( $probesets->[$i] || q{} ) );
    }

    return \@composite_sequences;
}

1;
