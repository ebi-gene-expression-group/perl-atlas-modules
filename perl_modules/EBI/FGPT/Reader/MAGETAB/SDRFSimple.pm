#!/usr/bin/env perl
#
# EBI/FGPT/Reader/MAGETAB/SDRFSimple.pm
#
# Anna Farne 2012 ArrayExpress team, EBI
#
# $Id: SDRFSimple.pm 25826 2014-09-11 11:45:37Z ewilliam $
#

=pod

=head1 NAME

EBI::FGPT::Reader::MAGETAB::SDRFSimple

=head1 DESCRIPTION

A module to perform a naive parse of a MAGE-TAB SDRF file without
attempting to build the full material processing graph.

Code adapted from ArrayExpress::MAGETAB::Checker written by Tim Rayner

=cut

package EBI::FGPT::Reader::MAGETAB::SDRFSimple;

use Moose;
use MooseX::FollowPBP;

use 5.008008;

use Carp;
use English qw( -no_match_vars );
use List::Util qw(first);
use Readonly;
use EBI::FGPT::Config qw($CONFIG);
use Data::Dumper;

extends 'Bio::MAGETAB::Util::Reader::Tabfile';

has 'investigation' =>
  ( is => 'rw', isa => 'Bio::MAGETAB::Investigation', required => 1 );
has 'logger'  => ( is => 'rw', isa => 'Log::Log4perl::Logger',       required => 1 );
has 'builder' => ( is => 'rw', isa => 'Bio::MAGETAB::Util::Builder', required => 1 );
has 'checker' => ( is => 'rw', isa => 'EBI::FGPT::Reader::MAGETAB',  required => 0 );

# Used to store per-row SDRF info.
has 'row_files'   => ( is => 'rw', default => sub { [] } );
has 'row_factors' => ( is => 'rw', default => sub { [] } );
has 'row_array' => ( is => 'rw', default => undef );
has 'row_hyb'   => ( is => 'rw', default => undef );
has 'row_assay' => ( is => 'rw', default => undef );

# Used to check usage of IDF objects in the SDRF.
has 'protocols_used'   => ( is => 'rw', default => sub { {} } );
has 'parameters_used'  => ( is => 'rw', default => sub { {} } );
has 'factors_used'     => ( is => 'rw', default => sub { {} } );
has 'termsources_used' => ( is => 'rw', default => sub { {} } );

# Used to track Characteristics for each material, to check for consistency.
has 'current_material' => ( is => 'rw', default => undef );
has 'char_cache'       => ( is => 'rw', default => sub { {} } );
has 'reported_cache'   => ( is => 'rw', default => sub { {} } );
has 'label_cache'      => ( is => 'rw', default => sub { {} } );

# Used to accumulate SDRF info for passing back to the data file
# checks.
has 'file_info'      => ( is => 'rw', default => sub { [] } );
has 'hybridizations' => ( is => 'rw', default => sub { {} } );
has 'scans'          => ( is => 'rw', default => sub { {} } );
has 'normalizations' => ( is => 'rw', default => sub { {} } );
has 'hyb_to_array'   => ( is => 'rw', default => sub { {} } );

has 'all_chars' => ( is => 'rw', default => sub { {} } );
has 'all_fvs'   => ( is => 'rw', default => sub { {} } );

# Certain checks will only be done if there is a suitable logger
# for them to be written to

Readonly my $CURATION   => "EBI::FGPT::CheckSet::Curation";
Readonly my $AE_ARCHIVE => "EBI::FGPT::CheckSet::AEArchive";

sub find_logger_for {

	my ( $self, $check_set_name ) = @_;

	if ( my $checker = $self->get_checker ) {
		if ( exists $checker->get_check_set_objects->{$check_set_name} ) {
			my $checkset = $checker->get_check_set_objects->{$check_set_name};
			return $checkset->get_logger;
		}
	}

	return undef;
}

