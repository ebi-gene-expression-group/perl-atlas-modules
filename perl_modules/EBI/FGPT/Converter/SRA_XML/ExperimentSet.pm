#!/usr/bin/env perl
#
# SRA_XML/ExperimentSet.pm - create SRA xml from magetab
#
# Anna Farne, European Bioinformatics Institute, 2009
#
# $Id: ExperimentSet.pm 2438 2012-05-31 15:02:48Z ehastings $

package EBI::FGPT::Converter::SRA_XML::ExperimentSet;

use Moose;
use MooseX::FollowPBP;
use XML::Writer;
use Log::Log4perl qw(:easy);
use Data::Dumper;

extends 'EBI::FGPT::Converter::SRA_XML::XML';

has 'output_file' => ( is => 'rw', isa => 'Str' );
has 'extract_to_sample' =>
  ( is => 'rw', isa => 'HashRef', default => sub { {} } );
has 'assay_to_extract' =>
  ( is => 'rw', isa => 'HashRef', default => sub { {} } );
has 'assay_to_fvs' => ( is => 'rw', isa => 'HashRef', default => sub { {} } );

sub BUILD {
	my $self = shift;

	# ensure output file have been supplied

	unless ( $self->get_output_file ) {
		LOGDIE "No output file supplied";
	}

	$self->set_schema_type("experiment");

	my $xml = $self->get_xml_writer;
	$xml->startTag('EXPERIMENT_SET');

	$self->create_experiments;
}

sub create_experiments {
	my ($self) = @_;
	foreach my $assay_name ( keys %{ $self->get_assay_to_extract } ) {
		$self->add_experiment($assay_name);
	}
}

