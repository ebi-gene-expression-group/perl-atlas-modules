#!/usr/bin/env perl
#
# Module to parse Affymetrix binary data files.
#
# Tim Rayner 2004, ArrayExpress team, European Bioinformatics Institute
#
# $Id: GDAC_CDF.pm 2081 2008-06-14 22:00:45Z tfrayner $
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
	    <td class="pagetitle">Module detail: GDAC_CDF.pm</td>
	  </tr>
      </table>
    </div>

=end html

=head1 NAME

ArrayExpress::Datafile::Affymetrix::GDAC_CDF.pm - GDAC CDF data file
parsing.

=head1 SYNOPSIS

 use ArrayExpress::Datafile::Affymetrix::CDF::GDAC_CDF;

 my $cdf = ArrayExpress::Datafile::Affymetrix::CDF::GDAC_CDF->new({
     input => 'HG-U133A.cdf',
 });
 $cdf->parse();

=head1 DESCRIPTION

This module implements parsing and export of data from Affymetrix GDAC
CDF files.

Please see L<ArrayExpress::Datafile::Affymetrix::Parser> for
methods common to all the Affymetrix parser classes.

=head1 METHODS

Most accessors and methods are implemented in the superclass; see
L<ArrayExpress::Datafile::Affymetrix::CDF>.

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

package ArrayExpress::Datafile::Affymetrix::CDF::GDAC_CDF;
use base 'ArrayExpress::Datafile::Affymetrix::CDF';

use strict;
use warnings;

use Carp;
use Scalar::Util qw(openhandle);
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

sub START {

    my ( $self, $id, $args ) = @_;

    $self->set_required_magic(1178878811);

    return;
}

#############################
# GDAC CDF specific methods #
#############################

sub parse_cdf : RESTRICTED {

    my ( $self, $fh ) = @_;

    openhandle($fh) or confess( 'Bad parameters passed to method' );

    binmode( $fh, ":crlf" );
    seek( $fh, 0, 0 ) or croak("Error rewinding filehandle for input: $!\n");

    my $label = <$fh>;
    $label =~ s/[\r\n]* \z//xms;
    unless ( $label eq '[CDF]' ) {
        croak("Error: Unrecognized CDF file format: $label\n");
    }

    my $version = <$fh>;

    # We just want the version string.
    $version =~ s{\A Version= ([^\r\n]*) [\r\n]*}{$1}xms;
    unless ( $version eq 'GC3.0' ) {
        croak("Error: Unrecognized CDF file version: $version\n");
    }
    $self->set_version($version);

    my $line = q{};
    until ( $line eq '[Chip]' ) { $line = $self->_get_line($fh); }

    $self->set_chip_type(   ( split /=/, $self->_get_line($fh) )[1] );
    $self->set_num_columns( ( split /=/, $self->_get_line($fh) )[1] );
    $self->set_num_rows(    ( split /=/, $self->_get_line($fh) )[1] );
    $self->set_num_cells(   ( split /=/, $self->_get_line($fh) )[1] );
    my $max_cell = ( ( split /=/, $self->_get_line($fh) )[1] );
    $self->set_num_qc_cells( ( split /=/, $self->_get_line($fh) )[1] );

    # Here we skip all the QC info for now

    my $data;
    $data->[ $self->get_num_cells() - 1 ] = {};

    # Generate a mapping of unit names and numbers
    foreach my $cell (@$data) {

        my ( $unitno, $unitname );
        until ( $line =~ m{\[ Unit \d+ \]}xms ) {
            unless ( defined( $line = <$fh> ) ) {
                croak("Premature end of CDF file.");
            }
        }

        until ( ( $unitname ) = ( $line =~ m{\A Name= ([^\r\n]+) [\r\n]* \z}xms ) ) {
            unless ( defined( $line = <$fh> ) ) {
                croak("Premature end of CDF file.");
            }
        }
        until ( ( $unitno ) = ( $line =~ m{\A UnitNumber= (\d+) [\r\n]* \z}xms ) ) {
            unless ( defined( $line = <$fh> ) ) {
                croak("Premature end of CDF file.");
            }
        }

        # Expression CDFs don't keep the name in the unit, but in the blocks.
        if ( $unitname eq 'NONE' ) {
            $unitname = undef;
            until ( $line =~ m!\[Unit($unitno)_Block\d+\]! ) {
                unless ( defined( $line = <$fh> ) ) {
                    croak("Premature end of CDF file.");
                }
            }
            until ( ($unitname) = ( $line =~ m/^Name=([^\r\n]+)[\r\n]*$/ ) ) {
                unless ( defined( $line = <$fh> ) ) {
                    croak("Premature end of CDF file.");
                }
            }
        }

        unless ($unitname) {
            croak("Error: No name for unit $unitno.\n");
        }
        $cell->{cell_no} = $unitno;
        $cell->{name}    = $unitname;
    }
    $self->set_data($data);

    return;
}

1;
