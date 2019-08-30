#!/usr/bin/env perl
#
=pod

=head1 NAME

Atlas::AtlasConfig::ExperimentConfigFactory - functions to create an
Atlas::AtlasConfig::ExperimentConfig object.

=head1 SYNOPSIS
	
	use Atlas::AtlasConfig::ExperimentConfigFactory qw( create_experiment_config );

	# ...
	my $experimentConfig = create_experiment_config(
		$Magetab4AtlasObject,		# contains Atlas-relevant data from MAGE-TAB
		$atlasXMLExperimentType,	# e.g. microarray_1colour_mrna_differential
		$experimentAccession,
		$referenceFactorValuesHash,
	);


=head1 DESCRIPTION

This module exports functions to create the Atlas XML config, as a Moose
object.

=cut

package Atlas::AtlasConfig::ExperimentConfigFactory;

use Moose;
use MooseX::FollowPBP;
use Atlas::AtlasConfig::BiologicalReplicate;
use Atlas::AtlasConfig::AssayGroup;
use Atlas::AtlasConfig::Analytics;
use Atlas::AtlasConfig::Analytics::Differential;
use Atlas::AtlasConfig::Analytics::Differential::AssayGroupsOnly;
use Atlas::AtlasConfig::Contrast;
use Atlas::AtlasConfig::ExperimentConfig;
use Log::Log4perl;
use Data::Compare;

use base 'Exporter';
our @EXPORT_OK = qw(
	create_experiment_config
);
	
my $logger = Log::Log4perl::get_logger;

=head1 METHODS

=over 2

=item create_experiment_config

Takes a Magetab4Atlas object and an Atlas experiment type, and returns an
Atlas::AtlasConfig::ExperimentConfig object with the appropriate
Atlas::AtlasConfig::Analytics objects inside, ready for writing to XML.

=cut

sub create_experiment_config {
	my ($magetab4atlas, $atlasExperimentType, $experimentAccession, $referenceFactorValues, $assayGroupsOnly) = @_;
	
	# Get the assays.
	my $platformsToAssays = $magetab4atlas->get_platforms_to_assays;

	# Empty array for the analytics object(s).
	my $atlasAnalyticsSet = [];
	
	# Variable to store the assay group ID counter. This counter is passed to
	# each new Analytics element, and incremented during its creation (see
	# Analytics.pm). That way we avoid re-using the same assay group IDs for
	# different Anaytics elements, when we have more than one platform in the
	# same experiment.
	my $assayGroupIDCounter = 1;

	foreach my $platform (sort keys %{ $platformsToAssays }) {

        $logger->info( "Working on platform $platform..." );

		# For a Baseline experiment...
		if($atlasExperimentType =~ /baseline/) {
			# Make a new Analytics object.
			my $atlasAnalytics = Atlas::AtlasConfig::Analytics->new( 
				platform => $platform,
				assays => $platformsToAssays->{ $platform },
				assay_group_id_counter => $assayGroupIDCounter,
			);
			
			# Check that it worked by trying to access assay groups.
			if( eval { $atlasAnalytics->get_atlas_assay_groups } ) {
				# If it worked, add Analytics object to array.
				push @{ $atlasAnalyticsSet }, $atlasAnalytics;
			}
			# If not, warn.
			else {
				if($platform eq "rnaseq") {
					$logger->warn("No analytics created.");
				} else {
					$logger->warn("No analytics created for platform $platform.");
				}
			}
			# Get the new assay group count, to pass to the Analytics element
			# for the next platform, if any.	
			$assayGroupIDCounter = $atlasAnalytics->get_assay_group_id_counter;
		}
		# For a Differential experiment...
		elsif($atlasExperimentType =~ /differential/) {
			
			my $atlasAnalytics;

			unless( $assayGroupsOnly ) {
				# Make a new Analytics::Differential object
				$atlasAnalytics = Atlas::AtlasConfig::Analytics::Differential->new(
					platform => $platform,
					assays => $platformsToAssays->{ $platform },
					reference_factor_values => $referenceFactorValues,
					assay_group_id_counter => $assayGroupIDCounter,
				);
			}
			else {
				$atlasAnalytics = Atlas::AtlasConfig::Analytics::Differential::AssayGroupsOnly->new(
					platform => $platform,
					assays => $platformsToAssays->{ $platform },
					assay_group_id_counter => $assayGroupIDCounter,
					assay_groups_only => $assayGroupsOnly
				);
			}
			
			# Flag to set if analytics creation was successful.
			my $analyticsCreated = 0;

			# If we were passed assay groups only option, try and access the
			# assay groups to check that analytics creation worked.
			if( $assayGroupsOnly ) {

				if( eval { $atlasAnalytics->get_atlas_assay_groups } ) {
					
					# If it worked, add the analytics object to the array.
					push @{ $atlasAnalyticsSet }, $atlasAnalytics;
					
					# Increment flag.
					$analyticsCreated++;
				}
			}
			else {
				# Check that it worked by trying to access contrasts.
				if( eval { $atlasAnalytics->get_atlas_contrasts } ) {
					# If it worked, add object to array.
					push @{ $atlasAnalyticsSet }, $atlasAnalytics;

					$analyticsCreated++;
				}
			}

			# If no analytics were created, warn.
			unless( $analyticsCreated ) {
				if($platform eq "rnaseq") {
					$logger->warn("No analytics created.");
				} else {
					$logger->warn("No analytics created for platform $platform.");
				}
			}

			# Get the new assay group count, to pass to the Analytics element
			# for the next platform, if any.	
			$assayGroupIDCounter = $atlasAnalytics->get_assay_group_id_counter;
		}
	}
	
	# If we don't have any Analytics objects for this experiment, can't do anything so die.
	unless( eval { @{ $atlasAnalyticsSet } } ) {
		$logger->logdie("No analytics elements were created for this experiment. Cannot continue");
	}

	# If we're still alive, create the config.
	my $experimentConfig = Atlas::AtlasConfig::ExperimentConfig->new(
		atlas_analytics => $atlasAnalyticsSet,
		atlas_experiment_type => $atlasExperimentType,
		experiment_accession => $experimentAccession,
	);

	return $experimentConfig;
}


1;

=back

=head1 AUTHOR

Expression Atlas team <arrayexpress-atlas@ebi.ac.uk>

=cut