sub add_experiment {
	my ( $self, $assay_name ) = @_;
	my $xml   = $self->get_xml_writer;
	my $title = $self->get_experiment->get_title;

	my @lib_atts = qw(LIBRARY_STRATEGY LIBRARY_SOURCE LIBRARY_SELECTION);

	my @extracts = @{ $self->get_assay_to_extract->{$assay_name} };
	my $extract  = $extracts[0];

	if ($#extracts) {

		# Warn if there is more than 1 extract as we will take protocol
		# from the first one only
		WARN "Warning: more than one extract found for assay $assay_name. ";
		INFO "Getting protocol from extract " . $extract->get_name;

	}

	my $extract_protocol = $self->get_protocol_text($extract);
	my $layout           = $self->get_comment( $extract, "LIBRARY_LAYOUT" );

	my $hardware = $self->get_assay_hardware($assay_name);
	my $platform = $self->get_platform_from_hardware($hardware);

	$xml->startTag( "EXPERIMENT", alias => $self->make_alias($assay_name) );

	$xml->dataElement( "TITLE", $title );
	$xml->emptyTag(
		"STUDY_REF",
		refname   => $self->get_accession,
		refcenter => $self->get_center_name
	);

	$xml->startTag("DESIGN");
	$xml->dataElement( "DESIGN_DESCRIPTION", $title );

	if ($#extracts) {
		INFO "Adding multiple extracts/samples to assay $assay_name\n";
		$xml->startTag(
			"SAMPLE_DESCRIPTOR",
			refname   => "$assay_name:unassigned",
			refcenter => $self->get_center_name
		);
		$xml->startTag("POOL");
		foreach my $extract (@extracts) {
			my $tag = $self->get_comment( $extract, "BARCODE" );
			my $samples = $self->get_extract_to_sample->{ $extract->get_name };
			my $sample_alias = $self->make_alias( $samples->[0]->get_name );
			$xml->startTag( "MEMBER",     refname        => $sample_alias );
			$xml->startTag( "READ_LABEL", read_group_tag => $tag );
			$xml->characters("barcode_tag");
			$xml->endTag;
			$xml->endTag;
		}
		$xml->endTag;
		$xml->endTag;
	}
	else {
		my @samples = @{ $self->get_extract_to_sample->{ $extract->get_name } };
		if ($#samples) {
			LOGDIE "Error: more than 1 sample pooled to extract "
			  . $extract->get_name . "\n";
		}
		my $sample_alias = $self->make_alias( $samples[0]->get_name );
		$xml->emptyTag( "SAMPLE_DESCRIPTOR", refname => $sample_alias );
	}
	$xml->startTag("LIBRARY_DESCRIPTOR");
	$xml->dataElement( "LIBRARY_NAME", $extract->get_name );
	foreach my $att (@lib_atts) {
		$xml->dataElement( $att, $self->get_comment( $extract, $att ) );
	}
	$xml->startTag("LIBRARY_LAYOUT");
	if ( $layout =~ /SINGLE/i ) {
		$xml->emptyTag("SINGLE");
	}
	elsif ( $layout =~ /PAIRED/i ) {
		my $nominal_length = $self->get_comment( $extract, "NOMINAL_LENGTH" );
		my $nominal_sdev   = $self->get_comment( $extract, "NOMINAL_SDEV" );

		#Only add standard dev if you have the value
		if ($nominal_sdev) {
			$xml->startTag(
				"PAIRED",
				"NOMINAL_LENGTH" => $nominal_length,
				"NOMINAL_SDEV"   => $nominal_sdev
			);
		}

		else {
			$xml->startTag( "PAIRED", "NOMINAL_LENGTH" => $nominal_length );
		}

		$xml->endTag;
	}
	else {
		WARN "Layout $layout not recognised. Defaulting to single layout\n";
		$layout = "SINGLE";
		$xml->emptyTag("SINGLE");
	}
	$xml->endTag;
	$xml->dataElement( "LIBRARY_CONSTRUCTION_PROTOCOL", $extract_protocol );
	$xml->endTag;

	# Insert default spot descriptor xml
	# We need to pass the raw data object so we can get
	# annotations such as READ_INDEX_1_BASE_COORD from it
	# to replace some default values
	my @raw_data = $self->get_file_from_assay_name($assay_name);
	my $raw_data = $raw_data[0];
	if ($#raw_data) {
		WARN
		  "Warning: more than one raw data file found for assay $assay_name. ";
		INFO "Getting comments from raw data " . $raw_data->get_uri;
	}

	$self->add_spot_descriptor( $platform, $layout, \@extracts, $assay_name );

	$xml->endTag;

	$xml->startTag("PLATFORM");
	$xml->startTag($platform);
	$xml->dataElement( "INSTRUMENT_MODEL", $hardware );
	$self->add_required_elements( $platform, $assay_name );
	$xml->endTag;
	$xml->endTag;

	# Insert default processing xml
	$self->add_processing( $platform, $layout );

	# Add experiment attributes
	$xml->startTag("EXPERIMENT_ATTRIBUTES");

	# Add factor values as experiment attributes if we have any
	my $fvs = $self->get_assay_to_fvs->{$assay_name};
	if ( @{ $fvs || [] } ) {
		foreach my $fv (@$fvs) {
			my $name = "Experimental Factor: " . $self->get_fv_factor_name($fv);
			my $value = $self->get_factor_value_text($fv);
			$self->add_experiment_attribute( $name, $value );
		}
	}

	# Add strand information if we have any
	my $strand = $self->get_comment( $extract, "LIBRARY_STRAND" );
	if ($strand) {
		my $name  = "LIBRARY_STRAND";
		my $value = $strand;
		$self->add_experiment_attribute( $name, $value );
	}
	$xml->endTag;
	$xml->endTag;
}

