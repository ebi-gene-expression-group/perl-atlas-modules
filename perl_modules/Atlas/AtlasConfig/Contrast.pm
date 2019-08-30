#!/usr/bin/env perl
#
=pod

=head1 NAME

Atlas::AtlasConfig::Contrast - contains assay groups required for a contrast, a contrast ID and a contrast name.

=head1 SYNOPSIS

        use Atlas::AtlasConfig::Contrast;

		# ...
		my $contrast = Atlas::AtlasConfig::Contrast->new(
			reference_assay_group => $testAssayGroupObject,
			test_assay_group => $referenceAssayGroupObject,
		);

=head1 DESCRIPTION

An Atlas::AtlasConfig::Contrast object stores a reference and a test assay group, a contrast
name and a contrast ID in the format "g1_g2".

=cut

package Atlas::AtlasConfig::Contrast;

use strict;
use warnings;
use 5.10.0;

use Moose;
use MooseX::FollowPBP;
use Moose::Util::TypeConstraints;
use Log::Log4perl;
use XML::Writer;

use Atlas::AtlasConfig::BatchEffect;
use Atlas::AtlasConfig::Batch;
use Atlas::AtlasConfig::BiologicalReplicate;
use Atlas::AtlasConfig::Common qw(
	get_all_factor_types
	print_stdout_header_footer	
);


=head1 ATTRIBUTES

=over 2

=item test_assay_group

Atlas::AtlasConfig::AssayGroup to be used as the test group in the contrast.

=cut

# Attributes for analytics.
has 'test_assay_group' => (
	is => 'rw',
	isa => 'Atlas::AtlasConfig::AssayGroup',
	required => 1,
);

=item reference_assay_group

Atlas::AtlasConfig::AssayGroup to be used as the reference group in the contrast.

=cut

has 'reference_assay_group' => (
	is => 'rw',
	isa => 'Atlas::AtlasConfig::AssayGroup',
	required => 1,
);

=item contrast_name

The human-readable name of the contrast, e.g. "mutant vs. wild type".

=cut

has 'contrast_name' => (
	is => 'rw',
	isa => 'Str',
	lazy_build => 1,
);

=item contrast_id

The contrast ID, which is in the format <reference_assay_group_id>_<test_assay_group_id>.

=cut

has 'contrast_id' => (
	is => 'ro',
	isa => subtype(
		as 'Str',
		where { /^g\d+_g\d+$/ },
	),
	lazy_build => 1,
);

=item contrast_position

The position the contrast takes in the output file (optional). This is needed
when we re-write XML files e.g. during QC, so that we maintain the curated
ordering of the contrasts in the re-written file. The ordering of the contrasts
in the XML file is used in the web interface.

=cut

has 'contrast_position' => (
	is => 'rw',
	isa => 'Int',
	predicate => 'has_contrast_position'
);

=item batch_effects

Reference to array containing Atlas::AtlasConfig::BatchEffect objects.

=cut
has 'batch_effects' => (
	is => 'rw',
	isa => 'ArrayRef[ Atlas::AtlasConfig::BatchEffect ]',
	predicate => 'has_batch_effects',
	clearer => 'clear_batch_effects'
);

=item cttv_primary

This attribute denotes whether the contrast is a "primary" "disease vs normal"
type contrast -- CTTV only want to show transcript activity for contrasts on
real human subjects and where primary diseased tissue is compared with primary
non-diseased tissue. This excludes things like cell lines, treatments, and
experiments where a non-primary tissue is being investigated e.g. breat
carcinoma in lymph node (E-GEOD-44408).

=cut

has 'cttv_primary' => (
    is => 'rw',
    isa => 'Bool',
    default => 0
);

=back

=head1 METHODS

Each attribute has accessor (get_*) and mutator (set_*) methods.

=over 2

=item new

Instantiates a new Atlas::AtlasConfig::Contrast object.

