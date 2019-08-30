#!/usr/bin/env perl
#
# EBI/FGPT/Resource/BioPortal/Object.pm
# 
# Anna Farne 2012 ArrayExpress team, EBI
#
# $Id: Object.pm 19968 2012-06-07 15:15:50Z farne $
#

package EBI::FGPT::Resource::BioPortal::Object;

use Moose;
use MooseX::FollowPBP;

use 5.008008;

use Carp;
use English qw( -no_match_vars );

use JSON;
use Data::Dumper;

has 'json_string' => (is => 'rw', isa => 'Str', required => 1);
has 'json' => (is => 'rw', isa => 'HashRef', builder => '_parse_json', lazy => 1);
has 'id'   => (is => 'rw', isa => 'Str', builder => '_find_id', lazy => 1);
has 'bean_type' => (is => 'rw', isa => 'Str', required => 1);

sub _parse_json{
	
	my ($self) = @_;
	
	my $json = decode_json($self->get_json_string)
	or croak("Could not parse JSON string");
	
	# FIXME: should check for more than 1 result here
	my $result = $json->{'success'}->{'data'}->[0]->{$self->get_bean_type}
	or croak("JSON response contains no ".$self->get_bean_type);
	
	$self->set_json($result);
}

sub _find_id{
	
	my ($self) = @_;
	
	my $id = $self->get_json->{'id'};	
	$self->set_id($id);
}
1;