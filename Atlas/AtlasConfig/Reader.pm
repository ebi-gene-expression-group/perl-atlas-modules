#!/use/bin/env perl
#
=pod

=head1 NAME

Atlas::AtlasConfig::Reader - reads an Atlas XML config file in to Atlas::AtlasConfig objects.

=head1 SYNOPSIS

use Atlas::AtlasConfig::Reader qw( parseAtlasConfig );

my $configXMLfilename = "E-MTAB-1066-configuration.xml";

my $experimentConfig = parseAtlasConfig( $configXMLfilename );

=head1 DESCRIPTION

This module exports functions to read Atlas XML config files
(-configuration.xml or -factors.xml) and create the relevant Atlas::AtlasConfig
object (ExperimentConfig or FactorsConfig) to represent the information stored
therein.

=cut

package Atlas::AtlasConfig::Reader;

use 5.10.0;

use Moose;
use MooseX::FollowPBP;
use XML::Simple qw(:strict);
use File::Basename;
use Log::Log4perl;
use Data::Dumper;

use Atlas::Assay;
use Atlas::AtlasConfig::BiologicalReplicate;
use Atlas::AtlasConfig::AssayGroup;
use Atlas::AtlasConfig::Analytics;
use Atlas::AtlasConfig::Analytics::Differential;
use Atlas::AtlasConfig::Contrast;
use Atlas::AtlasConfig::ExperimentConfig;
use Atlas::AtlasConfig::BatchEffect;
use Atlas::AtlasConfig::FactorsConfig;

use base 'Exporter';
our @EXPORT_OK = qw(
	parseAtlasConfig
    parseAtlasFactors
);

$| = 1;

my $logger = Log::Log4perl::get_logger;

=head1 METHODS

=over 2

=item parseAtlasConfig

This function takes an Atlas XML config file and returns an
Atlas::AtlasConfig::ExperimentConfig object representing it.

=cut
sub parseAtlasConfig {

	my ( $atlasXMLfile , $experimentAccession) = @_;

	# Get the experiment accession from the file name if undefined.
	$experimentAccession = $experimentAccession // basename( $atlasXMLfile );
	$experimentAccession =~ s/^(E-\w{4}-\d+)-.*/$1/g;

	# Read in XML.
	my $xml = XMLin(
		$atlasXMLfile,
		ForceArray => [
			'analytics',
			'assay',
			'contrast',
			'assay_group',
			'batch_effect',
			'batch',
		],
		KeyAttr => {
			contrast => 'id',
			assay_group => 'id',
			batch_effect => 'name',
			batch => 'value',
		}
	);

	# Get the experiment type.
	my $atlasExperimentType = $xml->{ 'experimentType' };

    # Get the flag for presence/absence of R experiment summaries.
    my $rDataPresent = $xml->{ 'r_data' };

	# Make an array of Atlas::AtlasConfig::Analytics objects.
	my $allAnalytics = _make_all_analytics( $xml->{ 'analytics' } , $atlasExperimentType, $atlasXMLfile );

	# Make ExperimentConfig object.
	my $atlasExperimentConfig = Atlas::AtlasConfig::ExperimentConfig->new(
		atlas_analytics => $allAnalytics,
		atlas_experiment_type => $atlasExperimentType,
		experiment_accession => $experimentAccession,
        r_data_present => $rDataPresent,
	);

	return $atlasExperimentConfig;
}


=item parseAtlasFactors

This function takes an Atlas factors XML file and returns a hash.

=cut

