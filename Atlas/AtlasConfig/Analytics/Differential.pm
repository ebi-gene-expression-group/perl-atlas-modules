#!/usr/bin/env perl
#

=pod

=head1 NAME

Atlas::AtlasConfig::Analytics::Differential - contains assay groups needed for Atlas analytics, as well as contrasts.

=head1 SYNOPSIS

        use Atlas::AtlasConfig::Analytics::Differential;

		# ...
		
		my $atlasAnalytics = Atlas::AtlasConfig::Analytics::Differential->new(
			platform => $platform,	# "rnaseq" or ArrayExpress array design accession
			assays => $arrayRefOfAssayObjects,
			reference_factor_values => $referenceFactorValuesHash,
		);

=head1 DESCRIPTION

An Atlas::AtlasConfig::Analytics::Differential object stores an array of
Atlas::AtlasConfig::AssayGroup objects that are used in one Atlas analytics element of
an Atlas experiment. It also stores the Contrast(s) containing AssayGroup
objects found in the array of AssayGroups. Building an object of this class
checks that each AssayGroup passed has at least three BiologicalReplicate
objects in its biological_replicates array.

=cut

package Atlas::AtlasConfig::Analytics::Differential;

use strict;
use warnings;
use 5.10.0;
use Moose;
use MooseX::FollowPBP;
use Log::Log4perl;
use Data::Compare;
use Data::Dumper;

use Atlas::AtlasConfig::Common qw(
	get_all_factor_types
	print_stdout_header_footer
	get_numeric_timepoint_value
	get_time_factor
);

extends 'Atlas::AtlasConfig::Analytics';

=head1 ATTRIBUTES

Inherited from Atlas::AtlasConfig::Analytics: atlas_assay_groups

=over 2

=item atlas_contrasts

An array of Atlas::AtlasConfig::Contrast objects.

=cut

has 'atlas_contrasts' => (
	is => 'rw',
	isa => 'ArrayRef[ Atlas::AtlasConfig::Contrast ]',
	lazy => 1,
	builder => '_build_atlas_contrasts',
	predicate => 'has_atlas_contrasts'
);

=item reference_factor_values

Hashref mapping known reference factor values to 1.

=cut

has 'reference_factor_values' => (
	is => 'rw',
	isa => 'HashRef',
);

my $logger = Log::Log4perl::get_logger;

=back

=head1 METHODS

Each attribute has accessor (get_*) and mutator (set_*) methods.

=over 2

=item new

Instantiates a new Atlas::AtlasConfig::Analytics::Differential object. Checks that all
AssayGroups passed have at least the minimum allowed BiologicalReplicates, dies
if not.

=cut

sub BUILD {
	my ($self) = @_;

	# Check that all assay groups provided have at least three biological
	# replicates.
	foreach my $atlasAssayGroup (@{ $self->get_atlas_assay_groups }) {
		if(@{ $atlasAssayGroup->get_biological_replicates } < $self->get_minimum_biological_replicates) {
			$logger->logdie("Assay group \"", $atlasAssayGroup->get_label, "\" does not have at least three biological replicates.\n");
		}
	}
}


# _build_minimum_biological_replicates
# Returns the minimum allowed number of BiologicalReplicates in a differential
# experiment. Currently this is 3.
sub _build_minimum_biological_replicates {
	return 3;
}


# _build_atlas_contrasts
# Attempts to create contrasts using supplied AssayGroup objects. If there's a
# "time" factor, calls _decide_time_series_contrasts. If not, calls
# _decide_contrasts.
sub _build_atlas_contrasts {
	my ($self) = @_;
	
	print_stdout_header_footer("Contrast creation START");

	# First look at the factor types of all the assay groups and see if "time"
	# is there.
	# Get all factor types.
	my $allFactorTypes = get_all_factor_types(@{ $self->get_atlas_assay_groups });

	# Empty array for the contrasts we find.
	my $contrasts = [];

	# Look for time.
	if( get_time_factor( $allFactorTypes ) ) {
		$logger->info( "Time factor found (", get_time_factor( $allFactorTypes ), ")" );

		$contrasts = $self->_decide_time_series_contrasts(
			$self->get_atlas_assay_groups, 
			$allFactorTypes,
		);
	}
	else {
		$contrasts = $self->_decide_contrasts(
			$self->get_atlas_assay_groups,
			$self->get_reference_factor_values,
		);
	}

	# Check whether any contrasts have been made. If not, log and return.
	unless( eval ' @{ $contrasts } ' ) {
		if($self->get_platform eq "rnaseq") {
			$logger->info("No contrasts found.");
		} else {
			$logger->info("No contrasts found for platform ", $self->get_platform, ".");
		}
		return;
	}
	
	# If we're still here, log and return the contrasts.
	my $numContrasts = @{ $contrasts };
	$logger->info("$numContrasts contrasts created.");

	print_stdout_header_footer("Contrast creation END");

	return $contrasts;
}

