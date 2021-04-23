#!/usr/bin/env perl
#
# EBI/FGPT/CheckSet/Curation.pm
#
# Anna Farne 2012 ArrayExpress team, EBI
#
# $Id: Curation.pm 25735 2014-08-04 10:13:25Z emma $
#

=pod

=head1 NAME

EBI::FGPT::CheckSet::Curation

=head1 SYNOPSIS

 use EBI::FGPT;

 my $check_sets = {
	'EBI::FGPT::CheckSet::Curation'  => 'curator_checks',
 };

 my $idf = $ARGV[0];
 my $checker = EBI::FGPT::Reader::MAGETAB->new(
    'idf'                  => $idf,
    'check_sets'           => $check_sets,
 );
 $checker->parse();

=head1 DESCRIPTION

Additional MAGETAB checks to perform during ArrayExpress curation. See L<CheckSet|EBI::FGPT::CheckSet>
for superclass methods.

=head1 CHECKS

=head1 Simple IDF checks:

IDF must provide factors, contacts, protocols and experiment description (ERROR)

Contacts should have a first name and affiliation (WARN)

Term sources should have a file/uri (WARN)

Experimental Factors must have a factor type (ERROR)

PubMed IDs must be numerical (ERROR)

Protocols should have a description of over 50 characters (WARN)

Sequencing experiments must have a protocol of type "nucleic acid library construction protocol" (ERROR)

Comment[AEExperimentType] must be specified and be from the approved list (ERROR)

=head1 Simple SDRF checks:

Factors and protocols declared in the IDF should be used in the SDRF (WARN)

Each SDRF should refer to some data files (WARN)

=head1 Full parse checks:

Protocol parameters declared in the IDF should be used in the SDRF (WARN)

Term Sources declared in the IDF should be used in the IDF or SDRF (WARN)

The materials used in a Hybridization must be LabeledExtracts (ERROR)

LabeledExtracts must have a Label (ERROR)

Hybs must not use multiple LabeledExtracts with the same Label (ERROR)

Check if the number of different Labels exceeds the number of channels (WARN)

Sources should have more than 2 Characteristics (WARN)

Check for variable Characteristics which have not been listed as factors (WARN)

Check for materials and data which are not described by a protocol (WARN)

Check units are from an approved list (ERROR)

=head1 Data file checks:

MD5, compression checks and previously loaded file checks are only run on non-matrix files

For files with a Comment[MD5] their actual MD5 sum must match that specified (ERROR)

The following checks are only run on files which are assoicated with an array design:

Affymetrix CHP file must be listed as Derived data (ERROR)

For Affymetrix files the chip type in the file must match that in the array design name, if available (ERROR)

Skip checks for binary non-affy data files (WARN)

File must be parsable with ArrayExpress::Datafile (ERROR)

File must not contain duplicate column headings (ERROR)

File must not contain duplicate design elements (ERROR)

If file contains exactly 65535 rows it may have been truncated by old version of Excel (WARN)

All design elements in the file must be described on the array design (ERROR)

We skip MD5, compression checks for raw seq files

=cut

package EBI::FGPT::CheckSet::Curation;

use Data::Dumper;
use Array::Utils qw(:all);
use File::Spec;
use Digest::MD5;
use English qw( -no_match_vars );

# FIXME: Test::MockObject is used to create a temporary
# Bio::MAGE object until this requirement has been removed
# from the ArrayExpress::Datafile matrix parsing code
use Test::MockObject;

use Moose;
use MooseX::FollowPBP;
use List::Util qw(max);
use File::Temp qw( tempfile );
use Scalar::Util qw( openhandle );
use Text::TabularDisplay;

use ArrayExpress::Datafile;
use ArrayExpress::Datafile::Affymetrix;

use EBI::FGPT::Config qw($CONFIG);
use EBI::FGPT::Resource::Database::ArrayExpress;
use EBI::FGPT::Common qw(open_log_fh);

use EBI::FGPT::Resource::ArrayExpressREST;

extends 'EBI::FGPT::CheckSet';

has 'ae_rest' => (
	is      => "ro",
	default => sub { EBI::FGPT::Resource::ArrayExpressREST->new() },
	lazy    => 1
);
has 'adf_elements' => ( is => 'rw', isa => 'HashRef', default => sub { {} } );
has 'adf_parsers'  => ( is => 'rw', isa => 'HashRef', default => sub { {} } );
has 'file_info_table' => (
	is        => 'rw',
	isa       => 'Text::TabularDisplay',
	builder   => '_create_table',
	lazy      => 1,
	predicate => 'has_file_info_table'
);
has 'affy_info_table' => (
	is        => 'rw',
	isa       => 'Text::TabularDisplay',
	builder   => '_create_affy_table',
	lazy      => 1,
	predicate => 'has_affy_info_table'
);
has 'missing_features' =>
  ( is => 'rw', isa => 'HashRef', default => sub { {} } );
has 'duplicate_features' =>
  ( is => 'rw', isa => 'HashRef', default => sub { {} } );
has 'raw_file_type' => ( is => 'rw', isa => 'HashRef', default => sub { {} } );
has 'illumina_matrix_files' => (
	is      => 'rw',
	isa     => 'ArrayRef[ArrayExpress::Datafile]',
	default => sub { [] }
);

augment 'run_idf_checks' => sub {

	my ($self) = @_;

	$self->check_idf_has("factors");
	$self->check_idf_has("contacts");
	$self->check_idf_has("protocols");
	$self->check_idf_has("description");
	$self->check_idf_has( "designTypes", "warn" );

	$self->check_contacts();
	$self->check_term_sources();
	$self->check_factors();
	$self->check_pubmed_id();
	$self->check_protocols();
	$self->check_ae_expt_type();

};

augment 'run_simple_sdrf_checks' => sub {

	my ($self) = @_;

	$self->check_idf_objects_used('factors');
	$self->check_idf_objects_used('protocols');

	$self->report_annotation();

	$self->run_data_checks();
	$self->write_data_report();
	$self->write_feature_log();

	$self->run_illumina_matrix_checks();
};

augment 'run_sdrf_checks' => sub {

	my ($self) = @_;

	# These checks can only be done after a full MAGE-TAB parse
	$self->check_parameters_used();
	$self->check_idf_objects_used('termSources');

	$self->check_hyb_inputs();
	$self->check_source_annot();
	$self->check_extract_comment_annot();
	$self->check_for_missing_factors();
	$self->check_for_protocol_apps();
	$self->check_unit_terms();

	# Only run on non-matrix files
	$self->run_data_md5_check();
	$self->check_compressed_file_integrity();

	$self->check_for_derived_data();
};

sub check_for_derived_data {

	my ($self) = @_;

	my @data = $self->get_magetab->get_data;

	my @derived_data = grep { $_->get_dataType->get_value eq "derived" } @data;

	unless (@derived_data) {
		$self->warn("Experiment has no derived data");
	}
}

