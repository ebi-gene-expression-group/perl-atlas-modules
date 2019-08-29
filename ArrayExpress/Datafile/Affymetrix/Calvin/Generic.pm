#!/usr/bin/env perl
#
# $Id: Generic.pm 1984 2008-03-03 17:47:18Z tfrayner $

use strict;
use warnings;

package ArrayExpress::Datafile::Affymetrix::Calvin::Generic;

use Class::Std;
use Carp;

require ArrayExpress::Datafile::Affymetrix::Calvin::DataGroup;
require ArrayExpress::Datafile::Affymetrix::Calvin::DataHeader;

use ArrayExpress::Datafile::Affymetrix::Calvin::Binary qw(
    get_signed_integer
    get_unsigned_char
    get_unsigned_integer
);

my %filename   : ATTR( :get<filename>,    :init_arg<filename>,   :default<undef> );
my %filehandle : ATTR( :set<filehandle>,  :init_arg<filehandle>, :default<undef> );

my %magic            : ATTR( :name<magic>,            :default<undef> );
my %version          : ATTR( :name<version>,          :default<undef> );
my %num_data_groups  : ATTR( :name<num_data_groups>,  :default<undef> );
my %data_group       : ATTR( :set<data_group>,        :default<[]>    );
my %data_header      : ATTR( :name<data_header>,      :default<undef>  );

sub START {

    my ( $self, $id, $args ) = @_;

    unless ( $filename{ ident $self } || $filehandle{ ident $self } ) {
	croak("Error: no filename or filehandle attribute set.\n");
    }

    my $fh = $self->get_filehandle();

    # The systell function doesn't exist, we use this instead.
    my $init_pos = sysseek( $fh, 0, 1 );

    # File header is at the beginning of the file (no surprises there
    # then).
    sysseek( $fh, 0, 0 )
	or croak("Error resetting filehandle: $!");

    my $magic = get_unsigned_char( $fh );
    unless( $magic == 59 ) {
	croak("Error: Unrecognized file magic number: $magic");
    }
    $magic{ ident $self } = $magic;

    $version{ ident $self }         = get_unsigned_char( $fh );
    $num_data_groups{ ident $self } = get_signed_integer( $fh );
    my $first_group_pos = get_unsigned_integer( $fh );
    my $first_group = ArrayExpress::Datafile::Affymetrix::Calvin::DataGroup->new({
	filehandle => $fh,
	position   => $first_group_pos,
    });
    $data_group{ ident $self }[0] = $first_group;

    # This recurses through the file to set the positions of all the
    # data groups.
    $self->populate_data_groups($first_group, $self->get_num_data_groups() - 1);

    # This iterates and recurses over the data headers.
    my $data_header = ArrayExpress::Datafile::Affymetrix::Calvin::DataHeader->new({
	filehandle => $fh,
	position   => 10,
    });

    $self->set_data_header( $data_header );

    # Reset the filehandle.
    sysseek( $fh, $init_pos, 0 )
	or croak("Error resetting filehandle: $!");

    return;
}

sub get_filehandle : RESTRICTED {

    my ( $self ) = @_;

    unless ( $filehandle{ ident $self } ) {
	open( my $fh, '<', $self->get_filename() )
	    or croak("Error: Unable to open input file: $!");
	$filehandle{ ident $self } = $fh;
    }

    return $filehandle{ ident $self };
}

sub get_data_group {

    my ( $self, $num ) = @_;

    # These should all have been created in START.
    unless ( defined $data_group{ ident $self }[ $num ] ) {
	croak("Error: No data group found for number $num");
    }

    return $data_group{ ident $self }[ $num ];
}

sub populate_data_groups : PRIVATE {

    my ( $self, $group, $num_groups ) = @_;

    return unless $num_groups;

    $group ||= $self->get_data_group( 0 )
	or croak("Error: Initial data group not created.\n");

    # The last data group should point to zero (but we don't rely on it).
    my $next_group = ArrayExpress::Datafile::Affymetrix::Calvin::DataGroup->new({
	filehandle => $self->get_filehandle(),
	position   => $group->get_next_group_position(),
    });
    push @{ $data_group{ ident $self } }, $next_group;
    $self->populate_data_groups($next_group, $num_groups - 1);

    return;
}

1;
