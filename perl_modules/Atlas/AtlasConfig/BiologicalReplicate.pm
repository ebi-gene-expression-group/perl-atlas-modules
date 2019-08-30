#!/usr/bin/env perl
#
=pod

=head1 NAME

Atlas::AtlasConfig::BiologicalReplicate - a single Atlas::Assay object, or set of Atlas::Assay
objects that are technical replicates of one another.


=head1 SYNOPSIS
	
	use Atlas::AtlasConfig::BiologicalReplicate;

	# ...
	my $biologicalReplicate = Atlas::AtlasConfig::BiologicalReplicate->new(
		assays => $arrayRefOfAssayObjects,
		technical_replicate_group => $technicalReplicateID,
	);


=head1 DESCRIPTION

An Atlas::AtlasConfig::BiologicalReplicate object contains an array of Atlas::Assay objects
that have been determined to belong to the same group of technical replicates.
Most of the time, the Atlas::AtlasConfig::BiologicalReplicate object will only contain a
single Atlas::Assay object, but using this container simplifies the case when we
have a set of technical replicates that together for a single biological
replicate.  Each Atlas::AtlasConfig::BiologicalReplicate object stores a technical replicate
group ID (string, e.g.  "t1"), which is unique to that technical replicate
group within an Atlas::AtlasConfig::Analytics object.

=cut

package Atlas::AtlasConfig::BiologicalReplicate;

use Moose;
use MooseX::FollowPBP;
use Data::Compare;

=head1 ATTRIBUTES

=over 2

=item assays

A reference to an array of Atlas::Assay objects, that have been determined to be
technical replicates of each other based on their shared technical replicate
group ID.

=cut
has 'assays' => (
	is => 'rw',
	isa => 'ArrayRef[ Atlas::Assay ]',	# Only accept arrays of Atlas::Assay objects.
	required => 1,
);

=item technical_replicate_group

String value of the ID of the technical replicate group the assay belongs to. Optional.

=cut

has 'technical_replicate_group' => (
	is => 'rw',
	isa => 'Str',
	predicate => 'has_technical_replicate_group',
);

=item factors

Hashref mapping factors to their values.

=cut

has 'factors' => (
	is => 'ro',
	isa => 'HashRef',
	lazy_build => 1,
);

=item characteristics

Hashref mapping characteristics to their values.

=cut

has 'characteristics' => (
	is => 'ro',
	isa => 'HashRef',
	lazy_build => 1,
);

=back

=head1 METHODS

Each attribute has accessor (get_*) and mutator (set_*) methods.

=over 2

=item new

Instantiates a new Atlas::AtlasConfig::BiologicalReplicate oject.

=item _build_factors

Returns a hash of factors and their values taken from first Atlas::Assay object
passed.

=cut

sub _build_factors {
	my ($self) = @_;

	# Get the assays.
	my @assays = @{ $self->get_assays };
	# Get the first one (their factors should all be the same).
	my $assay = $assays[0];
	# Get the factors.
	my $factors = $assay->get_factors;
	# Return them for BiologicalReplicate to use.
	return $factors;
}

=item _build_characteristics

Returns a hash of characteristics and their values taken from first Atlas::Assay object
passed.

=cut

sub _build_characteristics {
	my ($self) = @_;

	# Get the assays.
	my @assays = @{ $self->get_assays };
	# Get the first one (their characteristics should all be the same).
	my $assay = $assays[0];
	# Get the characteristics.
	my $characteristics = $assay->get_characteristics;
	# Return them for BiologicalReplicate to use.
	return $characteristics;
}

1;

=back

=head1 AUTHOR

Expression Atlas team <arrayexpress-atlas@ebi.ac.uk>

=cut

