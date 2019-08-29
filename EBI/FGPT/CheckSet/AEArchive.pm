#!/usr/bin/env perl
#
# EBI/FGPT/CheckSet/AEArchive.pm
#
# Anna Farne 2012 ArrayExpress team, EBI
#
# $Id: AEArchive.pm 24643 2013-09-26 11:02:14Z emma $
#

=pod

=head1 NAME

EBI::FGPT::CheckSet::AEArchive

=head1 SYNOPSIS
 
 use EBI::FGPT;
 
 my $check_sets = {
	'EBI::FGPT::CheckSet::AEArchive'  => 'ae_validation',
 };

 my $idf = $ARGV[0];
 my $checker = EBI::FGPT::Reader::MAGETAB->new( 
    'idf'                  => $idf, 
    'check_sets'           => $check_sets,
 );
 $checker->parse();

=head1 DESCRIPTION

Additional MAGETAB checks to determine if experiment can be loaded
into ArrayExpress Archive. See L<CheckSet|EBI::FGPT::CheckSet>
for superclass methods.

=head1 METHODS

=item get_additional_files

Returns a list of Comment[AdditionalFiles] identified in the IDF

=head1 CHECKS

All checks produce ERROR messages except for the check for
EFO-styling of Characteristics / factor name terms (only throws
warning)

=head1 IDF checks:

IDF must provide an ArrayExpress accession.

IDF must provide an experiment type via Comment[AEExperimentType]
and the type must come from the approved list from Experimental
Factor Ontology

IDF must have a release date in YYYY-MM-DD format

IDF must contain at least one submitter with an email address

IDF must reference an SDRF

Common strings (e.g. "GROW") not allowed as protocol names.

=head1 SDRF checks:

Source materials must have an organism characteristic.

Experimental Factors must have variable values. Where factor are dependent at least
one of them must vary. Dependent factors: compound+dose and irradiate+dose

# Comment fields in the SDRF shouldn't have identical names as the AE2 loader cannot
# handle them properly (whichever one read last will overwrite previous instances).

Submissions with a possible CEPH family cell lines ID and age value are blocked
because it is potentially human-identifiable data

Source characteristics and factor name terms are preferably
in lowercase, not Title Case or CamelCase so they're in EFO style,
warn if they are not. 


=cut

package EBI::FGPT::CheckSet::AEArchive;

use Data::Dumper;

use Moose;
use MooseX::FollowPBP;

extends 'EBI::FGPT::CheckSet';

augment 'run_idf_checks' => sub {

	my ($self) = @_;

	$self->check_for_ae_accession;
	$self->check_ae_expt_type;
	$self->check_submitter;
	$self->check_for_sdrf;
	$self->check_for_release_date;
	$self->check_common_protocol_names;

};

augment 'run_sdrf_checks' => sub {

	my ($self) = @_;

	$self->check_source_species;
	$self->check_factor_values;
	$self->check_ceph;
	$self->check_chars_factors_efo_styling;
};

sub check_submitter {

	my ($self) = @_;

	# Must have at least 1 submitter
	my @submitters;
	foreach my $contact ( @{ $self->get_investigation->get_contacts || [] } ) {
		if ( my @roles = $contact->get_roles ) {
			if ( grep { $_->get_value eq "submitter" } @roles ) {
				push @submitters, $contact;
			}
		}
	}

	$self->error("No contact with role 'submitter' provided") unless @submitters;

	# Submitters must have email address
	foreach my $sub (@submitters) {
		$self->error( "Submitter ", $sub->get_firstName, " ", $sub->get_lastName,
			" has no email address" )
		  unless $sub->get_email;
	}

}

sub check_for_release_date {

	my ($self) = @_;

# IDF must specify release date
# FIXME: dates are not being parsed correctly
# e.g. 2013-01-01 and 01/01/2013 both read without error but stored as 2012-12-31T23:00:00....
	$self->debug( "Release date: " . $self->get_investigation->get_publicReleaseDate );
	unless ( $self->get_investigation->get_publicReleaseDate ) {
		$self->error("No Public Release Date specified");
		return;
	}

	# Check release date was specified in the correct format
	$self->check_release_date_format();

}

sub get_additional_files {

	my ($self) = @_;

	# Store names of additional files for later data file checking
	my @additional_files =
	  grep { $_->get_name =~ /^AdditionalFile/i }
	  @{ $self->get_investigation->get_comments || [] };
	my @data_files =
	  map { { name => $_->get_value, type => 'additional' } } @additional_files;

	return @data_files;
}

