#!/usr/bin/env perl
#
=pod

=head1 NAME

Atlas::AtlasConfig::Analytics - contains assay groups needed for Atlas analytics

=head1 SYNOPSIS

	use Atlas::AtlasConfig::Analytics;

	# ...
	
	my $atlasAnalytics = Atlas::AtlasConfig::Analytics->new(
		platform => $platform,	# "rnaseq" or ArrayExpress array design accession
		assays => $arrayRefOfAssayObjects,
	);

=head1 DESCRIPTION

An Atlas::AtlasConfig::Analytics object stores an array of Atlas::AtlasConfig::AssayGroup
objects that are used in one Atlas analytics element of an Atlas experiment.

=cut

package Atlas::AtlasConfig::Analytics;

use Moose;
use MooseX::FollowPBP;
use Moose::Util::TypeConstraints;

use Atlas::AtlasConfig::AssayGroup;
use Atlas::AtlasConfig::BiologicalReplicate;
use Atlas::AtlasConfig::Common qw(
	print_stdout_header_footer
);

use Log::Log4perl;
use Data::Compare;

=head1 ATTRIBUTES

=over 2

=item atlas_assay_groups

Reference to array containing Atlas::AtlasConfig::AssayGroup objects.

=cut
has 'atlas_assay_groups' => (
	is => 'rw',
	isa => 'ArrayRef[ Atlas::AtlasConfig::AssayGroup ]',
	lazy => 1,
	builder => '_build_atlas_assay_groups',
	required => 1,
);

=item platform

String representing the platform for this analytics element. Either "rnaseq" or an ArrayExpress array design accession.

=cut
has 'platform' => (
	is => 'rw',
	isa => subtype( 
		as 'Str',
		where { /^A-\w{4}-\d+$/ || /^rnaseq$/ || /^proteomics$/ },
	),
	required => 1,
);

=item assays

Reference to an array of Atlas::Assay objects.

=cut
has 'assays' => (
	is => 'rw',
	isa => 'ArrayRef[ Atlas::Assay ]',
);

=item minimum_biological_replicates

Integer specifying the minimum number of biological replicates allowed in an AssayGroup.

=cut
has 'minimum_biological_replicates' => (
	is => 'ro',
	isa => 'Int',
	lazy => 1,
	builder => '_build_minimum_biological_replicates',
	required => 1,
);

=item assay_group_id_counter

Integer to start counting assay group IDs.

=cut
has 'assay_group_id_counter' => (
	is => 'rw',
	isa => 'Int',
	default => 1,
);

=back

=head1 METHODS

Each attribute has accessor (get_*) and mutator (set_*) methods.

=over 2

=item new

Instantiates a new Atlas::AtlasConfig::Analytics object.

=cut

my $logger = Log::Log4perl::get_logger;

# _build_minimum_biological_replicates
# Returns the minimum number of biological replicates required in a Baseline
# Atlas experiment (currently 1). This is overridden by the same builder method
# in Atlas::AtlasConfig::Analytics::Differential.
sub _build_minimum_biological_replicates {
	return 1;
}

# _build_atlas_assay_groups
# Returns an array of Atlas::AtlasConfig::AssayGroup objects.

sub _build_atlas_assay_groups {
	my ($self) = @_;
	
	print_stdout_header_footer("Assay group creation START");

	# First sort assays by shared factor values.
	my $factorValuesToAssays = _map_factors_to_assays($self->get_assays);
	
	# Empty array for created assay groups.
	my $assayGroups = [];

	# Now go through and make assay groups for them.
	foreach my $factorValues (sort keys %{ $factorValuesToAssays }) {
		$logger->info("Trying to create assay group with factor values \"$factorValues\"...");

		# Create assay group ID with counter.
		my $assayGroupID = "g".$self->get_assay_group_id_counter;

		# Try to create a new assay group.
		my $assayGroup = Atlas::AtlasConfig::AssayGroup->new(
			assays => $factorValuesToAssays->{ $factorValues },
			minimum_biological_replicates => $self->get_minimum_biological_replicates,
			assay_group_id => $assayGroupID,
		);

		# If we got a valid AssayGroup back, add it to the array and increment
		# the assay group counter. Check if it's valid by trying to get its
		# BiologicalReplicates.
		if( eval { $assayGroup->get_biological_replicates } ) {
			$logger->info("Successfully created assay group \"", $assayGroup->get_assay_group_id, "\".");
			
			# Add to array.
			push @{ $assayGroups }, $assayGroup;

			# Increment counter.
			$self->set_assay_group_id_counter( $self->get_assay_group_id_counter + 1 );
		} 
		else {
			$logger->info("Could not create assay group for factor values \"$factorValues\".");
		}
	}
	
	# Count the assay groups.
	my $numAssayGroups = @{ $assayGroups };
	# Log this.
	$logger->info("$numAssayGroups assay groups created.");

	print_stdout_header_footer("Assay group creation END");
	
	return $assayGroups;
}


# _map_factors_to_assays
# Creates a hash with factor values as keys and arrayrefs of assays as values.
sub _map_factors_to_assays {

	my ($assays) = @_;

	my $factorValuesToAssays = {};

	foreach my $assay (@{ $assays }) {

		my $assayFactorValueString = _factor_values_to_string($assay);

		if($factorValuesToAssays->{ $assayFactorValueString }) {
			push @{ $factorValuesToAssays->{ $assayFactorValueString } }, $assay;
		} else {
			$factorValuesToAssays->{ $assayFactorValueString } = [ $assay ];
		}
	}
	return $factorValuesToAssays;
}


# _factor_values_to_string
# Returns a string of factor values joined with "; ".
sub _factor_values_to_string {
	
	my ($assay) = @_;

	my $factors = $assay->get_factors;

	my @factorValues = ();

	foreach my $factorType ( sort keys %{ $factors } ) {
		
		# Ignore "block", if it's there.	
		unless( $factorType =~ /^block$/i ) {
			push @factorValues, keys %{ $factors->{ $factorType } };
		}
	}

	my $factorValueString = join "; ", @factorValues;

	return $factorValueString;
}


=item remove_assay_group

Removes an assay group from the analytics object. Returns 1 if removing the
assay group means that the analytics object no longer has any contrasts left.
Returns 0 otherwise.

=cut

sub remove_assay_group {

	my ( $self, $idToRemove ) = @_;

	# Empty array for new assay groups.
	$_ = {} for my ( $newAssayGroups );

	# Go through each assay group.
	foreach my $assayGroup ( @{ $self->get_atlas_assay_groups } ) {

		# If this isn't the one we want to remove, add it to array of new assay
		# groups.
		unless( $assayGroup->get_assay_group_id eq $idToRemove ) {

			$newAssayGroups->{ $assayGroup->get_assay_group_id } = $assayGroup;
		}
	}

	# If we still have at least one assay group left, set the new assay groups
	# for this analytics object. Return 0 to indicate nothing is wrong.
	if( keys %{ $newAssayGroups } ) {

		my @newAssayGroupsArray = sort values %{ $newAssayGroups };

		$self->set_atlas_assay_groups( \@newAssayGroupsArray );
		
		return;
	}
	# Otherwise, log and return 1 to indicate we can't use this analytics
	# object any more.
	else {
		$logger->warn( "No assay groups remaining for analytics on platform \""
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
