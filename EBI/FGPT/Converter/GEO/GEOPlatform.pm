#!/usr/bin/env perl

=head1 NAME

EBI::FGPT::Converter::GEO::GEOPlatform
 
=head1 SYNOPSIS


	my $soft = GEOPlatform->new(
								 {
								   gpl        => $gpl,
								   target_dir => $target_dir
								 }
	);
=head1 DESCRIPTION

Module to download platform information from GEO and provide methods to
write it out in ArrayExpress ADF format. 

=head1 AUTHOR

Written by Anna Farne and updated by Emma Hastings, <emma@ebi.ac.uk>
 
=head1 COPYRIGHT AND LICENSE

Copyright [2011] EMBL - European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the
"License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at
http://www.apache.org/licenses/LICENSE-2.0
Unless required by applicable law or agreed to in writing,
software distributed under the License is distributed on an
"AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
either express or implied. See the License for the specific
language governing permissions and limitations under the
License.

=cut

package EBI::FGPT::Converter::GEO::GEOPlatform;

use Moose;
use MooseX::FollowPBP;
use File::Spec;
use File::Path;
use File::Basename;
use File::Copy;
use File::Spec::Functions;
use Date::Manip;
use Text::CSV_XS 0.69;
use Archive::Extract;
use LWP::Simple qw($ua get getstore is_success);
use File::Fetch;
use Log::Log4perl;

use Data::Dumper;
use Bio::MAGETAB::ArrayDesign;
use Bio::MAGETAB::Util::Writer;
use Bio::MAGETAB::Util::Writer::ADF;
use namespace::autoclean;
use EBI::FGPT::Common qw(check_linebreaks);
use EBI::FGPT::Config qw($CONFIG);

has 'gpl'       => ( is => 'rw', default => 'undef' );
has 'soft_file' => ( is => 'rw', default => 'undef' );
has 'target_dir' => ( is => 'rw', isa => 'Str' );
has 'accession' => ( is => 'rw', default => 'undef' );
has 'platform_atts' => ( is => 'rw', isa => 'HashRef', default => sub { {} } );
has 'table_headings' => ( is => 'rw', default => sub { [] } );
has 'table_values'   => ( is => 'rw', isa => 'ArrayRef', default => sub { [] } );
has 'database_names' => ( is => 'rw', isa => 'ArrayRef', default => sub { [] } );
has 'heading_descs'  => ( is => 'rw', isa => 'ArrayRef', default => sub { [] } );
has 'reporters'      => ( is => 'rw', isa => 'ArrayRef', default => sub { [] } );
has 'list_cols'          => ( is => 'rw', isa => 'ArrayRef' );
has 'merge_rules'        => ( is => 'rw', isa => 'ArrayRef' );
has 'num_coords_missing' => ( is => 'rw', isa => 'Int', default => '0' );
has 'adf'                => ( is => 'rw', isa => 'Bio::MAGETAB::ArrayDesign' );
has 'additional_file' =>
  ( is => 'rw', isa => 'FileHandle', builder => '_build_additional_file', lazy => 1 );
has 'is_seq' => ( is => 'rw', isa => 'Bool', default => 0 );

# Set up log4perl
my $conf = q(
log4perl.rootLogger              = WARN, SCREEN
log4perl.appender.SCREEN         = Log::Log4perl::Appender::Screen
log4perl.appender.SCREEN.stderr  = 0
log4perl.appender.SCREEN.layout  = Log::Log4perl::Layout::PatternLayout
log4perl.appender.SCREEN.layout.ConversionPattern = %d %p %m %n
  );

Log::Log4perl::init( \$conf );
my $logger = Log::Log4perl->get_logger();
my $SEP    = ";";
$ENV{ftp_proxy} = 'http://www-proxy.ebi.ac.uk:3128';

sub BUILD
{
	my $self = shift;

	if ( my $proxy = $CONFIG->get_HTTP_PROXY )
	{
		$logger->info("Setting proxy: $proxy");
		$ua->proxy( ['http'], $proxy );
	}

	# Check we have required attributes
	unless ( $self->get_gpl )
	{
		$logger->logdie("You must supply a GPL number to create a GEOPlatform object");
	}
	unless ( $self->get_target_dir )
	{
		$logger->logdie(
				"You must supply a target directory where downloaded files can be saved");
	}

	# Make sure GPL number is in the format GPLnnnn...
	if ( my $accession = $self->get_gpl )
	{
		if ( $accession =~ /^ (?:GPL)? (\d*) $/ixms )
		{
			$self->set_gpl( "GPL" . $1 );
		}
		else
		{
			$logger->logdie("GPL number $accession is not in the expected format");
		}
	}

	# Download the SOFT file first
	$self->import_gpl;
	$self->read_soft;

	# Set up our MAGE-TAB ADF object
	# Name is required so set a dummy value now and then replace with info from SOFT file
	my $adf = Bio::MAGETAB::ArrayDesign->new( name => "GEO import" );
	$self->set_adf($adf);

}

