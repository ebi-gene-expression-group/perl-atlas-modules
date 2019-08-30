#!/usr/bin/env perl
#
=pod

=head1 NAME

Atlas::AtlasConfig::ExperimentConfig - contains Atlas analytics objects for experiment XML config.

=head1 SYNOPSIS

        use Atlas::AtlasConfig::ExperimentConfig;

		# ...

		my $experimentConfig = Atlas::AtlasConfig::ExperimentConfig->new(
			atlas_analytics => $arrayRefOfAtlasAnalyticsObjects,
			atlas_experiment_type => $atlasXmlExperimentType,
			experiment_accession => $experimentAccession,
		);


=head1 DESCRIPTION

An Atlas::AtlasConfig::ExperimentConfig object stores an array of
Atlas::AtlasConfig::Analytics objects to be written to the final experiment XML
config.  For RNA-seq experiments, there should be only one Analytics object.
For microarray, there should be one Analytics object per array design.

=cut

package Atlas::AtlasConfig::ExperimentConfig;

use Moose;
use MooseX::FollowPBP;
use Moose::Util::TypeConstraints;
use Log::Log4perl;
use Term::ANSIColor;

use Atlas::AtlasConfig::Common qw( 
	get_all_factor_types 
	get_numeric_timepoint_value	
	get_time_factor
);
use Atlas::Common qw(
    get_array_design_name_from_arrayexpress
    create_atlas_site_config
);

=head1 ATTRIBUTES

=over 2

=item atlas_analytics

An array containing one or more Atlas::AtlasConfig::Analytics objects to print to the
XML config file.

=cut

# Attributes for experiment config.
has 'atlas_analytics' => (
	is => 'rw',
	isa => 'ArrayRef[ Atlas::AtlasConfig::Analytics ]',
	required => 1,
);

=item atlas_experiment_type

A string containing the Atlas experiment type. These are defined in the Atlas site config.

=cut

has 'atlas_experiment_type' => (
	is => 'rw',
	isa => __PACKAGE__->_collect_allowed_experiment_types,
	required => 1,
);

=item experiment_accession

ArrayExpress accession of experiment, e.g. E-MTAB-1066.

=cut

has 'experiment_accession' => (
	is => 'rw',
	isa => subtype(
		as 'Str',
		where { /^E-\w{4}-\d+$/ },
	),
	required => 1,
);

=item r_data_present

1 if an R experiment summary exists for the experiment, 0 if not. Most
experiments have these, but proteomics and some special-access RNA-seq datasets
do not.

=cut

has 'r_data_present' => (
    is => 'rw',
    isa => 'Bool',
    predicate => 'has_r_data_present',
);


my $logger = Log::Log4perl::get_logger;

=back

=head1 METHODS

Each attribute has accessor (get_*), mutator (set_*), and predicate (has_*) methods.

=over 2

=item new

Instantiates a new Atlas::AtlasConfig::ExperimentConfig object.

=cut

