#!/usr/bin/env perl
#
=pod

=head1 NAME

Atlas::ZoomaClient - Perl client to query Zooma for ontology mappings

=head1 SYNOPSIS

    use Atlas::ZoomaClient;

    my $zoomaClient = Atlas::ZoomaClient->new;

    my ( $type, $value ) = ( "organism part", "liver" );

    my $ontologyMapping = $zoomaClient->mapterm( $type, $value );

=head1 DESCRIPTION

An Atlas::ZoomaClient object queries the EBI SPOT Zooma service to map a term,
specified by its type and value, to an ontology URI (in few cases sometimes
more than one URI?).

The workflow is as follows:

1) Search Zooma using property type and value.
2) Get all the Zooma annotation summaries for the search results.
3) Filter these annotation summaries using the cutoff proportion (see below).
4) Get the mapping result based on these annotation summaries.
5) Return the mapping result.

=cut

package Atlas::ZoomaClient;

use 5.10.0;

use Moose;
use MooseX::FollowPBP;
use URL::Encode qw( url_encode_utf8 );
use JSON::Parse qw( parse_json );
use Array::Compare;
use Log::Log4perl;

use Atlas::Common qw( make_http_request );
use Atlas::ZoomaClient::MappingResult;


=head1 ATTRIBUTES

=over 2

=item zooma_api_base

Base URL for Zooma API.

=cut

has zooma_api_base => (
    is => 'rw',
    isa => 'Str',
    builder => '_build_zooma_api_base'
);

=item data_sources

An array ref containing the curated data sources to allow mappings from, in
order of preference.

=cut

has data_sources => (
    is => 'rw',
    isa => 'ArrayRef',
    default => sub { [ 'atlas', 'gwas' ] }
);

=item ontologies

An array ref of ontologies to allow mappings from. These are considered by
Zooma only _after_ considering the data sources.

=cut

has ontologies => (
    is => 'rw',
    isa => 'ArrayRef',
    default => sub { [ 'efo' ] }
);

=item cutoff_proportion

The minimum proportion of the score of the best result to allow lower-scoring
results to have. E.g. if the cutoff_proportion is 0.9 and the best result has a
score of 85, we filter out any results with a score less than 0.9 * 85 = 76.5.

=cut

has cutoff_proportion => (
    is => 'rw',
    isa => 'Num',
    default => 0.9
);

=back

=cut

my $logger = Log::Log4perl::get_logger;

=head1 METHODS

=over 2

=item map_term

Given a property type and property value, use Zooma to map the term to one or
more ontology URIs.

=cut

sub map_term {

    my ( $self, $propertyType, $propertyValue ) = @_;

    # Step 1: Get the results from Zooma, an array ref of hash refs
    # representing the JSON from the Zooma API.
    $logger->debug( "Querying zooma for $propertyType : $propertyValue ..." );

    my $queryResults = $self->_query_zooma( $propertyType, $propertyValue );
    
    unless( $queryResults ) {

        $logger->warn( "No results found for $propertyType : $propertyValue" );

        my $mappingResult = Atlas::ZoomaClient::MappingResult->new(
            zooma_error => "No results found for $propertyType : $propertyValue"
        );

        return $mappingResult;
    }
    
    $logger->debug(
        "Got ",
        scalar @{ $queryResults },
        " results for $propertyType : $propertyValue"
    );

    # If there are any results, create the mapping result.
    if( @{ $queryResults } ) {

        $logger->debug( "Getting mapping result for $propertyType : $propertyValue ..." );

        my $mappingResult = Atlas::ZoomaClient::MappingResult->new(
            zooma_results => $queryResults,
        );

        unless( $mappingResult ) {
            $logger->logdie( "Error getting mapping result." );
        }
        else {
            $logger->debug( 
                "Mapping category is ",
                $mappingResult->get_mapping_category,
                " with ontology mapping ",
                $mappingResult->get_ontology_mapping
            );

            return $mappingResult;
        }
    }
    else {

        $logger->warn( "No results found for $propertyType : $propertyValue" );

        my $mappingResult = Atlas::ZoomaClient::MappingResult->new(
            zooma_error => "No results found for $propertyType : $propertyValue"
        );

        return $mappingResult;
    }
}


=item _query_zooma

Given a property type and value, return a hash containing the query results.

=cut

sub _query_zooma {

    my ( $self, $propertyType, $propertyValue ) = @_;
    
    my ( $propertyType4url, $propertyValue4url ) = ( $propertyType, $propertyValue );

    # First we need to make sure the property type and value are in the right
    # format for a URL.
    $_ = url_encode_utf8( $_ ) for ( $propertyType4url, $propertyValue4url );
    
    # Get the data sources string.
    my $dataSourcesString = $self->_data_sources_to_string;
    my $ontologiesString = $self->_ontologies_to_string;

    # Build the query URL.
    my $queryURL = $self->get_zooma_api_base
                    . "services/annotate?propertyValue=$propertyValue4url&propertyType=$propertyType4url"
                    . "&filter=required:[$dataSourcesString],preferred:[$dataSourcesString],ontologies:[$ontologiesString]";

    my $zoomaJSON = make_http_request( $queryURL, "json" );

    # If we've been given an HTTP::Response object back instead of some text,
    # something went wrong.
    if( $zoomaJSON->isa( "HTTP::Response" ) ) {

        if( $zoomaJSON->code == 400 ) {
            $logger->warn(
                "Query URL was malformed, Zooma could not return any results."
            );

            return;
        }
        else {
            
            $logger->error(
                "Unable to map $propertyType : $propertyValue"
            );
            
            $logger->error(
                "Full query URL was: $queryURL"
            );

            $logger->logdie( "Zooma is not responding. Cannot continue." );

            return;
        }
    }

    # Parse the JSON from the request results into a hash.
    my $zoomaResults = parse_json( $zoomaJSON );
    
    return $zoomaResults;
}


=item _data_sources_to_string

Converts data sources array ref into a comma-separated string and returns it.

=cut

sub _data_sources_to_string {

    my ( $self ) = @_;

    my $dataSources = $self->get_data_sources;

    my $dataSourcesString = join ",", @{ $dataSources };

    return $dataSourcesString;
}

=item _ontologies_to_string

Converts ontologies array ref into a comma-separated string and returns it.

=cut

sub _ontologies_to_string {

    my ( $self ) = @_;

    my $ontologies = $self->get_ontologies;

    my $ontologiesString = join ",", @{ $ontologies };

    return $ontologiesString;
}


sub _build_zooma_api_base {

    my $zoomaAPIbaseVar = "ZOOMA_API_BASE";

    my $zoomaApiBase = $ENV{ $zoomaAPIbaseVar };

    if( $zoomaApiBase ) {
        return $zoomaApiBase;
    }
    else {
        
        my $default = "http://www.ebi.ac.uk/spot/zooma/v2/api/";
        
        $logger->warn( 
            "Your \$$zoomaAPIbaseVar variable is not set. Defaulting to $default" 
        );

        return $default;
    }
}


1;
