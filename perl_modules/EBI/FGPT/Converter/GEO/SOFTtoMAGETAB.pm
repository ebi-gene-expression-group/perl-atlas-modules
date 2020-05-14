#!/usr/bin/env perl
#
#
# Module to convert a SOFT file into MAGETAB objects
# Uses Bio::MAGETAB API written by Tim Rayner
#
# Anna Farne 2009, ArrayExpress team, European Bioinformatics Institute
#
# $Id: SOFTtoMAGETAB.pm 19858 2012-05-28 14:42:32Z emma $

package EBI::FGPT::Converter::GEO::SOFTtoMAGETAB;

use Moose;
use MooseX::FollowPBP;
use LWP::Simple qw($ua get getstore is_success);
use URI::Split qw(uri_split);
use Archive::Extract;
use Data::Dumper;
use XML::Simple;
use File::Spec;
use Log::Log4perl;
use Date::Manip;
use DateTime::Format::Strptime qw( );

use Bio::MAGETAB;
use Bio::MAGETAB::Util::Writer;
use Bio::MAGETAB::Util::Writer::IDF;
use Bio::MAGETAB::Util::Writer::SDRF;

use File::Fetch;

#$File::Fetch::BLACKLIST = [qw|netftp lftp|];

use EBI::FGPT::Common qw(get_range_from_list get_ena_fastq_uri);
use EBI::FGPT::Converter::GEO::GeoExperiment qw(get_SRA_study_accs_for_GSE);

has 'acc'       => ( is => 'rw', default => 'undef' );
has 'soft_path' => ( is => 'rw', default => 'undef' );
has 'target_dir' => ( is => 'rw', isa => 'Str' );
has 'data_dir'   => ( is => 'rw', isa => 'Str' );
has 'skip_download' => ( is => 'rw', default => 'undef' );
has 'gse_gds_file'  => ( is => 'rw', isa => 'Str' );
has 'gpl_acc_file'  => ( is => 'rw', isa => 'Str' );
has 'ena_acc_file'  => ( is => 'rw', isa => 'Str' );
has 'magetab'       => ( is => 'rw', isa => 'Bio::MAGETAB' );
has 'investigation' => ( is => 'rw', isa => 'Bio::MAGETAB::Investigation' );
has 'hyb_nodes'     => ( is => 'rw', isa => 'ArrayRef', default => sub { [] } );
has 'assay_nodes'   => ( is => 'rw', isa => 'ArrayRef', default => sub { [] } );
has 'dispatch'      => ( is => 'rw', isa => 'HashRef' );
has 'prot_hash'     => ( is => 'rw', isa => 'HashRef', default => sub { {} } );
has 'prot_num'    => ( is => 'rw', isa => 'Str',      default => '0' );
has 'id_ref_maps' => ( is => 'rw', isa => 'HashRef',  default => sub { {} } );
has 'is_virtual'  => ( is => 'rw', isa => 'HashRef',  default => sub { {} } );
has 'factors'     => ( is => 'rw', isa => 'ArrayRef', default => sub { [] } );
has 'srp_accs'    => ( is => 'rw', isa => 'HashRef',  default => sub { {} } );

has 'term_mapper' => ( is => 'rw', isa => 'EBI::FGPT::FuzzyRecogniser' );
has 'term_source' => ( is => 'rw', isa => 'Bio::MAGETAB::TermSource' );

has 'gse_gds_map' => ( is => 'rw', isa => 'HashRef', default => sub { {} } );
has 'gpl_acc_map' => ( is => 'rw', isa => 'HashRef', default => sub { {} } );
has 'ena_acc_map'     => ( is => 'rw', isa => 'Str',     default => 'undef' );
has 'runs_for_gse'    => ( is => 'rw', isa => 'HashRef', default => sub { {} } );
has 'accs_for_gse'    => ( is => 'rw', isa => 'HashRef', default => sub { {} } );
has 'runs_for_gsm'    => ( is => 'rw', isa => 'HashRef', default => sub { {} } );
has 'exps_for_gsm'    => ( is => 'rw', isa => 'HashRef', default => sub { {} } );
has 'samples_for_gsm' => ( is => 'rw', isa => 'HashRef', default => sub { {} } );
has 'fastqs_for_run'  => ( is => 'rw', isa => 'HashRef', default => sub { {} } );
has 'layout_for_gsm'  => ( is => 'rw', isa => 'HashRef', default => sub { {} } );

# Hashes required for protocol processing these are created on our first read through
# of the soft file.
has 'growth_protocol_hash' => (
								is      => 'rw',
								isa     => 'HashRef',
								default => sub { {} },
								traits  => ['Hash'],
								handles => {
											 exists_in_growth_hash => 'exists',
											 keys_in_growth_hash   => 'keys',
											 get_growth_hash       => 'get',
											 set_growth_hash       => 'set',
								}
);
has 'extraction_protocol_hash' => (
									is      => 'rw',
									isa     => 'HashRef',
									default => sub { {} },
									traits  => ['Hash'],
									handles => {
												 exists_in_extraction_hash => 'exists',
												 keys_in_extraction_hash   => 'keys',
												 get_extraction_hash       => 'get',
												 set_extraction_hash       => 'set',
									}
);
has 'treatment_protocol_hash' => (
								   is      => 'rw',
								   isa     => 'HashRef',
								   default => sub { {} },
								   traits  => ['Hash'],
								   handles => {
												exists_in_treatment_hash => 'exists',
												keys_in_treatment_hash   => 'keys',
												get_treatment_hash       => 'get',
												set_treatment_hash       => 'set',
								   }
);
has 'label_protocol_hash' => (
							   is      => 'rw',
							   isa     => 'HashRef',
							   default => sub { {} },
							   traits  => ['Hash'],
							   handles => {
											exists_in_label_hash => 'exists',
											keys_in_label_hash   => 'keys',
											get_label_hash       => 'get',
											set_label_hash       => 'set',
							   }
);
has 'hyb_protocol_hash' => (
							 is      => 'rw',
							 isa     => 'HashRef',
							 default => sub { {} },
							 traits  => ['Hash'],
							 handles => {
										  exists_in_hyb_hash => 'exists',
										  keys_in_hyb_hash   => 'keys',
										  get_hyb_hash       => 'get',
										  set_hyb_hash       => 'set',
							 }
);
has 'scan_protocol_hash' => (
							  is      => 'rw',
							  isa     => 'HashRef',
							  default => sub { {} },
							  traits  => ['Hash'],
							  handles => {
										   exists_in_scan_hash => 'exists',
										   keys_in_scan_hash   => 'keys',
										   get_scan_hash       => 'get',
										   set_scan_hash       => 'set',
							  }
);

has 'data_processing_protocol_hash' => (
										 is      => 'rw',
										 isa     => 'HashRef',
										 default => sub { {} },
										 traits  => ['Hash'],
										 handles => {
											   exists_in_data_processing_hash => 'exists',
											   keys_in_data_processing_hash   => 'keys',
											   get_data_processing_hash       => 'get',
											   set_data_processing_hash       => 'set',
										 }
);

# Hashes required to prevent duplicate Comment[XXX] columns
has 'source_comment_hash' => (
							   is      => 'rw',
							   isa     => 'HashRef',
							   default => sub { {} },
							   traits  => ['Hash'],
							   handles => {
											exists_in_hash_of_source_comment => 'exists',
											keys_in_hash_of_source_comment   => 'keys',
											get_hash_of_source_comment       => 'get',
											set_hash_of_source_comment       => 'set',
							   }
);

has 'comment_sample_characteristics_hash' => (
									is      => 'rw',
									isa     => 'HashRef',
									default => sub { {} },
									traits  => ['Hash'],
									handles => {
										exists_in_hash_of_sample_char_comment => 'exists',
										keys_in_hash_of_sample_char_comment   => 'keys',
										get_hash_of_sample_char_comment       => 'get',
										set_hash_of_sample_char_comment       => 'set',
									}
);

my %have_seen_protocol;
$| = 1;
my $files = 1;    #counter used for additional file naming

# set proxy to ensure File::Fetch can use all methods to fetch files
$ua->proxy( [ 'http', 'ftp' ], 'http://www-proxy.ebi.ac.uk:3128' );
$ENV{ftp_proxy} = 'http://www-proxy.ebi.ac.uk:3128';

my $logger = Log::Log4perl::get_logger("SOFT");

sub BUILD
{
	my $self = shift;

	# set up pur MAGE-TAB object now so it ready before we get going
	my $mtab = Bio::MAGETAB->new();
	$self->set_magetab($mtab);

	# If gse accession provided instead of file path then download soft file from ncbi
	unless ( $self->get_soft_path )
	{
		unless ( $self->get_acc )
		{
			$logger->error("You MUST provide either a SOFT file path or a GSE number");
		}
		my $gse       = $self->get_acc;
		my $soft_name = $gse . "_family.soft";
		my $gse_nnn   = substr($gse, 0, -3) . "nnn";
		my $uri       =
			"ftp://ftp.ncbi.nlm.nih.gov/geo/series/" . $gse_nnn . "/" . $gse . "/" . "soft" . "/"
			. $soft_name . ".gz";

		$soft_name = $self->_download_file( $uri, $self->get_target_dir )
		  or $logger->error("Could not download soft file for $gse from $uri");
		$self->set_soft_path( File::Spec->catfile( $self->get_target_dir, $soft_name ) );
	}

	# If we have a term mapper then make sure we also have a term source
	if ( $self->get_term_mapper )
	{
		unless (     $self->get_term_source
				 and $self->get_term_source->isa('Bio::MAGETAB::TermSource') )
		{
			$logger->error(
					"You have provided a term mapper, you must provide the corresponding "
					  . "Bio::MAGETAB::TermSource object" );
		}
	}

	# On dispatch each method is passed (text value, current hyb object, channel number)
	$self->set_dispatch(
		{

			#Series info
			"^SERIES"                 => sub { $self->_create_investigation(@_) },
			"!Series_title"           => sub { $self->get_investigation->set_title(@_) },
			"!Series_summary"         => sub { $self->_add_experiment_description(@_) },
			"!Series_overall_design"  => sub { $self->_add_experiment_description(@_) },
			"!Series_pubmed_id"       => sub { $self->_add_pmid(@_) },
			"!Series_status"          => sub { $self->_add_release_date(@_) },
			"!Series_submission_date" => sub {
				$self->_add_expt_comment( "ArrayExpressSubmissionDate", @_ );
			},
			"!Series_last_update_date" =>
			  sub { $self->_add_expt_comment( "GEOLastUpdateDate", @_ ) },
			"!Series_contact_email"      => sub { $self->_add_series_email(@_) },
			"!Series_contact_name"       => sub { $self->_add_series_contact_name(@_) },
			"!Series_contact_department" => sub { $self->_add_series_address_part(@_) },
			"!Series_contact_institute"  => sub { $self->_add_series_organization(@_) },
			"!Series_contact_address"    => sub { $self->_add_series_address_part(@_) },
			"!Series_contact_city"       => sub { $self->_add_series_address_part(@_) },
			"!Series_contact_state"      => sub { $self->_add_series_address_part(@_) },
			"!Series_contact_zip/postal_code" =>
			  sub { $self->_add_series_address_part(@_) },
			"!Series_contact_country" => sub { $self->_add_series_address_part(@_) },
			"!Series_contact_phone"   =>
			  sub { $self->get_investigation->get_contacts->[0]->set_phone(@_) },
			"!Series_contact_fax" =>
			  sub { $self->get_investigation->get_contacts->[0]->set_fax(@_) },
			"!Series_contributor" => sub { $self->_add_contact(@_) },
			"!Series_type"        => sub {
				$self->_add_expt_comment( "AEExperimentType",
										  $self->map_to_efo_type(@_) );
			},
			"!Series_supplementary_file" => sub { $self->_add_series_srp(@_) },

			# BioSample info
            "!Sample_relation" =>
                  sub { $self->_add_biosample_id( "BIOSAMPLE", @_ ) },

			# Sample info
			"!Sample_supplementary_file" => sub { $self->_download_supp_data(@_) },
			"!Sample_channel_count"      => sub { $self->_create_channels(@_) },
			"!Sample_organism"           => sub { $self->_add_species(@_) },
			"!Sample_characteristics"    => sub { $self->_add_chars(@_) },
			"!Sample_label"              => sub { $self->_add_label(@_) },

			# Protocol info begin
			"!Sample_treatment_protocol" =>
			  sub { $self->_correct_treatment_protocol(@_) },
			"!Sample_growth_protocol"  => sub { $self->_correct_growth_protocol(@_) },
			"!Sample_extract_protocol" => sub { $self->_correct_extraction_protocol(@_) },
			"!Sample_label_protocol"   => sub { $self->_correct_label_protocol(@_) },
			"!Sample_hyb_protocol"     => sub { $self->_correct_hyb_protocol(@_) },
			"!Sample_scan_protocol"    => sub { $self->_correct_scan_protocol(@_) },
			"!Sample_data_processing"  =>
			  sub { $self->_correct_data_processing_protocol(@_) },

			# Protocol info end

			"!Sample_source_name" =>
			  sub { $self->_correct_source_comment( "Sample_source_name", @_ ) },

			"!Sample_biomaterial_provider" => sub { $self->_add_provider(@_) },

			"!Sample_molecule"    => sub { $self->_add_extract_type(@_) },
			"!Sample_description" =>
			  sub { $self->_correct_source_comment( "Sample_description", @_ ) },

			"!Sample_instrument_model" =>
			  sub { $self->_add_extract_comment( "INSTRUMENT_MODEL", @_ ) },
			"!Sample_library_selection" => sub {
				$self->_add_extract_comment( "LIBRARY_SELECTION", @_ ),
				  $self->_remove_labeled_extract(@_);
			},
			"!Sample_library_source" =>
			  sub { $self->_add_extract_comment( "LIBRARY_SOURCE", @_ ) },
			"!Sample_library_strategy" =>
			  sub { $self->_add_extract_comment( "LIBRARY_STRATEGY", @_ ) },

		}
	);

	# Load the GSE->GDS and GPL->accession maps if we have them

	$self->load_gse_gds_map( $self->{gse_gds_file} ) if $self->{gse_gds_file};
	$self->load_gpl_acc_map( $self->{gpl_acc_file} ) if $self->{gpl_acc_file};
	$self->load_ena_acc_map( $self->{ena_acc_file} ) if $self->{ena_acc_file};

}