# _decide_contrasts
# Decides contrasts between a set of AssayGroups. First checks for presence of a
# possible reference value. If none is found in this set, it returns nothing.
# Then it goes through each pair of AssayGroups and decides if a contrast can be
# made between them. This is done by first checking if the pair only differs by exactly
# one factor value. If so, then it checks if, for this varying factor, one of the
# assay groups has a reference value and the other does not. If this condition is
# met, it creates a new Atlas::AtlasConfig::Contrast with them. It creates an ArrayRef
# of all the Contrasts it makes and returns this.
# It has an optional argument, $ignoreTime, which can be set to true if required.
# Doing this will mean that the function will ignore any "time" factor when
# counting the number of differences between assay group factor values.
sub _decide_contrasts {
	my ($self, $assayGroups, $ignoreTime) = @_;
    
    $logger->debug( "Deciding contrasts..." );
    
	# Check that we found at least one reference assay group. Return nothing if
	# not [or just do all vs. all instead?].
	unless( $self->_possible_reference_present($assayGroups) ) {
		$logger->warn("No potential reference assay group found.");
		return;
	}
    
    $logger->debug( "Possible reference assay group(s) found." );

	# Empty array to fill with contrasts.
	my $contrasts = [];

	# New data comparer to compare hashes and objects.
	my $dataComparer = Data::Compare->new();
	
	# Hash to remember pairs of assay groups we've already compared, so we
	# don't try to make twice the number of contrasts.
	my $seenPairs = {};

	# If we have at least one reference factor value, create contrast(s).
	# First thing we do is compare each assay group to each other assay group,
	# and check if, for each pair of assay groups, only one factor differs. The
	# check if the factor that varies has one reference value and one
	# non-reference value for this pair. If so, we can make a contrast.
	foreach my $assayGroupOne (@{ $assayGroups }) {
		foreach my $assayGroupTwo (@{ $assayGroups }) {
			# Skip if they are the same assay group.
			if($dataComparer->Cmp($assayGroupOne, $assayGroupTwo)) { next; }

			# Skip if we've seen this pair already.
			# Get numbers from assay group IDs
			(my $assayGroupOneNumber = $assayGroupOne->get_assay_group_id) =~ s/g//;
			(my $assayGroupTwoNumber = $assayGroupTwo->get_assay_group_id) =~ s/g//;
			# Sort them, stick them together.
			my $sortedIDnums = join "_", (sort { $a <=> $b } ($assayGroupOneNumber, $assayGroupTwoNumber));
			# Check if this ID is already in the $seenPairs hash. If so, skip
			# it. If not, add it and carry on.
			if($seenPairs->{ $sortedIDnums }) { next; }
			else { $seenPairs->{ $sortedIDnums } = 1; }


			# If there's only one difference, see if we can create a contrast.
			# For that, we have to find the factor that varies again.
			if( _one_factor_differs($assayGroupOne, $assayGroupTwo, $ignoreTime) ) {
				
				# Get the values of the varying factor for this pair.
				my ($assayGroupOneVaryingValue, $assayGroupTwoVaryingValue) = _get_varying_factor_values_for_pair(
					$assayGroupOne, 
					$assayGroupTwo, 
					$ignoreTime
				);

				# If both factor values are possible references, can't make a
				# contrast.
				if( $self->_is_reference_value( $assayGroupOneVaryingValue ) && $self->_is_reference_value( $assayGroupTwoVaryingValue ) ) {
					# Warn and skip.
					$logger->warn("Factor values \"$assayGroupOneVaryingValue\" and \"$assayGroupTwoVaryingValue\" are both potential reference values.");
					next;
				}

				# If we're still here, make a contrast.
				if( $self->_is_reference_value( $assayGroupOneVaryingValue ) ) {
					my $contrast = Atlas::AtlasConfig::Contrast->new(
						reference_assay_group => $assayGroupOne,
						test_assay_group => $assayGroupTwo,
					);
					$logger->info("Created contrast \"", $contrast->get_contrast_id, "\", named \"", $contrast->get_contrast_name, "\".");
					push @{ $contrasts }, $contrast;

				}
				elsif( $self->_is_reference_value( $assayGroupTwoVaryingValue ) ) {
					my $contrast = Atlas::AtlasConfig::Contrast->new(
						reference_assay_group => $assayGroupTwo,
						test_assay_group => $assayGroupOne,
					);
					$logger->info("Created contrast \"", $contrast->get_contrast_id, "\", named \"", $contrast->get_contrast_name, "\".");
					push @{ $contrasts }, $contrast;
				}
			}
			else {
				$logger->warn("Number of differences between assay groups \"", 
					$assayGroupOne->get_assay_group_id,
					"\" and \"",
					$assayGroupTwo->get_assay_group_id,
					"\" is not exactly 1.");
			}
		}
	}
    
    $logger->debug( "Contrasts decided." );

	return $contrasts;
}