sub parse_sdrf {

	my ($self) = @_;
	my $logger = $self->get_logger;
	$logger->info( "Naive parsing SDRF: ", $self->get_uri );

	my $sdrf_fh;
	eval { $sdrf_fh = $self->get_filehandle() };

	unless ($sdrf_fh) {
		$logger->error( "Unable to read SDRF file ", $self->get_uri );
	}

	# CSV parser will only work if $/ is set to correct eol character
	local $/ = $self->get_eol_char;

	# Scan past any empty or commented lines to get to the header row.
	my $headings;
	my $header_string;
  HEADERLINE:
	while ( $headings = $self->getline ) {
		next HEADERLINE if $self->can_ignore($headings);

		$header_string = join( q{}, @$headings );

		if ($header_string) {
			$logger->debug( "Identified the following heading line:\n", $header_string );
			last HEADERLINE;
		}
	}

	# Check that we don't have a Factor Value column before Hyridization Name
	# or Assay Name column
	my @head = @$headings;
	my $factor_pos;
	my $assay_pos;

	# Read head array in reverse so that if a Factor Value column
	# appears before a Hyridization Name or Assay Name column
	# we can tell from its poistion in the array

	for ( my $i = ( @head - 1 ) ; $i >= 0 ; $i-- ) {
		if ( $head[$i] =~ /^Factor/i ) { $factor_pos = $i; }
		if ( $head[$i] =~ /Assay Name|^Hybridi[sz]ation/i ) { $assay_pos = $i; }
	}

	if ( $factor_pos < $assay_pos
		and my $cur_logger = $self->find_logger_for($CURATION) )
	{
		$cur_logger->warn(
qq{Factor Value column found before Hyridization Name/Assay Name column in SDRF}
		);

	}

	# Check we've parsed to the end of the file.
	$self->confirm_full_parse($headings);

	# Give up if we have not found header
	unless ($header_string) {
		$self->get_logger->error("Could not find SDRF heading line");
		return;
	}

	# Get checks to perform on the SDRF contenct
	my $rowchecks = $self->check_sdrf_header($headings);

	# Read through the rest of the file, checking values as appropriate.
	my $sdrf_line_count = 0;
  FILE_LINE:
	while ( my $row = $self->getline ) {

		# Reset our per-row trackers.
		$self->set_row_array(undef);
		$self->set_row_files(   [] );
		$self->set_row_factors( [] );
		$self->set_row_hyb(undef);

		# Skip empty lines and comments
		next FILE_LINE if $self->can_ignore($row);

		# Count non-comment lines to check that we have some content
		$sdrf_line_count++;

		# Strip surrounding whitespace from each element.
		$row = $self->strip_whitespace($row);

		# Actually run the row-level checks here.
		for ( my $i = 0 ; $i < scalar @$row ; $i++ ) {
			my $sub = $rowchecks->[$i];

			if ( ref $sub eq 'CODE' ) {
				$self->get_logger->trace(
					qq{Running check on "$headings->[$i]" value "$row->[$i]"});
				$sub->( $row->[$i], $headings->[$i] );
			}
		}

		$self->check_file_info();
	}
	if ( $sdrf_line_count == 0 and my $ae_logger = $self->find_logger_for($AE_ARCHIVE) ) {
		$ae_logger->error("SDRF has no content");
	}
	if ( $sdrf_line_count == 1 and my $cur_logger = $self->find_logger_for($CURATION) ) {
		$cur_logger->warn("SDRF contains only 1 line of content");
	}

	# Check we've parsed to the end of the file.
	$self->confirm_full_parse;

}

