#!/usr/bin/env perl
#
# EBI/FGPT/Reader/MAGETAB/Builder.pm
# 
# Anna Farne 2012 ArrayExpress team, EBI
#
# $Id: Builder.pm 19690 2012-04-30 16:11:39Z farne $
#

=pod

=head1 NAME

EBI::FGPT::Reader::MAGETAB::Builder

=head1 DESCRIPTION

A custom Bio::MAGETAB::Util::Builder which allows certain MAGETAB objects to
be undeclared even when not using a "relaxed" parser.

Objects that can be undeclared because they are assumed to be in ArrayExpress are:

ArrayDesign
Reporter
CompositeElement

=cut

package EBI::FGPT::Reader::MAGETAB::Builder;

use Moose;
use MooseX::FollowPBP;

use 5.008008;
use strict;
use warnings;
use English qw( -no_match_vars );
use Carp;
use Data::Dumper;

use Log::Log4perl qw(:easy);

extends 'Bio::MAGETAB::Util::Builder';

has 'allow_undeclared' => (
                           is => 'rw', 
                           isa => 'HashRef', 
                           default =>sub{ {
                           	'Bio::MAGETAB::CompositeElement' => 1,
                           	'Bio::MAGETAB::Reporter' => 1,
                            'Bio::MAGETAB::ArrayDesign' => 1,
                           } },
                           );

has 'tech_type_default' => (is => 'rw', isa => 'Str');

override '_get_object' => sub {

    my ( $self, $class, $data, $id_fields ) = @_;
 
    # The matrix file check provides a default tech type value so that
    # undefined assays can be created and reported later
    if ($class eq "Bio::MAGETAB::Assay" and not $data->{technologyType}){
    	my $tech_type = Bio::MAGETAB::ControlledTerm->new({ 
    		category => "TechnologyType", 
    		value    => $self->get_tech_type_default,
    	});
    	$data->{technologyType} = $tech_type;
    }
    
    my $id = $self->_create_id( $class, $data, $id_fields );

    # Strip out aggregator identifier components.
    $data = $self->_strip_aggregator_info( $class, $data );

    if ( my $retval = $self->get_database()->{ $class }{ $id } ) {
        return $retval;
    }
    elsif ( $class eq "Bio::MAGETAB::Protocol"){
    	# Complain that the protocol is not declared and has no term source
    	# then create it anyway. This is just so a more meaningful error can
    	# be given to user
        my $retval;
        ERROR ("Undeclared protocol used (name: ",$data->{name},")");
        eval {
            $retval = $self->_find_or_create_object( $class, $data, $id_fields );
        };
        if ( $EVAL_ERROR ) {
            croak(qq{Error: Unable to autogenerate $class with ID "$id": $EVAL_ERROR\n});
        }
        return $retval;    	
    }
    elsif ( $self->get_relaxed_parser() or $self->get_allow_undeclared->{$class}) {
        # If we're relaxing constraints, try and create an
        # empty object (in most cases this will probably fail
        # anyway).
        eval {
            $retval = $self->_find_or_create_object( $class, $data, $id_fields );
        };
        if ( $EVAL_ERROR ) {
            croak(qq{Error: Unable to autogenerate $class with ID "$id": $EVAL_ERROR\n});
        }
        return $retval
    }
    else {
        croak(qq{Error: $class with ID "$id" is unknown.\n});
    }
};

1;