sub check_compressed_file_integrity {

	my ($self) = @_;

	if ( $self->get_skip_data_checks ) {
		$self->warn("Skipping data file integrity check");
		return;
	}

	foreach my $file ( $self->get_magetab->get_dataFiles ) {

		my ( $path, $name ) = $self->_get_file_path($file);

		# Ignore raw seq files, to do this we determine if assay
		# attached to file has technology type "sequencing"

		my $type       = $file->get_dataType->get_value;
		my @inputEdges = $file->get_inputEdges;
		my $assay;
		my @tech_types;

		# Store technology type associated with raw file
		if ( $type eq "raw" ) {
			foreach my $inputEdge (@inputEdges) {

				# If file input is an assay get technology type
				if ( $inputEdge->get_inputNode->isa("Bio::MAGETAB::Assay") ) {
					$assay = $inputEdge->get_inputNode;
					push @tech_types, $assay->get_technologyType->get_value;
				}

				# If file input is a scan
				elsif (
					$inputEdge->get_inputNode->isa(
						"Bio::MAGETAB::DataAcquisition")
				  )
				{

					my $scan      = $inputEdge->get_inputNode;
					my @scanEdges = $scan->get_inputEdges;

					foreach my $scanEdge (@scanEdges) {
						if (
							$scanEdge->get_inputNode->isa(
								"Bio::MAGETAB::Assay")
						  )
						{
							$assay = $scanEdge->get_inputNode;
							push @tech_types,
							  $assay->get_technologyType->get_value;
						}
					}
				}

				else {
					$self->warn(
						"Cannot determine technology type for " . $name );
				}

			}
		}

		my $is_seq;
		$is_seq = grep { $_ =~ /sequencing/i } @tech_types;

		if ( $is_seq and ( $type eq "raw" ) ) {
			$self->warn( "Skipping compression check for",
				$name . " (assuming it is sequencing data)" );
			next;
		}

		unless ( -e $path ) {
			$self->error("File $name doesn't exist in data directory");
		}

		# Use regular expressions to ignore files that don't match
		# standard sequencing naming conventions

		if ( -r $path ) {

			next if ( $name =~ m/\.(txt|CEL|pdf|fastq|bam)$/ );

			if ( $name =~ m/\.gz$/ ) {
				my $check_results = `gunzip -tv $path 2>&1`;
				if ( $check_results !~ m/ok/i ) {
					$self->error(
						"File $name fails compression integrity check");
				}

			}

			if ( $name =~ m/\.zip$/ ) {
				my $check_results = `unzip -tv $path 2>&1`;
				if ( $check_results !~ m/ok/i ) {
					$self->error(
						"File $name fails compression integrity check");
				}

			}

			if ( $name =~ m/\.bz2$/ ) {
				my $check_results = `bzip2 -tv $path 2>&1`;
				if ( $check_results !~ m/ok/i ) {
					$self->error(
						"File $name fails compression integrity check");
				}

			}
		}

	}

}

sub run_data_md5_check {

	my ($self) = @_;

	if ( $self->get_skip_data_checks ) {
		$self->warn("Skipping data MD5 check");
		return;
	}

	my %files_by_md5;
	foreach my $file ( $self->get_magetab->get_dataFiles ) {
		my ( $path, $name ) = $self->_get_file_path($file);

		# Ignore raw seq files, to do this we determine if assay
		# attached to file has technology type "sequencing"

		my $type       = $file->get_dataType->get_value;
		my @inputEdges = $file->get_inputEdges;
		my $assay;
		my @tech_types;

		# Store technology type associated with raw file
		if ( $type eq "raw" ) {
			foreach my $inputEdge (@inputEdges) {

				# If file input is an assay get technology type
				if ( $inputEdge->get_inputNode->isa("Bio::MAGETAB::Assay") ) {
					$assay = $inputEdge->get_inputNode;
					push @tech_types, $assay->get_technologyType->get_value;
				}

				# If file input is a scan
				elsif (
					$inputEdge->get_inputNode->isa(
						"Bio::MAGETAB::DataAcquisition")
				  )
				{

					my $scan      = $inputEdge->get_inputNode;
					my @scanEdges = $scan->get_inputEdges;

					foreach my $scanEdge (@scanEdges) {
						if (
							$scanEdge->get_inputNode->isa(
								"Bio::MAGETAB::Assay")
						  )
						{
							$assay = $scanEdge->get_inputNode;
							push @tech_types,
							  $assay->get_technologyType->get_value;
						}
					}
				}

				else {
					$self->warn(
						"Cannot determine technology type for " . $name );
				}

			}
		}

		my $is_seq;
		$is_seq = grep { $_ =~ /sequencing/i } @tech_types;
		my @md5_comments =
		  grep { $_ and $_->get_name eq "MD5" } $file->get_comments;

		if ( $is_seq and ( $type eq "raw" ) ) {
			$self->warn( "Skipping MD5 checks for ",
				$name . " (assuming it is sequencing data)" );

			# Should throw error if no MD5s provided by submitter
			if ( !@md5_comments ) {
				$self->error( "No MD5 comment for sequencing file: ", $name );
			}

			next;
		}

		open( my $fh, "<", $path )
		  or ( $self->error("Could not open $path to check MD5 sum"), next );

		$self->debug("Calculating MD5 for file $name");

		my $md5 = Digest::MD5->new();
		my $chunk;
		my $chunksize =
		  65536;    # 64k for reasonable efficiency (untested though).
		while ( my $bytes = read( $fh, $chunk, $chunksize ) ) {
			$md5->add($chunk);
		}

		my $actual_md5 = $md5->hexdigest();
		push @{ $files_by_md5{$actual_md5} }, $name;

		if (@md5_comments) {

			# Skip this file and complain if it has more than 1 MD5 sum
			if ( @md5_comments > 1 ) {
				$self->error( "More than 1 MD5 checksum provided for file ",
					$file->get_uri );
				next;
			}

			my $expected = $md5_comments[0]->get_value;

			unless ( $expected eq $actual_md5 ) {
				$self->error(
"File $name does not match expected MD5 sum (expected: $expected, got: $actual_md5)"
				);
			}

		}
	}

	foreach my $size ( keys %files_by_md5 ) {
		my @files_md5 = @{ $files_by_md5{$size} };
		if ( @files_md5 > 1 ) {
			$self->warn( "The following data files may have identical MD5s: ",
				join ", ", sort @files_md5 );
		}
	}
}


sub _get_file_path {

	my ( $self, $file ) = @_;

  # FIXME: file paths are a bit of a mess as we might be working within data_dir
  # already, or we might still be in original dir. Need to sort this out.

	# Sanity check
	$self->logdie(
		"Object passed to _get_file_path is not a Bio::MAGETAB::DataFile")
	  unless $file->isa('Bio::MAGETAB::DataFile');

	my $uri = $file->get_uri;
	$uri =~ s/file\://;

	my $path = $uri;

	#	my $path =  File::Spec->catfile ($self->get_data_dir, $uri);

	return wantarray ? ( $path, $uri ) : $path;
}

