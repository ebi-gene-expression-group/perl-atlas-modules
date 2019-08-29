#!/usr/bin/env perl
#
# $Id: CHP.pm 1982 2008-02-28 22:48:40Z tfrayner $

use strict;
use warnings;

package ArrayExpress::Datafile::Affymetrix::Calvin::CHP;
use base qw(ArrayExpress::Datafile::Affymetrix::Calvin::Facade);

use Class::Std;
use Carp;

sub export {

    my ( $self, $output_fh, $cdf ) = @_;

    my $data_set  = $self->get_data_set();
    my $data_type = $self->get_data_header()->get_data_type();

    # MAS5 results incorporates a value mapping. FIXME how to fall
    # back to 'No Call'?
    if ( $data_type eq 'affymetrix-expression-probeset-analysis' ) {
	$data_set->set_value_mapping(
	    [undef,{
		0 => 'Present',
		1 => 'Marginal',
		2 => 'Absent',
	    },undef,undef,undef,undef]
	);
    }

    $data_set->export( $output_fh );

    return;
}

sub generate_ded : RESTRICTED {

    my ( $self ) = @_;

    my $data_set  = $self->get_data_set();
    my $chip_type = $self->get_chip_type()
	or croak("Error: Chip type is not known.");

    my $fh  = $data_set->get_filehandle() or croak("Error: No filehandle.");
    my $pos = $data_set->get_data_table_start()
	or croak("Error: No data table start position.");

    # The systell function doesn't exist, we use this instead.
    my $init_pos = sysseek( $fh, 0, 1 );

    # Seek to data_table_start, create array of column readers,
    # and write the return values for each row to $output_fh.
    sysseek( $fh, $pos, 0 )
	or croak("Error resetting filehandle: $!");

    my @ded;
    my $columns  = $data_set->get_data_columns();
    my $id_col   = $columns->[0];
    my $reader   = $id_col->get_reader();
    my $size     = $id_col->get_size();
    my $other    = 0;
    my $num_cols = scalar( @{ $columns } );
    for ( my $i = 1; $i < $num_cols; $i++ ) {
	$other += $columns->[$i]->get_size();
    }
    for ( 1..$data_set->get_num_data_rows() ) {
	my $name = $reader->( $fh, $size );
	push @ded, "Affymetrix:CompositeSequence:$chip_type:$name";
	sysseek( $fh, $other, 1 );
    }

    $self->set_ded( \@ded );

    # Reset the filehandle.
    sysseek( $fh, $init_pos, 0 )
	or croak("Error resetting filehandle: $!");

    return;
}

1;