# _decide_time_series_contrasts

# Decides contrasts for experiments with "time" as a factor. First it sorts out
# all assay groups by time point, in a hash. Those that do not have a time value
# specified are grouped together. It does not allow different time units to be
# used -- all time points must have the same units. It also does not allow
# negative time points. 
# If "time" is the only factor, it finds the AssayGroup with the earliest time
# point and calls _decide_contrasts_against_reference_assay_group to create new
# Atlas::AtlasConfig::Contrast objects using this as the reference and each other
# AssayGroup as a test group. It then returns these contrasts in an ArrayRef.
# If "time" is not the only factor, it counts the number of assay groups at each
# time point. If there is only one assay group at each time point, then it calls
# _decide_contrasts with all the assay groups, passing $ignoreTime=1. If some
# time points have more than one assay group, then it looks at each time point in
# turn. If the time point has more than one assay group, it decides contrasts
# between them by calling _decide_contrasts. If the time point has only one assay
# group, and it looks like a reference time point (calls
# _looks_like_reference_timepoint), then it decides contrasts between this and
# all other assay groups by calling
# _decide_contrasts_against_reference_assay_group and passing $ignoreTime=1.
# It returns an ArrayRef containing all the contrasts it created.
sub _decide_time_series_contrasts {
	
    my ($self, $assayGroups, $allFactorTypes) = @_;
	
	# Empty array for the contrasts.
	my $contrastsForAnalytics = [];
	
	# Map time points to assay groups.
	my $assayGroupsByTimePoint = $self->_map_time_points_to_assay_groups( $allFactorTypes, $assayGroups );;

	# Check that time points all use the same units. Return here if not.
	if( _different_time_units( $assayGroupsByTimePoint ) ) {
		$logger->warn("Different time units detected, this is not allowed.");
        return;
	}

	# Check if there are any negative time points and return here if so.
	if( _negative_time_point( $assayGroupsByTimePoint ) ) {
		$logger->warn("Negative time points are not allowed.");
        return;
	}
	
	# If time is the only factor, find the smallest time point and use this as
	# the reference.
	if((keys %{ $allFactorTypes }) == 1) {
		$logger->info("Time factor type is the only factor type.");
		
		my $earliestTimePoint;

		foreach my $timePoint (keys %{ $assayGroupsByTimePoint }) {
			if( _is_earliest_time_point($timePoint, $assayGroupsByTimePoint ) ) {
				$earliestTimePoint = $timePoint;
				last;
			}
		}

		$logger->info("The earliest time point is \"$earliestTimePoint\". Deciding contrasts.");
		
		$contrastsForAnalytics = $self->_decide_contrasts_against_reference_assay_group(
			${ $assayGroupsByTimePoint->{ $earliestTimePoint } }[0],
			$assayGroups,
		);
		
		return $contrastsForAnalytics;
	}

	# If there is at least one other factor as well as time, then for each time point:
	# 	- If there's more than one assay group at this time point, decide
	# 	contrasts between them (use _decide_contrasts).
	# 	- If there's only one assay group at this time point, decide contrasts
	# 	between it and all other assay groups.
	#
	# Watch out for blank time values! Most likely to occur for the second case.
	else {
		$logger->debug("Found a time factor type and other factor type(s).");

		# For each time point, see how many assay groups there are.  First
		# check if there is only one assay group at every time point. If so
		# then we want to decide contrasts between all the assay groups using
		# _decide_contrasts() and ignoring the time factor.
		my $maxTimePointAssayGroups = 0;
		foreach my $timePoint (keys %{ $assayGroupsByTimePoint }) {
			# Number of assay groups at this time point.
			my $numAssayGroups = @{ $assayGroupsByTimePoint->{ $timePoint } };
			
			# If this number is larger than the largest we've seen so far,
			# remember it.
			if($numAssayGroups > $maxTimePointAssayGroups) {
				$maxTimePointAssayGroups = $numAssayGroups;
			}
		}
		
		# If there's only one assay group at each time point,
		# $maxTimePointAssayGroups will be 1. So we can decide the contrasts as
		# if there was no time factor -- by calling _decide_contrasts() with
		# all assay groups and $ignoreTime = 1. This means that we make
		# contrasts between assay groups regardless of whether time is
		# different.
		if($maxTimePointAssayGroups == 1) {
			$logger->info("One assay group at each time point, deciding contrasts between them.");
			# Parameter to pass to _decide_contrasts() so it knows to allow
			# time factor values to vary between assay groups in contrasts, but
			# not to consider them when counting how many factors differ
			# between a pair of assay groups.
			my $ignoreTime = 1;

			# Create contrasts.
			$contrastsForAnalytics = $self->_decide_contrasts($assayGroups, $ignoreTime);
			
			# Return them.
			return $contrastsForAnalytics;
		}

		
		# If we're still here, there must have been at least some time points
		# that had more than one assay group. So, we do the following:
		# 	- If there's one assay group at a time point, decide contrasts
		# 	between this assay group and the ones where time differs.
		# 	- If there's more than one assay group at a time point, decide
		# 	contrasts between just those assay groups.
		foreach my $timePoint (keys %{ $assayGroupsByTimePoint }) {
			my $timePointAssayGroups = $assayGroupsByTimePoint->{ $timePoint };
			
			# Number of assay groups at this time point.
			my $numTimePointAssayGroups = @{ $timePointAssayGroups };
			
			# If there's more than one assay group at this time point, decide
			# contrasts between them.
			if($numTimePointAssayGroups > 1) {
				if($timePoint eq "time_value_not_specified") {
					$logger->info("$numTimePointAssayGroups assay groups without a time point, deciding contrasts between them.");
				} else {
					$logger->info("$numTimePointAssayGroups assay groups at time point \"$timePoint\", deciding contrasts between them.");
				}

				# Get a hash of contrasts for this time point.
				my $timePointContrasts = $self->_decide_contrasts($timePointAssayGroups);
				
				# Add these contrasts to the hash of all contrasts for this
				# analytics element.
				foreach my $contrast (@{ $timePointContrasts }) {
					push @{ $contrastsForAnalytics }, $contrast;
				}
			}
			
			# If there's only one assay group at this time point, see if this
			# is a reference assay group for this time series. In this case,
			# the time point value will be the smallest out of all of them, and
			# the other factor value(s) should all be reference values(?).
			#
			# If it looks like a reference time point, then decide contrasts
			# between this assay group and the rest, using
			# _decide_contrasts_against_reference_assay_group().
			#
			# This will cater for the case where we have e.g.:
			#
			# Time		Compound
			# 0 hour	none
			# 2	hour	none
			# 2	hour	X
			# 4	hour	none
			# 4	hour	X
			#
			# And we want to get the following contrasts:
			# "X at 2 hour vs none at 0 hour", "X at 4 hour vs none at 0 hour".
			# The logic in the if() statement above will take care of the
			# contrasts between X and none at each time point.
			else {
				$logger->info("One assay group at time point \"$timePoint\".");
				
				# Get the assay group for this time point.
				my $timePointAssayGroup = ${ $timePointAssayGroups }[0];

				# We want to ignore the time factor when deciding contrasts.
				my $ignoreTime = 1;
				
				# If it looks like a reference timepoint assay group...
				if( $self->_looks_like_reference_timepoint(
						$timePoint, 
						$timePointAssayGroup, 
						$assayGroupsByTimePoint, 
			    ) ) {
					
					$logger->info("Assay group at \"$timePoint\" looks like a reference, deciding contrasts.");
					
					# Decide contrasts using this as a reference assay group.
					my $timePointContrasts = $self->_decide_contrasts_against_reference_assay_group(
						$timePointAssayGroup, 
						$assayGroups, 
						$ignoreTime
					);
						

					# Add the contrast(s) we got to the array of all
					# contrasts for this analytics element.
					foreach my $contrast (@{ $timePointContrasts }) {
						push @{ $contrastsForAnalytics }, $contrast;
					}

				}
				else {
					# If it doesn't look like a reference time point, skip.
					$logger->debug("Assay group \"",
						$timePointAssayGroup->get_assay_group_id,
						"\" at time point \"$timePoint\" does not look like a reference assay group, skipping.");
					next;
				}
			}
		}
	}
	return $contrastsForAnalytics;
}