# Historically, submitters completed MAGE-TAB templates which had procotol
# names like "GROWTH", "TREATMENT", ... etc already filled in, and they would
# complete the Protocol Description field and leave the name as it was. During
# MAGE-TAB export, the protocols are inserted into the ArrayExpress database
# and given accessions (P-MTAB-*) which replace the names from the template. In
# the past there was a problem which meant that protocol accessioning did not
# take place, and multiple protocols were inserted to ArrayExpress DB using the
# names from the MAGE-TAB template. This meant different protocols were
# overwriting each other, so some protocols were lost from the database.
#
# This check looks for the MAGE-TAB template names and fails if they are found.
# It is not applied during curation, since this could be prior to MAGE-TAB
# export when accessioning takes place.
#
# In the past, the check was not looking for a generic pattern e.g. /^P-\w{4}-\d+$/
# because there are some very old experiments in the database using protocols with non-standard
# accessions. If these are unloaded, this check would then fail for those
# experiments. We therefore relied on string match to a list of "banned" strings as
# protocol accessions.
#
# Now (6 Jan 2017) we decided not to worry about the very old experiments anymore
# and check for protocol accession patterns.

sub check_common_protocol_names {
	my ($self) = @_;

	# If AEArchive check happens during curation (e.g. when validate_magetab.pl
	# is called with -c (full curation) mode, experiment accession 
	# (set as Comment[ArrayExpressAccession] in
	# investigation object) will be "DUMMY". We skip this check

	my @acc_comments =
	  ( grep { $_->get_name eq "ArrayExpressAccession" }
		  $self->get_investigation->get_comments );
	my @accessions = map { $_->get_value } @acc_comments;
	if ( grep "DUMMY" eq $_, @accessions ) {
		$self->warn(
		"Not checking protocol names because experiment is under curation.
		 The check only applies if you are running AEArchive checks for AE loading eligibility."
		);
		return;
	}

	my @bad_prot_names_found;
	foreach my $prot ( $self->get_investigation->get_protocols ) {
		my $orig_prot_name       = $prot->get_name;
		unless ( $orig_prot_name =~/^P-\w+-\w+$/ ) {
			push( @bad_prot_names_found, $orig_prot_name );
		}
	}

	if ( scalar(@bad_prot_names_found) ) {
		my $bad_names = join ", ", sort @bad_prot_names_found;
		$self->error(
        "Found protocol names in common strings instead of ArrayExpress format: $bad_names."
		);
	}
}

sub check_source_species {

	my ($self) = @_;

	# All Sources must have Characteristic[Organism] or Characteristic[organism]
	# Lowercase is preferred (to match EFO style)

	foreach my $source ( $self->get_magetab->get_sources ) {
		my $organisms =
		  grep { $_->get_value and $_->get_category =~ /^organism$/i }
		  $source->get_characteristics;
		$self->error( "No organism provided for Source ", $source->get_name )
		  unless $organisms;
	}
}

sub check_factor_values {

	my ($self) = @_;

	# Do not do this check if only 1 assay and 1 channel
	if (    $self->get_magetab->get_assays < 2
		and $self->get_magetab->get_labeledExtracts < 2 )
	{
		$self->info(
"Will not check for invariant Factors because experiment does not have multiple Assays or multiple LabeledExtracts"
		);
		return;
	}

# FIXME:
# immunoprecipitate - warn only as this might not vary in ChIP-chip study with other factors

	# Define rules for factors that do not need to vary if any one of their
	# potentially dependent factors varies
	my %dependent_factors_for = (
		'compound'  => ['dose'],
		'irradiate' => ['dose'],
		'dose'      => [ 'compound', 'irradiate' ],
	);

	my %factor_info_for;

	# Store type and value count for each factor
	foreach my $factor ( $self->get_magetab->get_factors ) {

		my $factor_type;
		if ( my $type = $factor->get_factorType ) {
			$factor_type = $factor->get_factorType->get_value;
		}
		else {

			# Should this be an error or warning?
			$factor_type = "unknown type";
		}

   # Bio::MAGETAB does not create a FactorValue if a blank cell is found in an FV column
   # we need to check for cases where, e.g. some assays have a compound FV and some do not
		my $missing_for_some_rows = 0;
		foreach my $row ( $self->get_magetab->get_sdrfRows ) {
			unless ( grep { $_->get_factor == $factor } $row->get_factorValues ) {
				$missing_for_some_rows = 1;
				$self->warn(
					"FactorValue for ",      $factor->get_name,
					" missing on SDRF row ", $row->get_rowNumber
				);
			}
		}

		my @values =
		  grep { $_->get_factor == $factor } $self->get_magetab->get_factorValues;
		$self->debug( Dumper(@values) );
		my $value_count = @values;
		$value_count += $missing_for_some_rows;

		# Store for checks
		$factor_info_for{ $factor->get_name } =
		  { 'type' => $factor_type, 'count' => $value_count, 'factor' => $factor };
	}

# Check for variability in single factors, or groups of factors as defined in %dependent_factors_for
	foreach my $factor_name ( keys %factor_info_for ) {

		$self->info( "Checking values for factor ", $factor_name );

		# If factor does not vary
		if ( $factor_info_for{$factor_name}->{count} == 1 ) {

			# See if we have any dependent factor types for it, e.g. dose for compound
			if ( my $dependent_types =
				$dependent_factors_for{ $factor_info_for{$factor_name}->{type} } )
			{
				$self->info("Checking dependent factors for $factor_name");
				my $dependent_is_variable;

				# See if any of these vary
				foreach my $type ( @{ $dependent_types || [] } ) {
					my @dependents =
					  grep { $factor_info_for{$_}->{'type'} eq $type }
					  keys %factor_info_for;
					foreach my $dep_name (@dependents) {
						if ( $factor_info_for{$dep_name}->{'count'} > 1 ) {
							$dependent_is_variable++;
							$self->info("Dependent factor $dep_name varies");
						}
					}
				}
				unless ($dependent_is_variable) {

					# Complain if factor and none of its dependents vary
					$self->error(
						"Values do not vary for factor ",
						$factor_name,
						" or any of its dependent factor types (",
						( join ", ", @$dependent_types ),
						")"
					);
				}
			}
			elsif ( $factor_name =~ /immunoprecipitate/i ) {
				$self->warn(
					"Values do not vary for factor $factor_name. This a special case.");
			}
			else {

# Complain if factor does not vary, is not "immunoprecipitate", and does not have any dependent factors
				$self->error( "Values do not vary for factor ", $factor_name );
			}
		}
	}

}


