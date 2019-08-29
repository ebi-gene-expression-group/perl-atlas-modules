#!/usr/bin/env perl
#
# $Id: DataGroup.pm 1973 2008-02-27 18:10:51Z tfrayner $

use strict;
use warnings;

package ArrayExpress::Datafile::Affymetrix::Calvin::DataGroup;
use base qw(ArrayExpress::Datafile::Affymetrix::Calvin::Component);

use Class::Std;
use Carp;

require ArrayExpress::Datafile::Affymetrix::Calvin::DataSet;

use ArrayExpress::Datafile::Affymetrix::Calvin::Binary qw(
    get_signed_integer
    get_unsigned_integer
    get_wstring
);

my %next_group_position : ATTR( :name<next_group_position>, :default<undef> );
my %name                : ATTR( :name<name>,                :default<undef> );
my %num_data_sets       : ATTR( :name<num_data_sets>,       :default<undef> );
my %data_set            : ATTR( :set<data_set>,             :default<[]>    );

sub START {

    my ( $self, $id, $args ) = @_;

    my $fh  = $self->get_filehandle() or croak("Error: No filehandle.");
    my $pos = $self->get_position()   or croak("Error: No file position.");

    # The systell function doesn't exist, we use this instead.
    my $init_pos = sysseek( $fh, 0, 1 );

    # File header is at the beginning of the file (no surprises there
    # then).
    sysseek( $fh, $pos, 0 )
	or croak("Error resetting filehandle: $!");

    my $next_pos = get_unsigned_integer( $fh );
    $self->set_next_group_position( $next_pos ) if $next_pos;

    # We recurse into data set metadata here.
    my $first_set_pos   = get_unsigned_integer( $fh );

    $self->set_num_data_sets( get_signed_integer( $fh ) );
    $self->set_name( get_wstring( $fh ) );

    my $first_set = ArrayExpress::Datafile::Affymetrix::Calvin::DataSet->new({
	filehandle => $fh,
	position   => $first_set_pos,
    });

    $data_set{ident $self}[0] = $first_set;

    $self->populate_data_sets( $first_set, $self->get_num_data_sets() - 1 );

    # Reset the filehandle.
    sysseek( $fh, $init_pos, 0 )
	or croak("Error resetting filehandle: $!");

    return;
}

sub populate_data_sets : PRIVATE {

    my ( $self, $set, $num_data_sets ) = @_;

    # Recursion end point.
    return unless $num_data_sets;

    $set ||= $self->get_data_set( 0 )
	or croak("Error: Initial data set not created.");

    my $next_pos = $set->get_next_set_position()
	or croak("Error: Data set gives no position for next set.");

    my $next_set = ArrayExpress::Datafile::Affymetrix::Calvin::DataSet->new({
	filehandle => $self->get_filehandle(),
	position   => $next_pos,
    });
    push @{ $data_set{ ident $self } }, $next_set;

    # We need to recurse across sets here until we run out of data
    # sets.
    $self->populate_data_sets( $next_set, $num_data_sets - 1 );

    return;
}

sub get_data_set {

    my ( $self, $num ) = @_;

    # These should all have been created in START.
    unless ( defined $data_set{ ident $self }[ $num ] ) {
	croak("Error: No data set found for number $num");
    }

    return $data_set{ ident $self }[ $num ];
}

1;