=item _build_contrast_id

Creates a contrast ID out of the assay group IDs and returns it.

=cut

# Get the logger
my $logger = Log::Log4perl::get_logger;


sub BUILD {

	my ( $self ) = @_;

	$self->detect_and_add_batch_effects;
}


sub _build_contrast_id {
	my ($self) = @_;

	my $testAssayGroup = $self->get_test_assay_group;
	my $referenceAssayGroup = $self->get_reference_assay_group;

	my $contrastID = $referenceAssayGroup->get_assay_group_id . "_" . $testAssayGroup->get_assay_group_id;

	return $contrastID;
}


=item detect_and_add_batch_effects

Checks for batch effects and adds them if there are any.

=cut

sub detect_and_add_batch_effects {

	my ( $self ) = @_;
	
	# Get the contrast ID.
	my $contrastID = $self->get_contrast_id;
	
	# Get the assay groups for this contrast.
	my $testAssayGroup = $self->get_test_assay_group;
	my $referenceAssayGroup = $self->get_reference_assay_group;

	# Get the set of biological replicates for each assay group.
	my $testBioReps = $testAssayGroup->get_biological_replicates;
	my $refBioReps = $referenceAssayGroup->get_biological_replicates;
	
	# Go through the biological replicates for each assay group and check the
	# characteristics and factors for potential batch effects.
	# First we count each property type and value. All characteristics are
	# considered, as long as they aren't already factors. The only factor that
	# is considered is "block", as it can't be a characteristic. We also want
	# to consider the library layout, so we have to get that from the
	# Assay objects.
	my $testPropertyCounts = _count_properties( $testBioReps );
	my $refPropertyCounts = _count_properties( $refBioReps );

	# Now go through the counted properties and look for ones that could be
	# batch effects for this contrast. For each property, the count must be
	# more than one in both the test and reference group.
	my $batchTypes = _detect_batch_types( $testPropertyCounts, $refPropertyCounts );
	
	# If we have any batch effects, create an array of Atlas::BatchEffect objects.
	if( @{ $batchTypes } ) {

		$logger->info( "Processing batch effects for contrast $contrastID..." );

		# Empty array for batch effects.
		my $batchEffects = [];
		
		# Go through the array of types.
		foreach my $type ( @{ $batchTypes } ) {
			
			$logger->info( "Found potential batch effect: $type" );

			# Empty hash for this batch 
			my $batchEffectHash= {
				"type"	=> $type
			};
			
			# Go through the assays for each set of biological replicates and
			# get the values for this batch effect.
			foreach my $bioRepSet ( $testBioReps, $refBioReps ) {

				# Go through the biological replicates...
				foreach my $bioRep ( @{ $bioRepSet } ) {
					
					# Go through the the assays
					foreach my $assay ( @{ $bioRep->get_assays } ) {

						# Get the assay name.
						my $assayName = $assay->get_name;

						# If this is a block effect, the values are in the factors...
						if( $type eq "block" ) {
							
							# Get the factors.
							my $factors = $assay->get_factors;
							
							# Get the block value.
							my $value = ( keys %{ $factors->{ $type } } )[ 0 ];
							
							# Add this assay to the batch effects hash under this value
							# and type.
							$batchEffectHash->{ "values" }->{ $value }->{ $assayName } = 1;
						
						}
                        # If this is a library layout effect, the values are
                        # just in the library_layout attribute.
                        elsif( $type eq "library_layout" ) {
                            
                            my $libLayout = $assay->get_library_layout;

                            $batchEffectHash->{ "values" }->{ $libLayout }->{ $assayName } = 1;
                        }
                        else {
							
							# If this is not a block effect, then it's in the sample
							# characteristics.
							# Get the characteristics.
							my $characteristics = $assay->get_characteristics;

							# Get the value for this type.
							my $value = ( keys %{ $characteristics->{ $type } } )[ 0 ];

							# Add it to the batch effects hash.
							$batchEffectHash->{ "values" }->{ $value }->{ $assayName } = 1;
						}
					}
				}
			}

			my $batchEffect = _create_batch_effect( $batchEffectHash );

			push @{ $batchEffects }, $batchEffect;

			$logger->info( "Successfully created batch effect \"$type\"" );
		}

		$self->set_batch_effects( $batchEffects );
	
	}
}


