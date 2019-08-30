#!/usr/bin/env perl
#
# Module to parse Affymetrix binary data files.
#
# Tim Rayner 2004, ArrayExpress team, European Bioinformatics Institute
#
# $Id: GDAC_CHP.pm 1906 2008-01-23 10:05:42Z tfrayner $
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
	    <td class="pagetitle">Module detail: GDAC_CHP.pm</td>
	  </tr>
      </table>
    </div>

=end html

=head1 NAME

ArrayExpress::Datafile::Affymetrix::CHP::GDAC_CHP - GDAC CHP data file
parsing.

=head1 SYNOPSIS

 use base qw( ArrayExpress::Datafile::Affymetrix::CHP::GDAC_CHP );

=head1 DESCRIPTION

Abstract superclass for parsing and export of data from Affymetrix CHP
files. For older GDAC CHP files this class also implements a file
header parsing method, which can be used to determine the version of
the file (e.g. v8, v12, v13).

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

package ArrayExpress::Datafile::Affymetrix::CHP::GDAC_CHP;
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

sub START {

    my ( $self, $id, $args ) = @_;

    $self->set_required_magic(1701733703);

    return;
}

#############################
# GDAC CHP specific methods #
#############################

sub _parse_gdac_chp_params : PRIVATE {

    my ( $self, $paramstr ) = @_;

    ref $paramstr and confess( 'Bad parameters passed to method' );

    my @params = split /\s+/, $paramstr;

    my $parameter_hash;
    foreach my $param (@params) {
        my ( $name, $value ) = split /=/, $param;
        $parameter_hash->{$name} = $value;
    }

    $self->add_parameters($parameter_hash);

    return;
}

sub _parse_gdac_chp_stats : PRIVATE {

    my ( $self, $statstr ) = @_;

    ref $statstr and confess( 'Bad parameters passed to method' );

    my @statlists = split /[\s]+/, $statstr;

    my $stats_hash;
    foreach my $statlist (@statlists) {
        my ( $prefix, $valuestring ) = split /=/, $statlist;
        my @stats = split /,/, $valuestring;
        foreach my $stat (@stats) {
            my ( $value, $name ) = reverse( split /:/, $stat );
            my $fullkey = $name ? "$prefix $name" : $prefix;
            $stats_hash->{$fullkey} = $value;
        }
    }

    $self->add_stats($stats_hash);

    return;
}

sub parse_chp_header : RESTRICTED {

    my ( $self, $fh ) = @_;

    openhandle($fh) or confess( 'Bad parameters passed to method' );

    # Set fh to binary parsing, and rewind the file
    binmode( $fh, ":raw" );
    sysseek( $fh, 0, 0 )
        or croak("Error rewinding filehandle for input: $!\n");

    # Read the data in as a series of arrays/hashes
    my $label = get_ascii( $fh, 22 );
    unless ( $label eq 'GeneChip Sequence File' ) {
        croak("Error: unknown CHP file format: $label\n");
    }

    # Set the stardard qtd for ExpressionStat data.
    $self->set_headings( $self->get_affy_qtd_chp() );

    # Store this in a scalar var for speed of access.
    my $version = get_integer($fh);

    $self->set_version( $version );

    if ( $version == 8 ) {

	# Get what we can (version, algorithm, parameters, cell
	# numbers and chip_type). We don't attempt to parse the actual data.
	$self->set_algorithm( get_ascii( $fh, get_integer($fh) ) );
	$self->_parse_gdac_chp_params( get_ascii( $fh, get_integer($fh) ) );

	$self->set_num_columns( get_integer($fh) );
	$self->set_num_rows( get_integer($fh) );
	$self->set_num_cells( get_integer($fh) );    # Total

	my $max_cell_no  = get_integer($fh);     # Deprecated
	my $num_qc_cells = get_integer($fh);

	# Seek to the chip_type record.
	my $skipped = ( $max_cell_no + $self->get_num_cells() ) * 2 * 4;
	sysseek($fh, $skipped, 1);   # FIXME find a way to die meaningfully here.

	# header probe_array_type; NB contains a lot of junk.
	my $probe_array_type = get_ascii( $fh, 256 );
	$probe_array_type = ( split /[\n\r]+/, $probe_array_type )[0];
	$probe_array_type =~ s{\A ([\w-]*) .*}{$1}xms;
	$self->set_chip_type($probe_array_type);

	# And that's all we can parse for now.
	return;
    }
    elsif ( $version != 12 && $version != 13 ) {

	# We have no idea what this might be.
        croak("Fatal error: unrecognized CHP file version $version");
    }

    $self->set_algorithm( get_ascii( $fh, get_integer($fh) ) );

    # Algorithm version (skip for version 8 CHP)
    get_ascii( $fh, get_integer($fh) );

    $self->_parse_gdac_chp_params( get_ascii( $fh, get_integer($fh) ) );

    # Next line skipped for version 8 CHP
    $self->_parse_gdac_chp_stats( get_ascii( $fh, get_integer($fh) ) );

    $self->set_num_columns( get_integer($fh) );
    $self->set_num_rows( get_integer($fh) );
    $self->set_num_cells( get_integer($fh) );    # Total

    return;
}