sub check_ceph {

# Background we may need to remove age information from data from CEPH families cell lines in
# AE, Atlas and BioSD due to a paper which will be published this week. Thus this check
# will flag any submissions with a possible ceph id and age value

	# Restricted ids: can be in a comment or char column
	my @ceph_ids = (
		'GM13180', 'GM13181', 'GM13182', 'GM13183', 'GM13184', 'GM13185',
		'GM13187', 'GM13188', 'GM13189', 'GM13190', 'GM13191', 'GM13192',
		'GM13193', 'GM13194', 'GM13195', 'GM11035', 'GM11036', 'GM11037',
		'GM11038', 'GM11039', 'GM11040', 'GM11041', 'GM11042', 'GM11043',
		'GM11044', 'GM11045', 'GM11104', 'GM13055', 'GM13056', 'GM13057',
		'GM13356'
	);

	my ($self) = @_;

	my @sources               = $self->get_magetab->get_sources;
	my $age_char              = 0;
	my $age_comment           = 0;
	my $ceph_found            = 0;
	my $ceph_found_in_comment = 0;

	# For each source retrieve chars and comments
	foreach my $source (@sources) {
		my @chars    = @{ $source->get_characteristics || [] };
		my @comments = @{ $source->get_comments        || [] };

		foreach my $char (@chars) {

			my $char_category = $char->get_category;
			my $char_value    = $char->get_value;

			# Check to see if we have an age characteristic
			if ( $char_category =~ m/age/i ) {
				$age_char = 1;
			}

			# Check to see if we have one of the restricted
			# CEPH ids is in a characteristic value
			foreach my $ceph_id (@ceph_ids) {
				if ( $char_value =~ m/$ceph_id/i ) {
					$ceph_found = 1;
				}
			}
		}

		foreach my $comment (@comments) {
			my $comment_value = $comment->get_value;
			my $comment_name  = $comment->get_name;

			# Check to see if we have an age characteristic
			if ( $comment_name =~ m/age/i ) {
				$age_comment = 1;
			}

			# Check to see if we have one of the restricted
			# CEPH ids is in a comment value
			foreach my $ceph_id (@ceph_ids) {
				if ( $comment_value =~ m/$ceph_id/i ) {
					$ceph_found_in_comment = 1;
				}
			}

		}

	}

	if ( ( $ceph_found == 1 or $ceph_found_in_comment == 1 ) and $age_char == 1 ) {

		$self->error(
"Restricted CEPH id found in a Comment/Characteristic column alongside age characteristic in SDRF. Restricted ids are @ceph_ids"
		);
	}

	if ( ( $ceph_found == 1 or $ceph_found_in_comment == 1 )
		and $age_comment == 1 )

	{

		$self->error(
"Restricted CEPH id found in a Comment/Characteristic column alongside age comment in SDRF. Restricted ids are @ceph_ids"
		);
	}

}

sub check_chars_factors_efo_styling {

	# FIXME: should be checking against EFO dynamically in the future?
	# At the moment we're only checking for signs of Title Case or CamelCase
	my ($self) = @_;
	my @sources = $self->get_magetab->get_sources;

	my $char_not_in_efo_style = 0;

	foreach my $source (@sources) {
		my @chars = @{ $source->get_characteristics };
		if ( grep { $_->get_category =~ /[A-Z]/ } @chars ) {
			$char_not_in_efo_style = 1;
		}
	}

	if ( $char_not_in_efo_style == 1 ) {
		$self->warn("Please consider using lowercase EFO-style characteristic terms.");
	}

	my @factor_names = map { $_->get_name } $self->get_magetab->get_factors;
	if ( grep { $_ =~ /[A-Z]/ } @factor_names ) {
		$self->warn("Please consider using lowercase EFO-style factor names.");
	}

	my @factor_types =
	  map { $_->get_factorType->get_value } $self->get_magetab->get_factors;
	if ( grep { $_ =~ /[A-Z]/ } @factor_types ) {
		$self->warn("Please consider using lowercase EFO-style factor-type terms.");
	}
}

1;
