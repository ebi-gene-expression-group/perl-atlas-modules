#!/usr/bin/env perl
#
# Module to parse Affymetrix binary data files.
#
# Tim Rayner 2004, ArrayExpress team, European Bioinformatics Institute
#
# $Id: XDA_CHP.pm 1906 2008-01-23 10:05:42Z tfrayner $
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
	    <td class="pagetitle">Module detail: XDA_CHP.pm</td>
	  </tr>
      </table>
    </div>

=end html

=head1 NAME

ArrayExpress::Datafile::Affymetrix::CHP::XDA_CHP - XDA CHP data file
parsing.

=head1 SYNOPSIS

 use ArrayExpress::Datafile::Affymetrix::CHP::XDA_CHP;

 my $chp = ArrayExpress::Datafile::Affymetrix::CHP::XDA_CHP->new({
     input => 'mydata.CHP',
 });

 $chp->parse();

=head1 DESCRIPTION

This module implements parsing and export of data from Affymetrix XDA
CHP files.

Please see the L<ArrayExpress::Datafile::Affymetrix::Parser>
documentation for methods common to all the Affymetrix file classes.

=head1 METHODS

Most methods are implemented in the superclass. Please see
L<ArrayExpress::Datafile::Affymetrix::CHP::GDAC_CHP> for details.

=over 2

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

package ArrayExpress::Datafile::Affymetrix::CHP::XDA_CHP;
use base 'ArrayExpress::Datafile::Affymetrix::CHP';

use strict;
use warnings;
use Readonly;
use Carp;
use Scalar::Util qw( openhandle );
use IO::File;
use Class::Std;

use EBI::FGPT::Common qw(
    round
);

use ArrayExpress::Datafile::Binary qw(
    get_integer
    get_DWORD
    get_unsigned_short
    get_unsigned_char
    get_signed_char
    get_float
    get_ascii
    get_hexadecimal
);

my %results_type : ATTR( :name<results_type>, :default<undef> );

# The number of cells above which a genotyping chip is considered a
# "100k" chip, rather than a "10k" chip. Currently the former start at
# around 50k.
Readonly my $LARGE_CHIP_THRESHOLD => 25000;

sub START {

    my ( $self, $id, $args ) = @_;

    $self->set_required_magic(65);

    return;
}

############################
# XDA_CHP specific methods #
############################

# This sub parses CHP files. This has now been tested and found to work.

sub parse_chp_header : RESTRICTED {

    my ( $self, $fh ) = @_;

    openhandle($fh) or confess( 'Bad parameters passed to method' );

    # Binary-mode filehandle, rewind the file.
    binmode( $fh, ":raw" );
    sysseek( $fh, 0, 0 )
        or croak("Error rewinding filehandle for input: $!\n");

    my $magic = get_integer($fh);
    unless ( $magic == 65 ) {
        croak("Error: Unrecognized CHP type: $magic\n");
    }

    # Set the stardard qtd for ExpressionStat data.
    $self->set_headings( $self->get_affy_qtd_chp() );

    $self->set_version( get_integer($fh) );
    $self->set_num_columns( get_unsigned_short($fh) );
    $self->set_num_rows( get_unsigned_short($fh) );
    $self->set_num_cells( get_integer($fh) );    # Non-QC cells only
    my $num_qc_cells = get_integer($fh);
    my $results_type = get_integer($fh);

    $self->set_results_type( $results_type );

    # Fix QTD for Genotyping (SNP) data
    if ( $results_type == 1 ) {
	if ( $self->get_num_cells < $LARGE_CHIP_THRESHOLD ) {

	    # 10k chip.
	    $self->set_headings( $self->get_affy_qtd_chp_snp() );
	}
	else {

	    # 100k chip
	    $self->set_headings( $self->get_affy_qtd_chp_snp100() );
	}
    }

    my $programmatic_id = get_ascii( $fh, get_integer($fh) );
    my $cel_filename    = get_ascii( $fh, get_integer($fh) );
    $self->set_chip_type( get_ascii( $fh, get_integer($fh) ) );
    $self->set_algorithm( get_ascii( $fh, get_integer($fh) ) );
    my $algorithm_version = get_ascii( $fh, get_integer($fh) );

    # Parameters
    my $num_params = get_integer($fh);
    my $parameter_hash;
    for ( 1 .. $num_params ) {

        # Listed in the file as name, value
        my $name  = get_ascii( $fh, get_integer($fh) );
        my $value = get_ascii( $fh, get_integer($fh) );

        # Remove stray whitespace from value
        $value =~ s{\A \s* (.*?) \s* \z}{$1}xms;

        $parameter_hash->{$name} = $value;
    }
    $self->add_parameters($parameter_hash);

    # Summary stats
    my $num_stats = get_integer($fh);  # not sure about this (not in the spec)
    my $stats_hash;
    for ( 1 .. $num_stats ) {

        # Listed in the file as name, value
        my $name  = get_ascii( $fh, get_integer($fh) );
        my $value = get_ascii( $fh, get_integer($fh) );

        # Remove stray whitespace from value
        $value =~ s{\A \s* (.*?) \s* \z}{$1}xms;

        if ( $value =~ m/,/ ) {        # Complex values may exist, e.g. Noise
            foreach my $substat ( split /,/, $value ) {
                my ( $subname, $subval ) = split /:/, $substat;
                $stats_hash->{"$name $subname"} = $subval;
            }
        }
        else {
            $stats_hash->{$name} = $value;
        }
    }
    $self->add_stats($stats_hash);

    return;
}

