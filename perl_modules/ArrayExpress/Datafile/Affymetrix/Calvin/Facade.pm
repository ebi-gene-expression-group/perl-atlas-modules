#!/usr/bin/env perl
#
# $Id: Facade.pm 1984 2008-03-03 17:47:18Z tfrayner $

use strict;
use warnings;

package ArrayExpress::Datafile::Affymetrix::Calvin::Facade;
use base qw(ArrayExpress::Datafile::Affymetrix::Calvin::Generic);

use Class::Std;
use Carp;

my %data_set    : ATTR( :name<data_set>,    :default<undef> );
my %chip_type   : ATTR( :name<chip_type>,   :default<undef> );
my %algorithm   : ATTR( :name<algorithm>,   :default<undef> );
my %parameters  : ATTR( :get<parameters>,   :default<{}> );
my %stats       : ATTR( :get<stats>,        :default<{}> );
my %qtd         : ATTR( :name<qtd>,         :default<[]> );
my %ded         : ATTR( :set<ded>,          :default<[]> );
my %headings    : ATTR( :name<headings>,    :default<[]> );

sub START {

    my ( $self, $id, $args ) = @_;

    my $group    = $self->get_data_group(0);
    my $data_set = $group->get_data_set(0);

    $self->set_data_set( $data_set );

    # Num_columns and num_rows are only really available to the CEL
    # subclass.
    my %param2attr = (
	'affymetrix-algorithm-name' => 'set_algorithm',
	'affymetrix-array-type'     => 'set_chip_type',
	'affymetrix-cel-cols'       => 'set_num_columns',
	'affymetrix-cel-rows'       => 'set_num_rows',
    );

    my $params = $self->get_data_header()->get_parameters();
    my $pname;
    foreach my $param ( @$params ) {
	my $setter = $param2attr{ $param->get_name() };
	if ( $setter && $self->can($setter) ) {
	    $self->$setter( $param->get_value() );
	}
	elsif ( ( $pname )
	     = ( $param->get_name() =~ m/affymetrix-algorithm-param-(.*)/xms ) ) {
	    $self->add_parameter( $pname, $param->get_value() );
	}
	elsif ( ( $pname )
	     = ( $param->get_name() =~ m/affymetrix-chipsummary-(.*)/xms ) ) {
	    $self->add_stat( $pname, $param->get_value() );
	}
    }

    my $columns = $data_set->get_data_columns();
    my ( @headings, @qts );
    foreach my $col ( @$columns ) {
	push @headings, $col->get_name();
	push @qts, 'Affymetrix:QuantitationType:' . $col->get_name();
    }

    $self->set_headings( \@headings );
    $self->set_qtd( \@qts );
}

sub add_parameter : RESTRICTED {

    my ( $self, $key, $value ) = @_;

    $parameters{ ident $self }{ $key } = $value;

    return;
}

sub add_stat : RESTRICTED {

    my ( $self, $key, $value ) = @_;

    $stats{ ident $self }{ $key } = $value;

    return;
}

sub export {

    my ( $self, $output_fh, $cdf ) = @_;

    my $data_set  = $self->get_data_set();
    my $data_type = $self->get_data_header()->get_data_type();

    $data_set->export( $output_fh );

    return;
}

sub parse {
    # Dummy method - the Calvin parser does everything on
    # instantiation, but this is part of the published API.
}

sub parse_header {
    # Dummy method - the Calvin parser does everything on
    # instantiation, but this is part of the published API.
}

sub generate_ded : RESTRICTED {

    my ( $self ) = @_;

    croak("Error: Stub method called in abstract superclass.");
}

sub get_ded {

    my ( $self, $cdf, $chip_type ) = @_;

    unless ( scalar @{ $ded{ ident $self } } ) {
	$self->generate_ded();
    }

    return $ded{ ident $self };
}

1;
