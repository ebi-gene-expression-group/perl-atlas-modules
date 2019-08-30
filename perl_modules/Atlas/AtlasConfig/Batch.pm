#!/usr/bin/env perl
#
=pod

=head1 NAME

Atlas::AtlasConfig::Batch - represents a batch of assays in a batch effect.

=head1 SYNOPSIS

	use Atlas::AtlasConfig::Batch;

	# ...
	
	my $batch = Atlas::AtlasConfig::Batch->new(
		value => $value,		# e.g. "female"
		assays => $assayNames	# ArrayRef of assay names (strings).
	);

=head1 DESCRIPTION

An Atlas::AtlasConfig::Batch object stores the value (i.e. term) for this batch
eg. "female", "male", "greenhouse 1", ..., as well as the names of the assays
belonging to this batch.

=cut

package Atlas::AtlasConfig::Batch;

use Moose;
use MooseX::FollowPBP;

use Log::Log4perl;

=head1 ATTRIBUTES

=over 2

=item value

String containing the name of the batch e.g. "female".

=cut

has 'value' => (
	is => 'rw',
	isa => 'Str',
	required => 1
);

=item assays

ArrayRef, containing assay names as strings.

=cut

has 'assays' => (
	is => 'rw',
	isa => 'ArrayRef[ Str ]',
	required => 1
);

=back

=cut

my $logger = Log::Log4perl::get_logger;

sub remove_assay {

	my ( $self, $assayToRemove ) = @_;

	# Create a new array of only the allowed assays.
	my $newAssays = [];

	foreach my $assayName ( @{ $self->get_assays } ) {
		unless( $assayName eq $assayToRemove ) {
			push @{ $newAssays }, $assayName;
		}
	}

	# If there aren't enough assays left (less than two) for this batch, this
	# is invalid, so return 1. Otherwise, set the new array of assay names for
	# this batch's assays.
	if( @{ $newAssays } < 2 ) { 
		
		$logger->warn( 
			"Not enough assays left for batch \""
			. $self->get_value
			. "\" after removing assay \""
			. $assayToRemove . "\""
		);

		return 1;
	}
	else {
		$self->set_assays( $newAssays );
		return;
	}
}



=head1 AUTHOR

Expression Atlas team <arrayexpress-atlas@ebi.ac.uk>

=cut

1;
