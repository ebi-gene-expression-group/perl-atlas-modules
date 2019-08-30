#!/usr/bin/env perl
#
# EBI/FGPT/Resource/BioPortal/Ontology.pm
# 
# Anna Farne 2012 ArrayExpress team, EBI
#
# $Id: Ontology.pm 19968 2012-06-07 15:15:50Z farne $
#

package EBI::FGPT::Resource::BioPortal::Ontology;

use Moose;
use MooseX::FollowPBP;

use 5.008008;

use Carp;
use English qw( -no_match_vars );

use Data::Dumper;
use Log::Log4perl qw(:easy);

extends 'EBI::FGPT::Resource::BioPortal::Object';

has 'virtual_id'   => (is => 'rw', isa => 'Str', builder => '_find_virtual_id', lazy => 1);
has 'version'      => (is => 'rw', isa => 'Str', builder => '_find_version', lazy => 1);
has 'release_date' => (is => 'rw', isa => 'Str', builder => '_find_release_date', lazy => 1);

sub BUILDARGS{
	
	my ($self, $args) = @_;
	$args->{bean_type} = "ontologyBean";
	
	return $args;
}

sub _find_attribute{
	my ($self, $att) = @_;
	
	my $value = $self->get_json->{$att};
	
	ERROR "Could not find $att for ontology" unless $value;
	
	return $value;
}

sub _find_release_date{
	
	my ($self) = @_;
	
	return $self->_find_attribute("dateReleased");
}

sub _find_version{
	
	my ($self) = @_;
	
	return $self->_find_attribute("versionNumber");
}

sub _find_virtual_id{
	
	my ($self) = @_;
	
	return $self->_find_attribute("ontologyId");	
}
1;