sub run_data_checks {
	my ($self) = @_;

	# We do this check using the file_info gathered by SDRFSimple

	my @all_files = $self->check_for_data();

	if ( $self->get_skip_data_checks ) {
		$self->warn("Skipping all curation data file checks");
		return;
	}

	foreach my $file (@all_files) {

		next unless $file->{name};
		$self->debug( "Checking data file " . $file->{name} );

		my $path = File::Spec->catfile( $self->get_data_dir, $file->{name} );

		# Skip tests if we can't read the file, this error will be reported
		# by the main validation check
		next unless ( -r $path );

		# Skip checks if file is not associated with an array design
		# because it is probably a sequencing data file
		# Missing Array Design REF is reported as an error elsewhere
		unless ( $file->{array} ) {
			$self->info( "Skipping checks for file without Array Design REF \"",
				$file->{name}, "\" (assuming it is sequencing data)" );

		  # Info for data report: name type format columns rows array linebreaks
			my @info = (
				$file->{name}, $file->{type}, "not array data",
				"", "", "none", "",
			);
			$self->get_file_info_table->add(@info);
			next;
		}

		# Handle Affy files (NB. not including EXP checks as we
		# never see these anymore)
		if ( $file->{name} =~ m/\. (CHP|CEL) \z/ixms ) {
			$self->affymetrix_data_test($file);
			next;
		}

		# Skip checking for binary (non-Affy) files
		if ( -B $path ) {
			$self->warn( "Skipping checks for binary file \"",
				$file->{name}, "\"" );

		  # Info for data report: name type format columns rows array linebreaks
			my @info = (
				$file->{name}, $file->{type}, "binary", "", "", $file->{array},
				"",
			);
			$self->get_file_info_table->add(@info);
			next;
		}

		# Skip checking Illumina BeadChip files
		# Check removed for unglue
# 		my $ae_db = EBI::FGPT::Resource::Database::ArrayExpress->new();
# 		my $array_design_name =
# 		  $ae_db->get_array_design_name_by_acc( $file->{array} )
# 		  if ($ae_db);
# 		if ( ($array_design_name) && ( $array_design_name =~ /Illumina/ ) ) {
# 			$self->warn(
# "Recognised Illumina array using ADF name \'$array_design_name\', skipping checking file "
# 				  . $file->{name} );
# 			next;
# 		}

		# Now we've discarded the corner cases, get some actual
		# information from the file.
		my $df = ArrayExpress::Datafile->new(
			{
				path            => $path,
				name            => $file->{'name'},
				data_type       => $file->{'type'},
				array_design_id => $file->{'array'},
				mage_badata     => $file->{'ba_data'},
			}
		);

		# We need to set the mage_badata attribute as this is used
		# by existing ArrayExpress::Datafile to determine that transformed
		# file is a MAGE-TAB matrix (rather than Tab2MAGE)
		my $mock_badata = Test::MockObject->new;
		$mock_badata->set_always( 'getPropertySets', [] );
		$df->set_mage_badata($mock_badata);

		my $QTs      = {};
		my $hyb_ids  = {};
		my $norm_ids = {};
		my $scan_ids = {};

		my ( $feature_coords, $rc, $format );
		my ($orig_file_format_is_agilent) = 0;

		eval {
			$format = $df->parse_header;

# Need to catch Agilent data files because we need to fetch Agilent
# probe/reporter names later.
# Checking file type here because once parse_datafile is called,
# "fix_known_text_format" will be called (inside DataFile.pm),
# which in turn calls "_fix_Agilent".  "_fix_Agilent" turns the
# Agilent file into one with "generic" column headings (meta column, meta row etc).
# The generic column headings are added as the first four columns of
# the Agilent data file. The original headings start from column no. 5.

			if ( $df->get_format_type eq 'Agilent' ) {
				$orig_file_format_is_agilent = 1;
			}

			$self->debug( "Data format type is \'"
				  . $df->get_format_type
				  . "\' before parsing data file." );

			( $feature_coords, $rc ) =
			  $df->parse_datafile( $QTs, $hyb_ids, $norm_ids, $scan_ids, );

	   # Returned feature coordinates are in "1.1.1.1." style string (bc/br/c/r)
		};

		$self->debug( "Data format type is "
			  . $df->get_format_type
			  . " after parsing data file." );

		my @agilent_reporter_names;
		my $probename_col_num;

		if ( $orig_file_format_is_agilent == 1 ) {

			$self->info(
"We have Agilent raw file, need to retrieve reporter names too in case feature-level/coordinate checks fail."
			);

			my $agilent_file_path    = $df->get_path();
			my @cleaned_col_headings = @{ $df->get_column_headings() };

			# Need to find out which column "ProbeName" is in.
			# It differs between Agilent native Feature Extraction files.
			# The header line is always row 10.

			# Ignoring blank reporter names.

			open( IN, $agilent_file_path )
			  || $self->error(
				"Can't open Agilent data file: $agilent_file_path");

			while ( my $line = <IN> ) {
				next if $. < 10;

				if ( $. == 10 ) {
					my @row_content = split( "\t", $line );
					my $counter     = 0;
				  HEADER: foreach my $heading (@row_content) {

						if ( $heading =~ /^ProbeName$/ ) {
							$probename_col_num = $counter;
							last HEADER;
						}
						else {
							$counter++;
						}
					}
					$self->debug(
"ProbeName is in column index $probename_col_num. Actual column number is +1.\n"
					);

				}
				else {

					my @row_content = split( "\t", $line );
					my $reporter_name = $row_content[$probename_col_num];
					push( @agilent_reporter_names, $reporter_name )
					  unless $reporter_name =~ /^\s+$/;
				}
			}

			close IN
			  ; # handle of the same name is used for the next data file so must close it here first

			my $filename = $file->{name};
			$self->debug( "Retrieved "
				  . scalar @agilent_reporter_names
				  . " Agilent reporter names from $filename." );
		}

		if ( $EVAL_ERROR or $rc ) {
			$self->error( "Could not parse file \"",
				$file->{name}, "\": $EVAL_ERROR, $rc" );

		  # Info for data report: name type format columns rows array linebreaks
			my @info = (
				$file->{name}, $file->{type}, "could not parse",
				"", "", $file->{array}, "",
			);
			$self->get_file_info_table->add(@info);
			next;
		}

		if (    $df->get_data_type eq $CONFIG->get_RAW_DM_FILE_TYPE
			and $format eq "Illumina" )
		{
			my @all = @{ $self->get_illumina_matrix_files };
			push @all, $df;
			$self->set_illumina_matrix_files( \@all );
		}

		$self->report_file_info( $df, $format );

		$self->check_duplicate_columns($df);
		$self->check_duplicate_features( $df, $feature_coords );
		$self->check_excel_truncation($df);
		$self->check_features_match_array( $df, $feature_coords,
			\@agilent_reporter_names );
	}

}