sub parseAtlasFactors {

    my ( $factorsFilename ) = @_;

    # Make sure the factors XML file exists.
    unless( -r $factorsFilename ) {

        $logger->error(
            "Unable to read ",
            $factorsFilename,
            " -- please ensure it exists and is readable."
        );

        return;
    }

    my $xml = XMLin(
        $factorsFilename,
        ForceArray => [
            'factors-definition',
            'filterFactor',
            'mapping',
        ],
        KeyAttr => {
            'factors-definition'    => 'landingPageDisplayName',
        },

        # Don't create empty hashes for empty elements.
        SuppressEmpty => 'undef'
    );

    # Get the landing page display name and default query factor type, these
    # are required for all factors XML configs.
    my $displayName = $xml->{ "landingPageDisplayName" };
    my $defaultQueryFactorType = $xml->{ "defaultQueryFactorType" };

    # Create the new FactorsConfig
    my $factorsConfig = Atlas::AtlasConfig::FactorsConfig->new(
        landing_page_display_name => $displayName,
        default_query_factor_type => $defaultQueryFactorType
    );

    # Add the optional extras we found.
    # The defaultFilterFactors (multi-factor experiments only). These are the
    # default values to use for each factor, apart from the defaultQueryFactor,
    # to select assays to display in the heatmap.
    if( $xml->{ "defaultFilterFactors" } ) {

        # Get the ArrayRef of filter factors.
        my $xmlFilterFactors = $xml->{ "defaultFilterFactors" }->{ "filterFactor" };

        # Set the attribute with the new hash.
        $factorsConfig->set_default_filter_factors( $xmlFilterFactors );
    }

    # The menuFilterFactorTypes (multi-factor experiments only). These are the
    # factor types to display in the menu, for users to select assays to
    # display in the heatmap.
    if( $xml->{ "menuFilterFactorTypes" } ) {

        # Get the comma-separated string of factor types.
        my $menuTypesString = $xml->{ "menuFilterFactorTypes" };

        # Split them.
        my @menuFactorTypes = split /,\s*/, $menuTypesString;

        # Set the attribute with the split types.
        $factorsConfig->set_menu_filter_factor_types( \@menuFactorTypes );
    }

    # The data provider URL (for well-known consortia e.g. Blueprint, Genentech, etc).
    if( $xml->{ "dataProviderURL" } ) {

        $factorsConfig->set_data_provider_url( $xml->{ "dataProviderURL" } );
    }

    # The data provider description (for well-known consortia e.g. Blueprint,
    # Genentech, etc).
    if( $xml->{ "dataProviderDescription" } ) {

        $factorsConfig->set_data_provider_description( $xml->{ "dataProviderDescription" } );
    }

    # The speciesMapping (rarely used). This is for cases where we map reads
    # from one species against the genome of another. For example, E-GEOD-30352
    # has data from Pongo pygmaeus, which we mapped against the P. abelii
    # genome, because the P. pygmaeus genome is not available in Ensembl and
    # the species are very closely related. E-GEOD-30352 does not exist in
    # Atlas any more.
    if( $xml->{ "speciesMapping" }->{ "mapping" } ) {

        # Get the ArrayRef of species mappings.
        my $mappings = $xml->{ "speciesMapping" }->{ "mapping" };

        # Set the species_mapping attribute.
        $factorsConfig->set_species_mapping( $mappings );
    }

    if( $xml->{ "disclaimer" } ) {

        $factorsConfig->set_data_usage_agreement( $xml->{ "disclaimer" } );
    }

    if( $xml->{ "orderFactor" } ) {

        if( $xml->{ "orderFactor" } eq "curated" ) {

            $factorsConfig->set_curated_sequence( 1 );
        }
    }

    return $factorsConfig;
}

=item _get_contrast_id_order

Create a hash to remember the ordering of the contrasts. Needed if we have to
re-write an XML file e.g. in microarray QC.

=cut

sub _get_contrast_id_order {

	my ( $atlasXMLfile ) = @_;

	# Hash to store contrast IDs and their positions.
	my $contrastIDorder = {};

	# Grep for the contrast ID lines in the file.
	my $contrastTagLines = `grep \"<contrast id=\" $atlasXMLfile`;

	my @contrastTags = split "\n", $contrastTagLines;

	# Start counting contrasts at 1.
	my $contrastPosition = 1;

	# Go through the contrast ID lines.
	foreach my $contrastTag ( @contrastTags ) {

		# Get the contrast ID.
		( my $contrastID = $contrastTag ) =~ s/.*id="(g\d+_g\d+)".*>.*/$1/;

		# Add it to the hash with the position.
		$contrastIDorder->{ $contrastID } = $contrastPosition;

		# Increment position.
		$contrastPosition++;
	}

	return $contrastIDorder;
}

=item _make_all_analytics

Not exported. Takes arrayref of analytics elements from XML and XML experiment
type. Returns arrayref of Atlas::AtlasConfig::Analytics (or
Atlas::AtlasConfig::Analytics::Differential) objects.

