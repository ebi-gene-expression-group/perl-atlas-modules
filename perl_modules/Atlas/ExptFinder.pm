
=head1 NAME

Atlas::ExptFinder -- search ArrayExpress for candidate Expression Atlas experiments.
 
=head1 DESCRIPTION

Searches for potential experiments matching a given species. Child classes
assess suitability for a given analysis type (baseline or differential).

=head1 SYNOPSIS

use Atlas::ExptFinder::Baseline; # or Atlas::ExptFinder::Differential

# ...

my $searcher = Atlas::ExptFinder::Baseline->new;
$searcher->find_candidates( "Zea mays" );
$searcher->write_candidates_to_file( "Zea mays", "baseline" );

=head1 AUTHOR

Expression Atlas Team <arrayexpress-atlas@ebi.ac.uk>

=cut

package Atlas::ExptFinder;

use 5.10.0;

use Moose;
use MooseX::FollowPBP;
use File::Spec;
use Log::Log4perl;
use Config::YAML;
use File::Spec;
use File::Basename;

use Atlas::ExptFinder::ArrayExpressAPI;
use Atlas::Common qw( create_atlas_site_config );

#use EBI::FGPT::Resource::Database;
#use EBI::FGPT::Resource::Database::GXA;


has 'candidates_hash' => (
	is      => 'rw',
	isa     => 'HashRef',
	default => sub { {} }
);

has 'atlas_curated_accessions' => (
    is  => 'rw',
    isa => 'HashRef',
    builder => '_build_atlas_curated_accessions'
);

has 'species_list' => (
    is  => 'rw',
    isa => 'ArrayRef',
    predicate   => 'has_species_list'
);

has 'user_properties' => (
    is  => 'rw',
    isa => 'ArrayRef',
    predicate   => 'has_user_properties'
);

my $logger = Log::Log4perl::get_logger;

sub BUILD {

    my ( $self ) = @_;
    
    # If we weren't passed any species to search for, default to all the
    # species supported by Atlas (from Ensembl annotation source dir).
    unless( $self->has_species_list ) {

        $logger->info( "No species provided. Defaulting to list of all Atlas-supported species." );

        my $atlasProdDir = $ENV{ "ATLAS_PROD" };

        my $atlasSiteConfig = create_atlas_site_config;

        my $annsrcsDir = File::Spec->catfile(
            $atlasProdDir,
            $atlasSiteConfig->get_annotation_source_dir
        );

        unless( -d $annsrcsDir ) {
            $logger->logdie(
                "Annotation sources directory \"",
                $annsrcsDir,
                "\" does not look like a directory. Cannot collect Atlas species list."
            );
        }

        my @annsrcFiles = glob( 
            File::Spec->catfile( 
                $annsrcsDir,
                "*_*"
            )
        );

        my $speciesList = {};

        foreach my $file ( @annsrcFiles ) {

            my $species = basename( $file );

            if( $species =~ /^[a-z]+_[a-z]+$/i ) {
                
                # Replace the "_" with a space.
                $species =~ s/_/ /g;

                $speciesList->{ $species } = 1;
            }
        }
        
        my @speciesList = keys %{ $speciesList };

        $self->set_species_list( \@speciesList );
    }
}


sub _build_atlas_curated_accessions {

    my ( $self ) = @_;

    my $atlasProdDir = $ENV{ "ATLAS_PROD" };

    my $atlasSiteConfig = create_atlas_site_config;

    my $atlasCuratedAccsFile = File::Spec->catfile(
        $atlasProdDir,
        $atlasSiteConfig->get_atlas_curated_accessions_file
    );

    my $atlasCuratedAccs = Config::YAML->new( config => $atlasCuratedAccsFile );

    # Get the ArrayExpress accessions from the config. There are two places
    # with AE accessions, one for AE accessions for which we also have SRA
    # accessions, and one for AE accessions without SRA accessions.
    my $aeAccsNoSRA = $atlasCuratedAccs->get_arrayexpress_accessions_without_sra;
    my $aeAccsWithSRA = $atlasCuratedAccs->get_arrayexpress_accessions_with_sra;

    # Create a hash with only the AE accessions. We don't care about SRA
    # accessions for this.
    my %curatedAEaccs = ( ( map { $_ => 1 } @{ $aeAccsNoSRA } ), ( map { $_ => 1 } ( keys %{ $aeAccsWithSRA } ) ) );
    
    return \%curatedAEaccs;
}