sub run_illumina_matrix_checks {

	my ($self) = @_;

	foreach my $matrix ( @{ $self->get_illumina_matrix_files || [] } ) {

		# Check Hybs are defined in SDRF
		my @hybs = map { @{ $_ || [] } } @{ $matrix->get_heading_hybs || [] };
		my @qts = @{ $matrix->get_heading_qts || [] };

		my @sdrf_hybs;
		foreach my $sdrf ( @{ $self->get_simple_sdrfs || [] } ) {
			push @sdrf_hybs, keys %{ $sdrf->get_hybridizations || {} };
		}

		my %seen;
		foreach my $hyb_name (@hybs) {
			next if $seen{$hyb_name};
			$seen{$hyb_name} = 1;

			$self->info("Checking for existence of Hybridization $hyb_name");
			unless ( grep { $hyb_name eq $_ } @sdrf_hybs ) {
				$self->error(
"Hybridization $hyb_name not found in SDRF (Illumina matrix file: ",
					$matrix->get_name, ")"
				);
			}
		}

		# Bail out with error if number of hybs and QTs is different
		unless ( @hybs == @qts ) {
			$self->error(
				"Illumina matrix file ",
				$matrix->get_name,
				" contains ",
				scalar @hybs,
				" hybridizations, but ",
				scalar @qts,
				" quantitation types"
			);
			return;
		}

		# Check QT consistency
		my %qts_for_hyb;
		foreach my $i ( 0 .. $#hybs ) {
			my $qt_name  = $qts[$i];
			my $hyb_name = $hybs[$i];
			if ( $qts_for_hyb{$hyb_name}->{$qt_name} ) {
				$self->error(
					"Duplicate column in ",
					$matrix->get_name,
					": $hyb_name ($qt_name)"
				);
			}
			$qts_for_hyb{$hyb_name}->{$qt_name} = 1;
		}

		my $previous_qts;
		my $previous_hyb;
		foreach my $hyb ( keys %qts_for_hyb ) {
			my $qts = join ";", sort keys %{ $qts_for_hyb{$hyb} || {} };
			if ( $previous_qts and $previous_qts ne $qts ) {
				$self->error(
					"Inconsistent QTs in matrix ",
					$matrix->get_name,
					" e.g. $hyb has $qts, but $previous_hyb has $previous_qts"
				);
			}
			$previous_hyb = $hyb;
			$previous_qts = $qts;
		}
	}
}

sub write_data_report {

	my ($self) = @_;

	my $fh = open_log_fh( "expt", $self->get_input_name, "data" );

	if ( $self->get_skip_data_checks ) {
		print $fh "Data checking was skipped\n";
		return;
	}

	if ( $self->has_file_info_table ) {
		print $fh "\n\n";
		print $fh $self->get_file_info_table->render;
	}

	if ( $self->has_affy_info_table ) {
		print $fh "\n\n";
		print $fh $self->get_affy_info_table->render;
	}
}

sub write_feature_log {

	my ($self) = @_;

	my $fh = open_log_fh( "expt", $self->get_input_name, "feature" );

	my $missing = $self->get_missing_features;

	foreach my $ded_id ( keys %{ $missing || {} } ) {
		my $ded_atts = $missing->{$ded_id};
		print $fh "These files contain "
		  . $ded_atts->{'type'}
		  . " identifiers which are not on array "
		  . $ded_atts->{'array'} . ":\n\n";
		print $fh join "\n", @{ $ded_atts->{'files'} || [] };
		print $fh "\n\nMissing identifiers:\n\n";
		print $fh join "\n", @{ $ded_atts->{'list'} || [] };
		print $fh "\n\n";
	}

	print $fh ( q{-} x 80 );

	my $duplicate = $self->get_duplicate_features;

	foreach my $ded_id ( keys %{ $duplicate || {} } ) {
		my $ded_atts = $duplicate->{$ded_id};
		print $fh "\n\nThese files contain duplicate "
		  . $ded_atts->{'type'} . ":\n\n";
		print $fh join "\n", @{ $ded_atts->{'files'} || [] };
		print $fh "\n\nDuplicate identifiers:\n\n";
		print $fh join "\n", @{ $ded_atts->{'list'} || [] };
		print $fh "\n\n";
	}

}

sub check_excel_truncation {

	my ( $self, $file ) = @_;

	# Crappy Excel truncates files. Here we check for that.
	$self->debug( "File row count: ", $file->get_row_count );
	if ( $file->get_row_count() == 65535 ) {
		$self->warn( "Possible Excel-truncated file ", $file->get_name );
	}

}

sub _get_adf_elements_for {

	my ( $self, $acc, $type ) = @_;

	my $cache        = $self->get_adf_elements;
	my $wanted_class = "Bio::MAGETAB::$type";

	if ( exists $cache->{$acc}->{$type} ) {

		# We've already tried to load these elements
		# so just return what we have
		return $cache->{$acc}->{$type};
	}
	else {
		my $parser = $self->_get_adf_parser_for($acc);

		if ($parser) {
			$self->info("Getting $type identifiers from $acc");
			my $elements = [];  # ref to an array of elements we eventually want

			# Get a bag of features, reporters, composite element:
			my $all_design_elements = $parser->get_designElements();

			foreach my $element ( @{$all_design_elements} ) {
				if ( $element->isa($wanted_class) ) {
					if ( $type =~ /Reporter|Composite/ ) {
						push( @$elements, $element->get_name );
					}
					else {
						push(
							@$elements,
							(
								join ".",
								(
									$element->get_blockCol,
									$element->get_blockRow,
									$element->get_col,
									$element->get_row
								)
							)
						);
					}
				}
			}

			$self->debug( "Fetched "
				  . scalar @$elements
				  . " $type elements from ADF $acc." );

			if ( scalar @$elements == 0 ) {
				$self->error("Failed to get any $type from $acc")
				  if ( $acc !~ /^A-GEOD/ );
				$self->warn("Failed to get any $type from $acc")
				  if ( $acc =~ /^A-GEOD/ );
				$cache->{$acc}->{$type} = undef;
				return undef;
			}
			else {
				$cache->{$acc}->{$type} = $elements;
				return $elements;
			}
		}

		else {

			# If we failed to get the parser - set elements
			# to undef so we don't try to do it again
			$cache->{$acc}->{$type} = undef;
			return undef;
		}
	}

}