sub BUILD {

    my ( $self ) = @_;

    # Check whether we already have an r_data_present attribute. If so, this
    # has been specified externally (probably by reading an existing XML
    # config) so we shouldn't try and decide automatically.
    if( $self->has_r_data_present ) { return; }

    # Default value for having an R experiment summary is 1 i.e. true (most
    # experiments have them).
    my $rDataPresent = 1;

    # Need to check the experiment type and/or the experiment accession to see
    # if this experiment should have an R experiment summary.
    my $experimentType = $self->get_atlas_experiment_type;

    # Proteomics experiments don't have R experiment summaries as the data is
    # currently too heterogeneous.
    if( $experimentType =~ /proteomics/i ) { 
    
        $logger->info( "Proteomics experiment: no R experiment summary allowed." );

        $self->set_r_data_present( 0 );

        return;
    }

    # If we're still here, check the config file with accessions of
    # [non-proteomics] experiments that do not have experiment summaries. The
    # usual reason is that we're not allowed access to the raw data e.g. the
    # FANTOM5 datasets.
    
    # The file name is stored in the Atlas site config.
    my $atlasSiteConfig = create_atlas_site_config;
    
    # Get the directory of Atlas production deployment. Make sure this is set
    # before continuing.
    my $atlasProdDir = $ENV{ "ATLAS_PROD" };
    unless( $atlasProdDir ) {
        $logger->logdie( "ATLAS_PROD environment variable not set. Please set this and try again." );
    }
    
    # Get the name of the file containing the accessions of experiments missing
    # R experiment summaries.
    my $rDataMissingFile = File::Spec->catfile(
        $atlasProdDir,
        $atlasSiteConfig->get_no_r_data_accessions_file
    );
    
    # Make sure we can read the file.
    unless( -r $rDataMissingFile ) {
        $logger->logdie( 
            "Cannot read file ",
            $rDataMissingFile,
            " to check accessions of experiments without R experiment summaries. Cannot continue."
        );
    }

    # Open file for reading.
    open( my $fh, "<", $rDataMissingFile ) or $logger->logdie( "Can't open $rDataMissingFile: $!" );
    
    # Hash to store accessions.
    my $rDataMissingAccessions = {};

    while( defined( my $line = <$fh> ) ){
        
        # Remove newline.
        chomp $line;
        
        # Make sure this looks like an ArrayExpress accession. Skip if not.
        unless( $line =~ /^E-\w{4}-\d+$/ ) { next; }

        # Add to hash.
        $rDataMissingAccessions->{ $line } = 1;
    }

    close( $fh );

    # Get the accession of this experiment.
    my $experimentAccession = $self->get_experiment_accession;

    # If this accession was found in the file, unset the flag for R experiment
    # summary.
    if( $rDataMissingAccessions->{ $experimentAccession } ) {

        $logger->info( "$experimentAccession found in list of accessions without R experiment summaries." );
        
        $self->set_r_data_present( 0 );

        return;
    }

    # If we're still here, we must be allowed an R experiment summary, so set
    # the r_data_present attribute as 1.
    $self->set_r_data_present( 1 );
}

=item write_xml

Writes the Atlas::AtlasConfig::ExperimentConfig and all it contains in XML format.

=cut

