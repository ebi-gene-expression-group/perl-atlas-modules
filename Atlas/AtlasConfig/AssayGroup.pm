#!/usr/bin/env perl
#
=pod

=head1 NAME

Atlas::AtlasConfig::AssayGroup - a set of Atlas::Assay objects that are biological [or technical] replicates.

=head1 SYNOPSIS
	
	use Atlas::AtlasConfig::AssayGroup;

	# ...
	my $assayGroup = Atlas::AtlasConfig::AssayGroup->new(
		assays => $arrayRefOfAssay4atlasObjectsWithSameFactorValues,
		minimum_biological_replicates => $minimumNumberOfBiologicalReplicates,
		assay_group_id => $assayGroupID,
	);


=head1 DESCRIPTION

An Atlas::AtlasConfig::AssayGroup object contains an array of Atlas::Assay objects that have
been determined to be biological or technical replicates. Each Atlas::AtlasConfig::AssayGroup
object stores an assay group ID (string, e.g. "g1"), which is unique to that
assay group within an Atlas::AtlasConfig::Analytics object. Each Atlas::AtlasConfig::AssayGroup object also
stores a reference to a hash of factor types and their corresponding values
that are shared by all the Atlas::Assay objects in this assay group. The
Atlas::AtlasConfig::AssayGroup object also stores a label, which is a string containing the
factor value(s) shared by assays in this assay group.

=cut

package Atlas::AtlasConfig::AssayGroup;

use Moose;
use MooseX::FollowPBP;
use Moose::Util::TypeConstraints;
use Data::Compare;
use Log::Log4perl;

use Atlas::AtlasConfig::BiologicalReplicate;
use Atlas::AtlasConfig::Common qw( map_technical_replicate_ids_to_assays );

=head1 ATTRIBUTES

=over 2

=item assay_group_id

This is the unique identifier for the assay group within the
Atlas::AtlasConfig::Analytics object that contains it. Practically, it will be printed
in the XML config file in three places: 1) the id attribute for the assay_group
element, 2) the contrast ID of any contrasts that use it, and 3) in the
test_assay_group or reference_assay_group element of any contrasts that use it,
as appropriate.

=cut
has 'assay_group_id' => (
	is => 'rw',
	isa => 'Str',
	required => 1,
);

=item biological_replicates

An reference to array of Atlas::AtlasConfig::BiologicalReplicate objects.

=cut
has 'biological_replicates' => (
	is => 'rw',
	isa => 'ArrayRef[ Atlas::AtlasConfig::BiologicalReplicate ]',
	lazy => 1,
	builder => '_build_biological_replicates',
	required => 1,
);

=item factors

A reference to a hash containing factor type-factor value pairs shared by all
assays belonging to this assay group.

=cut
has 'factors' => (
	is => 'ro',
	isa => 'HashRef',
	lazy => 1,
	builder => '_build_factors',
	required => 1,
);

=item label

Assay group label. This is a string containing the factor value(s) shared by
all assays belonging to this assay group. In multi-factor experiments, the
factor values are separated by "; ", e.g. "wild type; none; 0 day".

=cut
has 'label' => (
	is => 'ro',
	isa => 'Str',
	lazy => 1,
	builder => '_build_label',
	required => 1,
);

=item assays

A reference to an array of Atlas::Assay objects, that have been determined to be
biological (or tecnical) replicates of each other based on their shared factor
values.

=cut
has 'assays' => (
	is => 'rw',
	isa => 'ArrayRef[ Atlas::Assay ]',
	required => 1,
);

=item minimum_biological_replicates

Integer value specifying minimum number of Atlas::AtlasConfig::BiologicalReplicate
objects to allow in an AssayGroup.

=cut
has 'minimum_biological_replicates' => (
	is => 'rw',
	isa => 'Int',
	required => 1,
);

=item in_contrast

Flag that is set when an AssayGroup is added to a Contrast in an
Analytics::Differential object. Used in printing XML. If an AssayGroup is not
in any Contrasts it will be flagged in the STDOUT and with a comment in the XML
file.

=cut
has 'in_contrast' => (
	is => 'rw',
	isa => enum( [ qw( 1 0 ) ] ),
	lazy => 1,
	builder => '_build_in_contrast',
	required => 1,
);

=back

=cut

# Get the logger
my $logger = Log::Log4perl::get_logger;

=head1 METHODS

Each attribute has accessor (get_*) and mutator (set_*) methods.

=over 2

=item new

Instantiates a new Atlas::AtlasConfig::AssayGroup oject. This should be called by
Atlas::AtlasConfig::Analytics rather than directly.

=cut

# _build_factors
# Returns a hash of factors taken from the first BiologicalReplicate in the array
# built.
sub _build_factors {
	my ($self) = @_;

	# Get the biological replicates array.
	my @biologicalReplicates = @{ $self->get_biological_replicates };

	# Get the first biological replicate (possibly the only one).
	my $firstBioRep = shift @biologicalReplicates;

	# Get its factors.
	my $firstBioRepFactors = $firstBioRep->get_factors;

	# If we're still alive, return the factors.
	return $firstBioRepFactors;
}