sub _get_adf_parser_for {

	my ( $self, $acc ) = @_;

	my $parsers = $self->get_adf_parsers;

	if ( exists $parsers->{$acc} ) {

		# We've already tried to create a parser so don't do it again
		return $parsers->{$acc};
	}
	else {

		# Download the ADF
		$self->info("Downloading ADF for $acc");

		my $adf = $self->get_ae_rest->get_adf($acc);

		# Save ADF temporarily as ADFParser needs a filepath. We use
		# File::Temp as a safe way of generating temporary files

		my ( $tmp_handle, $tmp_file ) =
		  tempfile( DIR => $CONFIG->get_AUTOSUBMISSIONS_FILEBASE, UNLINK => 1 );
		unless ( openhandle($tmp_handle) ) {
			die("Error: Could not open temporary file $tmp_file - $!");
		}
		print $tmp_handle $adf;    # assigns the downloaded ADF to the $tmp_file
		close $tmp_handle;

		# Set up our parser
		$self->debug("Initializing ADF parser for $acc");

		my $adf_reader =
		  Bio::MAGETAB::Util::Reader::ADF->new( { uri => $tmp_file, } );

		my $parser;

		eval { $parser = $adf_reader->parse() };

		if ($@) {
			$self->error( "There was a problem parsing the ADF for $acc. ",
				"Data file checking will not work properly.", $@ );
			unlink $tmp_file;
			$parsers->{$acc} = undef;
			return undef;
		}

		$parsers->{$acc} = $parser;
		$self->debug("Got ADF parser for $acc, returning it")
		  ;    # Catching cases where the parser somehow isn't cached properly
		return $parser;
	}
}

sub _check_features_match {

	my ( $self, $from_data, $from_adf ) = @_;

	my @missing = array_minus( @$from_data, @$from_adf );

	return @missing;

}

sub check_features_match_array {

	my ( $self, $file, $feature_coords, $agilent_reporter_names ) = @_;

	my $index_cols = $file->get_index_columns;
	my $acc        = $file->get_array_design_id;
	my $id_type;

	my $identifiers;
	my $heading;
	my $backup_identifiers;

	if ( scalar @$index_cols == 1 ) {

		# We have a Reporters or CompositeElements, decide which
		my $allowed = $CONFIG->get_T2M_INDICES;
		$heading = $file->get_column_headings->[ $index_cols->[0] ];

		if ( $heading =~ m/$allowed->{FGEM}[0]/i ) {
			$identifiers = $self->_get_adf_elements_for( $acc, "Reporter" );
			$id_type = "Reporter";
		}
		elsif ($heading =~ m/$allowed->{FGEM_CS}[0]/i
			|| $heading =~ m/$allowed->{AffyNorm}[0]/i
			|| $heading =~ m/$allowed->{GEO}[0]/i )
		{
			$identifiers =
			  $self->_get_adf_elements_for( $acc, "CompositeElement" );
			$id_type = "CompositeElement";
		}
		else {
			$self->logdie(
				$file->get_name,        " has unrecognized ",
				$file->get_format_type, " column heading $heading"
			);
		}
	}
	elsif ( scalar @$index_cols == 4 ) {

		# We have Features
		$heading            = "Features";
		$identifiers        = $self->_get_adf_elements_for( $acc, "Feature" );
		$backup_identifiers = $self->_get_adf_elements_for( $acc, "Reporter" );
		if ($backup_identifiers) {
			$self->debug(
				scalar @$backup_identifiers
				  . " reporters retrieved from ADF as backup for reporter-level checks"
			);
		}
		$id_type = "Feature (Block Column.Block Row.Column.Row)";

	}
	else {

		# We have a problem
		$self->logdie(
			$file->get_name,
			" has unsupported number of identifier columns (",
			scalar @$index_cols, ")"
		);
	}

	if ($identifiers) {

		# Check identifiers in data file are found on array
		$self->debug("Checking $heading match array $acc");
		my @missing =
		  $self->_check_features_match( $feature_coords, $identifiers );

# Try reporter-based checks if feature-based (coordinates) checks failed, to give it a second chance.
# If the reporter-based checks come clean, then @missing will be empty.

		if (   @missing
			&& $backup_identifiers
			&& scalar(@$agilent_reporter_names) > 0 )
		{
			$self->warn( "Agilent data file "
				  . $file->get_name
				  . " did not pass feature-level checks. Trying reporters." );
			$id_type = "Reporter";
			$heading = "Reporters";
			@missing =
			  $self->_check_features_match( $agilent_reporter_names,
				$backup_identifiers );
			if ( scalar @missing == 0 ) {
				$self->warn( "Agilent data file "
					  . $file->get_name
					  . " passed reporter-level check." );
			}
		}

		if (@missing
		  ) # Still can't match all identifiers in data file against ADF reporters
		{
			my $count = scalar @missing;
			$self->error( "File ", $file->get_name,
				" contains $count $heading which are not on array $acc" );

			# Record missing features for reporting
			my %feature_info = (
				'file'  => $file->get_name,
				'list'  => \@missing,
				'type'  => $id_type,
				'array' => $acc
			);

			$self->add_missing_features( \%feature_info );
		}
	}
	# Check removed for unglue
# 	elsif ( !$identifiers && $acc =~ /^A-GEOD-/ ) {
#
# # getting ADF name from DB and not from parsed ADF, in case ADF parsing failed and parser is undef
#
# 		my $ae_db    = EBI::FGPT::Resource::Database::ArrayExpress->new();
# 		my $adf_name = $ae_db->get_array_design_name_by_acc($acc);
# 		$self->warn(
# 			"No $heading found for GEO array $acc ($adf_name), ",
# 			"skipping identifier checks for file ",
# 			$file->get_name
# 		);
# 	}

	else {
		$self->error(
			"No $heading found for array $acc, ",
			"skipping identifier checks for file ",
			$file->get_name
		);
	}
	return;
}

sub add_missing_features {

	my ( $self, $args ) = @_;

	$self->add_feature_list( "missing_features", $args );

	return;
}

sub add_duplicate_features {

	my ( $self, $args ) = @_;

	$self->add_feature_list( "duplicate_features", $args );

	return;
}

sub add_feature_list {

	my ( $self, $type, $args ) = @_;

	my $getter = "get_$type";

	# Args are file, list, type, array

	# This code is based on the method used in
	# ArrayExpress::Curator::ExperimentChecker

	# We use an md5 hash string here rather than the full
	# listing to save on memory; typically multiple files will
	# share a list of missing features.
	my $md5 = Digest::MD5->new();
	$md5->add( @{ $args->{'list'} || [] } );
	my $ded_md5 = $md5->digest;

	# Reuse the list generated from previous files. Note that
	# we can also try writing the cache to disk and just index
	# via $ded_md5 in future.
	my $cache     = ( $self->$getter->{$ded_md5} || {} );
	my @file_list = @{ $cache->{'files'}         || [] };
	push @file_list, $args->{'file'};
	$cache->{'files'} = \@file_list;
	$cache->{'list'}  = $args->{'list'};
	$cache->{'type'}  = $args->{'type'};
	$cache->{'array'} = $args->{'array'};

	$self->$getter->{$ded_md5} = $cache;

	return;
}

