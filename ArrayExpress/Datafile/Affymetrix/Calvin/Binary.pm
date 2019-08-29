#!/usr/bin/env perl
#
# Module to provide basic binary file data parsing functions.used in
# e.g. Affymetrix file parsing module(s)
#
# Tim Rayner 2004, ArrayExpress team, European Bioinformatics Institute
#
# $Id: Binary.pm 1985 2008-03-03 18:32:27Z tfrayner $
#

package ArrayExpress::Datafile::Affymetrix::Calvin::Binary;

use strict;
use warnings;

use Carp;
use Readonly;

use base 'Exporter';
our @EXPORT_OK = qw(
    get_unsigned_short
    get_signed_short
    get_unsigned_char
    get_signed_char
    get_unsigned_integer
    get_signed_integer
    get_wchar
    get_wstring
    get_string
    get_datetime
    get_locale
    get_network_float
);

# This constant determines how floats are handled on big-endian systems.
# NB. it is unclear at this stage whether 64-bit systems will work.
Readonly my $IS_BIG_ENDIAN => unpack( "h*", pack( "s", 1 ) ) =~ /01/;

#################################
# Binary data parsing functions #
#################################

sub get_unsigned_short {
    my $fh = shift;
    my $num_bytes = sysread( $fh, my $value, 2 );
    croak($!) unless defined($num_bytes);
    return ( unpack "n*", $value );
}

sub get_signed_short {
    my $fh = shift;
    my $num_bytes = sysread( $fh, my $value, 2 );
    croak($!) unless defined($num_bytes);
    return ( unpack "n*", $value );
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

sub get_ascii {
    my ( $fh, $length ) = @_;
    my $num_bytes = sysread( $fh, my $value, $length );
    croak($!) unless defined($num_bytes);
    return ( unpack "a*", $value );
}

sub get_unsigned_integer {
    my $fh = shift;
    my $num_bytes = sysread( $fh, my $value, 4 );
    croak($!) unless defined($num_bytes);
    return ( unpack "N*", $value );
}

sub get_signed_integer {
    my $fh = shift;
    my $num_bytes = sysread( $fh, my $value, 4 );
    croak($!) unless defined($num_bytes);
    return ( unpack "N*", $value );
}

sub get_wchar {
    my ( $fh, $length ) = @_;
    my $num_bytes = sysread( $fh, my $value, $length );
    croak($!) unless defined($num_bytes);
    return $value;
}

sub get_wstring {
    my ( $fh, $total ) = @_;
    my $length = get_signed_integer( $fh ) * 2;
    my $value  = get_wchar( $fh, $length );
    if ( $total ) {
	sysseek( $fh, $total - ( $length + 4 ), 1 );
    }
    my $ascii = pack "C*", unpack "n*", $value;
    return $ascii;
}

sub get_string {
    my ( $fh, $total ) = @_;
    my $length = get_signed_integer( $fh );
    my $value  = get_ascii( $fh, $length );
    if ( $total ) {
	sysseek( $fh, $total - ( $length + 4 ), 1 );
    }
    return $value;
}

sub get_datetime {
    my $fh = shift;
    return get_wstring( $fh );
}

sub get_locale {
    my $fh = shift;
    return get_wchar( $fh, 14 );
}

sub get_network_float {
    my ( $fh ) = @_;
    my $num_bytes = sysread( $fh, my $value, 4 );
    croak($!) unless defined($num_bytes);

    my $retval;
    if ($IS_BIG_ENDIAN) {
        $retval = unpack 'f*', $value;
    }
    else {
        $retval = unpack "f*", pack "N*", unpack "V*", $value;
    }
    return sprintf( "%.5f", $retval );
}

1;