sub check_sdrf_header {
	my ( $self, $headings ) = @_;

	# Used in multiple sets of tests, we define these regexps here only once.


	my $characteristics_re = qr/ Characteristics             # heading prefix
				 [ ]*
				 \[ [ ]* ([^\]]+?) [ ]* \]    # bracketed term
				 /ixms;
	my $factorvalue_re = qr/ Factor [ ]* Value          # heading prefix
				 [ ]*
				 \[ [ ]* ([^\]]+?) [ ]* \]    # bracketed term
				 (
				   [ ]*
				   \( [ ]* ([^\)]+?) [ ]* \)  # optional parens term
			         )?
				 /ixms;
	my $parameter_re = qr/ Parameter [ ]* Values?       # heading prefix
				 [ ]*
				 \[ [ ]* ([^\]]+?) [ ]* \]    # bracketed term
				 /ixms;
	my $unit_re = qr/ Unit                         # heading prefix
				 [ ]*
				 \[ [ ]* ([^\]]+?) [ ]* \]    # bracketed term
				 /ixms;

	# Define the tests to be run on header values. Any subs here will
	# be passed match values $1 and $2 from the key regexps. FIXME
	# consider validating the ontology terms held in Characteristics[]
	# and Unit[] column headers.
	my %header_test = (
		$characteristics_re => 1,
		$factorvalue_re     => sub { $self->check_sdrf_factorvalue(@_) },
		$parameter_re       => sub { $self->check_sdrf_parameter(@_) },
		$unit_re            => 1,
	);

	# Define any tests and/or aggregation methods to be run on the
	# column values. Any subs here will be passed each value from the
	# column in turn, and the full column header itself.
	my %recognized = (

		qr/ Source    [ ]*              Names? /ixms =>
		  sub { $self->set_current_material(shift) },

		qr/ Sample    [ ]*              Names? /ixms =>
		  sub { $self->set_current_material(shift) },

		qr/ Extract   [ ]*              Names? /ixms =>
		  sub { $self->set_current_material(shift) },

		qr/ Labell?ed [ ]* Extract [ ]* Names? /ixms =>
		  sub { $self->set_current_material(shift) },

		qr/ Term [ ]* Accession [ ]* Numbers?  /ixms => 1,
		qr/ Providers?                         /ixms => 1,
		qr/ Material [ ]* Types?               /ixms => 1,
		qr/ Technology [ ]* Types?             /ixms => 1,
		qr/ Labels?                            /ixms => =>
		  sub { $self->check_label_against_cache(@_) },
		qr/ Descriptions?                      /ixms => 1,
		qr/ Performers?                        /ixms => 1,
		qr/ Dates?                             /ixms => 1,
		qr/ Image [ ]* Files?                  /ixms => 1,

		qr/ Hybridi[sz]ation [ ]* Names? /ixms => sub { $self->add_hybridization(@_) },

		qr/ Assay [ ]* Names? /ixms => sub { $self->add_assay(@_) },

		qr/ Scan [ ]* Names? /ixms => sub { $self->add_scan(@_) },

		qr/ Normali[sz]ation [ ]* Names? /ixms => sub { $self->add_normalization(@_) },

		qr/ Array [ ]* Data [ ]* Files? /ixms => sub { $self->add_row_file( 'raw', @_ ) },

		qr/ Derived [ ]* Array [ ]* Data [ ]* Files? /ixms =>
		  sub { $self->add_row_file( 'normalized', @_ ) },

		qr/ Array [ ]* Data [ ]* Matrix [ ]* Files? /ixms =>
		  sub { $self->add_row_matrix_file( $CONFIG->get_RAW_DM_FILE_TYPE(), @_ ) },

		qr/ Derived [ ]* Array [ ]* Data [ ]* Matrix [ ]* Files? /ixms =>
		  sub { $self->add_row_matrix_file( $CONFIG->get_FGEM_FILE_TYPE(), @_ ) },

		# Only check Term Source REF if the optional namespace is omitted.
		qr/ Term [ ]* Source [ ]* REFs?  # main heading only
	   /ixms
		  => sub { $self->check_sdrf_termsource(@_) },

		qr/ Term [ ]* Source [ ]* REFs?  # main heading, and
	    [ ]* :[^\t\"]+                # optional namespace
	    /ixms => 1,

		# Only check Protocol REF if the optional namespace is omitted.
		qr/ Protocol [ ]* REFs?          # main heading only
	    /ixms
		  => sub { $self->check_sdrf_protocol(@_) },

		qr/ Protocol [ ]* REFs?          # main heading, and
	    [ ]* :[^\t\"]+                # optional namespace       
	    /ixms => 1,

		qr/ Array [ ]* Design [ ]* REFs? # main heading
	    ( [ ]* :[^\t\"]+ )?           # optional namespace       
	    /ixms
		  => sub { $self->add_array(shift) },

		qr/ Comments?                    # heading prefix
	    [ ]*
	    \[ [ ]* ([^\]]+?) [ ]* \]    # bracketed term
	    /ixms => 1,

		# See above for these regexps.
		$characteristics_re => sub { $self->check_char_against_cache(@_) },
		$factorvalue_re     => sub { $self->add_row_factor(@_) },
		$parameter_re       => 1,
		$unit_re            => 1,
	);

	# An array of either CODE refs to run on a given column, or
	# other true scalar values.
	my @rowchecks;
	my $index        = 0;
	my @headings_tmp = @$headings;
	my $last_index   = $#headings_tmp;
	foreach my $col ( @{ $headings || [] } ) {
		if ( my $result = first { $col =~ m/\A [ ]* $_ [ ]* \z/xms } keys %recognized ) {
			push @rowchecks, $recognized{$result};

			# Check Parameter Value, Factor Value headings here.
			my @args;
			if ( my $key = first { @args = ( $col =~ $_ ) } keys %header_test ) {
				my $test = $header_test{$key};
				if ( ref $test eq 'CODE' ) {
					$test->(@args);
				}
			}
		}
		else {

			# If the final column has no header we allow it but we
			# need to check that it does not contain any values
			if ( $col eq "" and $index == $last_index ) {
				push @rowchecks, sub { $self->check_is_empty(shift) };
				if ( my $cur_logger = $self->find_logger_for($CURATION) ) {
					$cur_logger->warn(
						"Ignoring final column of SDRF which has no heading");
				}
				return \@rowchecks;
			}
			push @rowchecks, 0;
			$self->get_logger->error("Unrecognized SDRF column heading: \"$col\".");
		}
		$index++;
	}
	return \@rowchecks;
}

sub check_is_empty {

	my ( $self, $value ) = @_;

	unless ( $value eq "" ) {
		$self->get_logger->error(
			"Value \"$value\" found in column without column header");
	}
	return;
}

sub check_label_against_cache {

	my ( $self, $label ) = @_;

	my $cache    = $self->get_label_cache();
	my $material = $self->get_current_material();

	# This is a separate error
	return unless defined($material);

	my $stored_label = $cache->{$material};
	if ( exists $cache->{$material} and $cache->{$material} ne $label ) {
		$self->get_logger->error(
			"LabeledExtract \"$material\" has inconsistent Label associations");
	}

	$cache->{$material} = $label;
	$self->set_label_cache($cache);

	return;

}

sub check_char_against_cache {

	my ( $self, $value, $heading ) = @_;

	return unless my $cur_logger = $self->find_logger_for($CURATION);

	my $cache    = $self->get_char_cache();
	my $reported = $self->get_reported_cache();
	my $material = $self->get_current_material();

	# Drop out if there's no material for these characteristics (this
	# is a separate error, and will be reported elsewhere).
	return unless defined($material);

	# Beware autovivification here (of the $material keys).
	if ( exists $cache->{$material}{$heading}
		&& !exists $reported->{$material}{$heading} )
	{

		unless ( $cache->{$material}{$heading} eq $value ) {

			my $error =
			    qq{The material "$material" has inconsistent }
			  . qq{characteristics ("$heading").\n};

			$cur_logger->warn($error);

			$reported->{$material}{$heading} = $value;
		}
	}
	else {
		$cache->{$material}{$heading} = $value;
	}

	$self->set_char_cache($cache);
	$self->set_reported_cache($reported);

	$self->get_all_chars->{$heading}{$value}++;

	return;
}

sub check_sdrf_termsource {

	my ( $self, $name ) = @_;

	# Check this is a valid term source.
	unless ( $self->is_defined_in_idf( "termSources", $name ) ) {
		my $error_message =
		  qq{Unknown Term Source REF in SDRF: "$name" (must be declared in IDF).\n};
		$self->get_logger->error($error_message);
	}

	# Record the termsource usage for later.
	$self->get_termsources_used()->{$name}++;

	return;
}

sub check_sdrf_protocol {
	my ( $self, $name ) = @_;

	# It is acceptable to refer to a protocol from an external source, e.g. ArrayExpress
	# We no longer report a warning for undeclared protocols here
	# In main validation checks we will ensure the protocol has a Term Source REF
	if ( my $cur_logger = $self->find_logger_for($CURATION) ) {

		# Check we have a declared protocol.
		unless ( $self->is_defined_in_idf( "protocols", $name ) ) {
			$cur_logger->info(
qq{Unknown Protocol REF in SDRF: "$name" (must be declared in IDF unless it has a Term Source REF).}
			);
		}
	}

	# Record the protocol usage for later.
	$self->get_protocols_used()->{$name}++;

	return;
}

sub check_sdrf_factorvalue {

	my ( $self, $name ) = @_;

	$self->get_logger->debug("Checking for factor $name in IDF");

	# Check this is a valid factor name.
	unless ( $self->is_defined_in_idf( "factors", $name ) ) {
		my $error_message =
		  qq{Unknown Experimental Factor in SDRF: "$name" (must be declared in IDF).\n};
		$self->get_logger->error($error_message);
	}

	# Record the factor usage for later.
	$self->get_factors_used()->{$name}++;

	return;
}

sub check_sdrf_parameter {

	my ( $self, $name ) = @_;

# It is acceptable to refer to a protocol from an external source, e.g. ArrayExpress
# For curator checks we will warn about the undefined parameter
# In main validation checks we will ensure the protocol with this parameter has a Term Source REF
	if ( my $cur_logger = $self->find_logger_for($CURATION) ) {

		# Check this is a defined parameter.
		$cur_logger->debug("Checking parameter $name is defined in IDF");

		unless ( $self->is_defined_parameter($name) ) {
			$cur_logger->warn(
				qq{Unknown Parameter in SDRF: "$name" (must be declared in IDF).});
		}
	}

	# Record the parameter usage for later.
	$self->get_parameters_used()->{$name}++;

	return;
}

sub check_file_info {

	# Read the data from row_files, arrays, factors, check for
	# consistency, and store it in %fileinfo for later.

	my ($self) = @_;

	foreach my $info ( @{ $self->get_row_files() } ) {

		if ( my $array = $self->get_row_array() ) {
			$info->{'array'} = $array;
		}
		else {
			unless ( $self->get_row_assay ) {
				$self->get_logger->error(
					qq{Data file "$info->{name}" not associated with any array designs.});
			}
		}

		my @factors = @{ $self->get_row_factors() };
		if ( scalar @factors ) {
			$info->{'factors'} = \@factors;
		}
		else {
			if ( my $cur_logger = $self->find_logger_for($CURATION) ) {
				$cur_logger->error(
					qq{Data file "$info->{name}" not associated with any factor values.});
			}
		}

		$self->add_file_info($info);
	}

	return;
}

sub is_defined_in_idf {
	my ( $self, $attribute_type, $name ) = @_;

	# Ignore any empty strings passed to this check
	unless ( $name and $name ne "" ) {
		return 1;
	}

	my $getter = "get_$attribute_type";
	my $items  = $self->get_investigation->$getter || [];

	my $found = grep { $_->get_name eq $name } @$items;

	return $found ? 1 : 0;
}

sub is_defined_parameter {
	my ( $self, $name ) = @_;

	# Ignore any empty strings passed to this check
	unless ( $name and $name ne "" ) {
		return 1;
	}

	# Get all the parameters attached to our magetab object
	my @parameters = $self->get_builder->get_magetab->get_protocolParameters;

	# Compare protocols attached to magetab object with those appearing as SDRF headers
	my $found = grep { $_->get_name eq $name } @parameters;

	return $found ? 1 : 0;
}

sub add_hybridization {

	my ( $self, $name ) = @_;

	$self->get_hybridizations->{$name}++;

	$self->set_row_hyb($name);

	return;
}

sub add_assay {
	my ( $self, $name ) = @_;

	$self->set_row_assay($name);

	$self->add_hybridization($name);
}

sub add_array {

	my ( $self, $name ) = @_;

	$self->set_row_array($name);

	my $row_hyb = $self->get_row_hyb();

	# If this row's hyb is already linked to an array design
	# then check it is the same one
	if ( my $existing_array = $self->get_hyb_to_array->{$row_hyb} ) {
		if ( $name ne $existing_array ) {
			my $error =
qq{Hybridization $row_hyb associated with more than 1 array design ($existing_array and $name)\n};
			$self->get_logger->error($error);
		}
	}
	else {
		$self->get_hyb_to_array->{$row_hyb} = $name;
	}

	return;
}

sub add_scan {

	my ( $self, $name ) = @_;

	$self->get_scans->{$name}++;

	return;
}

sub add_normalization {

	my ( $self, $name ) = @_;

	$self->get_normalizations->{$name}++;

	return;
}

sub add_row_file {

	my ( $self, $type, $name ) = @_;

	my %files = map { $_->{'name'} => $_ } @{ $self->get_row_files() };

	$files{$name} = { 'name' => $name, 'type' => $type };

	$self->set_row_files( [ values %files ] );

	return;
}

sub add_row_matrix_file {

	my ( $self, $type, $name ) = @_;

	my %files = map { $_->{'name'} => $_ } @{ $self->get_row_files() };

	$files{$name} = {
		'name' => $name,
		'type' => $type,
	};

	$self->set_row_files( [ values %files ] );

	return;
}

sub add_row_factor {

	my ( $self, $value, $heading ) = @_;

	my %factors = map { $_ => 1 } @{ $self->get_row_factors() };

	$factors{$value} = 1;

	$self->set_row_factors( [ keys %factors ] );

	$self->get_all_fvs->{$heading}{$value}++;

	return;
}

sub add_file_info {

	my ( $self, $info ) = @_;

	my %files = map { $_->{'name'} => $_ } @{ $self->get_file_info() };

	$files{ $info->{'name'} } = $info;

	$self->set_file_info( [ values %files ] );

	return;
}

1;