sub _is_matrix {

	my ( $self, $file ) = @_;

	if (   $file->get_data_type eq $CONFIG->get_RAW_DM_FILE_TYPE
		or $file->get_data_type eq $CONFIG->get_FGEM_FILE_TYPE )
	{
		return 1;
	}

	return 0;
}

sub check_duplicate_columns {

	my ( $self, $file ) = @_;

	# Skip this for Matrix files because we check those during validation
	return if $self->_is_matrix($file);

	my $headings = $file->get_column_headings();

	my %column_count;
	foreach my $heading (@$headings) {
		$column_count{$heading}++;
	}

	if ( max( values %column_count ) > 1 ) {    # We've got trouble

		foreach my $col ( sort keys %column_count ) {
			if ( $column_count{$col} > 1 ) {
				$self->error( "Duplicate column in file ",
					$file->get_name, ": \"", $col, "\" occurs ",
					$column_count{$col}, " times" );
			}
		}
	}

	return;
}

sub check_duplicate_features {

	my ( $self, $file, $feature_coords ) = @_;

	my $id_type;
	my $index_cols = $file->get_index_columns;
	if ( scalar @$index_cols == 4 ) {
		$id_type = "Feature (Block Column.Block Row.Column.Row)";
	}
	else {
		$id_type = $file->get_column_headings->[ $index_cols->[0] ];
	}

	# Check for duplicate features in the data file
	my %seen_count;
	foreach my $feature (@$feature_coords) {
		$seen_count{$feature}++;
	}

	my @features;
	if ( max( values %seen_count ) > 1 ) {    # We've got trouble

		$self->error( "Duplicate $id_type found in file \"",
			$file->get_name, "\"" );

		foreach my $feature ( sort keys %seen_count ) {
			push( @features, $feature )
			  if ( $seen_count{$feature} > 1 );
		}

		# Record duplicate features for reporting
		my %feature_info = (
			'file'  => $file->get_name,
			'list'  => \@features,
			'type'  => $id_type,
			'array' => $file->get_array_design_id
		);

		$self->add_duplicate_features( \%feature_info );
	}

	return;
}

sub check_for_protocol_apps {

	my ($self) = @_;

	my @edges = $self->get_magetab->get_edges;
	my %reported;

	foreach my $edge (@edges) {
		unless ( $edge->get_protocolApplications ) {
			my $output_node = $edge->get_outputNode;
			my $name;
			if (   $output_node->isa('Bio::MAGETAB::Material')
				or $output_node->isa('Bio::MAGETAB::DataAcquisition')
				or $output_node->isa('Bio::MAGETAB::Assay') )
			{
				$name = $output_node->get_name;
			}
			elsif ( $output_node->isa('Bio::MAGETAB::Data') ) {
				$name = $output_node->get_uri;
			}
			else {

				# Just in case I missed something..
				$self->logdie(
					"Unknown node type ",
					ref($output_node),
					" encountered!"
				);
			}
			my $type = ref($output_node);
			$type =~ s/.*\:\://g;

			# Report lack of protocol once per output node
			next if ( $reported{ $type . $name } );
			$self->warn("No protocol describing $type $name");
			$reported{ $type . $name } = 1;
		}
	}
}

sub check_for_missing_factors {

	my ($self) = @_;

	# Store all Factor categories in hash
	my @factor_types =
	  map { $_->get_factorType } $self->get_magetab->get_factors;
	my %factor_categories =
	  map { $self->_normalize_category( $_->get_value ) => 1 } @factor_types;

	$self->debug( "Factor categories: ", join ", ", keys %factor_categories );

	my %annotations;
	foreach my $source ( $self->get_magetab->get_sources ) {
		foreach my $char ( $source->get_characteristics ) {
			$annotations{ $char->get_category }{ $char->get_value }++;
		}
	}

	# FIXME: need to match e.g. OrganismPart to organism_part or "organism part"
	while ( my ( $category, $valhash ) = each %annotations ) {

		$self->debug("Checking variability of $category annotations");

		# More than one value constitutes a variable.
		if ( scalar( grep { defined $_ } values %{$valhash} ) > 1 ) {
			$self->debug("Annotations vary for $category");
			my $norm_category = $self->_normalize_category($category);
			unless ( $factor_categories{$norm_category} ) {
				$self->warn(
"Experimental variable \"$category\" is not listed as a FactorValue"
				);
			}
		}
	}
}

sub check_source_annot {
	my ($self) = @_;

	my @sources = $self->get_magetab->get_sources;

	foreach my $source (@sources) {
		my @chars = grep { $_->get_value } $source->get_characteristics;
		unless ( @chars > 2 ) {
			my $name = $source->get_name;
			$self->warn("Source material $name may not be fully annotated");
		}
	}

}

sub check_extract_comment_annot {

	# This check was added to check for extracts that
	# may have multiple LIBRARY attributes assigned
	my ($self) = @_;

	my @extracts = $self->get_magetab->get_extracts;

	foreach my $extract (@extracts) {
		my $name = $extract->get_name;
		my @comment_for_extract;
		my @comments = @{ $extract->get_comments() || [] };

		# Store comment name in array which we can search for duplictaes
		foreach my $comment (@comments) {
			push @comment_for_extract, $comment->get_name;
		}

		# Check for duplicates in array
		my %uniq_elements;
		foreach my $comment_for_extract (@comment_for_extract) {
			$self->error(
				"Extract $name has multiple $comment_for_extract values")
			  if $uniq_elements{$comment_for_extract}++;
		}

	}

}

sub check_hyb_inputs {

	my ($self) = @_;

	my $magetab           = $self->get_magetab;
	my $max_channel_count = 0;
	my %all_labels;

	foreach my $assay ( $magetab->get_assays ) {

		# If hyb then get inputs
		if ( $assay->get_technologyType->get_value eq 'hybridization' ) {
			my $assay_name = $assay->get_name;
			$self->debug("Checking Labels for hyb $assay_name");

			my @input_edges =
			  grep { $_->get_outputNode == $assay } $magetab->get_edges;
			my @inputs = map { $_->get_inputNode } @input_edges;
			my $channel_count;
			my %labels_in_hyb;

			foreach my $input (@inputs) {
				$channel_count++;
				my $input_name = $input->get_name;

				# Check it is a LabeledExtract
				unless ( $input->isa('Bio::MAGETAB::LabeledExtract') ) {
					my $type = ref($input);
					$type =~ s/.*\:\://g;
					$self->error(
"Hybridization \"$assay_name\" uses an input which is not a LabeledExtract ($type: $input_name)"
					);
					next;
				}

			 # Check LabeledExtract has an associated label and record its usage
				my $label = $input->get_label;
				if ($label) {
					my $label_name = $label->get_value;
					$all_labels{$label_name}++;
					$labels_in_hyb{$label_name}++;
				}
				else {
					$self->error(
"LabeledExtract \"$input_name\" does not have an associated label"
					);
				}
			}

			# Check for duplicate labels
			while ( my ( $l_name, $count ) = each %labels_in_hyb ) {
				if ( $count > 1 ) {
					$self->error(
"Hybridization \"$assay_name\" uses $count $l_name LabeledExtracts"
					);
				}
			}

			# Set experiment max channel count
			if ( $channel_count > $max_channel_count ) {
				$max_channel_count = $channel_count;
			}
		}

	}

# Check total no. of labels seen does not exceed max channel count
# Warn only - mixed tech experiment could have max 2 channels but biotin, cy3 and cy5
	my @labels = keys %all_labels;
	if ( @labels > $max_channel_count ) {
		my $label_list = join ", ", sort @labels;
		$self->warn(
"Experiment uses more Labels than Channels (Channels: $max_channel_count, Labels: $label_list)"
		);
	}

}