sub write_xml {
	my ($self, $outputDirectory, $assayGroupsOnly) = @_;

	use IO::File;
	use XML::Writer;
	use File::Spec;
    
    # Experiment types that are allowed to have batch effects.
	my $allowedBatchEffects = {
		"microarray_1colour_mrna_differential" => 1,
		"microarray_1colour_microrna_differential" => 1,
		"rnaseq_mrna_differential" => 1
	};
	
	# Filename for XML file.
	my $filename = File::Spec->catdir( $outputDirectory, $self->get_experiment_accession . "-configuration.xml.auto" );

	$logger->info("Writing XML config...");

	my $outputFile = IO::File->new(">$filename");
	my $xmlWriter = XML::Writer->new(OUTPUT => $outputFile, DATA_MODE => 1, DATA_INDENT => 4);
	
	# XML declaration.
	$xmlWriter->xmlDecl("UTF-8");

	# Begin XML, add experiment type.
	$xmlWriter->startTag( "configuration", 
        "experimentType" => $self->get_atlas_experiment_type,
        "r_data"    => $self->get_r_data_present
    );

    # Flag if this is a multi-array experiment.
    my $multiArray = 0;

	if( $self->get_atlas_experiment_type =~ /array/ && @{ $self->get_atlas_analytics } > 1 ) {
        $multiArray = 1;
    }

	# Add the analytics element(s).
	foreach my $atlasAnalytics (@{ $self->get_atlas_analytics }) {
        
        # Add array design name to contrast names for multi-array experiments,
        # as long as this isn't an assay-groups-only experiment.
        if( $multiArray ) {
           
            $logger->info( "Multi-array experiment detected, will add array design names to contrast names..." );
         
            unless( $atlasAnalytics->isa( "Atlas::AtlasConfig::Analytics::Differential::AssayGroupsOnly" ) ) {
            
                $atlasAnalytics = _add_array_design_name( $atlasAnalytics );
            
            } else {
                
                print color 'yellow';
                $logger->warn( "Curator, please add array design names to contrast names for a multi-array experiment." );
                print color 'reset';
            }
        }
        
        # Begin the analytics element.
		$xmlWriter->startTag("analytics");

		# Write the array design if there is one.
		unless($atlasAnalytics->get_platform eq "rnaseq") {
			$xmlWriter->dataElement("array_design" => $atlasAnalytics->get_platform);
		}

		# Now write the assay groups.
		$xmlWriter->startTag("assay_groups");

		# Go through the assay groups...
		foreach my $assayGroup (@{ $atlasAnalytics->get_atlas_assay_groups }) {

			# Write the ID and label in the "assay_group" element.
			$xmlWriter->startTag("assay_group", 
				"id" => $assayGroup->get_assay_group_id, 
				"label" => $assayGroup->get_label,
			);
			
			# If this is a differential experiment, need to check if the assay
			# group is in a contrast. If it's not, log this and add a comment.
			if( $atlasAnalytics->isa('Atlas::AtlasConfig::Analytics::Differential') ) {
				unless( _in_contrast( $assayGroup->get_assay_group_id, $atlasAnalytics->get_atlas_contrasts ) ) {
					$logger->warn("Assay group \"", $assayGroup->get_assay_group_id, "\" (", $assayGroup->get_label, ") was not involved in any contrasts.");
					$xmlWriter->comment("This assay group is not involved in any contrasts");
				}
			}
			
			# Write each assay from this AssayGroup's BiologicalReplicates.
			foreach my $biologicalReplicate (@{ $assayGroup->get_biological_replicates }) {
				# Get the assays from the BiologicalReplicate.
				foreach my $assay (@{ $biologicalReplicate->get_assays }) {
					if($assay->has_technical_replicate_group) {
						$xmlWriter->dataElement(
							"assay" => $assay->get_name,
							"technical_replicate_id" => $assay->get_technical_replicate_group
						);
					} else {
						$xmlWriter->dataElement(
							"assay" => $assay->get_name,
						);
					}
				}
			}
			# End this assay_group element.
			$xmlWriter->endTag("assay_group");
		}
		# End the assay_groups element.
		$xmlWriter->endTag("assay_groups");

		# If this analytics object is differential, write the contrasts.
		if($atlasAnalytics->isa('Atlas::AtlasConfig::Analytics::Differential')) {
			# Begin the contrasts element.
			$xmlWriter->startTag("contrasts");
			
			unless( $assayGroupsOnly ) {

				my $sortedContrasts = {};

				# See whether the contrasts have been ordered previously.
				my ( $firstContrast ) = @{ $atlasAnalytics->get_atlas_contrasts };
				if( $firstContrast->has_contrast_position ) {
					$sortedContrasts = _sort_contrasts_by_position( $atlasAnalytics->get_atlas_contrasts );
				}
				else {
					# Otherwise, sort the contrasts by time point, if applicable.
					$sortedContrasts = _sort_contrasts_by_time($atlasAnalytics->get_atlas_contrasts);
				}
				
				# Go through the contrasts...
				foreach my $contrast (@{ $sortedContrasts }) {
					# Begin contrast element and add ID.
					$xmlWriter->startTag("contrast",
						"id" => $contrast->get_contrast_id,
                        "cttv_primary" => $contrast->get_cttv_primary,
					);

					# Write the name, reference and test assay groups.
					$xmlWriter->dataElement("name" => $contrast->get_contrast_name);
					$xmlWriter->dataElement("reference_assay_group" => $contrast->get_reference_assay_group->get_assay_group_id);
					$xmlWriter->dataElement("test_assay_group" => $contrast->get_test_assay_group->get_assay_group_id);

					# If any potential batch effects were found, add these as well.
					if( $contrast->has_batch_effects && $allowedBatchEffects->{ $self->get_atlas_experiment_type } ) {
						
						$xmlWriter->startTag( "batch_effects" );

						my $batchEffects = $contrast->get_batch_effects;

						foreach my $batchEffect ( @{ $batchEffects } ) {

							my $batchEffectName = $batchEffect->get_name;

							$xmlWriter->startTag( "batch_effect", "name" => $batchEffectName );

							my $batches = $batchEffect->get_batches;

							foreach my $batch ( @{ $batches } ) {

								my $batchValue = $batch->get_value;

								$xmlWriter->startTag( "batch", "value" => $batchValue );

								my $assayNames = $batch->get_assays;

								foreach my $assayName ( @{ $assayNames } ) {

									$xmlWriter->dataElement( "assay" => $assayName );
								}

								$xmlWriter->endTag( "batch" );
							}

							$xmlWriter->endTag( "batch_effect" );
						}
						
						$xmlWriter->endTag( "batch_effects" );
					}
					elsif( $contrast->has_batch_effects ) {

						$logger->warn( 
							"Batch effect(s) found but cannot yet process them for experiments of type ",
							$self->get_atlas_experiment_type,
							" -- not adding them to XML."
						);
					}

					# End the contrast element.
					$xmlWriter->endTag("contrast");
				}
			}
			else {

				$xmlWriter->comment( "Please complete contrasts section below" );
				$xmlWriter->startTag( "contrast",
					"id" => "replace_with_contrast_id"
				);
				$xmlWriter->dataElement( "name" => "replace_with_contrast_name" );
				$xmlWriter->dataElement( "reference_assay_group" => "replace_with_reference_assay_group_id" );
				$xmlWriter->dataElement( "test_assay_group" => "replace_with_test_assay_group_id" );
				$xmlWriter->endTag( "contrast" );
				$xmlWriter->comment( "Add more contrasts if required" );
			}


			# End the contrasts element.
			$xmlWriter->endTag("contrasts");
		}

		# End the analytics element.
		$xmlWriter->endTag("analytics");
	}
	# End the configuration element.
	$xmlWriter->endTag("configuration");

	# End the XML.
	$xmlWriter->end;
	# Close the file.
	$outputFile->close;
	
	$logger->info("XML config generation successfully written to $filename");
}


