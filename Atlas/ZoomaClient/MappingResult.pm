#!/usr/bin/env perl
#
=pod

=head1 NAME

Atlas::ZoomaClient::MappingResult - object containing mapping annotation
summaries, mapping category and ontology URI(s).

=head1 SYNOPSIS

    use Atlas::ZoomaClient::MappingResult;

    #...

    my $mappingResult = Atlas::ZoomaClient::MappingResult->new( zooma_results => $zoomaResults );

=head1 DESCRIPTION

An Atlas::ZoomaClient::MappingResult decides the mapping category and ontology
URI(s) to map a term to based on an array of
Atlas::ZoomaClient::ZoomaResult objects passed to it on instantiation.

=cut

package Atlas::ZoomaClient::MappingResult;

use 5.10.0;

use Moose;
use MooseX::FollowPBP;
use Moose::Util::TypeConstraints;
use Data::Dumper;
use Log::Log4perl;
use Atlas::Common qw( make_http_request );
use JSON::Parse qw( parse_json );

=head1 ATTRIBUTES

=over 2

=item zooma_results

Array ref containing the results from Zooma.

=cut

has zooma_results => (
    is => 'rw',
    isa => 'ArrayRef',
    predicate => 'has_zooma_results'
);

=item mapping_category

String describing the category of this mapping e.g. "AUTOMATIC", "REQUIRES_CURATION", ...

=cut

has mapping_category => (
    is => 'rw',
    isa => enum( [ qw(
            AUTOMATIC
            REQUIRES_CURATION
            NO_RESULTS
            EXCLUDED
    )]),
    predicate => 'has_mapping_category',
);

=item ontology_mapping

String representing the URI(s) this term is mapped to. Multiple URIs are separated by spaces.

=cut

has ontology_mapping => (
    is => 'rw',
    isa => 'Str',
    predicate => 'has_ontology_mapping',
);

=item zooma_property_value

Property value annotated in Zooma.

=cut

has zooma_property_value => (
    is => 'rw',
    isa => 'Str',
    predicate => 'has_zooma_property_value'
);

=item ontology_label

Preferred name of term.

=cut

has ontology_label => (
    is => 'rw',
    isa => 'Str',
    predicate => 'has_ontology_label'
);

=item reason_for_exclusion

=cut

has reason_for_exclusion => (
    is => 'rw',
    isa => 'Str',
    predicate => 'has_reason_for_exclusion'
);

=item zooma_error

A string containing an error message.

=cut

has zooma_error => (
    is => 'rw',
    isa => 'Str',
    predicate => 'has_zooma_error',
);

=item ols_api_base

The base URL for OLS API.

=cut

has ols_api_base => (
    is => 'rw',
    isa => 'Str',
    builder => '_build_ols_api_base',
);

=back

=cut

my $logger = Log::Log4perl->get_logger;

=head1 METHODS

=over 2

=item new

Instantiate a new Atlas::ZoomaClient::MappingResult object.

=cut

