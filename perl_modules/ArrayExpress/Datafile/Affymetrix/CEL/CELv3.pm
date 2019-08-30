#!/usr/bin/env perl
#
# Module to parse Affymetrix binary data files.
#
# Tim Rayner 2004, ArrayExpress team, European Bioinformatics Institute
#
# $Id: CELv3.pm 2021 2008-04-09 09:55:25Z tfrayner $
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
	    <td class="pagetitle">Module detail: CELv3.pm</td>
	  </tr>
      </table>
    </div>

=end html

=head1 NAME

ArrayExpress::Datafile::Affymetrix::CEL::CELv3.pm - CELv3 data file parsing

=head1 SYNOPSIS

 use ArrayExpress::Datafile::Affymetrix::CEL::CELv3;

 my $cel = ArrayExpress::Datafile::Affymetrix::CEL::CELv3->new({
     input => 'mydatafile.CEL',
 });
 $cel->parse();
 $cel->export($output_fh);

=head1 DESCRIPTION

This module implements parsing and export of data from Affymetrix GDAC
CEL (v3) files.

Please see L<ArrayExpress::Datafile::Affymetrix::Parser> for
methods common to all the Affymetrix parser classes.

=head1 METHODS

Most methods are implemented in the superclass. See
L<ArrayExpress::Datafile::Affymetrix::CEL> for details.

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

package ArrayExpress::Datafile::Affymetrix::CEL::CELv3;
use base 'ArrayExpress::Datafile::Affymetrix::CEL';

use strict;
use warnings;

use Readonly;
use Carp;
use Scalar::Util qw(openhandle);
use IO::File;
use Class::Std;

sub START {

    my ( $self, $id, $args ) = @_;

    $self->set_required_magic(1279607643);

    return;
}

##########################
# CELv3-specific methods #
##########################

sub parse_cel_header : RESTRICTED {

    my ( $self, $fh ) = @_;

    openhandle($fh) or confess( 'Bad parameters passed to method' );

    # Set fh to plain text parsing, and rewind the file
    binmode( $fh, ":crlf" );
    seek( $fh, 0, 0 ) or croak("Error rewinding filehandle for input: $!\n");

    # Read the data in as a series of arrays/hashes.

    ##########
    # HEADER #
    ##########
    my $label = $self->_get_line($fh);
    unless ( $label eq '[CEL]' ) {
        croak("Error: unknown CEL file format: $label\n");
    }

    $self->set_version( ( split /\=/, $self->_get_line($fh) )[1] );

    my $line = q{};
    until ( $line =~ m/\A \[HEADER\]/xms || ! defined( $line ) ) {
	$line = $self->_get_line($fh);
    }

    my $header_tags = q{};

    LINE:
    while ( $line = <$fh> ) {
        last LINE if ( $line =~ m/\A \s* \z/xms );
        $header_tags .= $line;
    }

    $self->parse_v3_header_tags($header_tags);

    #############
    # INTENSITY #
    #############
    until ( $line =~ m/\A \[INTENSITY\]/xms || ! defined( $line ) ) {
	$line = $self->_get_line($fh);
    }

    $self->set_num_cells( ( split /\=/, $self->_get_line($fh) )[1] );

    if ( $self->get_num_cells()
	     != ( $self->get_num_rows() * $self->get_num_columns() ) ) {
	carp(
	    "Format error: number of cells does not agree with row and column numbers"
	);
    }

    $self->add_stats(
        {   'Number of Cells' => $self->get_num_cells(),
            'Rows'            => $self->get_num_rows(),
            'Columns'         => $self->get_num_columns(),
        }
    );

    return;
}

sub parse_cel_body : RESTRICTED {

    my ( $self, $fh ) = @_;

    openhandle($fh) or confess( 'Bad parameters passed to method' );

    # Our filehandle should be set to the main data column headings line.
    if ( $self->_get_line($fh) ne "CellHeader=X\tY\tMEAN\tSTDV\tNPIXELS" ) {
        croak("Error: unrecognized CEL [INTENSITY] column headings.\n");
    }

    my $data;
    my $line = q{};

    LINE:
    while ( $line = $self->_get_line($fh) ) {

        last LINE if ( $line =~ m/\A \s* \z/xms );

        # Strip unnecessary whitespace.
        $line =~ s/\A [ ]*//xms;
        $line =~ s/[ ]* \z//xms;
        $line =~ s/[ ]* \t [ ]*/\t/gxms;

        my @line_array = split /\t/, $line;

        my $colno = $line_array[0];
        my $rowno = $line_array[1];

        $data->{"$colno\t$rowno"} = sprintf( "%.2f\t%.2f\t%d\tfalse\tfalse",
            @line_array[ 2 .. 4 ] );

    }

    #########
    # MASKS #
    #########
    until ( $line =~ m/\A \[MASKS\]/xms || ! defined( $line ) ) {
	$line = $self->_get_line($fh);
    }

    $self->set_num_masked( ( split /\=/, $self->_get_line($fh) )[1] );

    $self->add_stats( { 'Number Cells Masked' => $self->get_num_masked() } );

    if ( $self->_get_line($fh) ne "CellHeader=X\tY" ) {
        croak("Error: unrecognized CEL [MASKS] column headings.\n");
    }

    LINE:
    while ( $line = $self->_get_line($fh) ) {

        last LINE if ( $line =~ m/\A \s* \z/xms );

        my @line_array = split /\t/, $line;

        my $colno = $line_array[0];
        my $rowno = $line_array[1];

        $data->{"$colno\t$rowno"} =~ s{\t false \z}{\ttrue}xms;
    }

    ############
    # OUTLIERS #
    ############
    until ( $line =~ m/\A \[OUTLIERS\]/xms || ! defined( $line ) ) {
	$line = $self->_get_line($fh);
    }

    $self->set_num_outliers( ( split /\=/, $self->_get_line($fh) )[1] );

    $self->add_stats( { 'Number Outlier Cells' => $self->get_num_outliers() } );

    if ( $self->_get_line($fh) ne "CellHeader=X\tY" ) {
        croak("Error: unrecognized CEL [OUTLIERS] column headings.\n");
    }

    LINE:
    while ( $line = $self->_get_line($fh) ) {

        last LINE if ( $line =~ m/\A \s* \z/xms );

        my @line_array = split /\t/, $line;

        my $colno = $line_array[0];
        my $rowno = $line_array[1];

        $data->{"$colno\t$rowno"} =~ s{\t false \t (?= \w+ \z)}
	                              {\ttrue\t}xms;
    }

    ############
    # MODIFIED #
    ############
    until ( $line =~ m/\A \[MODIFIED\]/xms || ! defined( $line ) ) {
	$line = $self->_get_line($fh);
    }

    $self->set_num_modified( ( split /\=/, $self->_get_line($fh) )[1] );

    $self->add_stats( { 'Number Cells Modified' => $self->get_num_modified() } );

    warn( "Warning: ignoring " . $self->get_num_modified() . " cells.\n" )
        if $self->get_num_modified();

    if ( $self->_get_line($fh) ne "CellHeader=X\tY\tORIGMEAN" ) {
        croak("Error: unrecognized CEL [MODIFIED] column headings.\n");
    }

    # Insert the data table into the object
    $self->set_data($data);

    return;
}

1;
