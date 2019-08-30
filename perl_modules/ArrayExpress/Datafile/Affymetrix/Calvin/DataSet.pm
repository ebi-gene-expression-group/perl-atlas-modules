#!/usr/bin/env perl
#
# $Id: DataSet.pm 1984 2008-03-03 17:47:18Z tfrayner $

use strict;
use warnings;

package ArrayExpress::Datafile::Affymetrix::Calvin::DataSet;
use base qw(ArrayExpress::Datafile::Affymetrix::Calvin::Component);

use Class::Std;
use Carp;

require ArrayExpress::Datafile::Affymetrix::Calvin::DataColumn;

use ArrayExpress::Datafile::Affymetrix::Calvin::Binary qw(
    get_signed_char
    get_signed_integer
    get_unsigned_integer
    get_wstring
);

my %next_set_position   : ATTR( :name<next_set_position>,   :default<undef> );
my %name                : ATTR( :name<name>,                :default<undef> );
my %num_data_rows       : ATTR( :name<num_data_rows>,       :default<undef> );
my %data_table_start    : ATTR( :name<data_table_start>,    :default<undef> );
my %data_columns        : ATTR( :name<data_columns>,        :default<[]>    );
my %value_mapping       : ATTR( :name<value_mapping>,       :default<[]>    );

sub START {

    my ( $self, $id, $args ) = @_;

    my $fh  = $self->get_filehandle() or croak("Error: No filehandle.");
    my $pos = $self->get_position()   or croak("Error: No file position.");

    # The systell function doesn't exist, we use this instead.
    my $init_pos = sysseek( $fh, 0, 1 );

    sysseek( $fh, $pos, 0 )
	or croak("Error resetting filehandle: $!");

    $self->set_data_table_start( get_unsigned_integer( $fh ) );
    $self->set_next_set_position( get_unsigned_integer( $fh ) );
    $self->set_name( get_wstring( $fh ) );

    my $num_parameters = get_signed_integer( $fh );
    for ( 1..$num_parameters ) {
	my $param = $self->parse_parameter( $fh );
	$self->add_parameters( $param );
    }

    my $num_columns = get_unsigned_integer( $fh );

    for ( 1..$num_columns ) {
	my $cname = get_wstring( $fh );
	my $ctype = get_signed_char( $fh );
	my $csize = get_signed_integer( $fh );
	my $column = ArrayExpress::Datafile::Affymetrix::Calvin::DataColumn->new({
	    name => $cname,
	    type => $ctype,
	    size => $csize,
	});
	$self->add_data_columns( $column );
    }

    $self->set_num_data_rows( get_unsigned_integer( $fh ) );

    # Reset the filehandle.
    sysseek( $fh, $init_pos, 0 )
	or croak("Error resetting filehandle: $!");

    return;
}

sub export {

    my ( $self, $output_fh ) = @_;

    my $fh  = $self->get_filehandle() or croak("Error: No filehandle.");
    my $pos = $self->get_data_table_start()
	or croak("Error: No data table start position.");

    # The systell function doesn't exist, we use this instead.
    my $init_pos = sysseek( $fh, 0, 1 );

    # Seek to data_table_start, create array of column readers,
    # and write the return values for each row to $output_fh.
    sysseek( $fh, $pos, 0 )
	or croak("Error resetting filehandle: $!");

    # Our column readers are created as an array of closures.
    my $readers = $self->get_data_readers();
    my $mappers = $self->get_value_mapping();

    # Read the values in, and use any (optional) mappings to modify
    # the output data on the fly.
    for ( 1..$self->get_num_data_rows() ) {
	my @row_values;
	foreach my $i ( 0..$#$readers ) {
	    my $val = $readers->[$i]->();
	    if ( my $map = $mappers->[$i] ) {
		$val = $map->{$val};
	    }
	    push @row_values, $val;
	}
	print $output_fh (join("\t", @row_values), "\n");
    }

    # Reset the filehandle.
    sysseek( $fh, $init_pos, 0 )
	or croak("Error resetting filehandle: $!");

    return;
}

sub get_data_readers {

    my ( $self ) = @_;

    my $fh = $self->get_filehandle() or croak("Error: No filehandle.");

    # Our column readers are created as an array of closures. Note
    # that before you use these you need to sysseek to
    # $self->get_data_table_start().
    my @readers = map {
	my $x = $_;
	sub { $x->get_reader()->( $fh, $x->get_size() ) };
    } @{ $self->get_data_columns() };

    return \@readers;
}

sub add_data_columns : PRIVATE {

    my ( $self, @columns ) = @_;

    push @{ $data_columns{ ident $self } }, @columns;

    return;
}

1;