sub BUILD {

    my ( $self ) = @_;
    
    # Special case if there were no results from Zooma.
    unless( $self->has_zooma_results ) {

        unless( $self->has_mapping_category ) {
            
            $self->set_mapping_category( "NO_RESULTS" );

            return;
        }
        
        return;
    }

    # If there's only one result...
    if( @{ $self->get_zooma_results } == 1 ) {

        # Get the only result.
        my $zoomaResult = $self->get_zooma_results->[ 0 ];

        $self->set_ontology_mapping( _uris_to_string( $zoomaResult->{ "semanticTags" } ) );

        # Get the zooma label.
        my $ontoLabel = $self->_retrieve_ontology_label( $zoomaResult );
        $self->set_ontology_label( $ontoLabel );

        # Get the Zooma result annotated value.
        $self->set_zooma_property_value( _find_zooma_property_value( $zoomaResult ) );
        
        my $confidence = $zoomaResult->{ "confidence" };

        # If the confidence is high, the mapping is automatic.
        if( $confidence eq "HIGH" ) {

            $self->set_mapping_category( "AUTOMATIC" );
        } 
        else {
            $self->set_mapping_category( "REQUIRES_CURATION" );
        }
    }
    # If there's more than one result...
    elsif( @{ $self->get_zooma_results } > 1 ) {
        
        $self->set_mapping_category( "REQUIRES_CURATION" );

        # Get the "best" result.
        my $bestZoomaResult = $self->_find_best_result;

        $self->set_ontology_mapping( _uris_to_string( $bestZoomaResult->{ "semanticTags" } ) );
        
        # Get the zooma label.
        my $ontoLabel = $self->_retrieve_ontology_label( $bestZoomaResult );
    
        # In rare cases there isn't a Zooma label.
        unless( $ontoLabel ) {
            $ontoLabel = "";
        }

        $self->set_ontology_label( $ontoLabel );
        
        # Get the Zooma result annotated value.
        $self->set_zooma_property_value( _find_zooma_property_value( $bestZoomaResult ) );
    }
    else {
        $logger->logdie( "Results are empty. Cannot continue." );
    }

    # At the end, check that the mapping_category and ontology_mapping attributes are set.
    unless( $self->has_mapping_category && $self->has_ontology_mapping ) {

        $logger->logdie( "Mapping result is missing mapping category or ontology mapping or both." );
    }
}


sub _build_ols_api_base {

    my $olsAPIBaseVar = "OLS_API_BASE";

    my $olsAPIBase = $ENV{ "OLS_API_BASE" };

    if( $olsAPIBase ) {
        return $olsAPIBase;
    }
    else {

        my $default = "http://www.ebi.ac.uk/ols/api/";

        $logger->warn(
            "Your \$$olsAPIBaseVar variable is not set. Defaulting to $default"
        );

        return $default;
    }
}


sub _find_best_result {

    my ( $self ) = @_;

    my $zoomaResultsByConfidence = _index_zooma_results_by_confidence( $self->get_zooma_results );

    # First try the "good" hits, then "medium", then "low".
    if( $zoomaResultsByConfidence->{ "GOOD" } ) {
        
        # Get the top-scoring result.
        my $goodResults = $zoomaResultsByConfidence->{ "GOOD" };
        
        # The first result returned is the best one.
        return $goodResults->[ 0 ];
    }
    elsif( $zoomaResultsByConfidence->{ "MEDIUM" } ) {

        my $mediumResults = $zoomaResultsByConfidence->{ "MEDIUM" };

        # The first result returned is the best one.
        return $mediumResults->[ 0 ];
    }
    elsif( $zoomaResultsByConfidence->{ "LOW" } ) {

        my $lowResults = $zoomaResultsByConfidence->{ "LOW" };

        # The first result returned is the best one.
        return $lowResults->[ 0 ];
    }
    else {

        # If we didn't find anything, something weird happened.
        $logger->logdie( "No results found with HIGH, GOOD, MEDIUM, or LOW confidence." );
    }
}       


sub _index_zooma_results_by_confidence {

    my ( $zoomaResults ) = @_;

    my $indexedResults = {};

    foreach my $zoomaResult ( @{ $zoomaResults } ) {

        my $confidence = $zoomaResult->{ "confidence" };

        if( $indexedResults->{ $confidence } ) {
            push @{ $indexedResults->{ $confidence } }, $zoomaResult;
        }
        else {
            $indexedResults->{ $confidence } = [ $zoomaResult ];
        }
    }

    return $indexedResults;
}


sub _uris_to_string {

    my ( $uriArray ) = @_;

    my $uriString = join " ", @{ $uriArray };

    return $uriString;
}