=item remove_assay

Remove an assay from the experiment config. This may be needed if an assay
fails QC.

=cut

# FIXME: Would be safer to just comment out, or move to a "failed_qc" section of
# XML? Deleting completely can mean that if the experiment is re-processed, the
# failed assay(s) will not show up in the QC reports and it will not be obvious
# to users why they are not included.

sub remove_assay {

	my ( $self, $assayName ) = @_;

	foreach my $analytics ( @{ $self->get_atlas_analytics } ) {

		# Flag to set if we run out of assay groups/contrasts for this analytics
		# object.
		my $invalidAnalytics = 0;

		foreach my $assayGroup ( @{ $analytics->get_atlas_assay_groups } ) {
			
			# Flag to set if we run out of biological replicates for this assay
			# group.
			my $invalidAssayGroup = 0;

			foreach my $assay ( @{ $assayGroup->get_assays } ) {

				if( $assay->get_name eq $assayName ) {

					# Remove the assay from the assay group.
					$invalidAssayGroup = $assayGroup->remove_assay( $assayName );

					# Here need to remove the assay from any batch effects of
					# any contrasts that might exist as well.
					if( $analytics->isa( "Atlas::AtlasConfig::Analytics::Differential" ) ) {

						my $contrasts = $analytics->get_atlas_contrasts;

						foreach my $contrast ( @{ $contrasts } ) {

							if( $contrast->has_batch_effects ) {

								foreach my $batchEffect ( @{ $contrast->get_batch_effects } ) {

									$logger->debug( "Checking batch effect \"", $batchEffect->get_name, "\"..." );

									# A flag to set if any batch is invalid
									# after removing an assay. If any single
									# batch is invalid, we must remove the
									# entire batch effect.
									my $invalidBatch = 0;

									foreach my $batch ( @{ $batchEffect->get_batches } ) {

										# A flag to set if any assays are removed
										# at all. We need this so that after
										# removing all required assays we can then
										# check that this batch still has assays
										# from both the test and reference assay
										# groups.
										my $assaysRemoved = 0;

										$logger->debug( "checking batch \"", $batch->get_value, "\"..." );

										foreach my $assay ( @{ $batch->get_assays } ) {

											if( $assay eq $assayName ) {

												$logger->debug( 
													"Found assay \"$assayName\" in batch \"", 
													$batch->get_value,
													"\", removing it..."
												);

												# Need to remove it from the batch, and
												# then check that this batch and its batch
												# effect are still valid.
												# The batch is valid if there is more than
												# one assay left in it.
												$invalidBatch = $batch->remove_assay( $assayName );

												$logger->debug( 
													"Assay \"$assayName\" successfully removed from batch \"",
													$batch->get_value, "\""
												);

												if( $invalidBatch ) { last; }
											}
										}

										# If any assays were removed from this
										# batch, we now need to check that the
										# batch still contains assays from both
										# assay groups. If not, set the invalid
										# batch flag.
										$invalidBatch = _check_batch_is_valid( $batch, $contrast );
									}

									# If at least one of the batches was invalid, we have
									# to remove this batch effect from the contrast.
									if( $invalidBatch ) {
										
										$logger->warn( 
											"Removing batch effect \""
											. $batchEffect->get_name
											. "\" from contrast \""
											. $contrast->get_contrast_id
											. "\" as it is no longer valid after QC"
										);

										$contrast->remove_batch_effect( $batchEffect->get_name );
									}
									else {
										$logger->debug(
											"Batch effect \"", $batchEffect->get_name, "\" OK after QC"
										);
									}
								}
							}
						}
					}
				}
			}

			# If the assay group is invalid after removing this assay, i.e.
			# there are no longer enough biological replicates, then we need to
			# remove this assay group from the analytics object.
			if( $invalidAssayGroup ) {
				
				$invalidAnalytics = $analytics->remove_assay_group( $assayGroup->get_assay_group_id );
			}
		}


		
		# If the analytics object is invalid after removing this assay group,
		# we need to remove it from the experiment config.
		if( $invalidAnalytics ) {

			$self->_remove_analytics( $analytics->get_platform );
		}
	}
}