=item _create_batch_effect

Creates and returns an Atlas::AtlasConfig::BatchEffect object.

=cut

sub _create_batch_effect {

	my ( $batchEffectHash ) = @_;

	my $batches = [];

	my $type = $batchEffectHash->{ "type" };

	foreach my $value ( keys %{ $batchEffectHash->{ "values" } } ) {

		my @assayNames = keys %{ $batchEffectHash->{ "values" }->{ $value } };

		my $batch = Atlas::AtlasConfig::Batch->new(
			value => $value,
			assays => \@assayNames,
		);

		push @{ $batches }, $batch;
	}
	
	unless( @{ $batches } > 1 ) {
		$logger->logdie( "Batch effects must have at least two batches. Property \"$type\" does not meet this condition." );
	}

	my $batchEffect = Atlas::AtlasConfig::BatchEffect->new(
		name => $type,
		batches => $batches,
	);

	return $batchEffect;
}


=item _detect_batch_types

Check the property counts for batch effect types.

=cut

sub _detect_batch_types {

	my ( $testPropertyCounts, $refPropertyCounts ) = @_;

	my $batchTypes = [];

	# Go through the test assay group's property counts...
	foreach my $testType ( keys %{ $testPropertyCounts } ) {

		# First check that this type has more than one value in the test assay
		# group. Skip if not.
		my @testValues = sort keys %{ $testPropertyCounts->{ $testType } };
		unless( @testValues > 1 ) { next; }

		# If we're still here, this property has more than one value in the
		# test assay group. Next thing is to check that it exists in the
		# reference assay group, and skip if not.
		unless( exists( $refPropertyCounts->{ $testType } ) ) { next; }

		# If we're still here, we have the same property type in the reference
		# assay group. Next we need to make sure the values for this type in
		# the reference assay group are the same as the ones in the test assay
		# group.
		my @refValues = sort keys %{ $refPropertyCounts->{ $testType } };
		# First check the arrays of values are the same length.
		unless( @testValues == @refValues ) { next; }
		# If we're still here, go through the values and make sure they are all
		# the same.
		my $potential = 1;	# flag to unset if two values are not the same.
		my $length = @testValues;
		
		for( my $i = 0; $i < $length; $i++ ) {

			# If the two values at this position are not the same, unset the
			# flag.
			unless( $testValues[ $i ] eq $refValues[ $i ] ) { $potential = 0; }
		}
		
		if( $potential ) {
			push @{ $batchTypes }, $testType;
		}
	}

	return $batchTypes;
}

=item _count_properties

Count the occurrences of each characteristic value, as well as factor "block"
and library layouts -- while looking for potential batch effects.

=cut