=cut
sub _make_all_analytics {

	my ( $xmlAnalytics, $atlasExperimentType, $atlasXMLfile ) = @_;

	my $allAnalytics = [];

	# Go through the analytics elements.
	foreach my $xmlAnalytics ( @{ $xmlAnalytics } ) {

		# Make an array of Atlas::AtlasConfig::AssayGroup objects.
		my $analyticsAssayGroups = _make_analytics_assay_groups( $xmlAnalytics->{ 'assay_groups' }->{ 'assay_group' } , $atlasExperimentType );

		# Get all the assays.
		my $analyticsAssays = [];
		foreach my $assayGroup ( @{ $analyticsAssayGroups } ) {

			my $assayGroupAssays = $assayGroup->get_assays;

			foreach my $assay ( @{ $assayGroupAssays } ) {

				push @{ $analyticsAssays }, $assay;
			}
		}

		# Add platform info.
		my $platform;
		# RNA-seq
		if( $atlasExperimentType =~ /rnaseq/ ) { $platform = "rnaseq"; }
        # Proteomics
        elsif( $atlasExperimentType =~ /proteomics/ ) { $platform = "proteomics"; }
		# Microarray array design.
		else {
			$platform = $xmlAnalytics->{ 'array_design' };
			# Remove any whitespace from the array design accession, as this is
			# not allowed.
			$platform =~ s/[\n\s]//g;
		}

		# Variable for Atlas::AtlasConfig::Analytics.
		my $analytics;

		# For baseline experiments.
		if( $atlasExperimentType =~ /baseline/ ) {

			# Make the new Atlas::AtlasConfig::Analytics object.
			$analytics = Atlas::AtlasConfig::Analytics->new(
				atlas_assay_groups => $analyticsAssayGroups,
				platform => $platform,
			);

			$analytics->set_assays( $analyticsAssays );
		}
		# For differential experiments, also need to get the contrasts.
		else {

			# Get the contrast ordering.
			my $contrastIDorder = _get_contrast_id_order( $atlasXMLfile );

			my $analyticsContrasts = _make_analytics_contrasts(
				$xmlAnalytics->{ 'contrasts' }->{ 'contrast' },
				$analyticsAssayGroups,
				$contrastIDorder
			);

			$analytics = Atlas::AtlasConfig::Analytics::Differential->new(
				atlas_assay_groups => $analyticsAssayGroups,
				platform => $platform,
				atlas_contrasts => $analyticsContrasts,
			);

			$analytics->set_assays( $analyticsAssays );
		}

		push @{ $allAnalytics }, $analytics;
	}

	return $allAnalytics;
}


=item _make_analytics_assay_groups

Not exported. Takes arrayref of assay_group elements from XML and XML
experiment type. Returns arrayred of Atlas::AtlasConfig::AssayGroup objects.

=cut
sub _make_analytics_assay_groups {

	my ( $xmlAssayGroups, $atlasExperimentType ) = @_;

	# Decide minimum biological replicates.
	my $minBioRep = 1;
	if( $atlasExperimentType =~ /differential/ ) {
		$minBioRep = 3;
	}

	my $analyticsAssayGroups = [];

	foreach my $assayGroupID ( sort keys %{ $xmlAssayGroups } ) {

		# Get the label for this assay group -- it contains the factor(s) which
		# we add to the assay objects we'll create.
		my $assayGroupLabel = $xmlAssayGroups->{ $assayGroupID }->{ 'label' };

        # Handle cases where there isn't an assay group label -- just use assay group ID.
        unless( $assayGroupLabel ) {
            $assayGroupLabel = $assayGroupID;
        }

		# Get the assays in this assay group.
		my $xmlAssays = $xmlAssayGroups->{ $assayGroupID }->{ 'assay' };

		# Create Atlas::Assay objects
		my $assayGroupAssays = _make_assay_group_assays( $xmlAssays, $assayGroupLabel );

		# Create a new Atlas::AtlasConfig::AssayGroup.
		my $assayGroup = Atlas::AtlasConfig::AssayGroup->new(
			assay_group_id => $assayGroupID,
			assays => $assayGroupAssays,
			minimum_biological_replicates => $minBioRep,
		);

		# Add it to the array.
		push @{ $analyticsAssayGroups }, $assayGroup;
	}

	return $analyticsAssayGroups;
}


=item _make_assay_group_assays

Not exported. Takes arrayref of assay elements from XML and XML assay group
label. Returns arrayref of Atlas::Assay objects.