# Read the allowed experiment types from the site config.
sub _collect_allowed_experiment_types {

    my $atlasSiteConfig = create_atlas_site_config;

    return enum( $atlasSiteConfig->get_allowed_xml_experiment_types );
}


# _add_array_design_name
# Adds the array design names from the database to each contrast name for an Analytics object.
sub _add_array_design_name {
	
	my ( $atlasAnalytics ) = @_;

    my $arrayDesignAccession = $atlasAnalytics->get_platform;
    
    $logger->info( "Adding array design name to contrasts for $arrayDesignAccession..." );

    my $arrayDesignName = get_array_design_name_from_arrayexpress( $arrayDesignAccession );
    
    my $contrasts = $atlasAnalytics->get_atlas_contrasts;

    my $newContrasts = [];

    foreach my $contrast ( @{ $contrasts } ) {

        my $contrastName = $contrast->get_contrast_name;

        $contrastName .= " on '$arrayDesignName'";

        $contrast->set_contrast_name( $contrastName );
        
        push @{ $newContrasts }, $contrast;
    }

    $atlasAnalytics->set_atlas_contrasts( $newContrasts );

    $logger->info( "Array design names added." );
	
    return $atlasAnalytics;
}


# _in_contrast
# Test whether an assay group is involved in a contrast.
sub _in_contrast {

	my ( $assayGroupID, $contrasts ) = @_;
	
	# Flag to set if the assay group ID is found in a contrast.
	my $inContrast = 0;
	
	# Go through the contrasts...
	foreach my $contrast ( @{ $contrasts } ) {

		# Set the flag if the assay group ID matches that of either of the contrast's assay groups.
		foreach my $contrastAssayGroup ( $contrast->get_test_assay_group, $contrast->get_reference_assay_group ) {
			
			if( $contrastAssayGroup->get_assay_group_id eq $assayGroupID ) {

				$inContrast++;
			}
		}
	}
	
	return $inContrast;
}


# _sort_contrasts_by_time
# If there's a time factor, sort the contrasts to try and make the earliest one appear first.
sub _sort_contrasts_by_time {
	my ($contrasts) = @_;

	# First get all the test assay groups and then see if there's a time
	# factor.
	my $testAssayGroups = [];

	foreach my $contrast (@{ $contrasts }) {
		push @{ $testAssayGroups }, $contrast->get_test_assay_group;
	}

	my $testFactorTypes = get_all_factor_types(@{ $testAssayGroups });

	# If there's no time factor just return the contrasts as they are.
	unless( get_time_factor( $testFactorTypes ) ) {
		return $contrasts;
	}

	# If we're still here that means we've got a time factor in the test assay
	# groups, so need to sort.
	# Here's an array to put sorted contrasts in.
	my $sortedContrasts = [];

	# First sort the contrasts into a hash with the numeric value of the test
	# assay group's time factor as the key. If the test assay group does not
	# have a time factor, add them to the $sortedContrasts array at the start.
	my $timeValuesToContrasts = {};

	foreach my $contrast (@{ $contrasts }) {
		# Get the test assay group.
		my $testAssayGroup = $contrast->get_test_assay_group;
		
		# Get its factors.
		my $testFactors = $testAssayGroup->get_factors;

        my %testAgFactorTypes = map { $_ => 1 } ( keys %{ $testFactors } );

		# Find the time factor type.
		my ( $timeFactorType ) = get_time_factor( \%testAgFactorTypes );

		# Check that there is a time factor for this assay group. If not, push
		# it on to $sortedContrasts array now. Then it will appear first,
		# before the time contrasts, in the XML.
		unless($timeFactorType) {
			$logger->debug("No time factor for assay group \"", $testAssayGroup->get_assay_group_id, "\".");
			push @{ $sortedContrasts }, $contrast;
			next;
		}
		
		# If we're still here, get the numeric value of the time factor value.
		my $numericTimeValue = get_numeric_timepoint_value( ( keys %{ $testFactors->{ $timeFactorType } } )[ 0 ] );
		
		# Add the contrast to the hash under the key for the numeric time
		# point. There may be more than one contrast at this time point, so
		# create an array for each time point.
		if( $timeValuesToContrasts->{ $numericTimeValue } ) {
			push @{ $timeValuesToContrasts->{ $numericTimeValue } }, $contrast;
		} else {
			$timeValuesToContrasts->{ $numericTimeValue } = [ $contrast ];
		}
	}
	
	# Now add the time contrasts to the $sortedContrasts array as well.
	foreach my $numericTimeValue (sort { $a <=> $b } keys %{ $timeValuesToContrasts }) {

		foreach my $contrast (@{ $timeValuesToContrasts->{ $numericTimeValue } }) {

			push @{ $sortedContrasts }, $contrast;
		}
	}
	
	return $sortedContrasts;
}