sub _build_additional_file
{
	my $self      = shift;
	my $file_name = $self->get_accession . "_comments.txt";
	my $path      = catfile( $self->get_target_dir, $file_name );

	# Open output file for writing
	open( my $fh, ">", $path ) or die $!;
	return ($fh);

}

sub import_gpl
{

	my ($self) = @_;

	my $target_dir = $self->get_target_dir;

	my $gpl_file = $self->get_gpl . "_family.soft.gz";

	my $gpl_ftp_location =
	    "ftp://ftp.ncbi.nih.gov/pub/geo/DATA/SOFT/by_platform/"
	  . $self->get_gpl . "/"
	  . $gpl_file;

	my $ff        = File::Fetch->new( uri => $gpl_ftp_location );
	my $file_name = $ff->file;

	$logger->info("Downloading file $file_name");

	my $file_path = File::Spec->catfile( $target_dir, $file_name );

	my $where = $ff->fetch( to => $target_dir )
	  or $logger->logdie(
			$ff->error . "Could not download file from $gpl_ftp_location to $file_path" );

	my $extracted_name;

	# Unpack the file
	my $archive = Archive::Extract->new( archive => $file_path );
	if ($archive)
	{
		$logger->info("Extracting file $gpl_file");
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
		my $extracted_path =
		  File::Spec->rel2abs( File::Spec->catfile( $target_dir, $extracted_name ) );
		$self->set_soft_file($extracted_path);

	}
	else
	{
		$logger->logdie("Could not process archive $file_path");
	}

	return;

}