=cut
sub _make_assay_group_assays {

	my ( $xmlAssays, $assayGroupLabel ) = @_;

	# Map the assay names to their techincal replicate IDs. If assays are not
	# technical replicates they will be under the key
	# "no_techincal_replicate_id".
	my $techRepsToAssayNames = _map_technical_replicates_to_assay_names( $xmlAssays );

	my $assayGroupAssays;

	# Go through the technical replicate IDs.
	foreach my $technicalReplicateID (sort keys %{ $techRepsToAssayNames } ) {

		# First deal with the ones that aren't technical replicates.
		if( $technicalReplicateID eq "no_technical_replicate_id" ) {
			foreach my $assayName ( @{ $techRepsToAssayNames->{ "no_technical_replicate_id" } } ) {

				# Create a new Atlas::Assay object.
				my $assay4atlas = Atlas::Assay->new(
					name => $assayName,
					# Add the label as factors and characteristics placeholder.
					factors => { 'label' => { $assayGroupLabel => 1 } },
					characteristics => { 'label' => { $assayGroupLabel => 1 } },
				);

				push @{ $assayGroupAssays }, $assay4atlas;
			}
		}
		# Now the ones that are technical replicates
		else {

			# Create new Atlas::Assay objects.
			foreach my $assayName ( @{ $techRepsToAssayNames->{ $technicalReplicateID } } ) {

				# Create the Atlas::Assay object.
				my $assay4atlas = Atlas::Assay->new(
					name => $assayName,
					factors => { 'label' => { $assayGroupLabel => 1 } },
					characteristics => { 'label' => { $assayGroupLabel => 1 } },
					technical_replicate_group => $technicalReplicateID,
				);

				# Add this to the array.
				push @{ $assayGroupAssays }, $assay4atlas;
			}
		}
	}

	# Return the array of Atlas::Assay objects.
	return $assayGroupAssays;
}


=item _map_technical_replicates_to_assay_names

Not exported. Takes an arrayref of assay elements from XML. Returns a hashref
with technical replicate IDs (or "no_technical_replicate_id") as keys and
arrayrefs of corresponding assay names as values.

=cut
sub _map_technical_replicates_to_assay_names {

	my ( $xmlAssays ) = @_;

	# Ref to empty hash for mapping technical replicate IDs to assay names.
	my $techRepsToAssayNames = {};

	# Go through the assays.
	foreach my $xmlAssay ( @{ $xmlAssays } ) {

		# If this assay is a hash this means it has a technical replicate ID.
		if( ref( $xmlAssay ) eq "HASH" ) {

			# Get the technical replicate ID.
			my $technicalReplicateID = $xmlAssay->{ 'technical_replicate_id' };

            # Check that it doesn't start with a number. This is not allowed in
            # case we try to use them as column headings in R later.
            if( $technicalReplicateID =~ /^\d/ ) {
                die( "ERROR - Technical replicate IDs must not start with a number. Please check and correct as necessary.\n" );
            }

			# Add it to an array in the hash.
			if( $techRepsToAssayNames->{ $technicalReplicateID } ) {

				push @{ $techRepsToAssayNames->{ $technicalReplicateID } }, $xmlAssay->{ 'content' };

			} else {

				$techRepsToAssayNames->{ $technicalReplicateID } = [ $xmlAssay->{ 'content' } ];
			}

		}
		# Otherwise, if it's not a hash, this assay is not a technical
		# replicate, so add it to the hash under the key
		# "no_technical_replicate_id".
		else {

			if( $techRepsToAssayNames->{ "no_technical_replicate_id" } ) {

				push @{ $techRepsToAssayNames->{ "no_technical_replicate_id" } }, $xmlAssay;

			} else {

				$techRepsToAssayNames->{ "no_technical_replicate_id" } = [ $xmlAssay ];
			}
		}
	}

	return $techRepsToAssayNames;
}


=item _make_analytics_contrasts

Not exported. Takes arrayref of contrast elements from XML and arrayref of
Atlas::AtlasConfig::AssayGroup objects. Returns arrayref of Atlas::AtlasConfig::Contrast
objects.

