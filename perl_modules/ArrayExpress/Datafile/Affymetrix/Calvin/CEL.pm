#!/usr/bin/env perl
#
# $Id: CEL.pm 1984 2008-03-03 17:47:18Z tfrayner $

use strict;
use warnings;

package ArrayExpress::Datafile::Affymetrix::Calvin::CEL;
use base qw(ArrayExpress::Datafile::Affymetrix::Calvin::Facade);

use Class::Std;
use Carp;
use Readonly;

# The parent class knows how to populate these.
my %num_columns   : ATTR( :name<num_columns>,   :default<undef> );
my %num_rows      : ATTR( :name<num_rows>,      :default<undef> );

Readonly my @DATA_SET_NAMES => qw(Intensity StdDev Pixel Outlier Mask);

sub START {

    my ( $self, $id, $args ) = @_;

    # Sort out the QTD here.
    my $data_group = $self->get_data_group(0);
    my $num_sets   = $data_group->get_num_data_sets();

    my @qtd = map { "Affymetrix:QuantitationType:$_" } @DATA_SET_NAMES;
    $self->set_qtd( \@qtd );
    $self->set_headings( \@DATA_SET_NAMES );

    return;
}

sub export {

    my ( $self, $output_fh ) = @_;

    my $fh = $self->get_filehandle() or croak("Error: No filehandle.");

    # The systell function doesn't exist, we use this instead.
    my $init_pos = sysseek( $fh, 0, 1 );

    my $data_group = $self->get_data_group(0);
    my $num_sets   = $data_group->get_num_data_sets();

    # One big data set in memory. Not a good way to do things, but the
    # alternative is a lot of seeking in the file, which we're not
    # really set up for. Why does Affy insist on breaking up the CEL
    # data this way?
    my ( @data, %outlier, %mask );
    for ( my $i = 0; $i < $num_sets; $i++ ) {

	my $data_set = $data_group->get_data_set( $i );
	my $set_name = $data_set->get_name();
	my $readers  = $data_set->get_data_readers();

	sysseek( $fh, $data_set->get_data_table_start(), 0 )
	    or croak("Error seeking in filehandle: $!");

	# N.B. the following assumes that Intensity, StdDev and Pixel
	# data sets all have the same number and order of design
	# elements.
	for ( 1..$data_set->get_num_data_rows() ) {

	    if ( $set_name eq 'Outlier' ) {
		my ( $x, $y ) = map { $_->() } @$readers;
		$outlier{"$x,$y"}++;
	    }
	    elsif ( $set_name eq 'Mask' ) {
		my ( $x, $y ) = map { $_->() } @$readers;
		$mask{"$x,$y"}++ if ( defined $x && defined $y );
	    }
	    else {

		# There should only be one reader per set here, but if
		# not for some reason the values are joined with '|'.
		my $row = join("|", map { $_->() } @$readers);
		push @{ $data[$i] }, $row;
	    }
	}
    }

    # Y is rows, X is columns.
    for ( my $y = 0; $y < $self->get_num_rows(); $y++ ) {
        for ( my $x = 0; $x < $self->get_num_columns(); $x++ ) {
	    my @values = map { shift( @{ $data[$_] } ) } qw( 0 1 2 );
	    push @values, $outlier{ "$x,$y" } ? 'true' : 'false';
	    push @values, $mask   { "$x,$y" } ? 'true' : 'false';
	    print $output_fh (join("\t", @values), "\n");
        }
    }

    # Reset the filehandle.
    sysseek( $fh, $init_pos, 0 )
	or croak("Error resetting filehandle: $!");

    return;
}

sub generate_ded : RESTRICTED {

    my ( $self ) = @_;

    my $chip_type = $self->get_chip_type()
	or croak("Error: Chip type is not known.");

    my @ded;

    # Y is rows, X is columns.
    for ( my $y = 0; $y < $self->get_num_rows(); $y++ ) {
        for ( my $x = 0; $x < $self->get_num_columns(); $x++ ) {
	    push @ded, sprintf(
		"Affymetrix:Feature:$chip_type:Probe(%d,%d)", $x, $y,
	    );
        }
    }

    $self->set_ded( \@ded );

    return;
}

1;
