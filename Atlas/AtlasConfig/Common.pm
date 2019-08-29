#!/usr/bin/env perl
#
=pod

=head1 NAME

Atlas::AtlasConfig::Common - functions shared by multiple classes in Atlas::AtlasConfig

=head1 SYNOPSIS
	
	use Atlas::AtlasConfig::Common qw(
		get_all_factor_types
		print_stdout_header_footer
		get_numeric_timepoint_value
	);

	# ...
	
	my $allFactorTypes = get_all_factor_types($assayGroupOne, $assayGroupTwo);

=head1 DESCRIPTION

This module exports functions that are used by multiple classes creating
Expression Atlas XML config.

=cut

package Atlas::AtlasConfig::Common;

use Moose;
use MooseX::FollowPBP;
use Scalar::Util qw(looks_like_number);
use Log::Log4perl;

use base 'Exporter';
our @EXPORT_OK = qw(
	get_all_factor_types
	print_stdout_header_footer
	get_numeric_timepoint_value
	map_technical_replicate_ids_to_assays
	get_time_factor
);

my $logger = Log::Log4perl::get_logger;

=head1 METHODS

=over 2

=item get_all_factor_types

This function takes an array of Atlas::AtlasConfig::AssayGroup objects and finds all
the factor types they have, even non-shared ones.

=cut
sub get_all_factor_types {
	my @assayGroups = @_;

	my $allFactorTypes = {};
	foreach my $assayGroup (@assayGroups) {
		my $factors = $assayGroup->get_factors;
		$allFactorTypes = {
			map { $_ => 1 } (
				(sort keys %{ $allFactorTypes }),
				(sort keys %{ $factors }),
			),
		};
	}
	return $allFactorTypes;
}


=item print_stdout_header_footer

This function takes a string and passes it to the logger, padded with dashes.
It's used by Atlas::AtlasConfig classes to mark the starts and ends of the AssayGroup
and Contrast creation sections of the STDOUT.

=cut
sub print_stdout_header_footer {
	my ($text) = @_;

	$text = "---------- $text ";
	
	# Lifted from http://perlmeme.org/faqs/manipulating_text/string_faq.html
	my $pad_len = 80;
	my $pad_char = "-";
	my $padded = $text . $pad_char x ( $pad_len - length( $text ) );
	
	$logger->info($padded);
}


=item get_numeric_timepoint_value

Given a string e.g. "2.5 hour" will pull out the numeric value and return it.
Dies if what it pulls out was not numeric. For ranges, e.g. "2 to 4", this will
take only the first numeric value in the range, in this case "2".

=cut
sub get_numeric_timepoint_value {
	my ($timePoint) = @_;

	# Split the time point on spaces.
	my @splitTimePoint = split " ", $timePoint;

	# Take the first element of the split time point array.
	my $numeric = shift @splitTimePoint;

	# Die if this isn't a number, something weird happened.
	unless( looks_like_number($numeric) ) {
		$logger->logdie("Time point value \"$numeric\" does not look like a number.");
	}

	# If we're still here, return the numeric value.
	return $numeric;
}


=item map_technical_replicate_ids_to_assays

Returns a hash with technical replicate IDs as keys and arrayrefs of assay
groups belonging to each technical replicate group as the values. If an assay
does not belong to a technical replicate group, it is placed under key
"no_technical_replicate_id".

=cut

sub map_technical_replicate_ids_to_assays {
	my ($assays) = @_;
	
	my $techRepIDsToAssays = {};

	foreach my $assay (@{ $assays }) {
		# Get technical replicate ID, if there is one.
		my $technicalReplicateID;
		if($assay->has_technical_replicate_group) {
			$technicalReplicateID = $assay->get_technical_replicate_group;
		} else {
			# If there isn't one, use a placeholder. All the assays that aren't
			# technical replicates will get be placed in the array assigned to
			# this key in the hash.
			$technicalReplicateID = "no_technical_replicate_id";
		}

		# Add assay to hash.
		if($techRepIDsToAssays->{ $technicalReplicateID }) {
			push @{ $techRepIDsToAssays->{ $technicalReplicateID } }, $assay;
		}
		else {
			$techRepIDsToAssays->{ $technicalReplicateID } = [ $assay ];
		}
	}
	return $techRepIDsToAssays;
}

=item get_time_factor

Returns 0 if no time factor type is found. Returns a single factor type if any
time factor is found. If there are two time factors, one /^time$/i and one
/^age$/i, the /^age$/i factor is treated like a non-time factor. Otherwise, if
more than one time factor is found, it dies. 

=cut

sub get_time_factor {

	my ( $allFactorTypes ) = @_;

	my $timeFactorTypes = {};

	foreach my $factorType (sort keys %{ $allFactorTypes }) {
		if( $factorType =~ /^time$/i || $factorType =~ /^age$/i ) {
			$timeFactorTypes->{ $factorType } = 1;
		}
	}

	# If we didn't find any time factors, return 0.
	unless( keys %{ $timeFactorTypes } ) { return 0; }

	# If we're still here there must be a time factor.
	# If we found two time factors...
	if( keys %{ $timeFactorTypes } == 2 ) {

		# See if one of them is "age".
		if( grep { /^age$/i } keys %{ $timeFactorTypes } ) {

			# If so, delete it, as in this case we will treat age as a non-time
			# factor.
			delete $timeFactorTypes->{ "age" };
		}
		else {
			$logger->logdie( "More than one time factor found. Cannot continue." );
		}
	}

	# Check that now we only have one time factor. Die if not.
	if( keys %{ $timeFactorTypes } > 1 ) {
		$logger->logdie( "More than one time factor found. Cannot continue." );
	}

	my ( $timeFactorType ) = sort keys %{ $timeFactorTypes };

	return $timeFactorType;
}


1;

=back

=head1 AUTHOR

Expression Atlas team <arrayexpress-atlas@ebi.ac.uk>

=cut