sub _retrieve_ontology_label {

    my ( $self, $zoomaResult ) = @_;

    my @ontologyURIs = @{ $zoomaResult->{ "semanticTags" } };
    
    my @ontoLabels = ();

    foreach my $ontologyURI ( @ontologyURIs ) {
        
        my $ontoLabelsURL = $self->get_ols_api_base . "terms?iri=" . $ontologyURI;

        my $olsJSON = make_http_request( $ontoLabelsURL, "json" );

        my $ontoLabel;
        
        # Warn if we got an HTTP::Response object back, there was an error.
        if( $olsJSON->isa( "HTTP::Response" ) ) {

            $logger->warn( "Failed to get label from OLS for $ontologyURI : ", $olsJSON->status_line );
        
        } 
        # Otherwise, we should have some results.
        else {
            
            my $olsResults = parse_json( $olsJSON );

            # Check that there are some results.
            my $numResults = $olsResults->{ "page" }->{ "totalElements" };

            # If we didn't get any results, warn but continue.
            unless( $numResults ) {

                $logger->warn(
                    "Number of results missing from OLS data."
                );
            }
            else {
                
                # If there were no results, warn.
                if( $numResults == 0 ) {

                    $logger->warn( "Failed to get a label from OLS for $ontologyURI" );

                    $ontoLabel = "";
                }
                # Otherwise we got some hits, try to get a label.
                else {
                    
                    my $OLSHit;

                    # First look for an EFO hit.
                    # Map hits by the ontology they appear in.
                    my %mappedHits = map { $_->{ "ontology_name" } => $_ } @{ $olsResults->{ "_embedded" }->{ "terms" } };
                    
                    # If there is a hit from EFO, take that one.
                    if( $mappedHits{ "efo" } ) {

                        $OLSHit = $mappedHits{ "efo" };
                    }
                    # Otherwise, look for the defining ontology, and take the
                    # label from there instead.
                    else {
                        
                        foreach my $hit ( @{ $olsResults->{ "_embedded" }->{ "terms" } } ) {
                            
                            if( $hit->{ "is_defining_ontology" } ) {

                                $OLSHit = $hit;
                            }
                        }

                        # If we didn't get a hit from the defining ontology,
                        # try to use the hit with a matching prefix.
                        unless( $OLSHit ) {

                            my $ontoID = ( split "/", $ontologyURI )[ -1 ];
                            
                            foreach my $hit ( @{ $olsResults->{ "_embedded" }->{ "terms" } } ) {

                                if( $ontoID =~ /$hit->{ "ontology_prefix" }/ ) {

                                    $OLSHit = $hit;
                                }
                            }
                        }

                        # If we didn't get a hit with a matching prefix, just
                        # take the first hit returned.
                        unless( $OLSHit ) {

                            $OLSHit = ( @{ $olsResults->{ "_embedded" }->{ "terms" } } )[ 0 ];
                        }

                    }

                    # If we found a hit to use, take its label.
                    if( $OLSHit ) {

                        $ontoLabel = $OLSHit->{ "label" };

                        # Check for obsolescence.
                        if( $OLSHit->{ "is_obsolete" } ) {

                            $logger->warn(
                                $ontologyURI,
                                " is obsolete according to OLS. Please update mappings."
                            );
                        }
                    }
                    else {
                        $logger->warn(
                            "No hit found in OLS for $ontologyURI -- cannot get a label."
                        );

                        $ontoLabel = "";
                    }
                }
            }
        }

        if( $ontoLabel ) {
            push @ontoLabels, $ontoLabel;
        }
    }
    
    if( scalar @ontoLabels ) {

        my $fullOntoLabel = join ", ", @ontoLabels;

        return $fullOntoLabel;
    }
    else {
        return;
    }
}


sub _find_zooma_property_value {

    my ( $zoomaResult ) = @_;

    my $zoomaPropertyValue = $zoomaResult->{ "derivedFrom" }->{ "annotatedProperty" }->{ "propertyValue" };

    return $zoomaPropertyValue;
}


1;