sub add_spot_descriptor {
	my ( $self, $platform, $layout, $extracts_ref, $assay_name ) = @_;

	my @extracts = @$extracts_ref;

	# If there are multiple extracts per assay then barcodes
	# must be used to identify sequence for each extract
	my $is_barcode = $#extracts;

	my @raw_files = $self->get_file_from_assay_name($assay_name);
	my @raw_files_comments;
	my @files;

	foreach my $raw_file (@raw_files) {

		my $raw_file_name = $raw_file->get_uri;
		$raw_file_name =~ s/^file://g;
		push @files,              $raw_file_name;
		push @raw_files_comments, $raw_file->get_comments;
	}

	INFO "Data for $assay_name:\n";
	my %file_types;
	foreach my $file (@files) {
		my $name = $file;
		INFO "File: " . $name . "\n";

		# remove archive extensions
		$name =~ s/\.gz//ig;
		$name =~ s/\.zip//ig;
		$name =~ s/\.bz2//ig;
		$name =~ s/\.tar//ig;

		$name =~ /\.(\w*)$/g;
		my $type = $1;
		$type = lc($type);
		$type = "fastq" if $type eq "fq";
		$file_types{$type}++;

	}

	while ( my ( $key, $value ) = each(%file_types) ) {
		INFO "File type $key: $value found\n";
	}

	# No spot descriptor needed for:
	# BAM files
	# SFF files if single and no barcode
	# fastq files if single and no barcode or tech read
	# Complete genomics does not have a spot descriptor

	# As of Apr 2013 these require a spot descriptor

	# 1 pair SOLiD csfasta/qual and single and not barcode
	# 2 pairs SODiD	csfasta/qual and paired and not barcode

	# tested
	if ( $file_types{"bam"}
		and !grep { $_ ne "bam" } keys %file_types )
	{

		INFO "No spot descriptor needed for bam files";
		return;
	}
	if ( $platform =~ /COMPLETE_GENOMICS/i ) {

		INFO "No spot descriptor needed for Complete Genomics platform";
		return;
	}

	# tested
	if (    $file_types{"sff"}
		and !grep { $_ ne "sff" } keys %file_types
		and $layout =~ /SINGLE/i
		and not $is_barcode )
	{

		INFO
		  "No spot decriptor needed for single read SFF files with no barcodes";
		return;
	}

	# tested
	if (    $file_types{"fastq"}
		and !grep { $_ ne "fastq" } keys %file_types
		and $layout =~ /SINGLE/i
		and not $is_barcode
		and not grep { $_->get_value eq "Technical Read" } @raw_files_comments )
	{

		INFO
"No spot decriptor needed for single read fastq files with no barcodes and no technical reads\n";
		return;
	}

	# Create all the other types of spot descriptor

	# tested
	my $barcode_spec;
	if ($is_barcode) {
		INFO "Creating barcode READ_SPEC\n";
		my @bc_table;
		my $index =
		  $self->get_required_comment( $assay_name, "BARCODE_READ_INDEX",
			@raw_files_comments );

		foreach my $extract (@extracts) {
			my $tag = $self->get_comment( $extract, "BARCODE" );
			my $basecall = { "BASECALL" => $tag, "read_group_tag" => $tag };
			push @bc_table, $basecall;
		}

		$barcode_spec = {
			"READ_INDEX"              => $index,
			"READ_LABEL"              => "Barcode Read",
			"READ_CLASS"              => "Technical Read",
			"READ_TYPE"               => "BarCode",
			"EXPECTED_BASECALL_TABLE" => \@bc_table
		};
	}

	my $forward_0_spec;
	$forward_0_spec = {
		"READ_INDEX" => 0,
		"READ_CLASS" => "Application Read",
		"READ_TYPE"  => "Forward",
		"BASE_COORD" => 1
	};

	# Illumina and SOLiD single are the same - tested
	if (    $layout =~ /SINGLE/i
		and $platform =~ /(Illumina|SOLiD)/i )
	{
		$forward_0_spec->{"SPOT_LENGTH"} =
		  $self->get_required_comment( $assay_name, "SPOT_LENGTH",
			@raw_files_comments );
		$self->add_spot_descriptor_from_spec_list( $forward_0_spec,
			$barcode_spec );
		return;
	}

	# Illumina paired - tested
	if (    $layout =~ /PAIRED/i
		and $platform =~ /Illumina/i )
	{
		my $coord =
		  $self->get_required_comment( $assay_name, "READ_INDEX_1_BASE_COORD",
			@raw_files_comments );
		my $spot_length =
		  $self->get_required_comment( $assay_name, "SPOT_LENGTH",
			@raw_files_comments );
		my $spec_0 = {
			"SPOT_LENGTH" => $spot_length,
			"READ_INDEX"  => 0,
			"READ_LABEL"  => "F",
			"READ_CLASS"  => "Application Read",
			"READ_TYPE"   => "Forward",
			"BASE_COORD"  => 1
		};
		my $spec_1 = {
			"READ_INDEX" => 1,
			"READ_LABEL" => "R",
			"READ_CLASS" => "Application Read",
			"READ_TYPE"  => "Reverse",
			"BASE_COORD" => $coord
		};
		$self->add_spot_descriptor_from_spec_list( $spec_0, $spec_1,
			$barcode_spec );
		return;
	}

	# SOLiD paired - tested
	if (    $layout =~ /PAIRED/i
		and $platform =~ /SOLiD/i )
	{
		$forward_0_spec->{"SPOT_LENGTH"} =
		  $self->get_required_comment( $assay_name, "SPOT_LENGTH",
			@raw_files_comments );
		my $coord =
		  $self->get_required_comment( $assay_name, "READ_INDEX_1_BASE_COORD",
			@raw_files_comments );
		my $spec_1 = {
			"READ_INDEX" => 1,
			"READ_CLASS" => "Application Read",
			"READ_TYPE"  => "Forward",
			"BASE_COORD" => $coord
		};
		$self->add_spot_descriptor_from_spec_list( $forward_0_spec, $spec_1,
			$barcode_spec );
		return;
	}

	# 454 single - tested
	if (    $layout =~ /SINGLE/i
		and $platform =~ /454/ )
	{
		my $spec_0 = {
			"READ_INDEX" => 0,
			"READ_CLASS" => "Technical Read",
			"READ_TYPE"  => "Adapter",
			"BASE_COORD" => 1
		};
		my $spec_1 = {
			"READ_INDEX" => 1,
			"READ_CLASS" => "Application Read",
			"READ_TYPE"  => "Forward",
			"BASE_COORD" => 5
		};
		$self->add_spot_descriptor_from_spec_list( $spec_0, $spec_1,
			$barcode_spec );
		return;
	}

	# 454 paired - tested
	if (    $layout =~ /PAIRED/i
		and $platform =~ /454/ )
	{
		my $linker =
		  $self->get_required_comment( $assay_name, "LINKER_BASECALL",
			@raw_files_comments );
		my $spec_0 = {
			"READ_INDEX" => 0,
			"READ_CLASS" => "Technical Read",
			"READ_TYPE"  => "Adapter",
			"BASE_COORD" => 1
		};
		my $spec_1 = {
			"READ_INDEX" => 1,
			"READ_CLASS" => "Application Read",
			"READ_TYPE"  => "Forward",
			"BASE_COORD" => 5
		};
		my $spec_2 = {
			"READ_INDEX"        => 2,
			"READ_CLASS"        => "Technical Read",
			"READ_TYPE"         => "Linker",
			"EXPECTED_BASECALL" => $linker
		};
		my $spec_3 = {
			"READ_INDEX"     => 3,
			"READ_CLASS"     => "Application Read",
			"READ_TYPE"      => "Reverse",
			"RELATIVE_ORDER" => { "follows_read_index" => 2 }
		};
		$self->add_spot_descriptor_from_spec_list( $spec_0, $spec_1, $spec_2,
			$spec_3, $barcode_spec );
		return;
	}

	# No standard spot descriptor for this technology
	ERROR(
		"no standard spot descriptor available for $platform assay $assay_name"
	);
	return;

}

