#!/usr/bin/env perl
#
# Module to parse Affymetrix binary data files.
#
# Tim Rayner 2004, ArrayExpress team, European Bioinformatics Institute
#
# $Id: CELv4.pm 1852 2007-12-13 10:14:27Z tfrayner $
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
	    <td class="pagetitle">Module detail: CELv4.pm</td>
	  </tr>
      </table>
    </div>

=end html

=head1 NAME

ArrayExpress::Datafile::Affymetrix::CEL::CELv4.pm - CELv4 data file parsing

=head1 SYNOPSIS

 use ArrayExpress::Datafile::Affymetrix::CEL::CELv4;

 my $cel = ArrayExpress::Datafile::Affymetrix::CEL::CELv4->new({
     input => 'mydatafile.CEL',
 });
 $cel->parse();
 $cel->export($output_fh);

=head1 DESCRIPTION

This module implements parsing and export of data from Affymetrix XDA
CEL (v4) files.

Please see L<ArrayExpress::Datafile::Affymetrix::Parser> for
methods common to all the Affymetrix parser classes.

=head1 METHODS

Most parsing methods and accessors are implemented in the
superclasses. See L<ArrayExpress::Datafile::Affymetrix::CEL::CELv3> for
information. The following attributes are specific to CELv4 files:

=over 2

=item get_cell_margin()

The cell margin.

=item get_num_subgrids()

The number of subgrids used on the chip (N.B. this is currently
UNTESTED).

=item get_subgrids()

A reference to a hash containing subgrid information (N.B. this is
currently UNTESTED).

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

package ArrayExpress::Datafile::Affymetrix::CEL::CELv4;
use base 'ArrayExpress::Datafile::Affymetrix::CEL';

use strict;
use warnings;

use Readonly;
use Carp;
use Scalar::Util qw(openhandle);
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
);

# Subgrids are v4 CEL only UNTESTED FIXME.
my %num_subgrids  : ATTR( :name<num_subgrids>, :default<undef> );
my %subgrids      : ATTR( :name<subgrids>,     :default<{}>    );
my %cell_margin   : ATTR( :name<cell_margin>,  :default<undef> );

sub START {
    my ( $self, $id, $args ) = @_;

    $self->set_required_magic(64);

    return;
}

#################
# CELv4 methods #
#################

sub parse_v4_parameters : PRIVATE {

    my ( $self, $paramstr ) = @_;

    ref $paramstr and confess( 'Bad parameters passed to method' );

    my @params = split /[;\s]+/, $paramstr;

    my $parameter_hash;
    foreach my $param (@params) {
        my ( $key, $value ) = split /[:=]/, $param;
        $parameter_hash->{$key} = $value;
    }

    $self->add_parameters($parameter_hash);

    return;
}

sub parse_cel_header : RESTRICTED {

    my ( $self, $fh ) = @_;

    openhandle($fh) or confess( 'Bad parameters passed to method' );

    # Binary-mode filehandle, rewind the file
    binmode( $fh, ":raw" );
    sysseek( $fh, 0, 0 )
        or croak("Error rewinding filehandle for input: $!\n");

    # We will read the data in as a series of arrays/hashes:

    my $magic = get_integer($fh);
    unless ( $magic == 64 ) {
        croak("Error: Unrecognized CEL type: $magic\n");
    }

    # Header parsing
    $self->set_version( get_integer($fh) );
    $self->set_num_columns( get_integer($fh) );
    $self->set_num_rows( get_integer($fh) );
    $self->set_num_cells( get_integer($fh) );    # col x row - tested below

    $self->add_stats(
        {   'Number of Cells' => $self->get_num_cells(),
            'Rows'            => $self->get_num_rows(),
            'Columns'         => $self->get_num_columns(),
        }
    );

    if ( $self->get_num_cells() != ( $self->get_num_rows() * $self->get_num_columns() ) ) {
        carp(
            "Format error: number of cells does not agree with row and column numbers"
        );
    }

    $self->parse_v3_header_tags( get_ascii( $fh, get_integer($fh) ) );

    $self->set_algorithm( get_ascii( $fh, get_integer($fh) ) );

    $self->parse_v4_parameters( get_ascii( $fh, get_integer($fh) ) );

    $self->set_cell_margin( get_integer($fh) );
    $self->set_num_outliers( get_DWORD($fh) );
    $self->set_num_masked( get_DWORD($fh) );
    $self->set_num_subgrids( get_integer($fh) );

    $self->add_stats(
        {   'Number Cells Masked'  => $self->get_num_masked(),
            'Number Outlier Cells' => $self->get_num_outliers(),
        }
    );

    return;
}

