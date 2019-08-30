#!/usr/bin/env perl
#
# Module to provide basic binary file data parsing functions.used in
# e.g. Affymetrix file parsing module(s)
#
# Tim Rayner 2004, ArrayExpress team, European Bioinformatics Institute
#
# $Id: Binary.pm 1973 2008-02-27 18:10:51Z tfrayner $
#

package ArrayExpress::Datafile::Binary;

use strict;
use warnings;

=pod

=begin html

    <div><a name="top"></a>
      <table class="layout">
	  <tr>
	    <td class="whitetitle" width="100">
              <a href="../../index.html">
                <img src="../T2M_logo.png"
                     border="0" height="50" alt="Tab2MAGE logo"></td>
              </a>
	    <td class="pagetitle">Module detail: Binary.pm</td>
	  </tr>
      </table>
    </div>

=end html

=head1 NAME

ArrayExpress::Datafile::Binary.pm - a module providing functions for
reading files in binary form.

=head1 SYNOPSIS

 use ArrayExpress::Datafile::Binary qw(get_integer get_float);
 
 my $int   = get_integer($fh);
 my $float = get_float($fh);

=head1 DESCRIPTION

This is a simple module providing functions which read an appropriate
number of bytes from the passed filehandle, and return the
appropriately unpacked value for further processing. Since this module
was originally developed to aid Affymetrix file parsing there is a
certain bias as to which data types are handled (the list is not
comprehensive; nor is it intended to be).

=head1 FUNCTIONS

=over 2

=item get_integer( $fh )

=item get_unsigned_short( $fh )

=item get_unsigned_char( $fh )

=item get_signed_char( $fh )

=item get_float( $fh, $length )

=item get_ascii( $fh, $length )

=item get_hexadecimal( $fh )

=back

=head1 AUTHOR

Tim Rayner (rayner@ebi.ac.uk), ArrayExpress team, EBI, 2008.

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

use Carp;
use Readonly;

use base 'Exporter';
our @EXPORT_OK = qw(
    get_integer
    get_DWORD
    get_unsigned_short
    get_unsigned_char
    get_signed_char
    get_float
    get_ascii
    get_hexadecimal
);

# This constant determines how floats are handled on big-endian systems.
# NB. it is unclear at this stage whether 64-bit systems will work.
Readonly my $IS_BIG_ENDIAN => unpack( "h*", pack( "s", 1 ) ) =~ /01/;

#################################
# Binary data parsing functions #
#################################

sub get_integer {    # Signed integer only.
    my $fh = shift;
    my $num_bytes = sysread( $fh, my $value, 4 );
    croak($!) unless defined($num_bytes);

    # Little-endian long, for portability's sake
    return ( unpack "V*", $value );
}

sub get_DWORD {
    my $fh = shift;
    my $num_bytes = sysread( $fh, my $value, 4 );
    croak($!) unless defined($num_bytes);
    return ( unpack "V*", $value );
}

sub get_unsigned_short {
    my $fh = shift;
    my $num_bytes = sysread( $fh, my $value, 2 );
    croak($!) unless defined($num_bytes);
    return ( unpack "v*", $value );
}

sub get_unsigned_char {
    my $fh = shift;
    my $num_bytes = sysread( $fh, my $value, 1 );
    croak($!) unless defined($num_bytes);
    return ( unpack "C*", $value );
}

sub get_signed_char {
    my $fh = shift;
    my $num_bytes = sysread( $fh, my $value, 1 );
    croak($!) unless defined($num_bytes);
    return ( unpack "c*", $value );
}

sub get_float {
    my ( $fh, $length ) = @_;
    $length ||= 4;    # defaults to a length of 4 bytes
    my $num_bytes = sysread( $fh, my $value, $length );
    croak($!) unless defined($num_bytes);
    if ($IS_BIG_ENDIAN) {
        return ( unpack 'f*', pack 'V*', unpack 'N*', $value );
    }
    else {
        return ( unpack "f*", $value );
    }
}

sub get_ascii {
    my ( $fh, $length ) = @_;

    # No longer default to a length of 1 byte - caused too many bugs
    #  $length ||= 1;
    my $num_bytes = sysread( $fh, my $value, $length );
    croak($!) unless defined($num_bytes);
    return ( unpack "a*", $value );
}

sub get_hexadecimal {    # High nybble first
    my ($fh) = @_;
    my $num_bytes = sysread( $fh, my $value, 1 );
    croak($!) unless defined($num_bytes);
    return ( unpack "H*", $value );
}

1;

