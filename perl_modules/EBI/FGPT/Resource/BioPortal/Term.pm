#!/usr/bin/env perl
#
# EBI/FGPT/Resource/BioPortal/Term.pm
# 
# Anna Farne 2012 ArrayExpress team, EBI
#
# $Id: Term.pm 19968 2012-06-07 15:15:50Z farne $
#

package EBI::FGPT::Resource::BioPortal::Term;

use Moose;
use MooseX::FollowPBP;

use 5.008008;

use Carp;
use English qw( -no_match_vars );
use Data::Dumper;
use JSON;

use Log::Log4perl qw(:easy);

extends 'EBI::FGPT::Resource::BioPortal::Object';

has 'label' => ( is => 'rw', isa => 'Str', builder => '_find_label', lazy => 1);
has 'subclasses' => ( is => 'rw', isa => 'ArrayRef', builder=>'_find_subclasses', lazy =>1 );
has 'is_partial' => ( is => 'rw', isa=> 'Bool', default => 0);

sub BUILDARGS{
	
	my ($self, $args) = @_;
	$args->{bean_type} = "classBean";
	
	return $args;
}

sub _find_label{
	
	my ($self) = @_;
	my $json = $self->get_json;
	
	my $label = $json->{'label'};
	
	ERROR "Could not find label for term ".$self->get_id unless $label;
	
	$self->set_label($label);
}

sub _find_subclasses{
	
	my ($self) = @_;
	my $json = $self->get_json;
	
	my @subclasses;
	
	my $relation_entry = $json->{'relations'}->[0]->{'entry'};
	foreach my $entry (@{ $relation_entry || []}){
		
		if($entry->{'string'} eq 'SubClass'){
		
			my $subclasses = $entry->{'list'}->[0]->{'classBean'};
			
			if (ref $subclasses eq "HASH"){
				$subclasses = [$subclasses];
			}
			
			foreach my $class (@{ $subclasses || [] }){

			    my $id = $class->{'id'};
			    
			    # FIXME. should allow a term to be created with json or json_string
			    my $new_term = __PACKAGE__->new({ 
			    	json => $class,
			    	json_string => "partial object",
			    	is_partial => 1,
			    });
			    push @subclasses, $new_term;
			    DEBUG "Found subclass ID: $id\n";
			}
		}
	}
	
	$self->set_subclasses(\@subclasses);
}
1;