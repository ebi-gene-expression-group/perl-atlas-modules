#!/usr/bin/env perl
#
# $Id: Component.pm 1984 2008-03-03 17:47:18Z tfrayner $

use strict;
use warnings;

package ArrayExpress::Datafile::Affymetrix::Calvin::Component;

use Class::Std;
use Carp;
use Readonly;

require ArrayExpress::Datafile::Affymetrix::Calvin::Parameter;

use ArrayExpress::Datafile::Affymetrix::Calvin::Binary qw(
    get_string
    get_wstring
);

my %position   : ATTR( :name<position>,   :default<undef> );
my %filehandle : ATTR( :name<filehandle>, :default<undef> );
my %parameters : ATTR( :name<parameters>, :default<[]>    );

# This constant determines how floats are handled on big-endian systems.
# NB. it is unclear at this stage whether 64-bit systems will work.
Readonly my $IS_BIG_ENDIAN => unpack( "h*", pack( "s", 1 ) ) =~ /01/;

sub START {

    my ( $self, $id, $args ) = @_;

    unless ( $self->get_position() ) {
	croak("Error: No file position given.\n");
    }
    unless ( $self->get_filehandle() ) {
	croak("Error: No filehandle given.\n");
    }

    return;
}

sub parse_parameter : RESTRICTED {

    # This method _does_ have an effect on filehandle position.
    my ( $self, $fh ) = @_;

    my $pname  = get_wstring( $fh );
    my $pvalue = get_string( $fh );
    my $ptype  = get_wstring( $fh );

    my %mime_map = (
	'text/x-calvin-integer-8'           => 'c*',
	'text/x-calvin-unsigned-integer-8'  => 'C*',
	'text/x-calvin-integer-16'          => 's*',
	'text/x-calvin-unsigned-integer-16' => 'n*',
	'text/x-calvin-integer-32'          => 'N*',
	'text/x-calvin-unsigned-integer-32' => 'N*',
	'text/plain'                        => 'a*',
	'text/ascii'                        => 'a*',
    );

    my $conv_val;
    if ( $ptype eq 'text/x-calvin-float' ) {
	if ($IS_BIG_ENDIAN) {
	    $conv_val = unpack 'f*', $pvalue;
	}
	else {
	    $conv_val = unpack "f*", pack "N*", unpack "V*", $pvalue;
	}
    }
    elsif (my $packtype = $mime_map{ $ptype }) {
	$conv_val = (unpack( $packtype, $pvalue ))[0];
    }
    else {
	croak("Unrecognized MIME type: $ptype");
    }

    if ( $ptype eq 'text/plain' ) {
	$conv_val = pack "C*", unpack "n*", $conv_val;
	$conv_val =~ s/\x{0}* \z//xms;
    }
    elsif ( $ptype eq 'text/x-calvin-float' ) {
	$conv_val = sprintf("%.5f", $conv_val);
    }

    my $param = ArrayExpress::Datafile::Affymetrix::Calvin::Parameter->new({
	name  => $pname,
	value => $conv_val,
	type  => $ptype,
    });

    return $param;
}

sub add_parameters : RESTRICTED {

    my ( $self, @params ) = @_;

    push @{ $parameters{ ident $self } }, @params;

    return;
}

1;
