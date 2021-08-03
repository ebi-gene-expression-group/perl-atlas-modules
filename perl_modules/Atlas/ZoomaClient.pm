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
use File::Basename;
use Atlas::Common qw( 
    make_http_request
    get_supporting_file
 );
use Atlas::ZoomaClient::MappingResult;
use HTTP::Request;

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
my $ontology_lookup = zooma_ontology_lookup ("zooma_ontologies.tsv");
my $plant_species = get_plants_species();

=head1 METHODS

=over 2

=item map_term

Given a property type and property value, use Zooma to map the term to one or
more ontology URIs.

=cut

sub map_term {

    my ( $self, $propertyType, $propertyValue, $organism ) = @_;

    # Step 1: Get the results from Zooma, an array ref of hash refs
    # representing the JSON from the Zooma API.
    $logger->debug( "Querying zooma for $propertyType : $propertyValue : $organism ..." );

    my $queryResults = $self->_query_zooma( $propertyType, $propertyValue, $organism );
    
    unless( $queryResults ) {

        $logger->warn( "No results found for $propertyType : $propertyValue" );

        my $mappingResult = Atlas::ZoomaClient::MappingResult->new(
            zooma_error => "No results found for $propertyType : $propertyValue : $organism"
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

        $logger->debug( "Getting mapping result for $propertyType : $propertyValue : $organism ..." );

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

    my ( $self, $propertyType, $propertyValue, $organism ) = @_;
    
    my ( $propertyType4url, $propertyValue4url ) = ( $propertyType, $propertyValue );

    # First we need to make sure the property type and value are in the right
    # format for a URL.
    $_ = url_encode_utf8( $_ ) for ( $propertyType4url, $propertyValue4url );

    my $ontology = lc ( get_ontology_for_type( $organism, $propertyType ) );
    $ontology =~ s/\s+$//;
    
    # Get the data sources string.
    my $dataSourcesString = $self->_data_sources_to_string;
    my $ontologiesString = $self->_ontologies_to_string;

    $logger->info("Mapping property type '", $propertyType, "' for species '", $organism, "' with ontology db - ", $ontology);

    # Build the query URL.
    my $queryURL = $self->get_zooma_api_base
                    . "services/annotate?propertyValue=$propertyValue4url&propertyType=$propertyType4url"
                    . "&filter=required:[$dataSourcesString],preferred:[$dataSourcesString],ontologies:[$ontology]";

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


sub zooma_ontology_lookup {
    my ( $filename ) = @_;
    my $abs_path = dirname(File::Spec->rel2abs(__FILE__));
    my $zoomaOntologyLookupFile = "$abs_path/../../supporting_files/". $filename;
    open (my $in_fh, '<', $zoomaOntologyLookupFile) or die $!;
    my %ontology_lookup;
    while ( my $line = <$in_fh> ) {
        my ( $property_type, $organism, $ontologies ) = split /\t/, $line;
        $ontology_lookup{$property_type}{$organism} = $ontologies;
    }   
    return \%ontology_lookup;
}

sub get_plants_species {

    # Plants file comes from
    # http://ftp.ebi.ac.uk/ensemblgenomes/pub/release-51/plants/species_EnsemblPlants.txt,
    # but the Ensembl FTP is a bit unreliable, so we bundle it here. 
    
    my $plants_file=get_supporting_file( 'species_EnsemblPlants.txt' );    
    open(PLANTS, $plants_file) or die("Could not open file $plants_file.");
    my @plants_species_list;
    foreach my $line (<PLANTS>)  { 
        next if $line =~ m/#name/;
        my @plants_species = split(/\t/,$line);
        push (@plants_species_list, $plants_species[1])
    }
    close(PLANTS)
    return \@plants_species_list;
}


sub get_ontology_for_type {
    my ( $organism, $property_type ) = @_;

    my $ontology;
    ## for plants specific
    if (grep { $_ =~ $organism } @{ $plant_species }) {
        print ("plant species - $organism \n");
        #set organism to plants
        my $organism='plants';
    }
    ## iterate over the lookup table to identify corresponding ontology db for zooma mappings
    foreach my $propertyType ( sort keys %{ $ontology_lookup } ) {
       if ( $propertyType =~ $property_type ){
           foreach my $species ( sort keys %{ $ontology_lookup->{$propertyType} } ) {
               if ( $species =~ $organism ){
                    $ontology = $ontology_lookup->{$propertyType}->{$species};
                }
                elsif ( $species =~ 'any' ){
                    $ontology = $ontology_lookup->{$propertyType}->{'any'};
                }
                elsif ( $species =~ 'other'){
                     $ontology = $ontology_lookup->{$propertyType}->{'other'};
                }
           }
                return $ontology;
        }
        else {
            $ontology='EFO';
        }
     }
     return $ontology;
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
