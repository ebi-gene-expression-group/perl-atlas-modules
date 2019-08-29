#!/usr/bin/env perl
#
# Module to parse Affymetrix binary data files.
#
# Tim Rayner 2004, ArrayExpress team, European Bioinformatics Institute
#
# $Id: CEL.pm 2023 2008-04-13 11:25:46Z tfrayner $
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
	    <td class="pagetitle">Module detail: CEL.pm</td>
	  </tr>
      </table>
    </div>

=end html

=head1 NAME

ArrayExpress::Datafile::Affymetrix::CEL.pm - CEL data file parsing

=head1 SYNOPSIS

 use ArrayExpress::Datafile::Affymetrix::CEL;

 my $cel = ArrayExpress::Datafile::Affymetrix::CEL->new({
     input => 'mydatafile.CEL',
 });
 $cel->parse();
 $cel->export($output_fh);

=head1 DESCRIPTION

This module implements an abstract superclass used in parsing and
export of data from Affymetrix CEL files.

Please see L<ArrayExpress::Datafile::Affymetrix::Parser> for
methods common to all the Affymetrix parser classes.

=head1 METHODS

=over 2

=item parse_header()

This method will take the C<input> attribute and parse only the header
metadata. Note that for older CEL file formats, the numbers of masked,
outlier or modified cells are not set by this method, since these
values are embedded in the main body of the data.

=item export($fh)

This method takes a filehandle and prints the parsed expression data
out to it. The QuantitationTypeDimension and DesignElementDimension of
the resulting matrix are given by the C<get_qtd> and C<get_ded> methods,
respectively.

=item get_ded($chip_type)

This method takes an optional string argument representing the chip type (e.g.,
"HG-U133A") and uses it to generate a reference to an array of Feature
identifiers arranged in the order that the B<export> method outputs
them (i.e., a DesignElementDimension). The chip type can be derived in
a number of ways; if EXP files are available, for instance, the
$exp->get_chip_type() method should return an appropriate string. If this 
argument is not supplied then the $cel->get_chip_type() method
is used to derive a value; note however that that method relies
on parsing an undocumented tag and as such it may fail.

=item get_num_masked()

The number of masked cells.

=item get_num_outliers()

The number of outlier cells.

=item get_num_modified()

The number of modified cells (this should always be zero).

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

package ArrayExpress::Datafile::Affymetrix::CEL;
use base 'ArrayExpress::Datafile::Affymetrix::Parser';

use strict;
use warnings;

use Readonly;
use Carp;
use Scalar::Util qw(openhandle);
use IO::File;
use Class::Std;

use ArrayExpress::Datafile::Binary qw(
    get_integer
);

my %dedimension    : ATTR( :set<ded>,             :default<[]>    );
my %num_masked     : ATTR( :name<num_masked>,     :default<undef> );
my %num_outliers   : ATTR( :name<num_outliers>,   :default<undef> );
my %num_modified   : ATTR( :name<num_modified>,   :default<undef> );

# Standard CEL QTD
Readonly my $AFFY_QTD_CEL => [
    qw(
        CELX
        CELY
        CELIntensity
        CELIntensityStdev
        CELPixels
        CELOutlier
        CELMask
        )
];

sub START {

    my ( $self, $id, $args ) = @_;

    $self->set_data_storage('HASH');

    # Set the stardard qtd for CEL data.
    $self->set_headings($AFFY_QTD_CEL);

    return;
}

sub parse {

    my ( $self ) = @_;

    # Parse_header returns the filehandle set to the top of the main data.
    my $fh = $self->parse_header();

    $self->parse_cel_body($fh);

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
	croak("Error: Incorrect parser class used for CEL type ("
		  . $self->get_magic() . ")");
    }

    $self->parse_cel_header($fh);

    return $fh;    # Filehandle now set for reading main data body.
}

sub export {    # Now in full tab-delimited glory...
    my ( $self, $fh ) = @_;

    openhandle($fh) or confess( 'Bad parameters passed to method' );

    my $data = $self->get_data();

    foreach my $coord ( sort keys %$data ) {
        print $fh ( join( q{}, $coord, "\t", $data->{$coord}, "\n" ) );
    }

    return;
}

sub get_ded {

    my ( $self, $chip_type ) = @_;

    ref $chip_type and confess( 'Bad parameters passed to method' );

    unless ( scalar @{ $dedimension{ident $self} } ) {

        # If no chip type passed, try and figure it out on our own.
        $chip_type ||= $self->get_chip_type();

        # Basic sanity check here.
        croak("No chip type information available to CEL->get_ded()\n")
            unless $chip_type;

        my $data = $self->get_data();

        my @features;

        # Initialize the array; prevents memory fragmentation (maybe).
        $#features = scalar( grep { defined $_ } values %$data ) - 1;

        my $counter = 0;
        foreach my $coord ( sort keys %$data ) {

            my ( $colno, $rowno ) = split /\t/, $coord;
            $features[$counter] = "Affymetrix:Feature:"
                . $chip_type
                . ":Probe($colno,$rowno)";

            $counter++;
        }

        $dedimension{ident $self} = \@features;

    }

    return $dedimension{ident $self};
}

sub parse_v3_header_tags : RESTRICTED {

    # NB this method is also useful to the CELv4 parser.

    my ( $self, $tagstr ) = @_;

    defined( $tagstr ) or confess( 'Bad parameters passed to method' );

    my @lines = split /[\r\n]+/, $tagstr;

    my %tag;
    foreach my $line ( @lines ) {
	my ( $key, $value ) = split /=/, $line, 2;
	$tag{ $key } = $value;
    }

    # CEL v4 parsing also uses this, but we don't want to override the
    # 'official' values.
    $self->set_num_columns( $tag{ 'Cols' } ) unless $self->get_num_columns();
    $self->set_num_rows(    $tag{ 'Rows' } ) unless $self->get_num_rows();
    $self->set_algorithm( $tag{ 'Algorithm' } || 'Unknown' );

    # The following is an undocumented tag, but seems to be consistently
    # used and is extremely useful. It's likely to be used by GDAC
    # Exporter (Affy) as it's the only way of identifying the chip type
    # if only the CEL file is available.
    my ($chip_type) = ( $tag{ 'DatHeader' } =~ m{[ ] ([^ .]*).1sq [ ]}ixms );
    $self->set_chip_type($chip_type);

    my @params = split /;/, $tag{ 'AlgorithmParameters' };

    my $parameter_hash = {};
    foreach my $param (@params) {
        my ( $key, $value ) = split /:/, $param;
        $parameter_hash->{$key} = $value;
    }

    $self->add_parameters($parameter_hash);

    return;
}

1;