=head
Series atts not yet handled:

!Series_web_link 

_row_count
_contact_web_link

Sample atts not yet handled:

!Sample_anchor 
!Sample_type 
!Sample_tag_count 
!Sample_tag_length 
!Sample_relation

=cut

sub parse_soft
{
	my ($self) = @_;

	open( my $fh, "<:encoding(utf-8)", $self->get_soft_path )
	  or $logger->logdie(
			   "Could not open SOFT file " . $self->get_soft_path . " for reading - $!" );

	# Variables to store context information as we read through SOFT file
	my $current_hyb;
	my @table_header;
	my $platform_company;
	my $platform_gpl;
	my $platform_title;
	my $sample_platform;

	$logger->info("Parsing soft file to create nodes and edges");

  LINE: while ( defined( my $line = <$fh> ) )
	{

		if ( $line =~ /!Platform_manufacturer\s*=\s*(.*)/ig )
		{
			$platform_company = $1;
			next LINE;
		}
		if ( $line =~ /!Platform_title\s*=\s*(.*)/ig )
		{
			$platform_title = $1;
			next LINE;
		}
		if ( $line =~ /\^PLATFORM\s*=\s*(.*)/ig )
		{
			$platform_gpl = $1;
			next LINE;
		}
		if ( $line =~ /!Platform_technology\s*=\s*high-throughput sequencing/ig )
		{
			# Store list of virtual seq platforms so we know which samples
			# are sequencing assays rather than hybs
			# Platform title will be used as Assay comment
			$self->get_is_virtual->{$platform_gpl} = $platform_title;
			next LINE;
		}

		if ( $line =~ /\!Sample_platform_id\s*=\s*(.*)/ig )
		{
			$sample_platform = $1;

			# We don't skip to next line as platform id will be handled by dispatch too
		}

		if ( $line =~ /([!\^]\w*)\s*=\s*(.*)/ )
		{
			my $tag   = $1;
			my $value = $2;

			# We create the hyb here rather than through dispatch
			# so that we can store the current hyb in this scope
			# 1 GEO Sample = 1 MAGETAB Hyb or Assay
			if ( $tag eq "^SAMPLE" )
			{
				my $hyb = $self->_create_assay($value);
				$current_hyb = $hyb;

				# Clear the table header from previous sample
				@table_header = ();
			}

			# this calls the methods in dispatch on the first read through of the file
			$self->_dispatch( $tag, $value, $current_hyb );

		}
		elsif ( $line =~ /#(.*)/g )
		{
			push @table_header, $1;
		}
		elsif ( $line =~ /!Sample_table_begin/i )
		{
			my $filename = $current_hyb->get_name . "_sample_table.txt";
			my $filepath = File::Spec->catfile( $self->get_data_dir, $filename, );
			open( my $out, ">", $filepath ) or die $!;

			# Get agilent id to spot_id map if we have one
			my $new_id_for = $self->get_id_ref_maps->{$sample_platform};

		  DATA_LINE: while ( defined( my $data_line = <$fh> ) )
			{
				if ( $data_line =~ /!Sample_table_end/i )
				{
					close $out;
					my $prot_text = join " ", @table_header;
					$self->_add_data_with_prot( $current_hyb, $filename, $prot_text );
					next LINE;
				}

				# For non Affy files we need to change the ID
				# column name to Reporter Identifier
				if ($platform_company)
				{
					unless ( $platform_company =~ /Affymetrix/ )
					{
						$data_line =~ s/^ID_REF/Reporter Identifier/;
					}
				}

				# Map ID_REFs to required IDs if we have map
				if ($new_id_for)
				{
					my @values = split "\t", $data_line;
					my $id = $values[0];
					$values[0] = ( $new_id_for->{$id} || $values[0] );
					print $out join "\t", @values;
				}
				else
				{
					print $out $data_line;
				}
			}
		}
		elsif ( $line =~ /!platform_table_begin/i )
		{

			# If this is an agilent design which is in AE we need to map IDs
			# unless it is a geo "Probe name version"
			if (    $platform_company =~ /Agilent/i
				 && $platform_title !~ /Probe Name version/i )
			{
				if ( exists $self->get_gpl_acc_map->{$platform_gpl} )
				{
					$self->_make_id_ref_map_for( $platform_gpl, $fh );
				}
			}
		}

	}

	$logger->info("Finished parsing soft file to create nodes and edges");

	# Add ENA accs from mapping file
	$self->_add_ena_accs;

# Redefine dispatch to handle protocols. We need to apply protocols on a second
# read through of the sdrf after all nodes and edges have been created.
#
# Platform id is handled here as it determines if we have an assay or a hyb
# and this affects which nodes are included and which sdrf they are added to
#
# Sample title is also handled because it can only be added after
# the channel count has been determined and Source objects created
#
# A number of fields are handle in the 2nd parse ( Sample description, Sample_source_name and
# Sample_characteristics). These are fields that will become Comments[XXX] columns
# and to prevent duplicates these must be stored in a hash and the values concatenated on the first parse.
# The Comments are created on the second parse so as to create only one column:

	$self->set_dispatch(
		{
		   "!Sample_platform_id" => sub { $self->_add_array_ref(@_) },

		   # Protocol info begin
		   "!Sample_scan_protocol" =>
			 sub { $self->_add_scan_protocol( "array scanning protocol", @_ ) },
		   "!Sample_data_processing" => sub {
			   $self->_add_normalization_protocol(
											 "normalization data transformation protocol",
											 @_ );
		   },
		   "!Sample_treatment_protocol" => sub {
			   $self->_add_sample_protocol( "sample treatment protocol", @_ );
		   },
		   "!Sample_extract_protocol" => sub {
			   $self->_add_sample_protocol( "nucleic acid extraction protocol", @_ );
		   },
		   "!Sample_growth_protocol" =>
			 sub { $self->_add_sample_protocol( "growth protocol", @_ ) },
		   "!Sample_label_protocol" => sub { $self->_add_label_protocol(@_) },
		   "!Sample_hyb_protocol"   => sub { $self->_add_hyb_protocol(@_) },

		   # Protocol info end

		   "!Sample_title" => sub { $self->_add_source_comment( "Sample_title", @_ ) },
		   "!Sample_source_name" =>
			 sub { $self->_add_source_comment( "Sample_source_name", @_ ) },
		   "!Sample_description" =>
			 sub { $self->_add_source_comment( "Sample_description", @_ ) },
		   "!Sample_characteristics" => sub { $self->_add_sample_chars_comment(@_) }
		}
	);
	seek( $fh, 0, 0 );
	$logger->info("Parsing soft file to add protocols and identify assays/hybs");
	while ( defined( my $line = <$fh> ) )
	{

		if ( $line =~ /([!\^]\w*)\s*=\s*(.*)/ )
		{
			my $tag   = $1;
			my $value = $2;

			# Get the current hyb
			if ( $tag eq "^SAMPLE" )
			{
				$current_hyb = $self->find_hyb($value);
			}

			$self->_dispatch( $tag, $value, $current_hyb );

		}
	}
	$logger->info("Finished parsing soft file to add protocols and identify assays/hybs");

	# Add nodes to relevant sdrf so that SDRF rows are assembled
	$logger->info("Assembling SDRF Rows");
	my @sdrfs;
	if ( @{ $self->get_hyb_nodes } )
	{
		my $hyb_sdrf = Bio::MAGETAB::SDRF->new(
							  {
								uri => File::Spec->catfile(
									 $self->get_data_dir, $self->get_acc . ".hyb.sdrf.txt"
								),
							  }
		);
		$hyb_sdrf->add_nodes( $self->get_hyb_nodes );
		push @sdrfs, $hyb_sdrf;
	}

	if ( @{ $self->get_assay_nodes } )
	{

		# All data files found in GEO for HTS assays should be listed as derived
		$self->_make_files_derived( $self->get_assay_nodes );

		my $assay_sdrf = Bio::MAGETAB::SDRF->new(
							{
							  uri => File::Spec->catfile(
								   $self->get_data_dir, $self->get_acc . ".assay.sdrf.txt"
							  ),
							}
		);
		$assay_sdrf->add_nodes( $self->get_assay_nodes );
		push @sdrfs, $assay_sdrf;

		# See if we have an SRA accession linked to this experiment
		$self->_add_sra_acc;

	}

	# Add FactorValues to SDRF rows
	if ( my $gds = $self->get_gse_gds_map->{ $self->get_acc } )
	{

		# Make FVs from GDS
		$logger->info("Adding factor values from GDS file");
		$self->_make_fvs_from_gds($gds);

	}
	else
	{
		$logger->info("Adding factor values from characteristics");
		$self->_make_fvs_from_chars;
	}
	$self->get_investigation->set_factors( $self->get_factors );

	# Add SDRFs to IDF
	$self->get_investigation->set_sdrfs( \@sdrfs );

	# Checks title to make sure it does not contain an arrayexpress accesssion
	#as we may be importing a submission GEO has imported from us

	my $title = $self->get_investigation->get_title;
	if ( $title =~ /^\[E-\w*-\d*.\]/ )
	{
		$logger->logdie(
"ArrayExpress accession appears in title-may be importing pre-existing Arrayexpress submission"
		);
	}
	my $contact = $self->get_investigation->get_contacts->[0];

	# Check to ensure we are not importing an ArrayExpress submission back from GEO
	if ( $contact->get_email )
	{
		if ( $contact->get_email eq "miamexpress\@ebi.ac.uk" )
		{
			$logger->logdie(
"Miamexpress\@ebi.ac.uk used as email address. May be importing pre-existing Arrayexpress submission"
			);
		}
	}

	# Make sure we have a contact email, add geo@ncbi.nlm.nih.gov if not
	if ( !$contact->get_email )
	{
		$contact->set_email("geo\@ncbi.nlm.nih.gov");

	}

	return;
}

sub _dispatch
{

	# find and run appropriate sub
	my ( $self, $tag, $value, $current_hyb ) = @_;

	# Remove double quotes from value text
	$value =~ s/\"/&quot;/g;

	# Split channel info from tag name
	my $channel;
	if ( $tag =~ /^(.*)_ch(\d*)$/g )
	{
		$tag     = $1;
		$channel = $2;
	}

	# Remove numerical suffix from supp file tag
	if ( $tag =~ /^(!Sample_supplementary_file)_(\d*)$/g )
	{
		$tag = $1;
		my $data_num = $2;    # We don't use this for now
	}

	my $sub = $self->get_dispatch->{$tag};

	if ($sub)
	{
		$sub->( $value, $current_hyb, $channel );
	}
	return;
}

sub _add_sra_acc
{
	my ($self) = @_;

	# Get any SRP accs found in series information
	my %srp_accs = %{ $self->get_srp_accs };

	my $gse = $self->get_acc;

	$logger->info("Searching for SRA accessions linked to $gse");
	my $sra_link = get_SRA_study_accs_for_GSE($gse);

	foreach my $link (@$sra_link)
	{
		$srp_accs{$link} = 1;
	}

	foreach my $srp ( keys %srp_accs )
	{
		$logger->info("Adding SRA Study accession $srp");
		$self->_add_expt_comment( "SecondaryAccession", $srp );
	}
	return;
}

sub _add_series_srp
{
	my ( $self, $uri ) = @_;

	if ( $uri =~ /.*\/(SRP\d*)$/g )
	{
		my $srp = $1;
		$self->get_srp_accs->{$srp} = 1;
	}

	elsif ( $uri =~ /.*\/(SRX\d*)$/g )
	{
		my $srx = $1;
		$logger->info("Skipping download of file from SRA - $uri");
		return;
	}

	else
	{
		my $extracted_name;
		$logger->info("Downloading series supplementary file from $uri");

		#splits uri so we can access the path which contains the file name
		my ( $scheme, $auth, $path ) = uri_split($uri);

		#get file name from path
		my ( $vol, $dir, $file_name ) = File::Spec->splitpath($path);

		#downloads file to the data file directory
		my $target_dir = $self->get_data_dir;

		if ( $file_name =~ /^NONE$/i )
		{
			$logger->info("Skipping download of file $file_name");
			return undef;
		}

		if ( $file_name =~ /.*RAW\.tar$/ )
		{
			$logger->info("Skipping download of file $file_name");
			return undef;
		}

		if ( $file_name =~ /.*zip$/i )
		{
			$logger->info("Skipping download of file $file_name");
			return undef;
		}

		if ( $file_name =~ /.*tar\.gz$/i )
		{
			$logger->info("Skipping download of file $file_name");
			return undef;
		}

		if ( $self->get_skip_download )
		{
			$logger->info("Skipping download of $file_name");
		}

		#call method to download files
		else
		{
			$extracted_name = $self->_download_file( $uri, $target_dir );
			unless ($extracted_name)
			{
				$logger->warn("File $uri will not be included in SDRF");
			}

			# add IDF comment
			if ($extracted_name)
			{
				my $value = "AdditionalFile:Data" . $files;
				$self->_add_expt_comment( $value, $extracted_name );
				$files++;
			}

		}

	}
	return;
}

sub _make_id_ref_map_for
{
	my ( $self, $gpl, $fh ) = @_;

	$logger->info("Attempting to create ID to SPOT_ID map for design $gpl");

	my $spot_id_col;
	my %new_id_for;

	while ( defined( my $line = <$fh> ) )
	{

		if ( $line =~ /!platform_table_end/i )
		{

			# Check if the mapping to SPOT_ID was available for all IDs
			# If not we will discard this mapping
			my $total          = keys %new_id_for;
			my $defined_values = grep { $_ =~ /.+/ } values %new_id_for;

			if ( $defined_values < $total )
			{
				$logger->warn(
"Total number of IDs: $total, number with defined SPOT_ID: $defined_values. "
					  . "Will not attempt to map to SPOT_IDs" );
			}
			else
			{

				# Store mapping
				$self->get_id_ref_maps->{$gpl} = \%new_id_for;
			}
			return;
		}

		if ( $line =~ /^ID/ and not defined $spot_id_col )
		{

			$new_id_for{ID_REF} = "Reporter Identifier";

			# Find column containing SPOT_ID
			my @headers = split "\t", $line;
			($spot_id_col) = grep { $headers[$_] =~ /SPOT_ID/ } 0 .. $#headers;

			unless ( defined $spot_id_col )
			{
				$logger->warn(
						 "Could not find SPOT_ID column for $gpl - will not map ID_REFs");
				return;
			}
		}
		elsif ( defined $spot_id_col )
		{

			#split up the line and store id to spot_id mapping
			my @values = split "\t", $line;
			$new_id_for{ $values[0] } = $values[$spot_id_col];
		}
	}
	return;
}

sub write_magetab
{
    my ($self, $prefix_idf) = @_;

    my $idf;
    
    if ($prefix_idf) {
        $logger->warn("Writing IDF with prefix - $prefix_idf");
        $idf = File::Spec->catfile( $self->get_target_dir, $self->get_acc . ".$prefix_idf" .".idf.txt" );
    }
    else {
        $idf = File::Spec->catfile( $self->get_target_dir, $self->get_acc . ".idf.txt" );
    }

	open( my $idf_fh, ">:encoding(utf-8)", $idf )
	  or $logger->error("Could not open IDF $idf for writing - $!");

	# Add all protocols we created to the IDF
	my %prot_hash = %{ $self->get_prot_hash };
	my @types     = keys %prot_hash;
	my @prot_list = map { values %{ $prot_hash{$_} } } @types;
	$self->get_investigation->set_protocols( \@prot_list );

	# Add term source
	if ( my $ts = $self->get_term_source )
	{

		# check if we have any other term sources already stored
		# in most cases this will be ArrayExpress and EFO
		if ( $self->get_investigation->has_termSources )
		{
			my @term_sources;
			push @term_sources, $self->get_investigation->get_termSources;
			push @term_sources, $ts;
			$self->get_investigation->set_termSources( \@term_sources );
		}

		else { $self->get_investigation->set_termSources( [$ts] ); }
	}

	# Write SDRFs
	foreach my $sdrf ( @{ $self->get_investigation->get_sdrfs || [] } )
	{
		my $sdrf_path = $sdrf->get_uri;
		$sdrf_path =~ s/file://g;
		$logger->info("Writing SDRF $sdrf_path");
		open( my $sdrf_fh, ">:encoding(utf-8)", $sdrf_path )
		  or $logger->error("Could not open file $sdrf_path for writing - $!");
		my $sdrf_writer = Bio::MAGETAB::Util::Writer::SDRF->new(
															   {
																 magetab_object => $sdrf,
																 filehandle => $sdrf_fh,
															   }
		);
		$sdrf_writer->write();
		$logger->info("Finished writing SDRF");
		my @path_parts = File::Spec->splitpath($sdrf_path);
		$sdrf->set_uri( pop @path_parts );
	}

	# Write IDF
	$logger->info("Writing IDF");
	my $idf_writer = Bio::MAGETAB::Util::Writer::IDF->new(
											{
											  magetab_object => $self->get_investigation,
											  filehandle     => $idf_fh,
											}
	);
	$idf_writer->write();
	$logger->info("Finished writing IDF");

	return;
}

sub _create_investigation
{
	my ( $self, $gse ) = @_;

	my $investigation = Bio::MAGETAB::Investigation->new( { title => 'No title', } );

	# Add AE accession and secondary accession
	my $comment =
	  Bio::MAGETAB::Comment->new( { name => 'SecondaryAccession', value => $gse } );
	my $ae_acc = $gse;
	$ae_acc =~ s/GSE/E-GEOD-/g;
	my $ae_comment =
	  Bio::MAGETAB::Comment->new( { name => 'ArrayExpressAccession', value => $ae_acc } );
	$investigation->set_comments( [ $comment, $ae_comment ] );

	# Set up our main contact (submitter) - we'll fill in details later
	my $role = Bio::MAGETAB::ControlledTerm->new(
												  {
													category => "Roles",
													value    => "submitter"
												  }
	);
	my $contact = Bio::MAGETAB::Contact->new(
											  {
												lastName => "GEO contact unknown",
												roles    => [$role],
											  }
	);
	$investigation->set_contacts( [$contact] );

	$self->set_investigation($investigation);
	$self->set_acc($gse);

	return;
}

sub _add_series_organization
{
	my ( $self, $org ) = @_;
	$self->get_investigation->get_contacts->[0]->set_organization($org);
	$self->_add_series_address_part($org);
	return;
}

sub _add_series_address_part
{
	my ( $self, $part ) = @_;

	# We assume that the address parts will be added in a sensible order
	my $main_contact = $self->get_investigation->get_contacts->[0];
	my $address      = $main_contact->get_address;
	my $new_address  = $address ? $address . ", " . $part : $part;
	$main_contact->set_address($new_address);
	return;
}

sub _add_expt_comment
{
	my ( $self, $category, $value ) = @_;

	return unless $value;

	my $expt = $self->get_investigation;
	$self->_add_comment( $category, $value, $expt );
}

sub _add_experiment_description
{
	my ( $self, $descr ) = @_;

	my $existing = $self->get_investigation->get_description;

	my $new = $existing
	  ? $existing .= " $descr"
	  : $descr;

	#remove any tabs and replace with space
	$new =~ s/\t+/ /g;

	$self->get_investigation->set_description($new);
}

sub _add_release_date
{
	my ( $self, $str ) = @_;

	my $value = 0;
	$str =~ s/^Public on //;
	my $date = ParseDate($str);

	# Need to add 12 hours or else Bio::MAGETAB modules default to the day before
	my $deltastr = "in 12 hours";
	$date = DateCalc( $date, $deltastr );
	$self->get_investigation->set_publicReleaseDate($date);
	$date =~ s/([\d]{4}[\d]{2}[\d]{2}).*/$1/g;
	$self->_add_expt_comment( "GEOReleaseDate", $date );
	$logger->info("Setting release date to $date");
	return;
}

sub _add_pmid
{
	my ( $self, $pmid ) = @_;

	my ( $title, $authors, $doi );

	# Attempt to fetch pulbication atts from NCBI
	my $uri =
	  "http://www.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=" . $pmid;
	$logger->info("Getting publication details for pmid $pmid");

	my $result = get($uri);

	if ($result)
	{

		my $ref = eval { XMLin($result); };

		if ($@)
		{
			$logger->warn("An error occurred: $@");
		}
		else
		{
			my $xml = XMLin($result);

			my @items = @{ $xml->{DocSum}->{Item} };

			my ($list) = grep { $_->{Name} eq "AuthorList" } @items;
			my @authors = map { $_->{content} } @{ $list->{Item} } if $list;
			$authors = join ", ", @authors;

			my ($title_item) = grep { $_->{Name} eq "Title" } @items;
			$title = $title_item->{content} if $title_item;

			my ($ids) = grep { $_->{Name} eq "ArticleIds" } @items;
			my ($doi_item) = grep { $_->{Name} eq "doi" } @{ $ids->{Item} } if $ids;
			$doi = $doi_item->{content} if $doi_item;
		}

	}
	else
	{
		$logger->error("Could not retrieve publication details from NCBI for $pmid");
	}

	my $pub = Bio::MAGETAB::Publication->new(
											  {
												title      => ( $title   || "" ),
												authorList => ( $authors || "" ),
												DOI        => ( $doi     || "" ),
												pubMedID   => $pmid,
											  }
	);

	my $existing = $self->get_investigation->get_publications;
	$self->get_investigation->set_publications( [ @{ $existing || [] }, $pub ] );

	return;
}

sub _add_contact
{
	my ( $self, $name ) = @_;

	my ( $fname, $initials, $lname ) = split ",", $name;
	my $contact = Bio::MAGETAB::Contact->new(
											  {
												lastName    => $lname,
												firstName   => $fname,
												midInitials => $initials,
											  }
	);

	my $existing = $self->get_investigation->get_contacts;
	$self->get_investigation->set_contacts( [ @{ $existing || [] }, $contact ] );

	return;
}

sub _add_series_contact_name
{
	my ( $self, $name ) = @_;
	my ( $fname, $initials, $lname ) = split ",", $name;

	my $main_contact = $self->get_investigation->get_contacts->[0];
	$main_contact->set_firstName($fname);
	$main_contact->set_lastName($lname);
	$main_contact->set_midInitials($initials);

	return;
}

sub _add_series_email
{
	my ( $self, $email ) = @_;

	# If the email is a string containing multiple emails split
	if ( $email =~ /;/ )
	{
		my @email = split( /;/, $email );
		$self->get_investigation->get_contacts->[0]->set_email( $email[0] );
	}

	elsif ( $email =~ /,/ )
	{
		my @email = split( /,/, $email );
		$self->get_investigation->get_contacts->[0]->set_email( $email[0] );
	}

	elsif ( $email =~ /\s/ )
	{
		my @email = split( /\s/, $email );
		$self->get_investigation->get_contacts->[0]->set_email( $email[0] );
	}

	else
	{
		$self->get_investigation->get_contacts->[0]->set_email($email);
	}

}

sub _create_assay
{
	my ( $self, $hyb_name ) = @_;

	# Tech type not known until we get to the sample platform
	my $type = Bio::MAGETAB::ControlledTerm->new(
												  {
													category => "TechnologyType",
													value    => "unknown",
												  }
	);

	my $hyb = Bio::MAGETAB::Assay->new(
										{
										  technologyType => $type,
										  name           => $hyb_name,
										}
	);

	return $hyb;
}

sub _add_data_file
{
	my ( $self, $args ) = @_;

	# Named args: filename, type, inputs (array of Nodes)
	# prot_app (option ProtocolApplication object)

	# Create the data object
	my $datafile = Bio::MAGETAB::DataFile->new(
										 {
										   uri    => $args->{filename},
										   format => Bio::MAGETAB::ControlledTerm->new(
															  {
																category => "DataFormat",
																value    => "?",
															  }
										   ),
										   dataType => Bio::MAGETAB::ControlledTerm->new(
																{
																  category => "DataType",
																  value => $args->{type},
																}
										   ),
										 }
	);

	foreach my $node ( @{ $args->{inputs} } )
	{
		my $edge = Bio::MAGETAB::Edge->new(
											{
											  inputNode  => $node,
											  outputNode => $datafile,
											}
		);
		if ( my $pa = $args->{prot_app} )
		{
			$edge->set_protocolApplications( [$pa] );
		}
	}

}

sub _add_data_with_prot
{
	my ( $self, $hyb, $filename, $text ) = @_;

	# Create the protocol app.
	# First find any exisiting normalisation protocols for this hyb

	my $prot_value = $self->get_data_processing_hash($hyb);
	if ($prot_value)
	{
		$text = $prot_value . " " . $text;
	}
	my $prot =
	  $self->find_or_create_protocol( "normalization data transformation protocol",
									  $text );
	my $prot_app = Bio::MAGETAB::ProtocolApplication->new( { protocol => $prot, } );

	# Create a normalization and link file to it
	my $norm = Bio::MAGETAB::Normalization->new( { name => "$filename norm", } );

	$self->_add_data_file(
						   {
							 filename => $filename,
							 type     => "derived",
							 inputs   => [$norm],
						   }
	);

	# See if we have any raw files for this hyb
	my @scan_edges = $self->_get_scan_edges($hyb);
	my @raw_files  = map { $_->get_outputNode } @scan_edges;

	# Link the normalization to the raw files or hyb
	unless (@raw_files) { push @raw_files, $hyb; }

	foreach my $node (@raw_files)
	{
		my $edge = Bio::MAGETAB::Edge->new(
											{
											  inputNode            => $node,
											  outputNode           => $norm,
											  protocolApplications => [$prot_app],
											}
		);
	}

	return;
}

sub _add_raw_file
{
	my ( $self, $file, $hyb ) = @_;
	$self->_add_data_file(
						   {
							 filename => $file,
							 type     => "raw",
							 inputs   => [$hyb],
						   }
	);

	return;
}

sub _get_scan_edges
{
	my ( $self, $hyb ) = @_;

	# Scan edges defined as any edge where the output is a raw data file
	# or a DataAcquisition node

	my @scan_edges = grep {
		      $_->get_inputNode == $hyb
		  and $_->get_outputNode->isa("Bio::MAGETAB::Data")
		  and $_->get_outputNode->get_dataType->get_value eq "raw"
	} $self->get_magetab->get_edges;

	push @scan_edges, grep {
		      $_->get_inputNode == $hyb
		  and $_->get_outputNode->isa("Bio::MAGETAB::DataAcquisition")
	} $self->get_magetab->get_edges;

	return @scan_edges;
}

sub _get_normalization_edges
{
	my ( $self, $input ) = @_;

	my @edges = grep {
		      $_->get_inputNode == $input
		  and $_->get_outputNode->isa("Bio::MAGETAB::Normalization")
	} $self->get_magetab->get_edges;

	return @edges;
}

sub find_or_create_protocol
{
	my ( $self, $type, $text ) = @_;

	my $prot_hash = $self->get_prot_hash;

	my $prot;
	if ( exists( $prot_hash->{$type}{$text} ) )
	{
		return $prot_hash->{$type}{$text};
	}
	else
	{

		my $term_source = Bio::MAGETAB::TermSource->new(
											{
											  name => "ArrayExpress",
											  uri  => "http://www.ebi.ac.uk/arrayexpress/"
											}
		);

		$prot = Bio::MAGETAB::Protocol->new(
					   {
						 name => "P-" . $self->get_acc . "-" . $self->_get_next_prot_num,
						 text => $text,
						 protocolType => Bio::MAGETAB::ControlledTerm->new(
															{
															  category => "ProtocolType",
															  value    => $type,
															}
						 ),
						 termSource => $term_source
					   }
		);
		$prot_hash->{$type}{$text} = $prot;
		$logger->info( "Created new protocol " . $prot->get_name );

		$self->get_investigation->set_termSources( [$term_source] );

	}

	return $prot;
}

sub _get_next_prot_num
{
	my ($self) = @_;
	my $num = $self->get_prot_num;
	$num++;
	$self->set_prot_num($num);
	return $num;
}

sub find_hyb
{

	my ( $self, $name ) = @_;

	my ($hyb) = grep { $_->get_name eq $name } $self->get_magetab->get_assays;

	return $hyb;
}

sub _download_file
{
	my ( $self, $uri, $target_dir ) = @_;

	unless ($target_dir)
	{
		$logger->warn(
"No target directory specified for download. Downloading to current working directory" );
		$target_dir = ".";
	}

	my $ff        = File::Fetch->new( uri => $uri );
	my $file_name = $ff->file;

	$logger->info("Downloading file $file_name");

	my $file_path = File::Spec->catfile( $target_dir, $file_name );

	my $where = $ff->fetch( to => $target_dir )
	  or
	  $logger->logdie( $ff->error . "Could not download file from $uri to $file_path" );

	my $extracted_name;

	# Not all supplementary files are compressed, e.g. bam files
	unless ( $file_name =~ /.*\.gz/i )
	{

		# We assume all compressed files are .gz
		# If not .gz we skip the extraction
		$logger->info("$file_name is not an archive. Skipping extraction.");
		return $file_name;
	}

	# Unpack the file
	my $archive = Archive::Extract->new( archive => $file_path );
	if ($archive)
	{
		$logger->info("Extracting file $file_name");
		if ( $archive->extract( to => $target_dir ) )
		{

			# delete archive if extraction was successful
			unlink $file_path;
		}
		else
		{
			$logger->error( "Could not unpack archive $file_path. " . $archive->error );
		}
		$extracted_name = $archive->files->[0];
	}
	else
	{
		$logger->error("Could not process archive $file_path");
		return undef;
	}
	return $extracted_name;
}

sub _download_supp_data
{
	my ( $self, $uri, $hyb ) = @_;

	my ( $scheme, $auth, $path ) = uri_split($uri);

	# Do not download files from SRA
	# Add as comment instead
	if (    $uri =~ m{ftp://ftp.ncbi.nlm.nih.gov/sra/.*/([^/]*)}g
		 or $uri =~ m{ftp://ftp-trace.ncbi.nih.gov/sra/.*/([^/]*)}g
		 or $uri =~ m{ftp://ftp-trace.ncbi.nlm.nih.gov/sra/.*/([^/]*)}g )
	{
		my $sra_acc = $1;
		$logger->info("Skipping download of file from SRA - $uri");
		$self->_add_comment( "ENA_EXPERIMENT", $sra_acc, $hyb );
		return;
	}

	my ( $vol, $dir, $file_name ) = File::Spec->splitpath($path);

	# Do not download CHP files - they are included as sample table
	if ( $file_name =~ /.*\.CHP(\..*)?/i )
	{
		$logger->info("Skipping download of CHP file $file_name");
		return undef;
	}

	# Do not attempt to download files named "NONE"
	if ( $file_name =~ /^NONE$/i )
	{
		$logger->info("Skipping download of file $file_name");
		return undef;
	}

	my $extracted_name;
	if ( $self->get_skip_download )
	{
		$logger->info("Skipping download of $file_name");
		$file_name =~ s/\.gz$//ig;
		$extracted_name = $file_name;
	}
	else
	{
		$extracted_name = $self->_download_file( $uri, $self->get_data_dir );
		unless ($extracted_name)
		{
			$logger->warn("File $uri will not be included in SDRF");
		}
	}

	# Add the file to the sdrf
	$self->_add_raw_file( $extracted_name, $hyb );

	return $extracted_name;
}

sub _create_channels
{
	my ( $self, $count, $hyb ) = @_;

	unless ( $count =~ /^\d*$/ )
	{
		$logger->warn("Channel count '$count' is not numeric - assuming only 1 channel");
		$count = 1;
	}

	foreach my $num ( 1 .. $count )
	{

		# Create LE and edge
		my $le = Bio::MAGETAB::LabeledExtract->new(
											{
											  name  => $hyb->get_name . " LE $num",
											  label => Bio::MAGETAB::ControlledTerm->new(
																   {
																	 category => "Label",
																	 value    => $num,
																   }
											  ),
											}
		);
		Bio::MAGETAB::Edge->new(
								 {
								   inputNode  => $le,
								   outputNode => $hyb,
								 }
		);

		# Create extract and edge
		my $extract =
		  Bio::MAGETAB::Extract->new( { name => $hyb->get_name . " extract $num", } );
		Bio::MAGETAB::Edge->new(
								 {
								   inputNode  => $extract,
								   outputNode => $le,
								 }
		);

		# Create source and edge
		my $source = Bio::MAGETAB::Source->new( { name => $hyb->get_name . " $num", } );
		Bio::MAGETAB::Edge->new(
								 {
								   inputNode  => $source,
								   outputNode => $extract,
								 }
		);
	}

	return;
}

sub _add_species
{
	my ( $self, $species, $hyb, $ch ) = @_;
	$self->_add_source_char( "organism", $species, $hyb, $ch );
}

sub _add_provider
{
	my ( $self, $provider, $hyb, $ch ) = @_;

	# Last name is mandatory thus add value as lastName
	my $provider_name = Bio::MAGETAB::Contact->new( { lastName => $provider, } );

	# Providers have to be an provided as an array ref
	my @providers = ($provider_name);
	my $prov_ref  = \@providers;

	$logger->info("Adding provider: $provider");

	my $name   = $hyb->get_name . " $ch";
	my $source = $self->find_material($name);
	$source->set_providers($prov_ref);
}

sub _add_source_char
{
	my ( $self, $category, $value, $hyb, $ch ) = @_;
	my $name   = $hyb->get_name . " $ch";
	my $source = $self->find_material($name);

	$category =~ s/\(//g;
	$category =~ s/\)//g;
	$category =~ s/\[//g;
	$category =~ s/\]//g;
	$category =~ s/\}//g;
	$category =~ s/\{//g;

	# ##############################################################################
	# ewilliam edit 2012-03-07:
	#
	# GEO and AE sometimes use a different name for the same thing eg. what we call
	# organism part GEO calls tissue. We want to change the GEO-specific names to AE
	# ones.
	#
	# This code creates a hash of what GEO categories should be changed to.
	# Then it checks each sample category and changes it to the AE one if there
	# is a match.
	################################################################################

	# hash of GEO categories and AE categories to change them to
	my %GEO_AE_terms = (
						 'tissue'             => 'organism part',
						 'gender'             => 'sex',
						 'agent'              => 'compound',
						 'Tissue'             => 'organism part',
						 'Gender'             => 'sex',
						 'Agent'              => 'compound',
						 'Strain'             => 'strain',
						 'ChIP'               => 'immunoprecipitate',
						 'timepoint'          => 'time',
						 'time point'         => 'time',
						 'OrganismPart'       => 'organism part',
						 'genotype variation' => 'genotype',
						 'genotype/variation' => 'genotype'
	);

	# change category if is in the list of ones to change
	if ( $GEO_AE_terms{$category} )
	{
		$category = $GEO_AE_terms{$category};
	}

	#################################################################################

	my $char = Bio::MAGETAB::ControlledTerm->new(
												  {
													category => $category,
													value    => $value,
												  }
	);

	$self->_map_term($char);

	my $existing = $source->get_characteristics;
	$source->set_characteristics( [ @{ $existing || [] }, $char ] );
}

sub _map_term
{
	my ( $self, $term_object ) = @_;

	my $value    = $term_object->get_value;
	my $category = $term_object->get_category;

	# F was mapping to degree fahrenheit and M was mapping to molar
	if ( $category =~ /sex$/i and ( lc($value) eq 'm' or lc($value) eq 'f' ) )
	{
		$logger->info(
"Value:$value with catergory:$category found- setting value equal male or female" );
		if ( $value =~ /m/i )
		{
			$value = "male";
		}
		if ( $value =~ /f/i )
		{
			$value = "female";
		}
	}

	# One letter value are hard to map so ignore
	if ( length($value) == 1 )
	{

		$logger->info("Term $value is only one character long- will not attempt to map");
		return;

	}

	else
	{
		if ( my $mapper = $self->get_term_mapper )
		{

			my $result = $mapper->find_match($value);
			my $match  = $result->{'value'};
			my $acc    = $result->{'term'}->{'accession'};
			my $score  = $result->{'similarity'};
			my $type   = $result->{'type'};

			$logger->info("Term $value mapped to $match (acc: $acc)");
			$logger->info("The similarity score is $score");

			if ( $type eq 'EBI::FGPT::FuzzyRecogniser::OntologyTerm::Synonym' )
			{
				$logger->info( "The value supplied is a synonym of: "
							   . $result->{'term'}->{'label'} );
			}

			if ( $score != 100 )
			{
				$logger->info(  "The similarity score indicates that this may not be an adequate match and may just be noise-> this value will not be added"
				);
			}

			if ( $score >= 80 )
			{
				$term_object->set_value($match);
				$term_object->set_accession($acc);
				$term_object->set_termSource( $self->get_term_source );
			}

		}
	}

	return $term_object;
}

sub _correct_source_comment
{

	# This method is used to prevent Comment[XXX] columns of the same type

	my ( $self, $category, $value, $hyb, $ch ) = @_;

	my $name = $hyb->get_name;
	my @sources;

	# Add comment to specified channel's source or both channels if none specified
	if ($ch)
	{
		$name .= " $ch";
		my $source = $self->find_material($name);
		push @sources, $source if $source;
	}
	else
	{
		foreach my $ch_num ( 1 .. 2 )
		{
			my $source_name = $name . " $ch_num";
			my $source      = $self->find_material($source_name);
			push @sources, $source if $source;
		}
	}

	# Create a hash of where the key is a concatenation of the source name and category
	# and the value is the actual comment value
	my $comment_value;
	foreach my $source (@sources)
	{
		my $category = $category . $source->get_name;
		if ( $self->exists_in_hash_of_source_comment($category) )
		{
			$comment_value = $self->get_hash_of_source_comment($category);
			$comment_value = $comment_value . " " . $value;
			$self->set_hash_of_source_comment( $category, $comment_value );
		}
		else { $self->set_hash_of_source_comment( $category, $value ); }
	}
	return;
}

sub _add_source_comment
{
	my ( $self, $category, $value, $hyb, $ch ) = @_;
	my $name = $hyb->get_name;
	my @sources;

	# Add comment to specified channel's source
	# Or both channels if none specified
	if ($ch)
	{
		$name .= " $ch";
		my $source = $self->find_material($name);
		push @sources, $source if $source;
	}
	else
	{
		foreach my $ch_num ( 1 .. 2 )
		{
			my $source_name = $name . " $ch_num";
			my $source      = $self->find_material($source_name);
			push @sources, $source if $source;
		}
	}

	foreach my $source (@sources)
	{
		my $category_key = $category . $source->get_name;
		if ( $self->exists_in_hash_of_source_comment($category_key) )
		{
			$value = $self->get_hash_of_source_comment($category_key);
			$self->_add_comment( $category, $value, $source );

		}

		else { $self->_add_comment( $category, $value, $source ); }

	}

	unless (@sources)
	{
		$logger->error( "No sources found for hyb " . $hyb->get_name );
	}
}

sub _add_comment
{
	my ( $self, $category, $value, $thing ) = @_;

	# If no value is provided we'll enter an empty string
	# If no category is provided the Comment creation will fail
	$value ||= "";

	# Have to do a lot of fiddling to get date right
	# Intially the $date will be a string like 20120801
	# Then we create a magetab format date 2012-08-01T00:00:00
	# and remove the time value
	if ( $category =~ /Date$/g )
	{
		my $date = ParseDate($value);
		$date =~ s/([\d]{4}[\d]{2}[\d]{2}).*/$1/g;
		my $format = DateTime::Format::Strptime->new( pattern => '%Y%m%d' );
		my $dt = $format->parse_datetime($date);
		$dt =~ s/([\d]{4}-[\d]{2}-[\d]{2})T.*/$1/g;
		$value = $dt;
	}

	my $comment = Bio::MAGETAB::Comment->new(
											  {
												name  => $category,
												value => $value,
											  }
	);

	# Check for existing identical comment before adding
	my $existing = $thing->get_comments;

	unless ( grep { $_->get_name eq $category and $_->get_value eq $value }
			 @{ $existing || [] } )
	{
		$thing->set_comments( [ @{ $existing || [] }, $comment ] );
	}

}

sub find_material
{
	my ( $self, $name ) = @_;
	my ($material) =
	  grep { $_->get_name eq $name } $self->get_magetab->get_materials;

	return $material;

}

sub _add_sample_chars_comment
{
	my ( $self, $text, $hyb, $ch ) = @_;
	my $category = $hyb->get_name . " $ch";

# Check our hash to see if we have something that could be added as a Comment[Sample_characteristics]
	if ( $self->exists_in_hash_of_sample_char_comment($category) )
	{
		my $value = $self->get_hash_of_sample_char_comment($category);
		$self->_add_source_comment( "Sample_characteristics", $value, $hyb, $ch );
	}

	else { return; }
}

sub _add_chars
{
	my ( $self, $text, $hyb, $ch ) = @_;

  # Clean up text string as it may have over-hanging whitespace or finish with punctuation
	$text =~ s/\s*$//;
	$text =~ s/;$//;
	$text =~ s/,$//;

	$logger->info( "Adding $text as a characteristic for  " . $hyb->get_name );

	# GEO sample characteristics are normally in the form of Tag:Value
	# There are norammly seperate !Sample_characteristics for each tag i.e. one per line
	# in the soft file e.g.
	#
	#	!Sample_characteristics_ch1 = genotype: wildtype
	#	!Sample_characteristics_ch1 = ecotype: Col-0

	#  Limit the number of sections the string will be split into to 2
	my @chars       = split( /:/, $text, 2 );
	my $char_length = @chars;

	# If we have a definite tag and value do some tidying and add to MAGE-TAB
	if ( $char_length == 2 )
	{
		my $tag   = $chars[0];
		my $value = $chars[1];

		# Clean up strings
		$tag   =~ s/^\s+//;
		$value =~ s/^\s+//;
		$tag   =~ s/\s+$//;
		$value =~ s/\s+$//;

		if ( $tag eq 'provider' )
		{

			$self->_add_provider( $value, $hyb, $ch );
			return;
		}

		my $value_length = length($value);

		# Can only add values to DB if there are less then 255 chars
		if ( $value_length <= 255 )
		{
			$self->_add_source_char( $tag, $value, $hyb, $ch );
		}

		else
		{
			my $category = $hyb->get_name . " $ch";
			if ( $self->exists_in_hash_of_sample_char_comment($category) )
			{
				my $comment_value = $self->get_hash_of_sample_char_comment($category);
				$comment_value = $comment_value . " " . $text;
				$self->set_hash_of_sample_char_comment( $category, $comment_value );
			}
			else { $self->set_hash_of_sample_char_comment( $category, $text ); }
			$logger->info( "Adding $text as a Comment [Sample_characteristics] for  "
						   . $hyb->get_name );

		}

	}

	# If all else fails just add as a comment
	else
	{
		my $category = $hyb->get_name . " $ch";
		if ( $self->exists_in_hash_of_sample_char_comment($category) )
		{
			my $comment_value = $self->get_hash_of_sample_char_comment($category);
			$comment_value = $comment_value . " " . $text;
			$self->set_hash_of_sample_char_comment( $category, $comment_value );
		}
		else { $self->set_hash_of_sample_char_comment( $category, $text ); }
		$logger->info(
			"Adding $text as a Comment [Sample_characteristics] for  " . $hyb->get_name );

	}

}

sub _add_label
{
	my ( $self, $dye_name, $hyb, $ch ) = @_;
	my $le_name = $hyb->get_name . " LE $ch";
	my $le      = $self->find_material($le_name);

	if ( $dye_name =~ /not applicable/i )
	{

		# Delete the LE object and link the extract to the hyb
		my $extract = $self->find_material( $hyb->get_name . " extract $ch" );
		my ($extract_to_le) =
		  grep { $_->get_outputNode == $le } $self->get_magetab->get_edges;
		my ($le_to_hyb) =
		  grep { $_->get_inputNode == $le } $self->get_magetab->get_edges;
		$self->get_magetab->delete_objects( $le, $le_to_hyb );
		$extract_to_le->set_outputNode($hyb);
	}
	else
	{

		# Fix casing of Cy dye names
		$dye_name =~ s/^cy/Cy/g;

		my $dye = Bio::MAGETAB::ControlledTerm->new(
													 {
													   category => "Label",
													   value    => $dye_name,
													 }
		);

		$le->set_label($dye);
	}
}

sub _remove_labeled_extract
{

	# This method is called when library selection is encountered
	# It removes labelled extract from HTS submissions as only HTS subs
	# should have library values in the SOFT file

	my ( $self, $sample_relation, $hyb, $ch ) = @_;

	my $le_name = $hyb->get_name . " LE 1";
	my $le      = $self->find_material($le_name);

	# Delete the LE object and link the extract to the hyb
	my $extract = $self->find_material( $hyb->get_name . " extract 1" );
	my ($extract_to_le) =
	  grep { $_->get_outputNode == $le } $self->get_magetab->get_edges;
	my ($le_to_hyb) =
	  grep { $_->get_inputNode == $le } $self->get_magetab->get_edges;

	$self->get_magetab->delete_objects( $le, $le_to_hyb );
	$extract_to_le->set_outputNode($hyb);
}

sub _add_extract_type
{
	my ( $self, $type_name, $hyb, $ch ) = @_;

	my $extract_name = $hyb->get_name . " extract $ch";
	my $extract      = $self->find_material($extract_name);

	my $type = Bio::MAGETAB::ControlledTerm->new(
												  {
													category => "MaterialType",
													value    => $type_name,
												  }
	);

	$extract->set_materialType($type);
}


sub _add_biosample_id
{
	my ( $self, $category, $value, $hyb) = @_;
 	my $name = $hyb->get_name;
 	my @extracts;

 	# BioSamples ids has only one channel source
 	my $ch_num = 1;

 	my $extract_name = $hyb->get_name . " extract $ch_num";
 	my $extract      = $self->find_material($extract_name);
 	push @extracts, $extract if $extract;
 
	foreach my $extract (@extracts)
 	{
  		if ($value =~ /^BioSample\:/) {

      		my @fields = split(/\//, $value);
      		my $biosample_id =  $fields[-1];

      		$self->_add_comment( $category, $biosample_id, $extract );
   		}
   		else {
       		next;
   		}
 	}

 	unless (@extracts)
 	{
  		$logger->error( "No extracts found for hyb " . $hyb->get_name );
 	}
}

sub _add_extract_comment
{
	my ( $self, $category, $value, $hyb, $ch ) = @_;
	my $name = $hyb->get_name;
	my @extracts;

	# Add comment to specified channel's source
	# Or both channels if none specified
	if ($ch)
	{

		my $extract_name = $hyb->get_name . " extract $ch";
		my $extract      = $self->find_material($extract_name);
		push @extracts, $extract if $extract;
	}
	else
	{
		foreach my $ch_num ( 1 .. 2 )
		{
			my $extract_name = $hyb->get_name . " extract $ch_num";
			my $extract      = $self->find_material($extract_name);
			push @extracts, $extract if $extract;
		}
	}

	foreach my $extract (@extracts)
	{
		$self->_add_comment( $category, $value, $extract );

	}

	unless (@extracts)
	{
		$logger->error( "No extracts found for hyb " . $hyb->get_name );
	}
}

sub _add_array_ref
{
	my ( $self, $gpl, $hyb ) = @_;

	# Only call this method after all nodes have been created
	my $name = $hyb->get_name;

	# Find all material nodes linked to this assay so we can
	# add them to the correct sdrf
	my @materials =
	  grep { $_->get_name =~ /^$name(\s.*|$)/ig } $self->get_magetab->get_materials;

	if ( my $title = $self->get_is_virtual->{$gpl} )
	{

		# This is an assay
		$hyb->get_technologyType->set_value("sequencing assay");

		# Add platform title as comment
		$self->_add_comment( "Platform_title", $title, $hyb );

		push @{ $self->get_assay_nodes }, $hyb, @materials;
	}
	else
	{

		# This is a hyb
		$hyb->get_technologyType->set_value("array assay");

		my $acc = $self->map_to_array_acc($gpl);

		my $term_source = Bio::MAGETAB::TermSource->new(
											{
											  name => "ArrayExpress",
											  uri  => "http://www.ebi.ac.uk/arrayexpress/"
											}
		);

		my $ad = Bio::MAGETAB::ArrayDesign->new(
												 {
												   name       => $acc,
												   termSource => $term_source
												 }
		);

		$hyb->set_arrayDesign($ad);

		push @{ $self->get_hyb_nodes }, $hyb, @materials;
	}
	return;
}

sub _make_files_derived
{

	my ( $self, $node_list ) = @_;

	my @assays = grep { $_->isa("Bio::MAGETAB::Assay") } @$node_list;

	# FIX: This part relies on GEO always using the sample name in the related
	# file names which seems to work for now..
	foreach my $assay (@assays)
	{
		my $name  = $assay->get_name;
		my @files =
		  grep { $_->get_uri =~ /$name(_.*|$)/ig } $self->get_magetab->get_data;
		foreach my $file (@files)
		{
			$file->get_dataType->set_value("derived");
		}
	}
}

# The following correct methods are used to fix problems
# with protocols. It ensures for each hyb or sample that we
# concatenate all the text for a particular protocol type into one string
# For label,treatment,growth and extraction method an entry is created in a hash where the
# key is the sample and the value is the protocol text for that sample.
# For hyb, scan and data_processing the same hash is created but the key is the hyb

sub _correct_label_protocol
{

	my ( $self, $text, $hyb, $ch ) = @_;

	my $prot_value;
	my $sample = $self->find_material( $hyb->get_name . " $ch" );

	if ( $self->exists_in_label_hash($sample) )
	{
		$prot_value = $self->get_label_hash($sample);
		$prot_value = $prot_value . " " . $text;
		$self->set_label_hash( $sample, $prot_value );
	}

	else { $self->set_label_hash( $sample, $text ); }

	return;
}

sub _correct_hyb_protocol
{

	my ( $self, $text, $hyb ) = @_;

	my $prot_value;

	if ( $self->exists_in_hyb_hash($hyb) )
	{
		$prot_value = $self->get_hyb_hash($hyb);
		$prot_value = $prot_value . " " . $text;
		$self->set_hyb_hash( $hyb, $prot_value );
	}
	else { $self->set_hyb_hash( $hyb, $text ); }

	return;

}

sub _correct_treatment_protocol
{

	my ( $self, $text, $hyb, $ch ) = @_;

	my $prot_value;
	my $sample = $self->find_material( $hyb->get_name . " $ch" );

	if ( $self->exists_in_treatment_hash($sample) )
	{
		$prot_value = $self->get_treatment_hash($sample);
		$prot_value = $prot_value . " " . $text;
		$self->set_treatment_hash( $sample, $prot_value );
	}
	else { $self->set_treatment_hash( $sample, $text ); }

	return;

}

sub _correct_growth_protocol
{

	my ( $self, $text, $hyb, $ch ) = @_;

	my $prot_value;
	my $sample = $self->find_material( $hyb->get_name . " $ch" );

	if ( $self->exists_in_growth_hash($sample) )
	{
		$prot_value = $self->get_growth_hash($sample);
		$prot_value = $prot_value . " " . $text;
		$self->set_growth_hash( $sample, $prot_value );
	}
	else { $self->set_growth_hash( $sample, $text ); }

	return;

}

sub _correct_extraction_protocol
{

	my ( $self, $text, $hyb, $ch ) = @_;

	my $prot_value;
	my $sample = $self->find_material( $hyb->get_name . " $ch" );

	if ( $self->exists_in_extraction_hash($sample) )
	{
		$prot_value = $self->get_extraction_hash($sample);
		$prot_value = $prot_value . " " . $text;
		$self->set_extraction_hash( $sample, $prot_value );
	}
	else { $self->set_extraction_hash( $sample, $text ); }

	return;

}

sub _correct_scan_protocol
{

	my ( $self, $text, $hyb ) = @_;

	my $prot_value;

	if ( $self->exists_in_scan_hash($hyb) )
	{
		$prot_value = $self->get_scan_hash($hyb);
		$prot_value = $prot_value . " " . $text;
		$self->set_scan_hash( $hyb, $prot_value );
	}
	else { $self->set_scan_hash( $hyb, $text ); }

	return;

}

sub _correct_data_processing_protocol
{

	my ( $self, $text, $hyb ) = @_;

	my $prot_value;
	$text =~ s/\r//;
	if ( $self->exists_in_data_processing_hash($hyb) )
	{
		$prot_value = $self->get_data_processing_hash($hyb);
		$prot_value = $prot_value . " " . $text;
		$self->set_data_processing_hash( $hyb, $prot_value );
	}
	else { $self->set_data_processing_hash( $hyb, $text ); }

	return;

}

sub _add_protocol
{
	my ( $self, $args ) = @_;

	# Named args: type, text, input, output, edges
	if ( $args->{text} =~ /^\s*not applicable\s*$/i )
	{
		$logger->warn(
			"Ignoring " . $args->{type} . " protocol with text '" . $args->{text} . "'" );
		return;
	}

	# Create the protocol application
	my $prot = $self->find_or_create_protocol( $args->{type}, $args->{text} );
	my $prot_app = Bio::MAGETAB::ProtocolApplication->new( { protocol => $prot, } );

	# Find the relevant edges
	my @edges;
	if ( my $input = $args->{input} )
	{
		@edges =
		  grep { $_->get_inputNode == $input } $self->get_magetab->get_edges;
	}
	elsif ( my $output = $args->{output} )
	{
		@edges =
		  grep { $_->get_outputNode == $output } $self->get_magetab->get_edges;
	}
	elsif ( $args->{edges} )
	{
		@edges = @{ $args->{edges} };
	}
	else
	{
		$logger->error("No input or output nodes or edges specified for _add_protocol");
	}

	# Add the prot app to the edges
	foreach my $edge (@edges)
	{
		my $existing = $edge->get_protocolApplications;
		$edge->set_protocolApplications( [ @{ $existing || [] }, $prot_app ] );
	}
	return;
}

sub _add_sample_protocol
{
	my ( $self, $type, $text, $hyb, $ch ) = @_;

	my $sample = $self->find_material( $hyb->get_name . " $ch" );
	my $prot_value;

	# Check type so we know what hash to pull protocol text from

	if ( $type eq "sample treatment protocol" )
	{
		$prot_value = $self->get_treatment_hash($sample);
	}

	if ( $type eq "nucleic acid extraction protocol" )
	{
		$prot_value = $self->get_extraction_hash($sample);
	}

	if ( $type eq "growth protocol" )
	{
		$prot_value = $self->get_growth_hash($sample);
	}

	# Clean up string by removing whitespace
	# from beginning of string, end and any scattered
	# in betweeen

	$prot_value =~ s/^\s+//;
	$prot_value =~ s/\s+$//;
	$prot_value =~ s/\t+/ /g;
	$prot_value =~ s/\s+/ /g;

	# This conditional stops repeated protocol columns that contain
	# the same value. The look checks to see if a protocol of the
	# current type has already been added for that sample
	# if it has it won't do it again

	# If its a HTS submission we need to have a
	# nucleic acid library construction protocol
	my $gse            = $self->get_acc;
	my $ena_study_accs = $self->get_accs_for_gse->{$gse};
	my @comments       = $self->get_investigation->get_comments;
	my $seq_exp_type;

	foreach my $comment (@comments)
	{
		my $comment_name  = $comment->get_name;
		my $comment_value = $comment->get_value;

		if ( $comment_value =~ m/seq/i )
		{
			$seq_exp_type = 1;
		}

	}

	if (     ( $ena_study_accs or $seq_exp_type )
		 and ( $type eq "nucleic acid extraction protocol" ) )
	{

		if ( $seq_exp_type == 1 )
		{
			$type = "nucleic acid library construction protocol";
			$logger->info(
					 "nucleic acid library construction protocol added as protocol type");
		}

	}

	if ( !$have_seen_protocol{$sample}{$type} )
	{

		$self->_add_protocol(
							  {
								type  => $type,
								text  => $prot_value,
								input => $sample,
							  }
		);

		$have_seen_protocol{$sample}{$type} = 1;
	}

	else { return; }

}

sub _add_label_protocol
{
	my ( $self, $text, $hyb, $ch ) = @_;

	my $label_name = $hyb->get_name . " LE $ch";
	my $label      = $self->find_material($label_name) or return;

	my $sample = $self->find_material( $hyb->get_name . " $ch" );

	my $prot_value = $self->get_label_hash($sample);

	# clean up string by removing whitespace
	# from beginning of string, end and any scattered
	# in betweeen

	$prot_value =~ s/^\s+//;
	$prot_value =~ s/\s+$//;
	$prot_value =~ s/\t+/ /g;
	$prot_value =~ s/\s+/ /g;

	# this conditional stops repeated protocol columns that contain
	# the same value. The look checks to see if a protocol of the
	# current type has already been added for that sample
	# if it has it won't do it again

	if ( !$have_seen_protocol{$sample}{"labelling protocol"} )
	{

		$self->_add_protocol(
							  {
								type   => "labelling protocol",
								text   => $prot_value,
								output => $label,
							  }
		);
		$have_seen_protocol{$sample}{"labelling protocol"} = 1;
	}

	else { return; }
}

sub _add_hyb_protocol
{
	my ( $self, $text, $hyb ) = @_;

	my $prot_value = $self->get_hyb_hash($hyb);

	# Clean up string by removing whitespace
	# from beginning of string, end and any scattered
	# in betweeen

	$prot_value =~ s/^\s+//;
	$prot_value =~ s/\s+$//;
	$prot_value =~ s/\t+/ /g;
	$prot_value =~ s/\s+/ /g;

	# This conditional stops repeated protocol columns that contain
	# the same value. The look checks to see if a protocol of the
	# current type has already been added for that sample
	# if it has it won't do it again

	if ( !$have_seen_protocol{$hyb}{"hybridization protocol"} )
	{
		$self->_add_protocol(
							  {
								type   => "hybridization protocol",
								text   => $prot_value,
								output => $hyb,
							  }
		);

		$have_seen_protocol{$hyb}{"hybridization protocol"} = 1;
	}

	else { return; }
}

sub _add_scan_protocol
{
	my ( $self, $type, $text, $hyb ) = @_;

	my @edges = $self->_get_scan_edges($hyb);

	unless (@edges)
	{

		# No scan edges, e.g. no raw data
		# so we get edges to norm data instead
		@edges = $self->_get_normalization_edges($hyb);
	}

	my $prot_value = $self->get_scan_hash($hyb);

	# clean up string by removing whitespace
	# from beginning of string, end and any scattered
	# in betweeen

	$prot_value =~ s/^\s+//;
	$prot_value =~ s/\s+$//;
	$prot_value =~ s/\t+/ /g;
	$prot_value =~ s/\s+/ /g;
	$prot_value =~ s/&quot;//g;

	# This conditional stops repeated protocol columns that contain
	# the same value. The look checks to see if a protocol of the
	# current type has already been added for that sample
	# if it has it won't do it again

	if ( !$have_seen_protocol{$hyb}{$type} )
	{
		$self->_add_protocol(
							  {
								type  => $type,
								text  => $prot_value,
								edges => \@edges,
							  }
		);

		$have_seen_protocol{$hyb}{$type} = 1;
	}

	unless (@edges)
	{

		# No raw or norm data found - record warning
		$logger->warn("No raw or normalized data found to link $type protocol to");
	}

	else { return; }

}

sub _add_normalization_protocol
{
	my ( $self, $type, $text, $hyb ) = @_;

	# We only need to worry about HTS submissions here as
	# for array submission the processed files are in the
	# soft file and we add them earlier using _add_data_with_prot
	# subroutine

	my @scan_edges = $self->_get_scan_edges($hyb);

	# If its a HTS submission we need to assign
	# protocol to scan. Use methods below to
	# determine type of exp
	my $gse            = $self->get_acc;
	my $ena_study_accs = $self->get_accs_for_gse->{$gse};
	my @comments       = $self->get_investigation->get_comments;
	my $seq_exp_type   = 0;

	foreach my $comment (@comments)
	{
		my $comment_name  = $comment->get_name;
		my $comment_value = $comment->get_value;

		if ( $comment_value =~ m/seq/i )
		{
			$seq_exp_type = 1;
		}

	}

	if ( $ena_study_accs and $seq_exp_type == 1 )
	{

		my $prot_value = $self->get_data_processing_hash($hyb);

		# clean up string by removing whitespace
		# from beginning of string, end and any scattered
		# in betweeen

		$prot_value =~ s/^\s+//;
		$prot_value =~ s/\s+$//;
		$prot_value =~ s/\t+/ /g;
		$prot_value =~ s/\s+/ /g;
		$prot_value =~ s/&quot;//g;

		# This conditional stops repeated protocol columns that contain
		# the same value. The look checks to see if a protocol of the
		# current type has already been added for that sample
		# if it has it won't do it again

		if ( !$have_seen_protocol{$hyb}{$type} )
		{
			$self->_add_protocol(
								  {
									type  => $type,
									text  => $prot_value,
									edges => \@scan_edges,
								  }
			);

			$have_seen_protocol{$hyb}{$type} = 1;
		}
	}

	unless (@scan_edges)
	{

		# No raw or norm data found - record warning
		$logger->warn("No raw or normalized data found to link $type protocol to");
	}
	else { return; }
}

 # ewilliam:  removed upper casing of factor name on 2014-10-22
 # name       =>  uc($type),  
 # becomes 
 # name       =>  ($type),


sub _add_factor
{
	my ( $self, $type ) = @_;

	my ($factor) = grep { $_->get_name eq uc($type) } @{ $self->get_factors };
	unless ($factor)
	{
		$factor = Bio::MAGETAB::Factor->new(
									   {     
										 name       =>  ($type),
										 factorType => Bio::MAGETAB::ControlledTerm->new(
											  {
												category => "ExperimentalFactorCategory",
												value    => $type,
											  }
										 ),
									   }
		);
		push @{ $self->get_factors }, $factor;
	}
	return $factor;
}

sub _make_fvs_from_gds
{
	my ( $self, $gds ) = @_;

  GDS: foreach my $gds_num (@$gds)
	{

		# add gds as secondary acc
		$self->_add_expt_comment( "SecondaryAccession", $gds_num );
		$logger->info("Adding GDS accession $gds_num to IDF");

		# Download the GDS file to the target directory
		my $gds_uri =
		  "ftp://ftp.ncbi.nih.gov/pub/geo/DATA/SOFT/GDS/" . $gds_num . ".soft.gz";
		my $path = $self->_download_file( $gds_uri, $self->get_target_dir );
		$path = $self->get_target_dir . $path;
		unless ($path)
		{
			$logger->warn("Could not download GDS soft file");
			next GDS;
		}
		open( my $fh, "<", $path )
		  or $logger->warn("Could not open GDS soft file $path: $!");

		my @subset_samples = ();
		my $description;
		my $type;

		# Find factor values
		while ( defined( my $line = <$fh> ) )
		{
			chomp $line;
			if ( $line =~ /^\^(SUBSET|DATASET)/i and defined $type )
			{

				# Remove any brackets in type as they cause loader fails
				$type =~ s/\(//g;
				$type =~ s/\)//g;
				$type =~ s/\[//g;
				$type =~ s/\]//g;
				$type =~ s/\}//g;
				$type =~ s/\{//g;

				$logger->info("Adding $type factor values");

				# Create Factor and FV
				my $factor = $self->_add_factor($type);

				my $term = Bio::MAGETAB::ControlledTerm->new(
															  {
																category => $type,
																value    => $description,
															  }
				);
				$self->_map_term($term);
				my $fv = Bio::MAGETAB::FactorValue->new(
														 {
														   factor => $factor,
														   term   => $term,
														 }
				);

				# Link FV to each hyb row in SDRF
				foreach my $hyb_name (@subset_samples)
				{
					my $hyb = $self->find_hyb($hyb_name);
					foreach my $row ( @{ $hyb->get_sdrfRows || [] } )
					{
						my $existing = $row->get_factorValues;
						$row->set_factorValues( [ @{ $existing || [] }, $fv ] );
					}
				}

				# Clear out storage variables
				@subset_samples = ();
				$description    = undef;
				$type           = undef;
			}
			elsif ( $line =~ /!subset_description\s*=\s*(.*)/i )
			{
				$description = $1;
			}
			elsif ( $line =~ /!subset_type\s*=\s*(.*)/i )
			{
				$type = $1;
			}
			elsif ( $line =~ /!subset_sample_id\s*=\s*(.*)/i )
			{
				@subset_samples = split ",", $1;
			}
		}
	}
	return;
}

sub _make_fvs_from_chars
{
	my ($self) = @_;

	# NB: this approach assumes that each source will only have 1 value per category

	# Find what characteristic categories we have
	my @sources =
	  grep { $_->isa("Bio::MAGETAB::Source") } $self->get_magetab->get_materials;
	my %types_to_values;
	foreach my $source (@sources)
	{
		my @chars = @{ $source->get_characteristics };
		foreach my $char (@chars)
		{
			$types_to_values{ $char->get_category }{ $char->get_value }++;
		}
	}

	# If a category has more than 1 value make it a factor
	foreach my $type ( keys %types_to_values )
	{
		if ( ( keys %{ $types_to_values{$type} } ) > 1 )
		{

			# Remove any brackets in type as they cause loader fails
			$type =~ s/\(//g;
			$type =~ s/\)//g;
			$type =~ s/\[//g;
			$type =~ s/\]//g;
			$type =~ s/\}//g;
			$type =~ s/\{//g;

			$logger->info("Adding $type factor values");

			# Create the Factor
			my $factor = $self->_add_factor($type);

			# Create the FactorValues and link them to sample rows
			foreach my $source (@sources)
			{
				my ($char) =
				  grep { $_->get_category eq $type } @{ $source->get_characteristics };

				# Characteristic may not be defined for all sources
				my $value;
				if ($char)
				{
					$value = $char->get_value;
				}
				else
				{
					$logger->warn(
							"No $type characteristic provided for " . $source->get_name );
					$value = "not specified";
				}

				my $term = Bio::MAGETAB::ControlledTerm->new(
															  {
																category => $type,
																value    => $value,
															  }
				);
				$self->_map_term($term);
				my $fv = Bio::MAGETAB::FactorValue->new(
														 {
														   factor => $factor,
														   term   => $term,
														 }
				);

				foreach my $row ( @{ $source->get_sdrfRows } )
				{
					my $existing = $row->get_factorValues;
					$row->set_factorValues( [ @{ $existing || [] }, $fv ] );
				}
			}
		}
	}

	###########################################################################
	# mkeays edit 2011-11-28:
	#
	# Check whether any characteristics have types that shouldn't be
	# characteristics -- e.g. 'compound', 'agent', 'time' ...  It looks at each
	# characteristic category type, and if it is allowed as a characteristic it
	# adds it to a new array of characteristics (@new_chars).  If it is not
	# allowed it does not add it to this array. At the end, the source
	# characteristics are set to what is left in @new_chars using
	# $source->set_characteristics.
	#
	###########################################################################
	foreach my $source (@sources)
	{

		# get the characteristics
		my (@chars) = @{ $source->get_characteristics };

		# a list of things that shouldn't go in Characteristics[]
		my @not_allowed =
		  qw/agent compound diet dose growth_condition stimulus_or_stress temperature time treatment/;

		# new array for allowed characteristics only
		my @new_chars;

		foreach my $char (@chars)
		{

			my $type = $char->get_category;

			# if the category is found in the list above, don't add it to the
			# new array.
			unless ( grep $_ eq lc($type), @not_allowed )
			{
				push @new_chars, $char;
			}
		}

		# set the source characteristics with the new array
		$source->set_characteristics( [@new_chars] );
	}
	###########################################################################
	# END mkeays edit 2011-11-28
	###########################################################################

	return;
}

sub load_gse_gds_map
{
	my ( $self, $map_file ) = @_;

	my $gse_gds_map = {};

	$logger->info("Loading GSE to GDS map file $map_file");
	open( my $map_fh, '<', $map_file )
	  or $logger->warn("Unable to open GDS map file $map_file: $!");

	return unless $map_fh;

	while ( defined( my $line = <$map_fh> ) )
	{
		chomp($line);
		my ( $line_accession, $gds_count, @accns ) = split( '\t', $line );
		$gse_gds_map->{ "GSE" . $line_accession } = [ map { "GDS$_" } @accns ];
	}

	close($map_fh);
	$self->set_gse_gds_map($gse_gds_map);

	$logger->info("Finished loading GSE to GDS map file");
}

sub load_gpl_acc_map
{
	my ( $self, $map_file ) = @_;

	my $accession_for = {};

	$logger->info("Loading platform map file $map_file");
	open( my $fh, '<', $map_file )
	  or $logger->warn("Unable to open platform map file $map_file: $!");

	return unless $fh;

	while ( defined( my $line = <$fh> ) )
	{
		chomp $line;
		my ( $platform, $ae_accn ) = split /\t/, $line;
		$accession_for->{$platform} = $ae_accn;
	}

	close $fh;
	$self->set_gpl_acc_map($accession_for);
	$logger->info("Finished loading platform map file");
}

sub load_ena_acc_map
{
	my ( $self, $map_file ) = @_;

	$logger->info("Loading ENA accession map file $map_file");
	open( my $fh, "<", $map_file )
	  or $logger->warn("Unable to open ENA accession map file $map_file: $!");

	return unless $fh;

	my %index_of;
	my @cols_of_interest =
	  qw(RUN_ID RUN_ALIAS STUDY_ID STUDY_ALIAS EXPERIMENT_ID FASTQ_FILES SAMPLE_ID LIBRARY_LAYOUT);

	while (<$fh>)
	{
		my $line = $_;
		chomp $line;
		my @values = split "\t", $line;
		if ( $. == 1 )
		{
			foreach my $heading (@cols_of_interest)
			{
				my ($index) = grep { $values[$_] eq $heading } 0 .. $#values;
				$index_of{$heading} = $index;
			}
			next;
		}
		my $study = $values[ $index_of{"STUDY_ALIAS"} ];
		if ($study)
		{

			# Old format for GEO Study Alias in mapping file
			if ( $study =~ /GEO Series accession: (GSE\d*)/g )
			{
				my $gse = $1;

				my $gsm = $values[ $index_of{"RUN_ALIAS"} ];
				$gsm =~ s/(GSM\d*).*/$1/g;

				my $run = $values[ $index_of{"RUN_ID"} ];

				$self->get_runs_for_gse->{$gse} ||= [];
				push @{ $self->get_runs_for_gse->{$gse} }, $run;

				$self->get_runs_for_gsm->{$gsm} ||= [];
				push @{ $self->get_runs_for_gsm->{$gsm} }, $run;

				# We use hashes here because experiment and study IDs may be
				# repeated on several lines of the mapping file
				$self->get_exps_for_gsm->{$gsm} ||= {};
				$self->get_exps_for_gsm->{$gsm}{ $values[ $index_of{"EXPERIMENT_ID"} ] } =
				  1;

				$self->get_accs_for_gse->{$gse} ||= {};
				$self->get_accs_for_gse->{$gse}{ $values[ $index_of{"STUDY_ID"} ] } = 1;

				$self->get_fastqs_for_run->{$run} ||= {};
				$self->get_fastqs_for_run->{$run} = $values[ $index_of{"FASTQ_FILES"} ];

				$self->get_samples_for_gsm->{$gsm} ||= {};
				$self->get_samples_for_gsm->{$gsm} = $values[ $index_of{"SAMPLE_ID"} ];

				$self->get_layout_for_gsm->{$gsm} ||= {};
				$self->get_layout_for_gsm->{$gsm} =
				  $values[ $index_of{"LIBRARY_LAYOUT"} ];
			}

			elsif ( $study =~ /GSE\d+/g )
			{
				my $gse = $study;

				my $gsm = $values[ $index_of{"RUN_ALIAS"} ];
				$gsm =~ s/(GSM\d*).*/$1/g;

				my $run = $values[ $index_of{"RUN_ID"} ];

				$self->get_runs_for_gse->{$gse} ||= [];
				push @{ $self->get_runs_for_gse->{$gse} }, $run;

				$self->get_runs_for_gsm->{$gsm} ||= [];
				push @{ $self->get_runs_for_gsm->{$gsm} }, $run;

				# We use hashes here because experiment and study IDs may be
				# repeated on several lines of the mapping file
				$self->get_exps_for_gsm->{$gsm} ||= {};
				$self->get_exps_for_gsm->{$gsm}{ $values[ $index_of{"EXPERIMENT_ID"} ] } =
				  1;

				$self->get_accs_for_gse->{$gse} ||= {};
				$self->get_accs_for_gse->{$gse}{ $values[ $index_of{"STUDY_ID"} ] } = 1;

				$self->get_fastqs_for_run->{$run} ||= {};
				$self->get_fastqs_for_run->{$run} = $values[ $index_of{"FASTQ_FILES"} ];

				$self->get_samples_for_gsm->{$gsm} ||= {};
				$self->get_samples_for_gsm->{$gsm} = $values[ $index_of{"SAMPLE_ID"} ];

				$self->get_layout_for_gsm->{$gsm} ||= {};
				$self->get_layout_for_gsm->{$gsm} =
				  $values[ $index_of{"LIBRARY_LAYOUT"} ];
			}

			else { next; }

		}

	}

}

sub _add_ena_accs
{
	my ($self) = @_;
	my $gse = $self->get_acc;
	my @file_list;

	# If we have an ENA study accession
	if ( my $ena_study_accs = $self->get_accs_for_gse->{$gse} )
	{
		$logger->info("Details of this GSE found in ENA mapping file");
		foreach my $acc ( keys %{$ena_study_accs} )
		{
			$logger->info("Adding SecondaryAccession $acc from ENA mapping file");
			$self->_add_expt_comment( "SecondaryAccession", $acc );
		}

		my @run_accs = @{ $self->get_runs_for_gse->{$gse} || [] };
		my $range = get_range_from_list( "SRR", @run_accs );
		my @ranges = split( ',', $range );

		# If range contains a comma
		# i.e. http://www.ebi.ac.uk/ena/data/view/SRR001985-SRR002046,SRR023866-SRR023869
		# we need to create to comments one for each range
		if (@ranges)
		{
			foreach my $r (@ranges)
			{
				$self->_add_expt_comment( "SequenceDataURI",
										  "http://www.ebi.ac.uk/ena/data/view/$r" );
				$logger->info("Adding SequenceDataURI for $r from ENA mapping file");
			}
		}

		else
		{
			$self->_add_expt_comment( "SequenceDataURI",
									  "http://www.ebi.ac.uk/ena/data/view/$range" );
			$logger->info("Adding SequenceDataURI for $range from ENA mapping file");
		}

	  ASSAY: foreach my $assay ( $self->get_magetab->get_assays )
		{
			$assay->get_name =~ /(GSM\d*)/g;
			my $gsm = $1;

			# Add sample accessions
			my $sample_acc = $self->get_samples_for_gsm->{$gsm};
			$self->_add_source_comment( "ENA_SAMPLE", $sample_acc, $assay );

			# Add library layout to extract
			my $lib_layout = $self->get_layout_for_gsm->{$gsm};
			$self->_add_extract_comment( "LIBRARY_LAYOUT", $lib_layout, $assay );

			# Check there is only one experiment per gsm
			my @exp_accs = keys %{ $self->get_exps_for_gsm->{$gsm} || {} };
			unless (@exp_accs)
			{

				# This assay has no corresponding ERX so we skip it
				next ASSAY;
			}
			if ( @exp_accs > 1 )
			{
				$logger->error("More than 1 ENA Experiment for $gsm");
			}
			$logger->info("Adding ENA_EXPERIMENT $exp_accs[0] from ENA mapping file");
			$self->_add_comment( "ENA_EXPERIMENT", $exp_accs[0], $assay );

            my @files; # keeps track of all processed files for a given assay. the files can be linked to more than one run/scan below

			# Add scan for each run
			RUN: foreach my $run ( @{ $self->get_runs_for_gsm->{$gsm} || [] } )
			{
				$logger->info("Adding ENA_RUN $run from ENA mapping file");

				my $fastq_count = $self->get_fastqs_for_run->{$run};

				# For paired experiments create a scan per file
				# and use the file name as the scan name
				my @scans;
				if ( $fastq_count == 2 )
				{
					push @scans, $run . "_1.fastq.gz";
					push @scans, $run . "_2.fastq.gz";
				}

                # Redirect edges with assay as input and non-scan (data acquisition) as output, to use scan as input instead.
                # These are edges that lead to processed data files as the output node. This redirection will create
                # scan (input) --edge-- file (output) connections.
                
                # First, find an edge that has the current assay as an input node.
                # Unless it's already an assay -- scan connection (we don't touch it), otherwise, do the redirection.
                # After redirection, create a new edge linking the assay to the scan.


				# Paired runs
				if ( scalar( @scans == 2 ) )
				{

					$logger->info("Paired submission - creating scan per file name");

					foreach my $scan_name (@scans)
					{
						my $scan =
						  Bio::MAGETAB::DataAcquisition->new( { name => $scan_name, } );

						# Find edge whose input node is our assay
						foreach my $edge ( grep { $_->get_inputNode == $assay }
										   $self->get_magetab->get_edges )
						{
							unless (
									 $edge->get_outputNode->isa(  
														  "Bio::MAGETAB::DataAcquisition") # pre-existing assay --edge-- scan trio
							  )
							{
								$edge->set_inputNode($scan);  # this is the redirection
                               			
							}
						}

						# Create assay to scan edge.  
						# Assays and scans are linked just by the creation of this new edge.
						# There is no need to explicitly assign the new edge to the input or output nodes.
						
						$logger->info("Creating new edge linking assay ".$assay->get_name." to scan ".$scan->get_name."...");				
						
						my $new_assay_to_scan_edge = Bio::MAGETAB::Edge->new(
															{
															  inputNode  => $assay,
															  outputNode => $scan,
															}
						);										
						
						# Ensure any files associated with each assay
						# gets linked to each scan. Firstly find edge(s)
						# that has current scan as an input node, and data
						# files as the output node. Keep the file names
						# inside the @files variable.
				
						# For paired submission the first scan encountered
						# gets the file associated with the assay assigned
						# The second scan doesn't and thus we must create this
						# edge based on the files we've noted down inside @files,
						# and link the files to the second scan.

						my @scan_edges =
						  grep { $_->get_inputNode == $scan }   
						  $self->get_magetab->get_edges;

						foreach my $scan_edge (@scan_edges)
						{
							if ( $scan_edge->get_outputNode->get_uri )
							{
								push (@files, $scan_edge->get_outputNode);
							}
						}            
                        
                       
						if ( !@scan_edges and @files )
						{

							foreach my $file (@files)
							{
							    $logger->info("Looking at file $file and scan ".$scan->get_name.", making new edge...");
								my $new_scan_to_file_edge = Bio::MAGETAB::Edge->new(
																   {
																	 inputNode  => $scan,
																	 outputNode => $file,
																   }
								);
							}

						}

						# Add run accessions to scan
						$self->_add_comment( "ENA_RUN", $run, $scan );
						my $uri = get_ena_fastq_uri($scan_name);
						$logger->info("Adding FASTQ_URI $uri");
						$self->_add_comment( "FASTQ_URI", $uri, $scan );

					}
				} # closing paired-end run loop

				else
				{

					# Single runs

					my $scan = Bio::MAGETAB::DataAcquisition->new( { name => $run, } );

					foreach my $edge ( grep { $_->get_inputNode == $assay }
									   $self->get_magetab->get_edges )
					{
						$edge->set_inputNode($scan)
						  unless $edge->get_outputNode->isa(
														 "Bio::MAGETAB::DataAcquisition");
					}

					# Create assay to scan edge                                        
					my $new_assay_to_scan_edge_single_end = Bio::MAGETAB::Edge->new(
														{
														  inputNode  => $assay,
														  outputNode => $scan,
														}
					);
					
					# Add run accessions to scan
					$self->_add_comment( "ENA_RUN", $run, $scan );

					$fastq_count = $self->get_fastqs_for_run->{$run};
					my @files;
					if ( $fastq_count == 1 )
					{
						push @files, "$run.fastq.gz";
					}
					foreach my $file (@files)
					{
						my $uri = get_ena_fastq_uri($file);
						$logger->info("Adding FASTQ_URI $uri");
						$self->_add_comment( "FASTQ_URI", $uri, $scan );
					}

				}  # closing single-end run loop
			}  # closing for each run loop
		}
	}

	else { $logger->info("This GSE accession not found in ENA accession map file"); }
}

sub map_to_array_acc
{
	my ( $self, $gpl ) = @_;
	my $acc = $self->get_gpl_acc_map->{$gpl};

	unless ($acc)
	{
		$gpl =~ /^GPL(\d*)$/g;
		$acc = "A-GEOD-" . $1;
	}
	return $acc;
}

sub map_to_efo_type
{
	my ( $self, $geo_type ) = @_;

	my %efo_type_for = (
		"Expression profiling by array" => "transcription profiling by array",
		"Expression profiling by genome tiling array" =>
		  "transcription profiling by tiling array",
		"Expression profiling by high throughput sequencing" => "RNA-seq of coding RNA",
		"Expression profiling by SAGE"      => "transcription profiling by SAGE",
		"Expression profiling by MPSS"      => "transcription profiling by MPSS",
		"Expression profiling by RT-PCR"    => "transcription profiling by RT-PCR",
		"Expression profiling by SNP array" => "transcription profiling by array",

		"Genome variation profiling by array" =>
		  "comparative genomic hybridization by array",
		"Genome variation profiling by genome tiling array" =>
		  "comparative genomic hybridization by array",
		"Genome variation profiling by high throughput sequencing" => "DNA-seq",
		"Genome variation profiling by SNP array"                  =>
		  "comparative genomic hybridization by array",

		"Genome binding/occupancy profiling by array" => "ChIP-chip by array",
		"Genome binding/occupancy profiling by genome tiling array" =>
		  "ChIP-chip by tiling array",
		"Genome binding/occupancy profiling by high throughput sequencing" => "ChIP-seq",
		"Genome binding/occupancy profiling by SNP array" => "ChIP-chip by SNP array",

		"Methylation profiling by array" => "methylation profiling by array",
		"Methylation profiling by genome tiling array" =>
		  "methylation profiling by array",
		"Methylation profiling by high throughput sequencing" =>
		  "methylation profiling by high throughput sequencing",
		"Methylation profiling by SNP array" => "methylation profiling by array",

		"Protein profiling by protein array" => "proteomic profiling by array",
		"Protein profiling by Mass Spec" => "proteomic profiling by mass spectrometer",

		"SNP genotyping by SNP array" => "genotyping by array",

		"Other" => "other",

		"Non-coding RNA profiling by array" => "transcription profiling by array",
		"Non-coding RNA profiling by genome tiling array" =>
		  "transcription profiling by array",
		"Non-coding RNA profiling by high throughput sequencing" =>
		  "RNA-seq of non coding RNA",
	);

	my $efo_type = $efo_type_for{$geo_type};

	unless ($efo_type)
	{
		$logger->warn(
					"\'$geo_type\' not mapped to EFO, using \'unknown experiment type\'");
		$efo_type = "unknown experiment type";
	}

	return $efo_type;
}

sub normalize_chars
{

	# This method was created to prevent duplicate columns appearing in the SDRF
	# when a samples do not have the same list of characteristics

	my ($self) = @_;
	my @sources =
	  grep { $_->isa("Bio::MAGETAB::Source") } $self->get_magetab->get_materials;

	#hash to store all possible characteristic catergories
	my %char_catergory = ();

	foreach my $source (@sources)
	{

		#retrieves characteristics for a given source
		my (@chars) = @{ $source->get_characteristics };
		foreach my $char (@chars)
		{

			#for each characteristic gets the category and adds in to a hash
			my $type = $char->get_category;
			$char_catergory{$type} = 1;
		}

	}

	#now we have a hash with all possible characteristics
	#lets check to see do all our characteristics have a value for this
	#characteristic and if not insert an empty string

	foreach my $source (@sources)
	{
		for my $key ( keys %char_catergory )
		{

			#if we do not have a catergory that matches the key
			#create a new characteristic and set the value to an empty string
			unless ( grep { $_->get_category eq $key } @{ $source->get_characteristics } )
			{

				my $char = Bio::MAGETAB::ControlledTerm->new(
															  {
																category => $key,
																value    => "",
															  }
				);

				#add new characteristic to list of existing characteristics
				my $existing = $source->get_characteristics;
				$source->set_characteristics( [ @{ $existing || [] }, $char ] );

			}

		}

	}

	### Do the same for comments##

	my %comment_catergory = ();

	foreach my $source (@sources)
	{

		#retrieves comments for a given source
		my (@comments) = @{ $source->get_comments };
		foreach my $comment (@comments)
		{
			my $type = $comment->get_name;
			$comment_catergory{$type} = 1;
		}

	}

	foreach my $source (@sources)
	{
		for my $key ( keys %comment_catergory )
		{
			unless ( grep { $_->get_name eq $key } @{ $source->get_comments } )
			{
				my $comment = Bio::MAGETAB::Comment->new(
														  {
															name  => $key,
															value => "",
														  }
				);

				my $existing = $source->get_comments;
				$source->set_comments( [ @{ $existing || [] }, $comment ] );

			}

		}
	}

	return;
}

1;
