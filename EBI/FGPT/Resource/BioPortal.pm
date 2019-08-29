#!/usr/bin/env perl
#
# Emma Hastings, European Bioinformatics Institute, 2014

=head1 NAME

BioPortal
 
=head1 DESCRIPTION

This module queries BioPortal API for a given term in a given ontology.
A subtree can be supplied which resticts searches to within that branch.

http://data.bioontology.org/documentation


=head1 SYNOPSIS
	
my $bp = BioPortal->new(
	subtree_root => "http%3A%2F%2Fpurl.obolibrary.org%2Fobo%2FUO_0000000",
	ontology => "EFO",
	exact_match => "true"

);

my $match1 = $bp->query_unit_term("nanomole");


=head1 AUTHOR

Expression Atlas team <arrayexpress-atlas@ebi.ac.uk>
Emma Hastings , <emma@ebi.ac.uk>

Created MAY-JUNE 2014
 
=head1 COPYRIGHT AND LICENSE

Copyright [2011] EMBL - European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the
"License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at
http://www.apache.org/licenses/LICENSE-2.0
Unless required by applicable law or agreed to in writing,
software distributed under the License is distributed on an
"AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
either express or implied. See the License for the specific
language governing permissions and limitations under the
License.

=cut

package EBI::FGPT::Resource::BioPortal;

use Moose;
use MooseX::FollowPBP;
use English qw( -no_match_vars );
use JSON;
use Log::Log4perl qw(:easy);
use Data::Dumper;
use EBI::FGPT::Config qw($CONFIG);
use Config::YAML;

extends 'EBI::FGPT::Resource';

has 'apikey'   => ( is => 'rw', isa => 'Str', default => $CONFIG->get_BIOPORTAL_API_KEY );
has 'base_uri' => ( is => 'rw', isa => 'Str', default => 'http://data.bioontology.org/' );
has 'subtree_root' => ( is => 'rw', isa => 'Str' );
has 'ontology'     => ( is => 'rw', isa => 'Str', default => "EFO" );
has 'exact_match'  => ( is => 'rw', isa => 'Str', default => "true" );

# Temporary list of allowed terms from flat file.
has 'allowed_terms' => (
    is      => 'rw',
    isa     => 'Config::YAML',
    lazy    => 1,
    builder => '_build_allowed_terms',
    required    => 1
);


after '_create_agent' => sub {

	my ($self) = @_;

	# We want to get results in JSON when querying BioPortal
	$self->get_user_agent->default_header( 'Accept' => 'application/json' );
};

=over

=item query_adf_term()

Temporary workaround, BioPortal query is broken as of July 2015. Finds the
exact match for the supplied term in the config file.

=cut

sub query_adf_term {

    my ( $self, $term ) = @_;

	if ( not defined $term or $term =~ /^ *$/ ) {
		return;
	}
    
	# Tidy up term
	$term =~ s/\s+$//;
        
    # Get all the allowed terms.
    my $allowedTerms = $self->get_allowed_terms;

    # Get just the ADF terms
    my %allowedAdfTerms = map { $_ => 1 } @{ $allowedTerms->get_adf_terms };
    
    # If we have a match, return it in an array.
    if( $allowedAdfTerms{ $term } ) {
        
        my @results = ( $term );

        return \@results;
    
    } 
    # Otherwise, return nothing.
    else {
        return;
    }
}


=item query_unit_term()

Temporary workaround, BioPortal query is broken as of July 2015. Finds the
exact match for the supplied term in the config file.

=cut

sub query_unit_term {

    my ( $self, $term ) = @_;

	if ( not defined $term or $term =~ /^ *$/ ) {
		return;
	}
    
	# Tidy up term
	$term =~ s/\s+$//;
        
    # Get all the allowed terms.
    my $allowedTerms = $self->get_allowed_terms;

    # Get just the ADF terms
    my %allowedUnitTerms = map { $_ => 1 } @{ $allowedTerms->get_units };
    
    # If we have a match, return it in an array.
    if( $allowedUnitTerms{ $term } ) {
        
        my @results = ( $term );

        return \@results;
    
    } 
    # Otherwise, return nothing.
    else {
        return;
    }
}


sub _build_allowed_terms {

    my ( $self ) = @_;

    my $list_path = $CONFIG->get_ONTO_TERMS_LIST;
    my $allowedTerms = Config::YAML->new( config => $list_path );

    return $allowedTerms;
}