# _possible_reference_present
# Takes an ArrayRef of Atlas::AtlasConfig::AssayGroup objects and a hash with known
# reference factor values as keys. It looks at all the factor values in the assay
# groups provided and returns a value greater than 0 if any are known references.
sub _possible_reference_present {
	my ($self, $assayGroups) = @_;
    
    $logger->debug( "Checking for possible reference assay group(s)." );

	my $possibleReference = 0;
	foreach my $assayGroup (@{ $assayGroups }) {
		my $assayGroupFactors = $assayGroup->get_factors;

		foreach my $factorType ( keys %{ $assayGroupFactors } ) {
            
            my $factorValue = ( keys %{ $assayGroupFactors->{ $factorType } } )[ 0 ];

			if( $self->_is_reference_value( $factorValue ) ) {
				$logger->debug( "Possible reference factor value: $factorValue" );
				$possibleReference++;
			}
		}
	}
	
	return $possibleReference;
}


# _is_reference_value
# Check if a given value matches one on the list of known reference values.
sub _is_reference_value {

    my ( $self, $possibleReference ) = @_;
    
    $logger->debug( "Checking if $possibleReference is a reference value..." );

    my $referenceFactorValues = $self->get_reference_factor_values;

    foreach my $knownRef ( keys %{ $referenceFactorValues } ) {
        
        if( $possibleReference =~ /^\Q$knownRef\E$/i ) {
            
            $logger->debug( "$possibleReference is a reference value." );

            return 1;
        }
    }

    $logger->debug( "$possibleReference is not a reference value." );

    # If we're still here, no possible reference was found.
    return;
}