sub check_for_data {

	# Data files are fetched from simple SDRFs.
	# See check_file_info method in Reader/MAGETAB/SDRFSimple.pm
	# File info includes not only file name but also:
	# expt factor, the assay and the ADF it's associated with.

	my ($self) = @_;

	$self->debug("Checking sdrfs contain data files");
	my @all_files;

	foreach my $sdrf ( @{ $self->get_simple_sdrfs || [] } ) {
		if ( @{ $sdrf->get_file_info || [] } ) {
			push @all_files, @{ $sdrf->get_file_info || [] };
		}
		else {
			$self->warn( "No data files found in SDRF ", $sdrf->get_uri );
		}
	}

	return @all_files;
}

sub check_parameters_used {

	my ($self) = @_;

	my @parameters = $self->get_magetab->get_protocolParameters;

	my %used;
	foreach my $sdrf ( @{ $self->get_simple_sdrfs || [] } ) {
		foreach my $ref ( keys %{ $sdrf->get_parameters_used } ) {
			$used{$ref} = 1;
		}
	}

	foreach my $param (@parameters) {
		my $name = $param->get_name;
		$self->debug("Checking parameter $name is used in the sdrf");
		unless ( $used{$name} ) {
			$self->warn(
"Parameter \"$name\" is defined in the idf but not used in the sdrf"
			);
		}
	}
}

sub check_idf_objects_used {

	my ( $self, $object_type ) = @_;

	my $sdrf_getter = "get_" . lc($object_type) . "_used";
	my $mtab_getter = "get_" . $object_type;
	my $singular    = $object_type;
	$singular =~ s/s$//;

	my %used;
	foreach my $sdrf ( @{ $self->get_simple_sdrfs || [] } ) {
		foreach my $ref ( keys %{ $sdrf->$sdrf_getter } ) {
			$used{$ref} = 1;
		}
	}

	# For termSources we need to check if they are used in the IDF too
	# before we report an error
	if ( $object_type eq "termSources" ) {
		unless ( $self->get_magetab ) {
			$self->warn(
"Cannot check if Term Sources are used in the IDF until a full MAGE-TAB parse is complete,",
				" will check if they are used in SDRF only"
			);
		}
		my @terms = $self->get_magetab->get_controlledTerms;
		foreach my $term (@terms) {
			if ( my $source = $term->get_termSource ) {
				$used{ $source->get_name } = 1;
			}
		}
	}

	foreach my $idf_object ( $self->get_investigation->$mtab_getter ) {
		my $name = $idf_object->get_name;
		$self->debug("Checking $singular $name is used");
		unless ( $used{$name} ) {
			$self->warn(
				"$singular \"$name\" is defined in the idf but not used");
		}
	}
}

sub check_protocols {

	my ($self) = @_;

	my $seq_expt_type          = undef;
	my $has_lib_construct_prot = 0;

	my @type_comments =
	  grep { $_->get_name eq "AEExperimentType" }
	  @{ $self->get_investigation->get_comments || [] };

	foreach my $comment (@type_comments) {
		my $type = $comment->get_value;
		if ( $type =~ /seq/i ) {
			$seq_expt_type = $type;
		}
	}

	foreach my $prot ( $self->get_investigation->get_protocols ) {
		$self->debug( "Checking protocol ", $prot->get_name );

		my $prot_type = $prot->get_protocolType->get_value;
		if ( $prot_type eq 'nucleic acid library construction protocol' ) {
			$has_lib_construct_prot = 1;
		}

		if ( my $text = $prot->get_text ) {
			unless ( length($text) > 50 ) {
				$self->warn( "Protocol description is too short for ",
					$prot->get_name );
			}
		}
		else {
			$self->warn( "Protocol ", $prot->get_name, " has no description" );
		}
	}

	if ( $seq_expt_type && $has_lib_construct_prot == 0 ) {
		$self->error(
"Experiment of type '$seq_expt_type' must have a protocol of type 'nucleic acid library construction protocol'."
		);
	}
}

sub check_pubmed_id {

	my ($self) = @_;

	foreach my $pub ( $self->get_investigation->get_publications ) {
		$self->debug( "Checking publication ", $pub->get_title );
		if ( my $pubmed = $pub->get_pubMedID ) {
			$self->debug("Checking pubmed id $pubmed");
			$self->error("Pubmed ID \"$pubmed\" is not numeric")
			  unless $pubmed =~ /^\d*$/;
		}
	}

}

sub check_factors {

	my ($self) = @_;

	my @factors = $self->get_investigation->get_factors;

	foreach my $factor (@factors) {
		unless ( $factor->get_factorType ) {
			$self->error( "Factor without a type (name: ",
				$factor->get_name, ")" );
		}
	}

}

sub check_term_sources {

	my ($self) = @_;

	my @sources = $self->get_investigation->get_termSources;

	my %source_name_count;
	my %source_uri_count
	  ; # this is to catch Term Source REFs with names spelt differently but identical URIs

	foreach my $source (@sources) {
		$source_name_count{ $source->get_name }++ if ( $source->get_name );
		$source_uri_count{ $source->get_uri }++   if ( $source->get_uri );
		unless ( $source->get_uri ) {
			$self->warn( "Term Source without a file/uri (name: ",
				$source->get_name, ")" );
		}
	}

	if ( scalar( keys %source_name_count ) > 0 ) {
		foreach my $source_name ( keys %source_name_count ) {
			if ( $source_name_count{$source_name} > 1 ) {
				$self->warn(
"Term Source Name \"$source_name\" appeared more than once in the IDF. Please clean up"
				);
			}
		}
	}

	if ( scalar( keys %source_uri_count ) > 0 ) {
		foreach my $source_uri ( keys %source_uri_count ) {
			if ( $source_uri_count{$source_uri} > 1 ) {
				$self->warn(
"Term Source File \"$source_uri\" appeared more than once in the IDF. Please clean up"
				);
			}
		}
	}
}