# OLD QUERY FUNCTION -- this is broken as of July 2015.
#--------------------------------------------------
# sub query_term
#-------------------------------------------------- 
#--------------------------------------------------
# {
#-------------------------------------------------- 
	#--------------------------------------------------
	# my ( $self, $term ) = @_;
	# my $match;
	# my $uri;
	# my @prefered_labels;
	#-------------------------------------------------- 

	#--------------------------------------------------
	# # Return if term is empty or just spaces
	# if ( not defined $term or $term =~ /^ *$/ )
	# {
	# 	return;
	# }
	#-------------------------------------------------- 

	#--------------------------------------------------
	# # Tidy up term
	# $term =~ s/\s+$//;
	#-------------------------------------------------- 

	#--------------------------------------------------
	# if ( $self->get_subtree_root )
	# {
	# 	$uri =
	# 	    $self->get_base_uri
	# 	  . "search?q="
	# 	  . $term
	# 	  . "&ontology="
	# 	  . $self->get_ontology
	# 	  . "&subtree_root="
	# 	  . $self->get_subtree_root
	# 	  . "&exact_match="
	# 	  . $self->get_exact_match
	# 	  . "&apikey="
	# 	  . $self->get_apikey;
	# }
	#-------------------------------------------------- 

	#--------------------------------------------------
	# else
	# {
	# 	$uri =
	# 	    $self->get_base_uri
	# 	  . "search?q="
	# 	  . $term
	# 	  . "&ontologies="
	# 	  . $self->get_ontology
	# 	  . "&exact_match="
	# 	  . $self->get_exact_match
	# 	  . "&apikey="
	# 	  . $self->get_apikey;
	# }
	#-------------------------------------------------- 

	#--------------------------------------------------
	# my $ua = $self->get_user_agent;
	# if ( my $proxy = $CONFIG->get_HTTP_PROXY )
	# {
	#-------------------------------------------------- 

	#--------------------------------------------------
	# 	# Using proxy because we're accessing an external site
	# 	$ua->proxy( [ 'http', 'ftp' ], $proxy );
	# }
	#-------------------------------------------------- 

	#--------------------------------------------------
	# my $response = $ua->get($uri);
	# my $json_result;
	#-------------------------------------------------- 

	#--------------------------------------------------
	# if ( $response->is_success )
	# {
	# 	$json_result = decode_json( $response->content );
	# }
	# else
	# {
	# 	FATAL "Could not get information from $uri: " . $response->status_line;
	# }
	#-------------------------------------------------- 

	#--------------------------------------------------
	# if ($json_result)
	# {
	# 	my $results = $json_result->{'collection'};
	#-------------------------------------------------- 

	#--------------------------------------------------
	# 	# Avoid empty results
	# 	if (@$results)
	# 	{
	# 		INFO "Result found for $term";
	# 		foreach my $result (@$results)
	# 		{
	# 			$match = $result->{'prefLabel'};
	#-------------------------------------------------- 

	#--------------------------------------------------
	# 			# Check for exact match
	# 			if ( $term eq $match )
	# 			{
	# 				INFO "prefLabel $match found which is an match for $term";
	# 				push @prefered_labels, $match;
	# 			}
	#-------------------------------------------------- 

	#--------------------------------------------------
	# 			# Term supplied is probably a synonym
	# 			else
	# 			{
	# 				INFO
	#-------------------------------------------------- 
#--------------------------------------------------
# "No prefLabel found exactly matching $term, likely its a synonym of $match";
#-------------------------------------------------- 
	#--------------------------------------------------
	# 				push @prefered_labels, $match;
	# 			}
	# 		}
	# 		return \@prefered_labels;
	# 	}
	#-------------------------------------------------- 

	#--------------------------------------------------
	# 	else
	# 	{
	# 		WARN "No result returned for $term";
	# 		return;
	# 	}
	#-------------------------------------------------- 

	#--------------------------------------------------
	# }
	#-------------------------------------------------- 

	#--------------------------------------------------
	# else { ERROR "No json content returned from query"; }
	#-------------------------------------------------- 
#--------------------------------------------------
# }
#-------------------------------------------------- 

__PACKAGE__->meta->make_immutable;

1;