# _one_factor_differs
# Takes a pair of AssayGroup objects and returns 1 if there is only one
# difference between their factor values.
# Takes an optional argument $ignoreTime, which if true means it will ignore any
# "time" factor when counting differences.
sub _one_factor_differs {
	my ($assayGroupOne, $assayGroupTwo, $ignoreTime) = @_;

	# Get the factors for each assay group.
	my $assayGroupOneFactors = $assayGroupOne->get_factors;
	my $assayGroupTwoFactors = $assayGroupTwo->get_factors;

	# Collect all factor types from both assays in a new hash. This is
	# to account for the case where a factor is defined for one assay
	# group but not the other.
	my $pairFactorTypes = get_all_factor_types($assayGroupOne, $assayGroupTwo);

	# A counter for the number of factors whose values differ between
	# this pair of assay groups.
	my $differencesCounter = 0;

	# Go through the factor types.
	foreach my $factorType (keys %{ $pairFactorTypes }) {

		# Ignore block if it's there.
		if( $factorType =~ /^block$/i ) {
			$logger->debug( "Ignoring block factor" );
			next;
		}

		# Ignore time factor if required.
		if($ignoreTime && $factorType =~ /time/i) {
			$logger->debug("Ignoring time factor.");
			next;
		}

		# Get the factor values from each assay group.
		my $assayGroupOneValue = ( keys %{ $assayGroupOneFactors->{ $factorType } } )[ 0 ];
		my $assayGroupTwoValue = ( keys %{ $assayGroupTwoFactors->{ $factorType } } )[ 0 ];

		# Check that the value is defined for both assa groups. Skip if not.
		unless($assayGroupOneValue && $assayGroupTwoValue) {
			$logger->debug("Factor \"$factorType\" is not defined for both assay groups in this pair, skipping.");
			next;
		}

		# If the factor values are the same, do nothing (skip).
		if($assayGroupOneValue eq $assayGroupTwoValue) {
			# Debugging log.
			$logger->debug("\"$assayGroupOneValue\" and \"$assayGroupTwoValue\" are the same.");
			next;
		}
		# If they are different...
		else {
			# Increment the counter of differences between this pair.
			$differencesCounter++;
		
			# Debugging log.
			$logger->debug("\"$assayGroupOneValue\" and \"$assayGroupTwoValue\" are different.");
		}
	}
	
	# Return true if there's only one difference, false otherwise.
	if($differencesCounter == 1) { return 1; }
	else { return 0; }
}


