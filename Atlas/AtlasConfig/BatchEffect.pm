#!/usr/bin/env perl
#
=pod

=head1 NAME 

Atlas::AtlasConfig::BatchEffect - representation of a batch effect for an Expression Atlas experiment.

=head1 SYNOPSIS

	use Atlas::AtlasConfig::BatchEffect;

	# ...
	
	my $batchEffect = Atlas::AtlasConfig::BatchEffect->new(
		name => $effectName,	# string e.g. "sex"
		batches => $batchArray	# ArrayRef of Atlas::AtlasConfig::Batch objects
	);

=head1 DESCRIPTION

An Atlas::AtlasConfig::BatchEffect object stores information about a single
batch effect in an Expression Atlas experiment. This could be e.g. "sex", or
"ethnic group". The object stores an array of Atlas::AtlasConfig::Batch
objects, which contain the names of assays belonging to each batch in the batch
effect.

=cut

package Atlas::AtlasConfig::BatchEffect;

use Moose;
use MooseX::FollowPBP;

=head1 ATTRIBUTES

=over 2

=item name

String containing the name of the batch effect e.g. "sex".

=cut

has 'name' => (
	is => 'rw',
	isa => 'Str',
	required => 1
);

=item batches

ArrayRef, containing Atlas::AtlasConfig::Batch objects.

=cut

has 'batches' => (
	is => 'rw',
	isa => 'ArrayRef[ Atlas::AtlasConfig::Batch ]',
	required => 1
);

=back

=head1 AUTHOR

Expression Atlas team <arrayexpress-atlas@ebi.ac.uk>

=cut

1;