sub parse_chp : RESTRICTED {    # CONFIRMED BY DIFF

    # NB quite a lot of stuff is being discarded here. This relieves
    # memory overhead, but we may want to add some things back at some
    # stage.

    my ( $self, $fh ) = @_;

    openhandle($fh) or confess( 'Bad parameters passed to method' );

    my $max_cell_no  = get_integer($fh);     # Deprecated
    my $num_qc_cells = get_integer($fh);

    if ( $self->get_num_cells > $max_cell_no ) {
        croak(
            "Error: Number of probe sets greater than the maximum possible!\n"
        );
    }

    # Initialize the array. Makes subsequent steps safer & easier
    # NB. when num_cells doesn't agree with num_rows*num_cells, it
    # appears that num_cells is the one to trust. This may not be a
    # good assumption in future.
    my $data;
    $data->[ $self->get_num_cells() - 1 ] = {};

    # Cell numbers are deprecated
    foreach my $cell (@$data) { get_integer($fh) }    # cell number
    foreach my $cell (@$data) { get_integer($fh) }    # cell num_pairs2
    for ( $self->get_num_cells() .. ( $max_cell_no - 1 ) ) {
        get_integer($fh);                             # Unused
    }

    foreach my $cell (@$data) { $cell->{type} = get_integer($fh) }

    for ( $self->get_num_cells() .. ( $max_cell_no - 1 ) ) {
        get_integer($fh);
    }    # Unused
    foreach my $cell (@$data) { get_integer($fh) }    # cell num_probes

    # header probe_array_type; NB contains a lot of junk.
    my $probe_array_type = get_ascii( $fh, 256 );

    $probe_array_type = ( split /[\n\r]+/, $probe_array_type )[0];
    $probe_array_type =~ s{\A ([\w-]*) .*}{$1}xms;

    $self->set_chip_type($probe_array_type);

    # header parent_cel_filename; NB contains a lot of junk.
    my $parent_cel = get_ascii( $fh, 256 );

    # header programmatic_id
    my $programmatic_id = get_ascii( $fh, get_integer($fh) );

    foreach my $cell (@$data) {

        if ( $cell->{type} == 3 ) {    # Expression data

	    # This call will vary between versions 12 and 13 of the
	    # CHP file format.
	    $self->parse_expression_cell( $fh, $cell );

        }
        elsif ( $cell->{type} == 2 ) {     # Genotyping data

            croak(
                "Error: Genotyping data file parsing not yet implemented for CHP v3.\n"
            );

        }
        else {

            croak("Error: Cell type $cell->{type} not known.\n");

        }
    }

    # Insert the data table into the object
    $self->set_data($data);

    # The next few sections are a work-in-progress
    my $reseq_length = get_integer($fh);

    if ($reseq_length) {

        croak("Error: Resequencing data file parsing not yet implemented.\n");

    }

    my @qc_cells;
    foreach my $qc_cell ( @qc_cells[ 0 .. ( $num_qc_cells - 1 ) ] ) {

        my $num_probes = get_integer($fh);
        get_integer($fh);    # qc_cell type

        my @probes;
        foreach my $probe ( @probes[ 0 .. ( $num_probes - 1 ) ] ) {

            get_integer($fh);    # probe X_coord
            get_integer($fh);    # probe Y_coord
            get_float($fh);      # probe intensity
            get_float($fh);      # probe stdev
            get_integer($fh);    # probe pixels
            get_float($fh);      # probe background

        }
    }

    return;
}

sub parse_expression_cell : RESTRICTED {

    my ( $self, $fh, $cell ) = @_;

    confess ("Error: Stub method called in abstract superclass.");
}

1;
