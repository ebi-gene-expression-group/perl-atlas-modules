#!/usr/bin/env perl
#
=pod

=head1 NAME

Atlas::AtlasContrastDetails -- model a contrast from the contrastdetails.tsv file.

=head1 DESCRIPTION

This package models a contrast from the Atlas contrastdetails.tsv file.

=head1 SYNOPSIS

use Atlas::AtlasContrastDetails;

# $sortedFileLines is a hashref indexing contrastdetails.tsv file lines by
# experiment accession and contrast ID.

my $allContrastDetails = [];

foreach my $expAcc ( keys %{ $sortedFileLines } ) {
	foreach my $contrastID ( keys %{ $sortedFileLines->{ $expAcc } } ) {
		my $contrastLines = $sortedFileLines->{ $expAcc }->{ $contrastID };
		my $contrastDetails = Atlas::AtlasContrastDetails->new( file_lines => $contrastLines );
		push @{ $allContrastDetails }, $contrastDetails;
	}
}

foreach my $contrastDetails ( @{ $allContrastDetails } ) {
	my $expAcc = $contrastDetails->get_exp_acc;
	my $contrastID = $contrastDetails->get_contrast_id;
	#...
}

=cut

use 5.10.0;

package Atlas::AtlasContrastDetails;

use Moose;
use MooseX::FollowPBP;
use Log::Log4perl;

=head1 ATTRIBUTES

=over 2

=item file_lines

Required. The lines from the contrastdetails.tsv file that describe the contrast.

=cut

has 'file_lines' => (
	is => 'rw',
	isa => 'ArrayRef',
	required => 1
);

my $logger = Log::Log4perl::get_logger;

=back

=head1 METHODS

=over 2

=item get_exp_acc

Returns the experiment accession, e.g. E-MTAB-1066.

=cut

sub get_exp_acc {

	my ( $self ) = @_;

	my $expAcc = $self->get_firstline_element( 0 );

	return $expAcc;
}


=item get_contrast_id

Returns the contrast ID, e.g. g1_g2.

=cut

sub get_contrast_id {

	my ( $self ) = @_;

	my $contrastID = $self->get_firstline_element( 1 );

	return $contrastID;
}


sub get_firstline_element {

	my ( $self, $elementNumber ) = @_;
	
	my $fileLines = $self->get_file_lines;

	my $firstLine = $fileLines->[ 0 ];

	my @splitLine = split "\t", $firstLine;

	my $element = $splitLine[ $elementNumber ];

	return $element;
}


=item get_characteristics

Returns a hashref containing the characteristic types and values for the test and
reference assay groups.

=cut

sub get_characteristics {

	my ( $self ) = @_;

	my $characteristics = $self->get_attribute_hash( "characteristic" );

	return $characteristics;
}


=item get_factors

Returns a hashref containing the factor types and values for the test and
reference assay groups.

=cut

sub get_factors {

	my ( $self ) = @_;

	my $factors = $self->get_attribute_hash( "factor" );

	return $factors;
}


sub get_attribute_hash {

	my ( $self, $attributeType ) = @_;

	my $fileLines = $self->get_file_lines;

	my $attributes = {};

	foreach my $line ( @{ $fileLines } ) {

		my @splitLine = split "\t", $line;
        
        # If this is the desired type of attribute (i.e. characteristic or factor)...
		if( $splitLine[ 3 ] eq $attributeType ) {

			# Skip blank ones.
			unless( $splitLine[ 5 ] ) { next; }
			
			# Add to the hash.
            #   - index 2 is "test" or "reference".
            #   - index 4 is the characteristic/factor type e.g. "genotype".
            #   - index 5 is the characteristic/factor value e.g. "wild type".
			$attributes->{ $splitLine[ 2 ] }->{ $splitLine[ 4 ] } = $splitLine[ 5 ];
		}
	}

	return $attributes;
}


=item get_efo_uris

Given a property type and property value, returns an ArrayRef of EFO URIs
(usually only one URI, but sometimes more), if any are available.

=cut

sub get_efo_uris {

	my ( $self, $type, $value ) = @_;
	
	my $fileLines = $self->get_file_lines;
	
	foreach my $line ( @{ $fileLines } ) {

		my @splitLine = split "\t", $line;

		unless( $splitLine[ 5 ] ) { next; }
		
		# Find the matching attribute type and value.
		if( $splitLine[ 4 ] eq $type && $splitLine[ 5 ] eq $value ) {
			
			# If there's one or more EFO URIs, return as an ArrayRef.
			if( $splitLine[ 6 ] ) {
				
				# Cater for multiple URIs.
				# Split the URI(s) on spaces.
				my @uris = split /\s/, $splitLine[ 6 ];
				
				# Return a reference to the array of URI(s).
			    return \@uris;
			}
			# Otherwise, return undef.
			else { 
				return undef;
			}
		}
	}
	
	# If we're still here, we didn't find the matching attribute type and/or
	# value in this contrast. This is strange, so log a warning.
	$logger->warn( "No match for attribute \"$type\" with value \"$value\" in contrast \""
					. $self->get_contrast_id
					. "\", experiment \""
					. $self->get_exp_acc . "\"" );

	return undef;
}


1;

=back

=head1 AUTHOR

Expression Atlas team <arrayexpress-atlas.ebi.ac.uk>

=cut