sub check_contacts {

	my ($self) = @_;

	my @contacts = $self->get_investigation->get_contacts;

	foreach my $contact (@contacts) {
		unless ( $contact->get_firstName ) {
			$self->warn( "Contact without a first name (last name: ",
				$contact->get_lastName, ")" );
		}
		unless ( $contact->get_organization ) {
			$self->warn( "Contact without an affiliation (last name: ",
				$contact->get_lastName, ")" );
		}
	}

}

sub check_idf_has {

	my ( $self, $att_name, $level ) = @_;

	my $getter = "get_$att_name";

	$self->debug("Attempting to $getter");
	unless ( $self->get_investigation->$getter ) {
		my $message = "Experiment has no $att_name";
		if ( $level && $level eq "warn" ) {
			$self->warn($message);
		}
		else {
			$self->error($message);
		}
	}

}

sub affymetrix_data_test {

	my ( $self, $file ) = @_;

	$self->debug( "Doing Affy tests on file ", $file->{name} );
	$file->{format} = 'Affymetrix';

	$self->confirm_affy_chip_type($file);

	# Very quick check to make sure CHP files are in the right place
	if (   $file->{name} =~ m/\.CHP$/i
		&& $file->{type} ne 'normalized' )
	{

		$self->error( "CHP file ", $file->{name},
			" should be a Derived Array Data File" );
	}

	# Some generic tests we can run.
	# $self->non_rowbased_data_test( $file );

	return;
}

sub confirm_affy_chip_type {

	my ( $self, $file ) = @_;

	# Takes an Affy Datafile (CHP or CEL), finds its chip_type (needs
	# to parse the files, wrapped in an eval); compares this to the
	# value returned from get_affy_design_id for the
	# ArrayDesign.accession (assuming both these values can be
	# obtained), and alert the user if they differ.

	my ( $chip_type, $is_gdac_chp );

	my $path = File::Spec->catfile( $self->get_data_dir, $file->{name} );
	local $EVAL_ERROR;
	my $sighandler = $SIG{__DIE__};
	delete $SIG{__DIE__};
	my $parser;
	eval {
		my $fac = ArrayExpress::Datafile::Affymetrix->new();
		$parser = $fac->make_parser($path);

		$parser->parse_header();

		$chip_type   = $parser->get_chip_type();
		$is_gdac_chp =
		  $parser->isa('ArrayExpress::Datafile::Affymetrix::CHP::GDAC_CHP');
	};
	$SIG{__DIE__} = $sighandler if $sighandler;
	if ($EVAL_ERROR) {

		# Affy parser failed, we need to report that.
		$self->error( "Unable to parse Affymetrix file ",
			$file->{name}, ", $EVAL_ERROR" );
	}
	else {

		# Check the chip type against the array accession.
		my $accession = $file->{array};
		if ( $accession && $chip_type ) {

			# eval this bit as it uses external resource
			my $wanted;
			eval {
				$wanted = $self->get_ae_rest->get_affy_design_id($accession);
			};
			if ($EVAL_ERROR) {
				$self->error(
"Could not retrieve Affy design ID for $accession - $EVAL_ERROR"
				);
			}

			if ($wanted) {
				unless ( $wanted eq $chip_type ) {
					$self->error( "Affy file assigned to wrong array (",
						$file->{name}, ": $chip_type, $accession: $wanted)" );
				}
			}
			else {
				$self->warn(
"No Affy [Design_ID] found in $accession array design name (",
					$file->{name},
					": $chip_type)"
				);
			}
		}
		elsif ( !$is_gdac_chp ) {

			# We skip this warning for old GDAC CHP files since we'd
			# have to parse the file fully (not just the header) to
			# get the chip_type.
			$self->warn( "Either array accession or chip type unavailable for",
				$file->{name} );

		}
	}

	$self->report_affy_file_info( $file, $parser );

	return;
}

sub _create_table {

  # Set up a text table for output to a log after data file checking is complete
	my @columns = qw(name type format columns rows array linebreaks);
	my $table   = Text::TabularDisplay->new(@columns);
}

sub _create_affy_table {

  # Set up a text table for output to a log after data file checking is complete
	my @columns = qw(name type format array chip_type);
	my $table   = Text::TabularDisplay->new(@columns);
}

sub report_file_info {

	my ( $self, $df, $format ) = @_;

	# $format can be used to report the original format type,
	# rather than the generic type information contained
	# in the df object after it has been parsed.
	$format ||= $df->get_format_type;

	my $col_count = scalar( @{ $df->get_column_headings || [] } );

	# Decided we don't need to have file info in
	# report log now that we have the  data file log

	#$self->report("File name:   ",$df->get_name);
	#$self->report("Data type:   ",$df->get_data_type);
	#$self->report("Data format: ",$format);
	#$self->report("Col count:   ",$col_count);
	#$self->report("Row count:   ",$df->get_row_count);
	#$self->report("Array acc:   ",$df->get_array_design_id);
	#$self->report("Line break:  ",$df->get_line_format);

	# See _create_table for order of columns
	my @info = (
		$df->get_name, $df->get_data_type, $format, $col_count,
		$df->get_row_count, $df->get_array_design_id, $df->get_line_format,
	);
	$self->get_file_info_table->add(@info);

	# Store raw file type info for reporting
	if ( $df->get_data_type eq 'raw' ) {
		$self->get_raw_file_type->{$format}++;
	}
}

sub report_affy_file_info {

	my ( $self, $file, $parser ) = @_;

	my @format = split "::", ref($parser);

	#$self->report("File name:   ",$file->{name});
	#$self->report("Data type:   ",$file->{type});
	#$self->report("Data format: ",$format[$#format]);
	#$self->report("Array acc:   ",$file->{array});
	#$self->report("Chip type:   ",$parser->get_chip_type);

	# See _create_affy_table for order of columns
	my @info = (
		$file->{name},  $file->{type}, $format[$#format],
		$file->{array}, $parser->get_chip_type,
	);
	$self->get_affy_info_table->add(@info);

	# Store raw file type info for reporting
	if ( $file->{type} eq 'raw' ) {
		$self->get_raw_file_type->{ $format[$#format] }++;
	}

}

sub report_annotation {

	my ($self) = @_;

	foreach my $sdrf ( @{ $self->get_simple_sdrfs || [] } ) {

		$self->report_section("Factor values");
		$self->report( $self->format_annotation_hash( $sdrf->get_all_fvs ) );

		$self->report_section("Source annotation");
		$self->report( $self->format_annotation_hash( $sdrf->get_all_chars ) );
	}
}

sub format_annotation_hash {
	my ( $self, $hashref ) = @_;

	my @lines;

	foreach my $category ( keys %{ $hashref || {} } ) {
		my $string = "$category: ";
		my @values = sort keys %{ $hashref->{$category} || {} };
		$string .= join ", ", @values;
		push @lines, $string;
	}

	return join "\n", @lines;
}
1;
