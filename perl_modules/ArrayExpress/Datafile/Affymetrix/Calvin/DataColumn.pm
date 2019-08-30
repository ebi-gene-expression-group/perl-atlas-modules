#!/usr/bin/env perl
#
# $Id: DataColumn.pm 1973 2008-02-27 18:10:51Z tfrayner $

use strict;
use warnings;

package ArrayExpress::Datafile::Affymetrix::Calvin::DataColumn;

# Simple class to store column definitions.

use Class::Std;
use Carp;

use ArrayExpress::Datafile::Affymetrix::Calvin::Binary qw(
    get_signed_char
    get_unsigned_char
    get_signed_short
    get_unsigned_short
    get_signed_integer
    get_unsigned_integer
    get_network_float
    get_string
    get_wstring
);

my %name   : ATTR( :name<name>,    :default<undef> );
my %type   : ATTR( :name<type>,    :default<undef> );
my %size   : ATTR( :name<size>,    :default<undef> );
my %reader : ATTR( :name<reader>,  :default<undef> );

# FIXME some of these may need sprintf-style reformatting.
my %readermap = (
    0 => \&get_signed_char,
    1 => \&get_unsigned_char,
    2 => \&get_signed_short,
    3 => \&get_unsigned_short,
    4 => \&get_signed_integer,
    5 => \&get_unsigned_integer,
    6 => \&get_network_float,
    7 => \&get_string,
    8 => \&get_wstring,
);

sub START {

    my ( $self, $id, $args ) = @_;

    unless ( $self->get_name() ) {
	croak("Error: Column name not set.");
    }

    if ( my $type = $self->get_type() ) {
	if ( my $coderef = $readermap{$type} ) {
	    $self->set_reader( $coderef );
	}
	else {
	    croak("Error: Unrecognized column type $type.");
	}
    }
    else {
	croak("Error: Column header type not set.");
    }

    return;
}

1;