sub parse_chp : RESTRICTED {

    my ( $self, $fh ) = @_;

    openhandle($fh) or confess( 'Bad parameters passed to method' );

    # Background zones
    my $num_bkd_zones     = get_integer($fh);
    my $bkd_smooth_factor = get_float($fh);
    for ( 1 .. $num_bkd_zones ) {
        my $bkd_zone;    # discarded at the moment
        $bkd_zone->{'x'}     = get_float($fh);
        $bkd_zone->{'y'}     = get_float($fh);
        $bkd_zone->{'value'} = get_float($fh);
    }

    my $results_type = $self->get_results_type();

    # This next is only present in expression results type files:
    my $expression_analysis_type;
    if ( $results_type == 0 ) {
        $expression_analysis_type = get_unsigned_char($fh);
        if (   $expression_analysis_type == 1
            || $expression_analysis_type == 3 ) {

            # Set the qtd for ExpressionStat data with comparison data
            $self->set_headings( $self->get_affy_qtd_chp_comparison() );
        }
    }

    my $data_size = get_integer($fh);    # The data record size in bytes

    # Initialize the array. Makes subsequent steps safer & easier
    my $data;
    $data->[ $self->get_num_cells() - 1 ] = {};

    foreach my $cell (@$data) {

        # Expression results type files (N.B. this is the one we're mainly
        # interested in.)
        if ( $results_type == 0 ) {

            $cell->{'CHPDetection'}       = get_unsigned_char($fh);
            $cell->{'CHPDetectionPvalue'} = round( get_float($fh), 5 );
            $cell->{'CHPSignal'}          = round( get_float($fh), 1 );
            $cell->{'CHPPairs'}           = get_unsigned_short($fh);
            $cell->{'CHPPairsUsed'}       = get_unsigned_short($fh);

            if (   $expression_analysis_type == 1
                || $expression_analysis_type == 3 ) {

                $cell->{'CHPChange'}             = get_unsigned_char($fh);
                $cell->{'CHPChangePvalue'}       = round( get_float($fh), 5 );
                $cell->{'CHPSignalLogRatio'}     = round( get_float($fh), 1 );
                $cell->{'CHPSignalLogRatioLow'}  = round( get_float($fh), 1 );
                $cell->{'CHPSignalLogRatioHigh'} = round( get_float($fh), 1 );
                $cell->{'CHPCommonPairs'}        = get_unsigned_short($fh);

            }

        }

        # Genotyping results type files.
        elsif ( $results_type == 1 ) {

            $cell->{CHPAllele}       = get_unsigned_char($fh);
            $cell->{CHPAllelePvalue} = get_float($fh);

            # we distinguish between 10k and 100k arrays here:
            if ( $self->get_num_cells() > $LARGE_CHIP_THRESHOLD ) {

                # 100k arrays
                $cell->{CHPAllelePvalueAA}     = get_float($fh);
                $cell->{CHPAllelePvalueAB}     = get_float($fh);
                $cell->{CHPAllelePvalueBB}     = get_float($fh);
                $cell->{CHPAllelePvalueNoCall} = get_float($fh);

            }
            else {

                # 10k arrays
                $cell->{CHPAlleleRAS1} = get_float($fh);
                $cell->{CHPAlleleRAS2} = get_float($fh);
                get_float($fh);    # unused?
                get_float($fh);    # unused?

            }
        }

        # Resequencing results type files.
        elsif ( $results_type == 2 ) {
            my $sequence_length = get_integer($fh);
            $cell->{sequence} = get_ascii( $fh, $sequence_length );

            # This should work. 4 is the integer size.
            $cell->{base_call_score}
                = get_float( $fh, ( $data_size - $sequence_length - 4 ) );
        }

        # Universal results type files.
        elsif ( $results_type == 3 ) {
            $cell->{bkd_value} = get_float($fh);
        }
    }

    # Insert the data into the object
    $self->set_data($data);

    return;
}

1;
