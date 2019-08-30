
=head1 NAME

Atlas::ExptFinder::ArrayExpressAPI.pm
 
=head1 DESCRIPTION

Searches the ArrayExpress API for potential experiments matching a given search query.

=head1 SYNOPSIS
	
Example:

	my $ae_api = new Atlas::ExptFinder::ArrayExpressAPI();

	my $searchParameters = {
		'species'	=> "Zea mays",
		'exptype'	=> "RNA-seq",
		'efcount'	=> 1,
		'factors'	=> [ 'organism part', 'developmental stage' ]
	};

	# Query the ArrayExpress API
	my $candidates = $ae_api->query_for_experiments( $searchParameters );

	# Count the number of factor values for a single-factor experiment.
	my $numFactorValues = $ae_api->get_num_factor_values( "E-GEOD-19232" );

=head1 AUTHOR

Emma Hastings , <emma@ebi.ac.uk>, script is an extension of findGrameneBaselineExpts.pl written by Maria Keayes

Created AUG 2014

=cut

package Atlas::ExptFinder::ArrayExpressAPI;

use Moose;
use MooseX::FollowPBP;
use JSON;
use XML::Simple qw(:strict);
use Data::Dumper;
use Log::Log4perl;
use URL::Encode qw( url_encode_utf8 );
use Atlas::Common qw( 
    make_http_request 
    http_request_successful    
);

has 'base_uri' => (
	is      => 'rw',
	isa     => 'Str',
	default => 'http://www.ebi.ac.uk/arrayexpress/xml/v2/experiments?raw=true'
);

has 'species_list' => (
    is  => 'rw',
    isa => 'ArrayRef',
    required => 1
);

has 'user_properties' => (
    is  => 'rw',
    isa => 'ArrayRef',
    predicate   => 'has_user_properties'
);

has 'efcount' => (
    is  => 'rw',
    isa => 'Int',
    predicate   => 'has_efcount'
);

has 'exptype' => (
    is  => 'rw',
    isa => 'Str',
    predicate   => 'has_exptype'
);

has 'queries' => (
    is  => 'rw',
    isa => 'ArrayRef',
    predicate   => 'has_queries'
);

my $logger = Log::Log4perl::get_logger;

sub query_for_experiments {

	my ( $self ) = @_;
	
	$self->construct_queries;

	my $candidates = {};

	foreach my $query ( @{ $self->get_queries } ) {

        $logger->info( "Running query: $query ..." );

		my $xml = $self->query_ae( $query );
		
		foreach my $expAcc ( keys %{ $xml->{'experiment'} } ) {
			$candidates->{ $expAcc } = 1;
		}

        $logger->info( "Query finished." );
	}

	# Return list of found experiments
	return $candidates;
}

sub construct_queries {

	my ( $self ) = @_;

	my $queries = [];

    # Run one query per species.
    foreach my $species ( @{ $self->get_species_list } ) {

        my $query = $self->get_base_uri 
                    . "&species=" 
                    . url_encode_utf8( $species );

        # If we've been passed any properties, add these to the query.
        # These have to go in as keywords as there doesn't seem to be a way
        # to query characteristic types.
        if( $self->has_user_properties ) {
            
            # Make sure the properties are URL-safe.
            my @properties4query = ();

            foreach my $property ( @{ $self->get_user_properties } ) {

                push @properties4query, url_encode_utf8( $property );
            }
            
            # Using OR query.
            my $joinedProperties = join( "+OR+", @properties4query );
            
            # Add the properties.
            $query .= "&keywords=$joinedProperties";
        }

        # If we have a number of allowed factors, add this.
        if( $self->has_efcount ) { $query .= "&efcount=" . $self->get_efcount; }

        # If we have an experiment type to limit search to, add this.
        if( $self->has_exptype ) { $query .= "&exptype=" . $self->get_exptype; }

        push @{ $queries }, $query;
    }
	
    $self->set_queries( $queries );
}

sub query_ae {

	my ( $self, $query ) = @_;

	my $aeXML = make_http_request( $query, "xml" );

    unless( http_request_successful( $aeXML ) ) {

        $logger->logdie( "HTTP request failed. URL was: $query" );
    }

	# Parse returned xml
	my $parsedXML = XMLin(
		$aeXML,
		ForceArray => [ 'experiment', 'experimentalfactor' ],
		KeyAttr    => { experiment    => 'accession' }
	);

	return $parsedXML;
}

sub get_num_factor_values {

	my ( $self, $expAcc ) = @_;
	
	# Create query for experiment.
	my $query = $self->get_base_uri . "?accession=$expAcc";

	# Run query.
	my $xml = $self->query_ae( $query );

	# Get the factor (assumes there is only one factor).
	if( @{ $xml->{ 'experiment' }->{ $expAcc }->{ 'experimentalfactor' } } != 1 ) {
		$logger->logdie(
			level	=> 'alert',
			message	=> "Trying to count factor values for $expAcc but it has more than one factor."
		);
	}

	my $factor = ${ $xml->{ 'experiment' }->{ $expAcc }->{ 'experimentalfactor' } }[ 0 ];

	# Count the number of factor values for this factor.
	my $numFactorValues = @{ $factor->{ 'value' } };

	return $numFactorValues;
}

1;
