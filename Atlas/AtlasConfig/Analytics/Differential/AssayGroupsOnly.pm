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

package Atlas::AtlasConfig::Analytics::Differential::AssayGroupsOnly;

use Moose;
use MooseX::FollowPBP;
use Log::Log4perl;
use Data::Compare;

use Atlas::AtlasConfig::Common qw(
	get_all_factor_types
	print_stdout_header_footer
	get_numeric_timepoint_value
	get_time_factor
);

extends 'Atlas::AtlasConfig::Analytics::Differential';

=head1 ATTRIBUTES

Inherited from Atlas::AtlasConfig::Analytics: atlas_assay_groups

=over 2

=item atlas_contrasts

An array of Atlas::AtlasConfig::Contrast objects.

=cut

has 'atlas_contrasts' => (
	is => 'rw',
	isa => 'ArrayRef',
	lazy => 1,
	builder => '_build_atlas_contrasts',
	predicate => 'has_atlas_contrasts'
);

=item assay_groups_only

Boolean: 1 = only create assay groups, 0 = create contrasts and assay groups.

=cut

has 'assay_groups_only' => (
	is => 'ro',
	isa => 'Int',
	predicate => 'has_assay_groups_only'
);


my $logger = Log::Log4perl::get_logger;

=back

=head1 METHODS

Each attribute has accessor (get_*) and mutator (set_*) methods.

=over 2

=item new

Instantiates a new Atlas::AtlasConfig::Analytics::Differential::AssayGroupsOnly
object. Checks that all AssayGroups passed have at least the minimum allowed
BiologicalReplicates, dies if not.

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
# Just prints a warning and returns an empty arrayref!
sub _build_atlas_contrasts {
	my ($self) = @_;
	
	$logger->warn( "Got assay groups only option ( -a ), will not create any contrasts." );

	return [];
}

1;