sub get_required_comment {

	my ( $self, $item_name, $comment_name, @comments ) = @_;

	# TODO: assumes we never have multiple comments of same type
	my ($comment) = grep { $_->get_name eq $comment_name } @comments;

	if ($comment) {
		return $comment->get_value;
	}
	else {
		ERROR
"REQUIRED COMMENT MISSING: no $comment_name comment found for $item_name";
		return undef;
	}

}

sub add_spot_descriptor_from_spec_list {

	my ( $self, @spec_list ) = @_;

	my $xml = $self->get_xml_writer;

	$xml->startTag("SPOT_DESCRIPTOR");
	$xml->startTag("SPOT_DECODE_SPEC");

	my $spot_length = $spec_list[0]->{"SPOT_LENGTH"};
	if ($spot_length) {
		$xml->dataElement( "SPOT_LENGTH", $spot_length );
	}

	my @possible_elements = qw(
	  READ_INDEX
	  READ_LABEL
	  READ_CLASS
	  READ_TYPE
	  RELATIVE_ORDER
	  BASE_COORD
	  CYCLE_COORD
	  EXPECTED_BASECALL
	);

	foreach my $spec (@spec_list) {
		next unless $spec;
		$xml->startTag("READ_SPEC");
		foreach my $element (@possible_elements) {
			if ( exists $spec->{$element} ) {
				my $value = $spec->{$element};
				if ( ref($value) eq "HASH" ) {
					$xml->dataElement( $element, "", %$value );
				}
				else {
					$xml->dataElement( $element, $value );
				}
			}
		}
		my $ebt = "EXPECTED_BASECALL_TABLE";
		if ( exists $spec->{$ebt} ) {
			$xml->startTag($ebt);
			my $basecall_table = $spec->{$ebt};
			foreach my $basecall (@$basecall_table) {
				my $content = $basecall->{'BASECALL'};
				delete $basecall->{'BASECALL'};
				$xml->startTag( "BASECALL", %$basecall );
				$xml->characters($content);
				$xml->endTag;
			}
			$xml->endTag;
		}
		$xml->endTag;
	}

	$xml->endTag;
	$xml->endTag;

	return;
}