# _sort_contrasts_by_position
# Contrast objects have a position attribute denoting which order they should
# appear in. This is used by the UI.
sub _sort_contrasts_by_position {

	my ( $contrasts ) = @_;
	
	my $sortedContrasts = [];

	my $contrastsByPosition = {};

	foreach my $contrast ( @{ $contrasts } ) {

		my $position = $contrast->get_contrast_position;

		$contrastsByPosition->{ $position } = $contrast;
	}

	foreach my $position ( sort { $a <=> $b } keys %{ $contrastsByPosition } ) {

		push @{ $sortedContrasts }, $contrastsByPosition->{ $position };
	}

	return $sortedContrasts;
}


# _check_batch_is_valid
# Not exported. Make sure a batch is still valid after removing assays that failed QC.
sub _check_batch_is_valid {

	my ( $batch, $contrast ) = @_;

	my $testAssays = $contrast->get_test_assay_group->get_assays;
	my $refAssays = $contrast->get_reference_assay_group->get_assays;

	my $batchAssays = $batch->get_assays;

	# Check the batch has assays in the test assay group.
	my $batchAssaysInTestGroup = 0;

	foreach my $batchAssay ( @{ $batchAssays } ) {

		foreach my $testAssay ( @{ $testAssays } ) {

			if( $testAssay->get_name eq $batchAssay ) {

				$batchAssaysInTestGroup++;
			}
		}
	}

	unless( $batchAssaysInTestGroup ) {
		
		$logger->warn( 
			"Batch \"",
			$batch->get_value,
			"\" does not have any assays left from the test assay group of contrast ",
			$contrast->get_contrast_id
		);
		
		return 1;
	}

	# If we're still here, also check that it still has assays in the reference assay group.
	my $batchAssaysInRefGroup = 0;

	foreach my $batchAssay ( @{ $batchAssays } ) {

		foreach my $refAssay ( @{ $refAssays } ) {

			if( $refAssay->get_name eq $batchAssay ) {

				$batchAssaysInRefGroup++;
			}
		}
	}

	unless( $batchAssaysInRefGroup ) {
		
		$logger->warn(
			"Batch \"",
			$batch->get_value,
			"\" does not have any assays left from the reference assay group of contrast ",
			$contrast->get_contrast_id
		);
		
		return 1;
	}

	# If we're still here, everything was OK, just return 0.
	return 0;
}


# _remove_analytics
# Removes an analytics object from the experiment config. Dies if there are
# none left after doing this.
sub _remove_analytics {

	my ( $self, $platformToRemove ) = @_;
	
	# Empty array for remaining analytics objects.
	my $newAnalytics = [];

	# Go through all the analytics objects...
	foreach my $analytics ( @{ $self->get_atlas_analytics } ) {
		
		# If this is not the one we want to remove, add it to the array of remaining
		# ones.
		unless( $analytics->get_platform eq $platformToRemove ) {
			push @{ $newAnalytics }, $analytics;
		}
	}
	
	# If we are still left with some analytics objects after removing one, set
	# the atlas_analytics attribute with the remaining ones.
	if( @{ $newAnalytics } ) {
		
		$self->set_atlas_analytics( $newAnalytics );
	}
	# Otherwise, we can't continue without any analytics objects, so we log and
	# die here.
	else {
		$logger->error( "No analytics elements remaining for experiment \""
							. $self->get_experiment_accession
							. "\" after removing analytics on platform \""
							. $platformToRemove
							. "\". Cannot continue."
		);
		exit 1;
	}
}

1;

=back

=head1 AUTHOR

Expression Atlas team <arrayexpress-atlas@ebi.ac.uk>

=cut