=cut
sub _make_analytics_contrasts {

	my ( $xmlContrasts, $assayGroups, $contrastIDorder ) = @_;

	# Map assay groups to their assay group IDs to make access easier.
	my $assayGroupIDsToAssayGroups = _map_assay_group_ids_to_assay_groups( $assayGroups );

	my $contrasts = [];

	foreach my $contrastID ( sort keys %{ $xmlContrasts } ) {

		my $xmlContrast = $xmlContrasts->{ $contrastID };
		my $contrastPosition = $contrastIDorder->{ $contrastID };

		my $testAssayGroupID = $xmlContrast->{ 'test_assay_group' };
		my $referenceAssayGroupID = $xmlContrast->{ 'reference_assay_group' };

        # Initialize $cttvPrimary with 0.
        my $cttvPrimary = 0;
        if( $xmlContrast->{ 'cttv_primary' } ) {
            $cttvPrimary = $xmlContrast->{ 'cttv_primary' };
        }

		# Create the batch effects if there are any.
		my $batchEffects;
		if( $xmlContrast->{ 'batch_effects' } ) {
			$batchEffects = _make_contrast_batch_effects( $xmlContrast->{ 'batch_effects' }->{ 'batch_effect' } );
		}

		my $contrast;

		if( $batchEffects ) {

			$contrast = Atlas::AtlasConfig::Contrast->new(
				test_assay_group => $assayGroupIDsToAssayGroups->{ $testAssayGroupID },
				reference_assay_group => $assayGroupIDsToAssayGroups->{ $referenceAssayGroupID },
				contrast_name => _contrast_name_to_safe( $xmlContrast->{ 'name' } ),
				contrast_id => $contrastID,
				contrast_position => $contrastPosition,
				batch_effects => $batchEffects,
                cttv_primary => $cttvPrimary,
			);

		} else {

			$contrast = Atlas::AtlasConfig::Contrast->new(
				test_assay_group => $assayGroupIDsToAssayGroups->{ $testAssayGroupID },
				reference_assay_group => $assayGroupIDsToAssayGroups->{ $referenceAssayGroupID },
				contrast_name => _contrast_name_to_safe( $xmlContrast->{ 'name' } ),
				contrast_id => $contrastID,
				contrast_position => $contrastPosition,
                cttv_primary => $cttvPrimary,
			);
		}

		push @{ $contrasts }, $contrast;
	}

	return $contrasts;
}


=item _contrast_name_to_safe

Try to make sure contrast names are safe for passing on cmdline.

=cut

sub _contrast_name_to_safe {

	my ( $contrastName ) = @_;

	$contrastName =~ s/\"/\'/g;

	return $contrastName;
}


=item _make_contrast_batch_effects

Not exported. Given a hash representing the batch effect(s) for a contrast,
create an array containing Atlas::AtlasConfig::BatchEffect objects and return
it.

=cut

sub _make_contrast_batch_effects {

	my ( $xmlBatchEffects ) = @_;

	my $batchEffects = [];

	foreach my $effectName ( sort keys %{ $xmlBatchEffects } ) {

		my $xmlBatches = $xmlBatchEffects->{ $effectName }->{ 'batch' };

		my $batches = [];

		foreach my $batchName ( sort keys %{ $xmlBatches } ) {

			my $assayNames = $xmlBatches->{ $batchName }->{ 'assay' };

			# Create a batch object for this batch.
			my $batch = Atlas::AtlasConfig::Batch->new(
				value => $batchName,
				assays => $assayNames
			);

			push @{ $batches }, $batch;
		}

		# Now we have an array of batches, create the batch effect object.
		my $batchEffect = Atlas::AtlasConfig::BatchEffect->new(
			name => $effectName,
			batches => $batches
		);

		push @{ $batchEffects }, $batchEffect;
	}

	return $batchEffects;
}


=item _map_assay_group_ids_to_assay_groups

Not exported. Takes arrayref of Atlas::AtlasConfig::AssayGroup objects. Returns a hash
mapping assay group IDs to Atlas::AtlasConfig::AssayGroup objects.

=cut

sub _map_assay_group_ids_to_assay_groups {

	my ( $assayGroups ) = @_;

	my $assayGroupIDsToAssayGroups = {};

	foreach my $assayGroup ( @{ $assayGroups } ) {

		my $assayGroupID = $assayGroup->get_assay_group_id;

		$assayGroupIDsToAssayGroups->{ $assayGroupID } = $assayGroup;
	}

	return $assayGroupIDsToAssayGroups;
}


1;

=back

=head1 AUTHOR

Expression Atlas team <arrayexpress-atlas@ebi.ac.uk>