sub parse_cel_body : RESTRICTED {

    # Parses CEL files (passed diff test against old CEL file format,
    # so more-or-less okay, but see subgrid comment at end)

    my ( $self, $fh ) = @_;

    openhandle($fh) or confess( 'Bad parameters passed to method' );

    # Data starts here. These are sizable arrays.  Our filehandle should
    # have been set to the start of the main data loop section.

    # Read intensities
    # $self->get_data() points to a hash of data values
    my $data;

    # Y is rows, X is columns.
    for ( my $rowno = 0; $rowno < $self->get_num_rows(); $rowno++ ) {
        for ( my $colno = 0; $colno < $self->get_num_columns(); $colno++ ) {

            $data->{"$colno\t$rowno"} = sprintf(
                "%.2f\t%.2f\t%d\tfalse\tfalse",
                round( get_float($fh), 1 ),
                round( get_float($fh), 1 ),
                get_unsigned_short($fh),
            );

        }
    }

    # Read masked cells
    for ( my $cell = 0; $cell < $self->get_num_masked(); $cell++ ) {
        my $colno = get_unsigned_short($fh);
        my $rowno = get_unsigned_short($fh);
        $data->{"$colno\t$rowno"} =~ s{\t false \z}{\ttrue}xms;
    }

    # Read outlier cells
    for ( my $cell = 0; $cell < $self->get_num_outliers(); $cell++ ) {
        my $colno = get_unsigned_short($fh);
        my $rowno = get_unsigned_short($fh);
        $data->{"$colno\t$rowno"} =~ s{\t false \t (?= \w+ \z)}
	                              {\ttrue\t}xms;
    }

    # NB we should parse out the subgrids here FIXME
    # Note - the following is untested code
    my $subgrids;
    for ( my $cell = 0; $cell < $self->get_num_subgrids(); $cell++ ) {
        $subgrids->[$cell]{row}    = get_integer($fh);
        $subgrids->[$cell]{column} = get_integer($fh);

        $subgrids->[$cell]{ul_x} = get_float($fh);    # pixel coords
        $subgrids->[$cell]{ul_y} = get_float($fh);
        $subgrids->[$cell]{ur_x} = get_float($fh);

        # typo in spec fixed here, I hope
        $subgrids->[$cell]{ur_y} = get_float($fh);
        $subgrids->[$cell]{ll_x} = get_float($fh);
        $subgrids->[$cell]{ll_y} = get_float($fh);
        $subgrids->[$cell]{lr_x} = get_float($fh);

        # typo in spec fixed here, I hope
        $subgrids->[$cell]{lr_y} = get_float($fh);

        $subgrids->[$cell]{left_pos}   = get_integer($fh);    # cell positions
        $subgrids->[$cell]{top_pos}    = get_integer($fh);
        $subgrids->[$cell]{right_pos}  = get_integer($fh);
        $subgrids->[$cell]{bottom_pos} = get_integer($fh);

        # We currently have no information on the format of these entries in
        # text files, so we don't print them out FIXME
    }

    $self->set_subgrids($subgrids);

    # Insert the data table into the object
    $self->set_data($data);

    return;
}

1;