# _get_varying_factor_values_for_pair
# Takes two AssayGroup objects and returns the values of the factor that varies.
# Takes an optional argument $ignoreTime, which if true means that it will ignore
# any "time" factor when finding the varying factor.
sub _get_varying_factor_values_for_pair {
	my ($assayGroupOne, $assayGroupTwo, $ignoreTime) = @_;

	my $pairFactorTypes = get_all_factor_types($assayGroupOne, $assayGroupTwo);
	
	# Get the factors for each assay group.
	my $assayGroupOneFactors = $assayGroupOne->get_factors;
	my $assayGroupTwoFactors = $assayGroupTwo->get_factors;
	
	my $varyingFactorType;

	foreach my $factorType (keys %{ $pairFactorTypes } ) {

		# Ignore block if it's there.
		if( $factorType =~ /^block$/i ) {
			next;
		}

		# If we're not considering the time factor here, skip it.
		if($ignoreTime && $factorType =~ /time/i) {
			next;
		}

		# Get the factor value for each assay group.
		my $assayGroupOneValue = ( keys %{ $assayGroupOneFactors->{ $factorType } } )[ 0 ];
		my $assayGroupTwoValue = ( keys %{ $assayGroupTwoFactors->{ $factorType } } )[ 0 ];

		# Check they're both defined.
		unless($assayGroupOneValue && $assayGroupTwoValue) {
			next;
		}

		# Find the ones that aren't the same.
		unless($assayGroupOneValue eq $assayGroupTwoValue) {
			$varyingFactorType = $factorType;
			last;
		}
	}

	# Now we know which factor varies, get the values and see if
	# one is a reference. If so, create a contrast and add it to
	# the hash. We use a hash to collect contrasts as it's easier
	# to make sure they're unique. 
	# Get the values of the varying factor.
	my $assayGroupOneVaryingValue = ( keys %{ $assayGroupOneFactors->{ $varyingFactorType } } )[ 0 ];
	my $assayGroupTwoVaryingValue = ( keys %{ $assayGroupTwoFactors->{ $varyingFactorType } } )[ 0 ];
	
	# Return these values.
	return($assayGroupOneVaryingValue, $assayGroupTwoVaryingValue);
}


# _map_time_points_to_assay_groups
# Takes a hash of factor types and an array of assay groups that have "time" as a
# factor. Returns a hash with the time points as keys and arrayrefs of assay
# groups as values.
sub _map_time_points_to_assay_groups {
	my ($self, $allFactorTypes, $assayGroups) = @_;

	# Get all the time factor values now. Create a hash of assay groups at
	# each time point. If assay group(s) have blank time values, warn and
	# use "time_value_not_specified" as a placeholder.
	
	# Get the time factor type.
	my $timeFactorType = get_time_factor( $allFactorTypes );

	# Now go through the assay groups and sort them out into a hash with
	# this time factor.
	my $assayGroupsByTimePoint = {};

	foreach my $assayGroup (@{ $assayGroups }) {
		
		my $assayGroupFactors = $assayGroup->get_factors;

		my $assayGroupTimePoint = ( keys %{ $assayGroupFactors->{ $timeFactorType } } )[ 0 ];
	
		# Use a placeholder if the time factor is not specified (TODO: is
		# this a good idea?).
		unless($assayGroupTimePoint) {
			$assayGroupTimePoint = "time_value_not_specified";
		}
		
		# Add assay group to hash under the time point value.
		if($assayGroupsByTimePoint->{ $assayGroupTimePoint }) {
			push @{ $assayGroupsByTimePoint->{ $assayGroupTimePoint } }, $assayGroup;
		} else {
			$assayGroupsByTimePoint->{ $assayGroupTimePoint } = [ $assayGroup ];
		}
	}
	return $assayGroupsByTimePoint;
}