sub _count_properties {

	my ( $bioReps ) = @_;

	my $propertyCounts = {};

	foreach my $bioRep ( @{ $bioReps } ) {

		my $characteristics = $bioRep->get_characteristics;
		my $factors = $bioRep->get_factors;

		foreach my $charType ( keys %{ $characteristics } ) {

			# Skip if this one is in the factors.
			if( grep $_ eq $charType, ( keys %{ $factors } ) ) { next; }
			
			# Get the value.
			my $charValue = ( keys %{ $characteristics->{ $charType } } )[ 0 ];

			# Add to the counts for this type and value.
			if( $propertyCounts->{ $charType }->{ $charValue } ) {
				$propertyCounts->{ $charType }->{ $charValue } += 1;
			}
			else {
				$propertyCounts->{ $charType }->{ $charValue } = 1;
			}
		}

		# Also check factors for "block" property which is only allowed in
		# factors and not characteristics.
		if( grep $_ =~ /block/i, ( keys %{ $factors } ) ) {

			my $blockValue = ( keys %{ $factors->{ "block" } } )[ 0 ];

			if( $propertyCounts->{ "block" }->{ $blockValue } ) {
				$propertyCounts->{ "block" }->{ $blockValue } += 1;
			}
			else {
				$propertyCounts->{ "block" }->{ $blockValue } = 1;
			}
		}

		# Also go through the assays and check the RNA-seq library layouts
		# (paired-end or single-end).
		my $assays = $bioRep->get_assays;

		foreach my $assay ( @{ $assays } ) {
			if( $assay->has_library_layout ) {

				my $libLayout = $assay->get_library_layout;

				if( $propertyCounts->{ "library_layout" }->{ $libLayout } ) {
					$propertyCounts->{ "library_layout" }->{ $libLayout } += 1;
				} else {
					$propertyCounts->{ "library_layout" }->{ $libLayout } = 1;
				}
			}
		}
	}

	return $propertyCounts;
}


=item remove_batch_effect 

Remove a batch effect if it is no longer valid after removing assay(s) that
failed QC.

=cut

sub remove_batch_effect {

	my ( $self, $nameToRemove ) = @_;

	my $newBatchEffects = [];

	foreach my $batchEffect ( @{ $self->get_batch_effects } ) {

		unless( $batchEffect->get_name eq $nameToRemove ) {
			push @{ $newBatchEffects }, $batchEffect;
		}
	}

	# If we still have some batch effects left after removing the invalid one,
	# set the batch efects array just using the new ones.
	if( @{ $newBatchEffects } ) {
		$self->set_batch_effects( $newBatchEffects );
	}
	else {
		# Otherwise, remove the batch effects attribute completely.
		$self->clear_batch_effects;
	}

}


=item _build_contrast_name

Creates contrast name and returns it. Uses the varying (non-shared) factor
values for the first part of the name e.g. "salt vs none". Then uses the shared
factor values for the second part e.g. "in wild type". Adds "at" for time
values.

=cut

sub _build_contrast_name {
	my ($self) = @_;

	# Find the varying factor(s) and the shared factor value(s) (if any).
	my ($testVaryingFactors, $referenceVaryingFactors, $sharedFactors) = _get_varying_and_shared_factors($self->get_test_assay_group, $self->get_reference_assay_group);

	# Now make the first part of the contrast name, from the varying factors.
	my $contrastNameBeginning = _make_contrast_name_beginning($testVaryingFactors, $referenceVaryingFactors);

	# Begin the contrast name.
	my $contrastName = $contrastNameBeginning;
	
	# Next create a contrast name ending from the shared factor values, if
	# there are any.
	if(keys %{ $sharedFactors }) {

		my $contrastNameEnding = _factor_values_to_sentence($sharedFactors);
	
		# If the only shared factor is a time value, join them together with " at ".
		if((keys %{ $sharedFactors }) == 1 && grep { /time/i } (keys %{ $sharedFactors })) {
			$contrastName .= " at $contrastNameEnding";
		} 
		# Otherwise, join them with " in ".
		else {
			$contrastName .= " in ".$contrastNameEnding;
		}
	}
	
	return $contrastName;
}


=item _get_varying_and_shared_factors

Takes a test and reference AssayGroup object, figures out which factor values
are shared between then and which are not, and returns three hashes: one of
non-shared test factors, one of non-shared reference factors, and one of the
shared factors.