sub find_candidates {

	my ( $self ) = @_;
    
    foreach my $species ( @{ $self->get_species_list } ) {

        $logger->info( "Querying for species $species..." );

        $self->run_ae_search( $species );
        unless( keys %{ $self->get_candidates_hash } ) {
            $logger->info( "No candidates for $species" );
            next;
        }
        #$self->quit_if_no_candidates;
        
        $self->remove_already_checked;
        unless( keys %{ $self->get_candidates_hash } ) {
            $logger->info( "No candidates for $species" );
            next;
        }
        #$self->quit_if_no_candidates;

        $self->remove_ineligible_experiments;
        unless( keys %{ $self->get_candidates_hash } ) {
            $logger->info( "No candidates for $species" );
            next;
        }
        #$self->quit_if_no_candidates;
        
        $self->write_candidates_to_file( $species );

        $self->set_candidates_hash( {} );

        $logger->info( "Finished $species" );
    }
}

sub quit_if_no_candidates {
	
	my ( $self ) = @_;

	my $analysisType = $self->get_analysis_type;

	unless( keys %{ $self->get_candidates_hash } ) {
		$logger->info(
			"No potential "
					   . $analysisType
					   . " candidates were found."
		);
		exit 0;
	}
}

sub run_ae_search {

	my ( $self, $species ) = @_;
	
	my $aeAPI = Atlas::ExptFinder::ArrayExpressAPI->new( species_list => [ $species ] );
    
    if( $self->has_user_properties ) {
        $aeAPI->set_user_properties( $self->get_user_properties );
    }
    
    $logger->info( "Starting queries..." );

	# Query the ArrayExpress API
	my $candidates = $aeAPI->query_for_experiments;

	# No match found
	unless( keys %{ $candidates } ) {

		my $message =
		    "No results found.";
		$logger->info(
			$message
		);
	}
	# Otherwise log how many we found.
	else {

		my $numExpts = keys %{ $candidates };

		my $message = "Found $numExpts experiments.";

		$logger->info(
			$message
		);
	}
	
	# Return the experiments we found.
	$self->set_candidates_hash( $candidates );
}

sub remove_from_candidates {

	my ( $self, $expAcc ) = @_;

	my $candidates = $self->get_candidates_hash;

	delete $candidates->{ $expAcc };

	$self->set_candidates_hash( $candidates );
}

sub remove_already_checked {
	
	my ( $self ) = @_;
	
    my $alreadyChecked = $self->get_atlas_curated_accessions;

	$logger->info(
		"Checking if experiments have already been checked..."
	);

	# Check database for each accession.
	foreach my $expAcc ( keys %{ $self->get_candidates_hash } ) {
        
        if( $alreadyChecked->{ $expAcc } ) {
            # Remove this one as it's already in Atlas.
            $self->remove_from_candidates( $expAcc );
        }
	}
	
	my $numExps = keys %{ $self->get_candidates_hash };

	$logger->info(
		"$numExps experiments have not yet been checked."
	);
}

sub write_candidates_to_file {

	my ( $self, $species ) = @_;
	
    my $outputFilename = $species . "_candidates.$$.txt";

	$logger->info(
		"Writing candidate experiment accessions to $outputFilename"
	);

	open( my $fh, ">", $outputFilename )
		or $logger->logdie(
			"Cannot open $outputFilename for writing: $!"
		);
	
	my $candidates = $self->get_candidates_hash;
    
    foreach my $acc ( keys %{ $candidates } ) {
        say $fh $acc;
    }
    
    close( $fh );

	$logger->info(
		"Successfully written candidate accessions."
	);
}

1;