# _looks_like_reference_timepoint
# Takes a time point, the assay group at that time point, all assay groups mapped
# to time points, and the reference factor values. Returns true if the assay
# group is the earliest time point over all, and all its other factor values are
# known reference values.
sub _looks_like_reference_timepoint {
	my ($self, $timePoint, $timePointAssayGroup, $assayGroupsByTimePoint) = @_;

	if( _is_earliest_time_point($timePoint, $assayGroupsByTimePoint) ) {

		$logger->debug("\"$timePoint\" is the earliest time point.");

		# Now see if the other factor values are known reference values.
		# Get the factors.
		my $assayGroupFactors = $timePointAssayGroup->get_factors;
	
		# Check that each value (except the time factor value) is a reference.
		# Flag to unset if non-reference is found.
		my $reference = 1;
		foreach my $factorType (keys %{ $assayGroupFactors }) {
			# Skip time.
			if($factorType =~ /time/i) { next; }
		
			# See if the value is a reference, set flag if not.
			unless( $self->_is_reference_value( ( keys %{ $assayGroupFactors->{ $factorType } } )[ 0 ] ) ) {
				$logger->debug("$factorType value \"", ( keys %{ $assayGroupFactors->{ $factorType } } )[ 0 ], "\" is not a known reference.");
				$reference = 0;
			}
		}
		if($reference) { 
			return 1; 
		} 
		else { 
			$logger->debug("Assay group at \"$timePoint\" does not look like a reference.");
			return 0; 
		}
	}
	else { 
		$logger->debug("Time point \"$timePoint\" is not the earliest time point.");
		return 0; 
	}
}


# _is_earliest_time_point
# Takes a time point and a hash of assay groups mapped to time points, and checks
# if the time point passed is the earliest of all of them. Returns 1 if so, 0 if not.
sub _is_earliest_time_point {
	my ($thisTimePoint, $assayGroupsByTimePoint) = @_;
	
	if($thisTimePoint =~ /time_value_not_specified/) {
		return 0;
	}

	# Get numeric time point values for each time point.
	my @numericTimePointValues = ();
	foreach my $timePoint (keys %{ $assayGroupsByTimePoint }) {

		if($timePoint =~ /time_value_not_specified/) { next; }
		
		push @numericTimePointValues, get_numeric_timepoint_value($timePoint);
	}
	
	# Sort them.
	@numericTimePointValues = sort { $a <=> $b } @numericTimePointValues;
	
	# Get the numeric value of *this* time point.
	my $thisTimePointNumeric = get_numeric_timepoint_value($thisTimePoint);
	
	# See if it's the same as the smallest value in the sorted time points.
	if($thisTimePointNumeric == $numericTimePointValues[0]) {
		return 1;
	} else {
		return 0;
	}
}


# _decide_contrasts_against_reference_assay_group
# Takes an assay group to use as a reference, an array of assay groups and a hash
# of known reference values. Tries to decide contrasts between the desired
# reference assay group and the assay groups in the array. Returns an ArrayRef of
# the contrasts it makes. Takes an optional argument $ignoreTime which if true
# means that any "time" factors are ignored when counting differences.
sub _decide_contrasts_against_reference_assay_group {
	my ($self, $referenceAssayGroup, $allAssayGroups, $ignoreTime) = @_;

	# Empty array to put contrasts in.
	my $contrasts = [];

	# Data comparer to compare hashes and objects.
	my $dataComparer = Data::Compare->new();

	foreach my $thisAssayGroup (@{ $allAssayGroups }) {
		# Skip if this is the same assay group as our intended reference.
		if($dataComparer->Cmp($referenceAssayGroup, $thisAssayGroup)) { next; }
		
		# See if there's one difference between the factors of this assay group
		# and our reference.
		if( _one_factor_differs($referenceAssayGroup, $thisAssayGroup, $ignoreTime) ) {
			# If so, get the factor values of the varying factor.
			my ($referenceAssayGroupVaryingValue, $thisAssayGroupVaryingValue) = _get_varying_factor_values_for_pair(
				$referenceAssayGroup,
				$thisAssayGroup,
				$ignoreTime
			);

			# Check the value from this assay group is not a reference as well, skip if it is.
			if( $self->_is_reference_value( $thisAssayGroupVaryingValue ) ) {
				$logger->debug("\"$thisAssayGroupVaryingValue\" and \"$referenceAssayGroupVaryingValue\" are both potential references.");
				next;
			}
			
			# Make a contrast.
			my $contrast = Atlas::AtlasConfig::Contrast->new(
				reference_assay_group => $referenceAssayGroup,
				test_assay_group => $thisAssayGroup,
			);
			
			push @{ $contrasts }, $contrast;
		}
		else {
			$logger->warn("Number of differences between assay groups \"", 
				$referenceAssayGroup->get_assay_group_id,
				"\" and \"",
				$thisAssayGroup->get_assay_group_id,
				"\" is not exactly 1.");
			next;
		}
	}
	
	return $contrasts;
}


