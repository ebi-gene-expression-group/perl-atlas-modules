#!/usr/bin/env perl
#


package EBI::FGPT::Resource::OLS;

use 5.10.0;
use Moose;
use MooseX::FollowPBP;
use JSON::Parse qw( parse_json );
use URI::Escape;
use Atlas::Common qw( make_http_request );

extends 'EBI::FGPT::Resource';

has 'ols_api_base' => (
    is => 'rw',
    isa => 'Str',
    default => 'http://www.ebi.ac.uk/ols/api/',
);

has 'ontologies' => (
    is => 'rw',
    isa => 'ArrayRef',
    default => sub { [ 'efo' ] },
);

has 'query_fields' => (
    is => 'rw',
    isa => 'ArrayRef',
    default => sub { [ 'label', 'synonym' ] },
);

has 'exact_match' => (
    is => 'rw',
    isa => 'Bool',
    default => 1
);


after '_create_agent' => sub {
    
    my ( $self ) = @_;
    
    $self->get_user_agent->default_header( 'Accept' => 'application/json' );
};


sub query_unit_term {

    my ( $self, $term ) = @_;

    # Return nothing if this is just a load of spaces.
    if( not defined $term or $term =~ /^ *$/ ) { 
        
        $self->debug( "Term is empty, will not query EFO." );

        return; 
    }

    # Remove spaces from the end (if any).
    $term =~ s/\s+$//;

    # Encode as UTF8.
    my $term4url = uri_escape_utf8( $term );

    # Create the query URL.
    my $url = $self->get_ols_api_base .
                "search?q=" .
                $term4url .
                "&ontology=" .
                _to_comma_separated_string( $self->get_ontologies ) .
                "&queryFields=" .
                _to_comma_separated_string( $self->get_query_fields ) .
                "&childrenOf=http://purl.obolibrary.org/obo/UO_0000000";

    # Add exact match if appropriate.
    if( $self->get_exact_match ) { $url .= "&exact=true"; }
    
    # Create the results hash here. We will return no results if the call to
    # OLS is unsuccessful due to OLS being unresponsive, as well as logging
    # that this has happened.
    my $resultsHash = {
        matched_label   => 0,
        possible_match  => 0,
        label           => undef
    };

    my $json = make_http_request( $url, "json" );

    unless( $json ) { return $resultsHash; }
    
    my $result = parse_json( $json );

    # Next we need to get interesting stuff out of the results. Most of this is
    # in the "response" section of the JSON.
    my $OLSJsonResponse = $result->{ "response" };

    # First, if there are no results, we can't continue.
    if( $OLSJsonResponse->{ "numFound" } == 0 ) { return $resultsHash; }
    
    # If there were some results, we want to have a look at them and try to
    # find the right one.
    my $matchingClasses = $OLSJsonResponse->{ "docs" };

    # First, see if there's a class with a label identical to our term.
    foreach my $class ( @{ $matchingClasses } ) {

        my $classLabel = $class->{ "label" };

        # If so, we can return here, everything is OK.
        if( $classLabel eq $term ) {
            
            $resultsHash->{ "label" } = $classLabel;
            $resultsHash->{ "matched_label" } = 1;

            return $resultsHash;
        }
        # If not, check if the casing is the problem. Return with possible
        # match if so.
        elsif( lc( $classLabel ) eq lc( $term ) ) {

            $resultsHash->{ "label" } = $classLabel;
            $resultsHash->{ "possible_match" } = 1;
        }
    }

    # If we're still here, maybe a synonym has matched, so have a look at
    # those. Matches to synonyms are stored in the "highlighting" section of
    # the JSON.
    my $OLSJsonHighlighting = $result->{ "highlighting" };

    foreach my $efoID ( keys %{ $OLSJsonHighlighting } ) {

        # If it had a matching label we'd have already returned so only look at
        # ones without labels.
        if( $OLSJsonHighlighting->{ $efoID }->{ "label" } ) { next; }

        if( $OLSJsonHighlighting->{ $efoID }->{ "synonym" } ) {

            my $matchingSynonyms = $OLSJsonHighlighting->{ $efoID }->{ "synonym" };
            
            foreach my $matchingSynonym ( @{ $matchingSynonyms } ) {

                # Remove the HTML tags.
                $matchingSynonym =~ s/<b>//g;
                $matchingSynonym =~ s/<\/b>//g;

                # Check that we really have a match. Don't need to check both
                # casings as we're not going to say this one is OK anyway, but just
                # suggest to the curator to use the label instead.
                if( lc( $matchingSynonym ) eq lc( $term ) ) {

                    # Get the label for this EFO ID.
                    foreach my $class ( @{ $matchingClasses } ) {

                        my $classID = $class->{ "id" };
                        
                        if( $classID eq $efoID ) {

                            $resultsHash->{ "possible_match" } = 1;
                            $resultsHash->{ "label" } = $class->{ "label" };

                            return $resultsHash;
                        }
                    }
                }
            }
        }
    }
    
    # If we're still here, we didn't get a matching label or synonym, so just
    # return the hash with no results.
    return $resultsHash;
}   


sub _to_comma_separated_string {

    my ( $values ) = @_;

    my $string = join ",", @{ $values };
    
    return $string;
}


1;