sub read_soft
{

	my ($self) = @_;

	my $file = $self->get_soft_file;

	$logger->info("Reading SOFT file $file");

	# check linebreaks (will die if file cannot be opened)
	my $eol = check_linebreaks($file);

	my $csv_parser = Text::CSV_XS->new(
		{
		  sep_char           => qq{\t},
		  quote_char         => qq{"},              # default
		  escape_char        => qq{"},              # default
		  binary             => 1,
		  eol                => ( $eol || "\n" ),
		  allow_loose_quotes => 1,
		}
	);

	open( my $fh, "<", $file )
	  or $logger->logdie("Could not open SOFT file $file");

	my $expected_row_count;
	my $line;

	# Store the platform attribute lines i.e. !Platform_distribution = custom-commercial
  ATT_LINE: while ( defined( $line = $csv_parser->getline($fh) ) )
	{

		# Ignore first few lines and start at '^PLATFORM = GPLXXXX'
		next unless $line->[0] =~ /\^PLATFORM \s* = \s* GPL(\d*)/ixms;
		$self->set_gpl( "GPL" . $1 );
		$self->set_accession( "A-GEOD-" . $1 );

		while ( defined( $line = $csv_parser->getline($fh) ) )
		{

			# Example line !Platform_manufacturer = NimbleGen
			$line->[0] =~ /!(\S*)\s*=\s*(.*)$/g;
			my $tag   = lc($1);
			my $value = $2;

			# These are usually dummy arrays for sequencing experiments
			# Do not import
			if (     $tag =~ /platform_technology/
				 and $value =~ /high-throughput sequencing/ )
			{
				$self->set_is_seq(1);
			}

			if ( $self->get_platform_atts->{$tag} )
			{
				$self->get_platform_atts->{$tag} .= " $value";
			}
			else
			{
				$self->get_platform_atts->{$tag} = $value;
			}

			# Store column heading descriptions (lines starting # before platform table)
			if ( $line->[0] =~ /\#(.*)/ )
			{
				push @{ $self->get_heading_descs }, $1;
			}

		   # Store expected row count so we can check platform table is the correct length
			if ( $tag =~ /platform_data_row_count/ixms )
			{
				$expected_row_count = $value;
			}

			last ATT_LINE if ( $line->[0] =~ /!platform_table_begin/ixms );
		}
	}

	# Then store the list of column headings
	# Parses a row from the file using and parses this row into an array ref
	$self->set_table_headings( $csv_parser->getline($fh) );

	# Then store the lists of values
	my $row_count = 0;
  VALUE_LINE: while ( defined( my $line = $csv_parser->getline($fh) ) )
	{
		last VALUE_LINE if $line->[0] =~ /!platform_table_end/ixms;
		push @{ $self->get_table_values }, $line;
		push @{ $self->get_reporters },    $line->[0];
		$row_count++;
	}

	if ( !$self->row_count_ok( $row_count, $expected_row_count ) )
	{
		$logger->logdie(
				"$row_count lines found in platform table, $expected_row_count expected");
	}
	$logger->info("Reading SOFT file done");

	return;
}

sub row_count_ok
{
	my ( $self, $count, $expected ) = @_;

	if ( !$expected )
	{
		$logger->warn(
					"Expected number of features is $expected, skipping row count check");
		return 1;
	}
	else
	{
		my $diff = $expected - $count;

		# make diff a positive number
		$diff = $diff * $diff;

		# Allow count to be out by 1
		if ( $diff > 1 )
		{
			return 0;
		}
		else
		{
			return 1;
		}
	}
	return;
}

sub write_adf
{
	my ( $self, $output ) = @_;

	my $adf = $self->get_adf;
	$logger->info( "Writing ADF file for " . $self->get_gpl );

	# GEO creates a dummy platform file for sequening submissions,
	# the arrays are virtual and have no body
	# therefore we ignore these as they have no value to ArrayExpress
	if ( $self->get_is_seq )
	{
		$logger->warn( "Sequencing platform, import terminated for " . $self->get_gpl );
		return;
	}

	# If there is no ADF body we just write the header information
	unless ( @{ $self->get_table_values } )
	{
		$logger->warn("No platform table lines, will fail validation");
		return;
	}

	open( my $fh, ">", $output )
	  or $logger->logdie("Could not open ADF file $output for writing");

	# Map geo to magetab headings
	my @orig_headings    = @{ $self->get_table_headings };
	my @magetab_headings = map { $self->geo_to_magetab_heading($_) } @orig_headings;

	# Set the list of databases used - we must do this before writing the header
	foreach my $heading (@magetab_headings)
	{
		if ( $heading =~ /.*Database.*\[(.*)]/ )
		{
			$self->add_database_name($1);
		}
	}

	# Get MAGETAB formatted column headings (duplicates will be merged)
	$self->merge_rules( \@magetab_headings );
	my $final_headings = $self->merge_columns( \@magetab_headings );

	# Need to write additional file first
	my $addition_fh = $self->get_additional_file;
	print $addition_fh join "\t", @$final_headings;
	print $addition_fh "\n";

	# Identify GEO_LIST columns
	my $list_cols = $self->list_cols( \@orig_headings );

	# Print out values using ";" as separator in list columns
	foreach my $line ( @{ $self->get_table_values } )
	{
		my @bits = @$line;
		foreach my $list (@$list_cols)
		{
			$bits[$list] =~ s/\s*,\s*/$SEP/g;
			$bits[$list] =~ s/\s+/$SEP/g;
		}

		my $values = $self->merge_columns( \@bits );
		print $addition_fh join "\t", @$values;
		print $addition_fh "\n";

	}
	close $addition_fh;
	$logger->info("Writing additional file done");

	# Now can write ADF
	$self->create_adf_header();
	my $adf_writer = Bio::MAGETAB::Util::Writer::ADF->new(
														   {
															 magetab_object => $adf,
															 filehandle     => $fh
														   }
	);

	$adf_writer->write();

	print $fh join "\t", "Reporter Name";
	print $fh "\n";

	# Print out values using ";" as separator in list columns
	foreach my $reporter ( @{ $self->get_reporters } )
	{
		print $fh $reporter;
		print $fh "\n";
	}

	close $fh;

	# Bio::MAGETAB is not complatible with GEO platforms
	# Therefore we need to do some text fixing
	$self->tidy_adf($output);
	return;
}

sub tidy_adf
{

	# Use Bio::MAGETAB to write the array
	# Need to tidy up the file a bit as a result
	$logger->info("Writing ADF");
	my ( $self, $output ) = @_;

	open( my $fh, "<", $output )
	  or $logger->logdie("Could not open ADF file $output for reading");

	my $temp = $output . "temp.txt";
	open( my $temp_fh, ">", $temp )
	  or $logger->logdie("Could not open temp for writing");

	while (<$fh>)
	{
		my $line = $_;
		chomp $line;
		next if ( $line =~ /^\[header\]/ );
		next if ( $line =~ /Block Column/ );
		next if ( $line =~ /^\s*$/ );
		if ( $line =~ /^\[main/ )
		{
			$line =~ s/\t*//g;
		}
		print $temp_fh $line ;
		print $temp_fh "\n";
	}

	move( $temp, $output ) or LOGDIE($!) if $output;
	unlink($temp);
	close $fh;
	close $temp_fh;
	return;

}

sub merge_rules
{
	my ( $self, $headings ) = @_;

	my $rules;
	my @merge_rules;

	if ( defined( $rules = $self->get_merge_rules ) )
	{
		return $rules;
	}
	else
	{

		# identify duplicate cols. store details of which cols to merge
		# store array of arrays,e.g. 0-(0), 1-(1), 2-(2,3), 3-(4)
		my %index_of;
		my @magetab_headings = @$headings;

		foreach my $index ( 0 .. $#magetab_headings )
		{
			my $heading = $magetab_headings[$index];
			if ( defined( my $existing_index = $index_of{$heading} ) )
			{
				push @{ $merge_rules[$existing_index] }, $index;
			}
			else
			{
				push @merge_rules, [$index];
				$index_of{$heading} = $index;
			}
		}
	}
	$self->set_merge_rules( \@merge_rules );
	return \@merge_rules;
}

sub list_cols
{

	my ( $self, $headings ) = @_;

	my $list;
	my @list_cols;

	if ( defined( $list = $self->get_list_cols ) )
	{
		return $list;
	}
	else
	{
		my @orig_headings = @$headings;
		@list_cols = grep { $orig_headings[$_] =~ /_LIST$/i } 0 .. $#orig_headings;
	}

	$self->set_list_cols( \@list_cols );
	return \@list_cols;
}

sub merge_columns
{
	my ( $self, $value_list ) = @_;
	my @new;
	my @old   = @$value_list;
	my $rules = $self->get_merge_rules;
	my @rules = @$rules;

	foreach my $rule (@rules)
	{
		if ( @$rule > 1 )
		{

			# get unique values
			my %unique = map { $_ => 1 } @old[@$rule];

			# merge them
			my $string = join $SEP, grep { $_ } keys %unique;
			push @new, $string;
		}
		else
		{
			push @new, @old[@$rule];
		}
	}

	return \@new;

}

sub geo_to_magetab_heading
{
	my ( $self, $geo ) = @_;
	my $heading_for = $self->get_geo_to_magetab_mapping;
	my $mtab = $heading_for->{$geo} || "Comment[" . $geo . "]";
	return $mtab;

}

sub create_adf_header
{

	my ($self) = @_;

	my $atts    = $self->get_platform_atts;
	my $contact = "";

	# For now we use name(email) but we could include other contact details in future

	if ( $atts->{platform_contact_email} )
	{
		$contact = $self->get_contact_name . " (" . $atts->{platform_contact_email} . ")";
		$contact =~ s/^\s//;
	}
	else
	{
		$contact = $self->get_contact_name . " (geo\@ncbi.nlm.nih.gov)";
		$contact =~ s/^\s//;
	}

	# Add release date so GEO arrays will go public in AE2
	my $geo_date = $atts->{platform_status};
	$geo_date =~ s/Public on //i;
	my $date = ParseDate($geo_date);
	$date =~ s/([\d]{4}[\d]{2}[\d]{2}).*/$1/g;
	substr( $date, 4, 0 ) = '-';
	substr( $date, 7, 0 ) = '-';
	$logger->info("Setting release date to $date");
	$atts->{platform_status} = $date;

  # Platform alternatives - first get list of relations from the soft file
  # Added by Eleanor Williams 2012-06-20
  # There are several types of relationship
  # 1. Alternative to:
  # 2. Affiliated with:
  # 3. Parent of: and Child of:
  # For automatic import we only want the alternatives as others may be different versions
  # or subsets of probes
  # Each alternative will be put into a Comment[SecondaryAccession] field

	my $all_relations = "";
	my @alternatives;

	if ( exists( $atts->{platform_relation} ) )
	{
		$all_relations = $atts->{platform_relation};

		# split out different parts, then keep only alternative to relations
		my @everything =
		  split( /\s[A-FH-Z]/, $all_relations );    # split on space then capital letter
		                                            # that is not a 'G'

		#keep only alternatives
		foreach my $relation (@everything)
		{
			if ( $relation =~ /lternative to:\s/ )
			{
				push @alternatives, $relation;
			}
		}

# check if alternatives are in platforms.txt
# platforms.txt holds list of GEO->AE accessions for many catalogue arrays e.g.
# Affy arrays. These weren't imported from GEO as already had them in AE.
# If alternative is in platforms.txt then need to change GEO accession to corresponding AE
# accession.

		# open platforms.txt file and put info into hash of GSEplatform -> AE accession
		my $platform_file = $CONFIG->get_GEO_PLATFORM_MAP;

		open( PLATFORMS, '<', $platform_file )
		  or die "No such file: $platform_file: $!";
		my @platform_lines = <PLATFORMS>;
		close(PLATFORMS);
		my %GSE_AE_platforms;

		foreach my $line (@platform_lines)
		{
			my ( $platform, $ae_accn, $cdf, $loaded_as_adf ) = split( /\t/, $line );
			$GSE_AE_platforms{$platform} = $ae_accn;
		}

		# look to see if each alternative is in the mapping file
		foreach my $alternative (@alternatives)
		{
			$alternative =~ /.*(GPL\d+)/;
			$alternative = $1;

	   # check if accession in platforms.txt mapping file, if so replace with AE accession
			if ( exists( $GSE_AE_platforms{$alternative} ) )
			{
				$alternative = $GSE_AE_platforms{$alternative};
			}

			# change accession to AE style
			$alternative =~ s/GPL/A-GEOD-/;
			$logger->info( "Alternative found = " . $alternative );

		}
	}

	my $adf = $self->get_adf;
	my @comments;
	$adf->set_name( $atts->{platform_title} );

	if ($contact)
	{
		$adf->set_provider($contact);
	}

	if ( $atts->{platform_manufacture_protocol} )
	{
		$adf->set_printingProtocol( $atts->{platform_manufacture_protocol} );
	}

	if ( $atts->{platform_coating} )
	{
		my $surface_type = Bio::MAGETAB::ControlledTerm->new(
													 {
													   category => "SurfaceType",
													   value => $atts->{platform_coating}
													 }
		);

		$adf->set_surfaceType($surface_type);
	}

	if ( $atts->{platform_support} )
	{
		my $substrate_type = Bio::MAGETAB::ControlledTerm->new(
													 {
													   category => "SubstrateType",
													   value => $atts->{platform_support}
													 }
		);

		$adf->set_substrateType($substrate_type);

	}

	my $ae_acc_comment =
	  Bio::MAGETAB::Comment->new(
					 { name => 'ArrayExpressAccession', value => $self->get_accession } );

	push @comments, $ae_acc_comment;

	if (@alternatives)
	{
		foreach my $platform_alternative (@alternatives)
		{
			my $alt_sec_acc_comment =
			  Bio::MAGETAB::Comment->new(
					   { name => 'SecondaryAccession', value => $platform_alternative } );

			push @comments, $alt_sec_acc_comment;
		}

	}

	my $sec_acc_comment =
	  Bio::MAGETAB::Comment->new(
							  { name => 'SecondaryAccession', value => $self->get_gpl } );

	push @comments, $sec_acc_comment;

	my $description =
	  Bio::MAGETAB::Comment->new(
							  { name => 'Description', value => $self->get_descr_text } );

	push @comments, $description;

	my $submitted_name =
	  Bio::MAGETAB::Comment->new(
						  { name => 'SubmittedName', value => $atts->{platform_title} } );

	push @comments, $submitted_name;

	my $organism =
	  Bio::MAGETAB::Comment->new(
							{ name => 'Organism', value => $atts->{platform_organism} } );

	push @comments, $organism;

	my $release_date =
	  Bio::MAGETAB::Comment->new( { name => 'ArrayExpressReleaseDate', value => $date } );

	push @comments, $release_date;

	my $additional_file_comment = Bio::MAGETAB::Comment->new(
										{
										  name  => 'AdditionalFile:TXT',
										  value => $self->get_accession . "_comments.txt"
										}
	);

	push @comments, $additional_file_comment;

	if (@comments) { $adf->set_comments( \@comments ); }

	return;
}

sub get_contact_name
{

	# Gets platform_contact_name attribute and removes extra commas and spaces
	my ($self) = @_;
	my $name = $self->get_platform_atts->{platform_contact_name};
	$name =~ s/,/ /g;
	$name =~ s/\s+/ /g;
	return $name;
}

sub get_descr_text
{
	my ($self) = @_;

	my $atts = $self->get_platform_atts;

	# Build description text from available array info
	my @bits;
	if ( my $manuf = $atts->{platform_manufacturer} )
	{
		push @bits, "Array Manufacturer: " . $manuf;
	}
	if ( my $number = $atts->{platform_catalog_number} )
	{
		push @bits, "Catalogue number: " . $number;
	}
	if ( my $dist = $atts->{platform_distribution} )
	{
		push @bits, "Distribution: " . $dist;
	}
	if ( my $dist = $atts->{platform_technology} )
	{
		push @bits, "Technology: " . $dist;
	}
	push @bits, $atts->{platform_description};

	my $text = ( join ", ", grep { $_ } @bits );
	if ( my $heading_descr = $self->get_heading_descr_text )
	{
		$text .= "<br> $heading_descr";
	}
	return $text;

}

sub get_heading_descr_text
{
	my ($self) = @_;
	my @descriptions;
	my @descr_lines = @{ $self->get_heading_descs };

	foreach my $line (@descr_lines)
	{
		$line =~ s/\"//g;

		$line =~ /([^\=]*)=(.*)/g;
		my $heading = $1;
		my $descr   = $2;

		if ($descr)
		{
			$descr   =~ s/(^\s*)||(\s*$)//g;
			$heading =~ s/(^\s*)||(\s*$)//g;
			my $new = $self->geo_to_magetab_heading($heading);
			push @descriptions, "$new = $descr";
		}
	}

	if (@descriptions)
	{
		return join "<br>", @descriptions;
	}
	return undef;
}

sub get_geo_to_magetab_mapping
{

	# All geo standard platform headers as defined here
	# http://www.ncbi.nlm.nih.gov/projects/geo/info/platform.html
	# (plus some obvious mappings seen in test imports)

	# Mapped to equivalent MTAB headings or to Comment
	my %geo_to_mtab = (
		ID                   => 'Reporter Name',
		SEQUENCE             => 'Reporter Sequence',
		GB_ACC               => 'Reporter Database Entry [genbank]',
		GB_LIST              => 'Reporter Database Entry [genbank]',
		GB_RANGE             => 'Comment[GB_RANGE]',
		RANGE_GB             => 'Comment[RANGE_GB]',
		RANGE_START          => 'Comment[RANGE_START]',
		RANGE_END            => 'Comment[RANGE_END]',
		RANGE_STRAND         => 'Comment[RANGE_STRAND]',
		GI                   => 'Reporter Database Entry [gi]',
		GI_LIST              => 'Reporter Database Entry [gi]',
		GI_RANGE             => 'Comment[GI_RANGE]',
		CLONE_ID             => 'Reporter Database Entry [clone_id]',
		CLONE_ID_LIST        => 'Reporter Database Entry [clone_id]',
		ORF                  => 'Comment[ORF]',
		ORF_LIST             => 'Comment[ORF]',
		GENOME_ACC           => 'Comment[GENOME_ACC]',
		SNP_ID               => 'Reporter Database Entry [dbsnp]',
		SNP_ID_LIST          => 'Reporter Database Entry [dbsnp]',
		miRNA_ID             => 'Reporter Database Entry [mirbase]',
		miRNA_ID_LIST        => 'Reporter Database Entry [mirbase]',
		SPOT_ID              => 'Comment[SPOT_ID]',
		ORGANISM             => 'Reporter Group [organism]',
		PT_ACC               => 'Reporter Database Entry [genbank]',
		PT_LIST              => 'Reporter Database Entry [genbank]',
		PT_GI                => 'Reporter Database Entry [genbank]',
		PT_GI_LIST           => 'Reporter Database Entry [genbank]',
		SP_ACC               => 'Reporter Database Entry [swissprot]',
		SP_LIST              => 'Reporter Database Entry [swissprot]',
		Description          => 'Reporter Comment',
		LOCUSLINK_ID         => 'Reporter Database Entry [locus]',
		UNIGENE_ID           => 'Reporter Database Entry [unigene]',
		CHROMOSOMAL_LOCATION => 'Reporter Database Entry [chromosome_coordinate]',
		DESCRIPTION          => 'Reporter Comment'

	);

	return \%geo_to_mtab;

}

sub add_database_name
{
	my ( $self, $db ) = @_;

	# Add a database to the list without introducing duplicates
	my @db_names = @{ $self->get_database_names };
	my %seen = map { $_ => 1 } @db_names;
	$seen{$db}++;
	$self->set_database_names( [ sort keys %seen ] );
	return;
}

__PACKAGE__->meta->make_immutable;
1;