=cut
sub _get_varying_and_shared_factors {
	my ($testAssayGroup, $referenceAssayGroup) = @_;

	# Get all the factor types for the test and reference.
	my $allFactorTypes = get_all_factor_types($testAssayGroup, $referenceAssayGroup);

	# Get the factors for each assay group.
	my $testAssayGroupFactors = $testAssayGroup->get_factors;
	my $referenceAssayGroupFactors = $referenceAssayGroup->get_factors;

	# Hashes to keep varying factor(s) in.
	$_ = {} for my ($testVaryingFactors, $referenceVaryingFactors, $sharedFactors);
	
	foreach my $factorType (sort keys %{ $allFactorTypes }) {

		# Skip block if it's there.
		if( $factorType =~ /^block$/i ) { next; }

		# Get the factor value for each assay group.
		my $testAssayGroupValue = ( keys %{ $testAssayGroupFactors->{ $factorType } } )[ 0 ];
		my $referenceAssayGroupValue = ( keys %{ $referenceAssayGroupFactors->{ $factorType } } )[ 0 ];

		# Check if they're both defined and if so, check if they are different:
		if($testAssayGroupValue && $referenceAssayGroupValue) {
			# If they're different, add them to their respective hashes to return.
			unless($testAssayGroupValue eq $referenceAssayGroupValue) {
				$testVaryingFactors->{ $factorType } = $testAssayGroupValue;
				$referenceVaryingFactors->{ $factorType } = $referenceAssayGroupValue;
			}
			# Otherwise if they're both defined but they are the same, add to
			# hash for shared factors.
			else {
				$sharedFactors->{ $factorType } = $testAssayGroupValue;
			}
		}
		# Otherwise if only the test assay group value is defined:
		elsif($testAssayGroupValue) {
			# Add it to the test group's hash.
			$testVaryingFactors->{ $factorType } = $testAssayGroupValue;
		}
		# Otherwise if only the referene assay group value is defined:
		elsif($referenceAssayGroupValue) {
			# Add it to the reference group's hash.
			$referenceVaryingFactors->{ $factorType } = $referenceAssayGroupValue;
		}
	}
    
	# Return the hashes we just made.
	return ($testVaryingFactors, $referenceVaryingFactors, $sharedFactors);
}


=item _make_contrast_name_beginning

Makes two sentences from the non-shared test and reference factor values, joins
them with " vs ".

=cut
sub _make_contrast_name_beginning {
	my ($testVaryingFactors, $referenceVaryingFactors) = @_;

	# Make the two halves of the contrast name beginning.
	my $testSentence = _factor_values_to_sentence($testVaryingFactors);
	my $referenceSentence = _factor_values_to_sentence($referenceVaryingFactors);

	# Join them with "vs" and return.
	return "$testSentence vs $referenceSentence";
}


=item _factor_values_to_sentence

Takes a hash mapping factors to factor values, and creates a sentence out of
them such as: "'wild type; none' at '2 hour'".

=cut
sub _factor_values_to_sentence {
	my ($factors) = @_;
    
    # An array for factor values that are not times.
	my $nonTimeValues = [];
	# Somewhere to put time factor value if we find one.
	my $timeValue;
	
	# Go through the factors...
	foreach my $factorType (sort keys %{ $factors }) {
		# Remember the time value if we see one.
		if($factorType =~ /time/i) {
			$timeValue = $factors->{ $factorType };
		}
		# Add non-time values to the array.
		else {
			push @{ $nonTimeValues }, $factors->{ $factorType };
		}
	}
	
	# Variable for sentence.
	my $sentence;

	# If there are non-time values:
	if(@{ $nonTimeValues }) {

		# Start sentence by joining non-time factor values.
		$sentence = "'". (join "; ", @{ $nonTimeValues }) ."'";

		# Add the time factor, if there is one.
		if($timeValue) {
			$sentence .= " at '$timeValue'";
		}
	}
	# Otherwise, if it's just a time value:
	else {
		$sentence = "'$timeValue'";
	}

	# Return the sentence we made.
	return $sentence;	
}

1;

=back

=head1 AUTHOR

Expression Atlas team <arrayexpress-atlas@ebi.ac.uk>

=cut

