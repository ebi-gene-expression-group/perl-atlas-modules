#!/usr/bin/env perl
#
# Module to parse Affymetrix binary data files.
#
# Tim Rayner 2004, ArrayExpress team, European Bioinformatics Institute
#
# $Id: CDF.pm 2155 2009-01-15 17:21:49Z farne $
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
	    <td class="pagetitle">Module detail: CDF.pm</td>
	  </tr>
      </table>
    </div>

=end html

=head1 NAME

ArrayExpress::Datafile::Affymetrix::CDF.pm - CDF data file
parsing.

=head1 SYNOPSIS

 use base qw( ArrayExpress::Datafile::Affymetrix::CDF );

=head1 DESCRIPTION

This module is an abstract superclass used in parsing and export of
data from Affymetrix CDF files.

Please see L<ArrayExpress::Datafile::Affymetrix::Parser> for
methods common to all the Affymetrix parser classes.

=head1 METHODS

=over 2

=item get_num_qc_cells()

The number of cells on the chip dedicated to QC measurements.

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

package ArrayExpress::Datafile::Affymetrix::CDF;
use base 'ArrayExpress::Datafile::Affymetrix::Parser';

use strict;
use warnings;

use Carp;
use Scalar::Util qw(openhandle);
use IO::File;
use Class::Std;

use ArrayExpress::Datafile::Binary qw(
    get_integer
);

my %num_qc_cells : ATTR( :name<num_qc_cells>, :default<undef> );

sub parse {

    my ( $self ) = @_;

    my $input = $self->get_input();

    my $fh;
    if ( openhandle($input) ) {
        $fh = $input;
    }
    else {
        $fh = IO::File->new( $input, '<' )
            or croak("Unable to open CDF file $input : $!\n");
    }

    binmode($fh);
    sysseek( $fh, 0, 0 )
        or croak("Error rewinding filehandle for input: $!\n");

    my $magic = get_integer($fh);

    unless ($magic == $self->get_required_magic()) {
	croak("Error: Incorrect parser class used for CDF type ($magic)");
    }

    $self->parse_cdf($fh);

    return;
}

sub get_probeset_ids {

    # Returns a list of probeset identifiers, in order.

    my ( $self ) = @_;

    my $data = $self->get_data();

    return [ map { $_->{name} } @{ $data } ];
}


sub get_all_data {
    my ( $self ) = @_;
    
    my $data = $self->get_data();
    return $data;
}

1;