# _different_time_units
# Tests whether time points have the same time units or different ones. Returns 1
# if different, 0 if the same.
sub _different_time_units {
	my ($assayGroupsByTimePoint) = @_;
	
	# Hash to collect units.
	my $seenUnits = {};

	foreach my $timePoint (keys %{ $assayGroupsByTimePoint }) {
		# Need to get the unit from the time point. This is the part after the
		# first space in the string.
		(my $unit = $timePoint) =~ s/^\S+\s+//g;
		
		# Don't bother trying to get units for "time_value_not_specified"
		if($unit eq "time_value_not_specified") { next; }
		
		# Add it to the hash of units we've seen.
		$seenUnits->{ $unit } = 1;
	}
	
	# If we've got more than one key in the hash, we've seen more than one
	# unit.
	if((keys %{ $seenUnits }) > 1) {
		return 1;
	} else {
		return 0;
	}
}


# _negative_time_point
# Checks if any time points have negative values. Returns 1 if so, 0 if not.
sub _negative_time_point {
	my ($assayGroupsByTimePoint) = @_;

	foreach my $timePoint (keys %{ $assayGroupsByTimePoint }) {

		if($timePoint =~ /time_value_not_specified/) { next; }

		# Test if the numeric value is < 0.
		if( get_numeric_timepoint_value($timePoint) < 0 ) {
			return 1;
		}
	}
}

=item remove_assay_group

Removes an assay group from the analytics object. Returns 1 if removing the
assay group means that the analytics object no longer has any contrasts left.
Returns 0 otherwise.

=cut

sub remove_assay_group {

	my ( $self, $idToRemove ) = @_;

	# Two empty arrays, one for new assay groups, one for new contrasts.
	$_ = {} for my ( $newAssayGroups, $newContrasts );

	my $contrastsRemoved = {};

	# Go through each assay group.
	foreach my $assayGroup ( @{ $self->get_atlas_assay_groups } ) {

		# If this isn't the one we want to remove, add it to array of new assay
		# groups.
		unless( $assayGroup->get_assay_group_id eq $idToRemove ) {

			$newAssayGroups->{ $assayGroup->get_assay_group_id } = $assayGroup;
		}
		
		# Go through the contrasts...
		foreach my $contrast ( @{ $self->get_atlas_contrasts } ) {
			
			# Flag to set if the assay group to remove is found in a contrast.
			my $idToRemoveInContrast = 0;
			
			# Go through the test and reference assay groups...
			foreach my $assayGroup ( $contrast->get_test_assay_group, $contrast->get_reference_assay_group ) {
				
				# If the assay group ID matches the one we want to remove, set
				# the flag.
				if( $assayGroup->get_assay_group_id eq $idToRemove ) {
					$idToRemoveInContrast++;
				}
			}
			
			# If the flag has not been set for this contrast, add it to the
			# array of new contrasts.
			unless( $idToRemoveInContrast ) {
				
				# If we haven't already added this contrast, then add it.
				unless( $newContrasts->{ $contrast->get_contrast_id } ) {
					
					# Add the contrast to the array of kept contrasts.
					$newContrasts->{ $contrast->get_contrast_id } = $contrast;
				}
			}
			# Otherwise, don't add it to the array of contrasts to keep, but
			# log that it's removed.
			else {
				
				# But only log if we haven't already.
				unless( $contrastsRemoved->{ $contrast->get_contrast_id } ) {

					$logger->info( "Removing contrast \"" 
									. $contrast->get_contrast_name 
									. "\" from analytics on platform \""
									. $self->get_platform . "\""
					);
				}

				$contrastsRemoved->{ $contrast->get_contrast_id } = 1;
			}
		}
	}

	# If we still have at least one contrast left, set the new assay groups and
	# contrasts for this analytics object. Return 0 to indicate nothing is wrong.
	if( keys %{ $newContrasts } ) {

		my @newAssayGroupsArray = sort values %{ $newAssayGroups };
		my @newContrastsArray = sort values %{ $newContrasts };

		$self->set_atlas_assay_groups( \@newAssayGroupsArray );
		$self->set_atlas_contrasts( \@newContrastsArray );
		
		return;
	}
	# Otherwise, log and return 1 to indicate we can't use this analytics
	# object any more.
	else {
		$logger->warn( "No contrasts remaining for analytics on platform \""
						. $self->get_platform
						. "\" after removing assay group \""
						. $idToRemove . "\""
		);

		return 1;
	}
}


1;

=back

=head1 AUTHOR

Expression Atlas team <arrayexpress-atlas@ebi.ac.uk>

=cut

