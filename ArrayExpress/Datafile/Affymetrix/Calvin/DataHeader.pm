#!/usr/bin/env perl
#
# $Id: DataHeader.pm 1973 2008-02-27 18:10:51Z tfrayner $

use strict;
use warnings;

package ArrayExpress::Datafile::Affymetrix::Calvin::DataHeader;
use base qw(ArrayExpress::Datafile::Affymetrix::Calvin::Component);

use Class::Std;
use Carp;

use ArrayExpress::Datafile::Affymetrix::Calvin::Binary qw(
    get_signed_integer
    get_datetime
    get_locale
    get_string
);

my %file_identifier : ATTR( :name<file_identifier>, :default<undef> );
my %data_type       : ATTR( :name<data_type>,       :default<undef> );
my %creation_date   : ATTR( :name<creation_date>,   :default<undef> );
my %locale_info     : ATTR( :name<locale_info>,     :default<undef> );
my %parent_headers  : ATTR( :name<parent_headers>,  :default<[]>    );

sub START {

    my ( $self, $id, $args ) = @_;

    my $fh  = $self->get_filehandle() or croak("Error: No filehandle.");
    my $pos = $self->get_position()   or croak("Error: No file position.");

    # The systell function doesn't exist, we use this instead.
    my $init_pos = sysseek( $fh, 0, 1 );

    # In principle this is probably unnecessary, but we do it anyway
    # just to be on the safe side.
    sysseek( $fh, $pos, 0 )
	or croak("Error resetting filehandle: $!");

    $self->set_data_type( get_string( $fh ) );
    $self->set_file_identifier( get_string( $fh ) );
    $self->set_creation_date( get_datetime( $fh ) );
    $self->set_locale_info( get_locale( $fh ) );

    my $num_parameters = get_signed_integer( $fh );
    for ( 1..$num_parameters ) {
	my $param = $self->parse_parameter( $fh );
	$self->add_parameters( $param );
    }

    # Recurse into the data headers, populating a nested hashref.
    my $num_parents = get_signed_integer( $fh );
    foreach my $num ( 1..$num_parents ) {
	my $current_pos = sysseek( $fh, 0, 1 );
	my $parent = __PACKAGE__->new({
	    filehandle => $fh,
	    position   => $current_pos,
	});
	$self->add_parent_headers( $parent );
    }

    # Reset the filehandle.
    sysseek( $fh, $init_pos, 0 )
	or croak("Error resetting filehandle: $!");    

    return;
}

sub add_parent_headers : PRIVATE {

    my ( $self, @parents ) = @_;

    push @{ $parent_headers{ ident $self } }, @parents;

    return;
}

1;