sub add_processing {
	my ( $self, $platform, $layout ) = @_;
	my $xml = $self->get_xml_writer;

	# PROCESSING deprecated in v1.2 (November 2010)
	# Empty element still needed
	$xml->emptyTag("PROCESSING");

}

sub get_assay_hardware {
	my ( $self, $assay_name ) = @_;

	# Get assay object and the find the associated hardware
	my $assay = $self->get_assay_from_name($assay_name);
	my $hw    = $self->get_protocol_hardware($assay);
	return $hw;
}

sub get_platform_from_hardware {
	my ( $self, $hw ) = @_;
	my $platform;
	my %plat_types = (
		ILLUMINA          => qr/^(Illumina|Solexa|HiSeq|NextSeq)/i,
		LS454             => qr/(454|GS)/i,
		HELICOS           => qr/Helicos/i,
		ABI_SOLID         => qr/^AB|SOLiD/,
		ION_TORRENT       => qr/^Ion/i,
		COMPLETE_GENOMICS => qr/Complete Genomics/i,
		OXFORD_NANOPORE   => qr/(MinION|GridION)/i
                PACBIO_SMRT       => qr/^PacBio/,
	);

	foreach my $type ( keys %plat_types ) {
		if ( $hw =~ $plat_types{$type} ) {
			$platform = $type;
			last;
		}
	}

	unless ($platform) {
		LOGDIE "Could not infer platform from hardware $hw";
	}
	return $platform;
}

sub add_required_elements {
	my ( $self, $plat, $assay_name ) = @_;
	my $xml   = $self->get_xml_writer;
	my $assay = $self->get_assay_from_name($assay_name);

	my %plat_elements = (
		ILLUMINA  => ["SPOT_COUNT"],
		LS454     => ["KEY_SEQUENCE"],
		ABI_SOLID => ["SPOT_COUNT"],
	);

	my @elements = @{ $plat_elements{$plat} || [] };
	foreach my $elem (@elements) {
		my $value = $self->get_comment( $assay, $elem );
		$xml->dataElement( $elem, $value ) if $value;
	}
}

sub get_factor_value_text {
	my ( $self, $fv ) = @_;

	my $fv_text;

	# For Measurement use value and unitNameCV or unitName
	# If not then use tern

	if ( my $measurement = $fv->get_measurement ) {
		my $unit = $measurement->get_unit;
		my $unit_name = $unit->get_value or $unit->get_category;
		$fv_text = $measurement->get_value . " " . $unit_name;
	}
	else {
		$fv_text = $fv->get_term->get_value;
	}

	return $fv_text;
}

sub get_fv_factor_name {
	my ( $self, $fv ) = @_;
	my @factor = $fv->get_factor;

	foreach my $factor (@factor) {
		my $fv_factor_name = $factor->get_name;

		if ($fv_factor_name) {
			return $fv_factor_name;
		}
		else {
			WARN("No ExperimentFactor identified for FactorValue");
			return undef;
		}
	}

}

sub add_experiment_attribute {
	my ( $self, $tag, $value ) = @_;
	my $xml = $self->get_xml_writer;

	$xml->startTag("EXPERIMENT_ATTRIBUTE");

	$xml->dataElement( "TAG",   $tag );
	$xml->dataElement( "VALUE", $value );

	$xml->endTag();
}

1;