# _build_label
# Returns a string with factor values joined by "; ".
sub _build_label {
	my ($self) = @_;

	# Get the factors
	my $factors = $self->get_factors;
	
	if( $factors ) {

		my @values = ();

		foreach my $type ( sort keys %{ $factors } ) {
			
			unless( $type =~ /^block$/i ) {
				
				push @values, ( keys %{ $factors->{ $type } } )[ 0 ];
			}
		}

		# Join the values together with "; ".
		my $label = join "; ", @values;

		return $label;
	}
	else {
		return "";
	}
}

# _build_biological_replicates
# Returns an array of Atlas::AtlasConfig::BiologicalReplicate objects. Each one contains
# an arrayref of Atlas::Assay objects that belong to the same technical replicate
# group. Assays that do not belong to a technical replicate group occupy their
# own BiologicalReplicate object solo.
sub _build_biological_replicates {
	my ($self) = @_;

	# Sort assays by technical replicate ID.
	my $techRepIDsToAssays = map_technical_replicate_ids_to_assays($self->get_assays);

	# Array to put new BiologicalReplicates in.
	my $biologicalReplicates = [];

	# Create a new biological replicate for each technical replicate ID.
	foreach my $technicalReplicateID (sort keys %{ $techRepIDsToAssays }) {
		
		my $biologicalReplicate;
		
		# First deal with the ones that aren't technical replicates.
		if($technicalReplicateID eq "no_technical_replicate_id") {
			foreach my $assay (@{ $techRepIDsToAssays->{ "no_technical_replicate_id" } }) {
				$biologicalReplicate = Atlas::AtlasConfig::BiologicalReplicate->new(
					assays => [ $assay ],
				);
				
				if( eval { $biologicalReplicate->get_assays } ) {
					push @{ $biologicalReplicates }, $biologicalReplicate;
				}
			}
		}
		# Now the ones in technical replicate groups.
		else {
			$biologicalReplicate = Atlas::AtlasConfig::BiologicalReplicate->new(
				assays => $techRepIDsToAssays->{ $technicalReplicateID },
				technical_replicate_group => $technicalReplicateID,
			);
			
			if( eval { $biologicalReplicate->get_assays } ) {
				push @{ $biologicalReplicates }, $biologicalReplicate;
			}
		}
	}

	# Now check we have enough BiologicalReplicates.
	if(@{ $biologicalReplicates } < $self->get_minimum_biological_replicates) {
		$logger->warn("Not enough biological replicates");
		return;
	} else {
		return $biologicalReplicates;
	}
}


# _build_in_contrast
# Returns default value to flag whether this AssayGroup belongs to an
# Atlas::AtlasConfig::Contrast. On creation, this is always 0.
sub _build_in_contrast {
	return 0;
}


=item remove_assay

Removes an assay from the assay group. Returns 1 if removing the assay means
that there are no longer enough biological replicates. Returns 0 otherwise.

=cut

sub remove_assay {

	my ( $self, $assayToRemove ) = @_;

	# Remove it from the assays.
	my $newAssays = [];
	foreach my $assay ( @{ $self->get_assays } ) {
		unless( $assay->get_name eq $assayToRemove ) {
			push @{ $newAssays }, $assay;
		}
	}

	# Remove it from biological replicates.
	# Array to put new biological replicates.
	my $newBioReps = [];
	foreach my $biologicalReplicate ( @{ $self->get_biological_replicates } ) {
		
		# Array to put new assays.
		my $newBioRepAssays = [];
		foreach my $assay ( @{ $biologicalReplicate->get_assays } ) {
			
			# If the assay name is not the one we are looking for, add it to
			# the new array.
			unless( $assay->get_name eq $assayToRemove ) {
				push @{ $newBioRepAssays }, $assay;
			}
		}

		# If we still have some assays for this biological replicate, set its
		# array of assays, and add the biological replicate to the new array of
		# biological replicates.
		if( @{ $newBioRepAssays } ) {
			
			$biologicalReplicate->set_assays( $newBioRepAssays );
			
			push @{ $newBioReps }, $biologicalReplicate;
		}
	}

	# Now check that there are enough biological replicates left. If there are,
	# reset the array and return 0 to indicate no errors.
	if( @{ $newBioReps } >= $self->get_minimum_biological_replicates ) {
		$self->set_assays( $newAssays );
		$self->set_biological_replicates( $newBioReps );
		return;
	}
	# Otherwise, return 1 to indicate that we can't use this assay group any
	# more as there aren't enough biological replicates left.
	else {
		$logger->warn( "Not enough biological replicates left for assay group \""
						. $self->get_assay_group_id
						. "\" after removing assay \""
						. $assayToRemove . "\""
		);

		return 1;
	}
}

1;

=back

=head1 AUTHOR

Expression Atlas team <arrayexpress-atlas@ebi.ac.uk>

=cut
