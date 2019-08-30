#!/usr/bin/env perl
#
# SRA_XML/RunSet.pm - create SRA xml from magetab
#
# Anna Farne, European Bioinformatics Institute, 2009
#
# $Id: RunSet.pm 2439 2012-05-31 15:06:53Z ehastings $

package EBI::FGPT::Converter::SRA_XML::RunSet;

use Moose;
use MooseX::FollowPBP;
use XML::Writer;
use File::Spec;
use Log::Log4perl qw(:easy);
use Data::Dumper;

extends 'EBI::FGPT::Converter::SRA_XML::XML';

has 'output_file' => ( is => 'rw', isa => 'Str' );
has 'extract_to_sample' =>
  ( is => 'rw', isa => 'HashRef', default => sub { {} } );
has 'assay_to_extract' =>
  ( is => 'rw', isa => 'HashRef', default => sub { {} } );
has 'skip_data' => ( is => 'rw', default => 'undef' );

sub BUILD {
	my $self = shift;

	# ensure output file have been supplied

	unless ( $self->get_output_file ) {
		LOGDIE "No output file supplied";
	}

	$self->set_schema_type("run");

	my $xml = $self->get_xml_writer;
	$xml->startTag('RUN_SET');

	$self->create_runs;
}

sub create_runs {
	my ($self) = @_;
	my %run_names;

	#for each file
	foreach my $file ( @{ $self->get_datafiles || [] } ) {

		my $assay      = $self->get_assay_from_file($file);
		my $assay_name = $assay->get_name;
		my $file_name  = $file->get_uri;
		$file_name =~ s/^file://g;

		# We need to know the layout and how many files we have per assay
		# so we can decide how many runs to create
		my @extracts  = @{ $self->get_assay_to_extract->{$assay_name} };
		my $extract   = $extracts[0];
		my $layout    = $self->get_comment( $extract, "LIBRARY_LAYOUT" );
		my @raw_files = $self->get_file_from_assay_name($assay_name);

		# Do not create runs for qual files, istead add them
		# to run with corresponding csfasta file
		next if ( $self->get_type($file_name) eq "SOLiD_native_qual" );

		# If the submission is paired and contains more than
		# one file per assay we create a run from the part of the
		# file name shared by both files
		if ( ($#raw_files) && ( $layout =~ /PAIRED/i ) ) {

			my $run_name = $file_name;
			$run_name =~
			  s/(1|2|F|R)(\.|_)(sequence\.txt|fq|fastq|csfasta)\.(gz|bz2)$//ig
			  or LOGWARN(
"Paired submission but file names do not match naming convention"
			  );

			$run_name =~ s/(_|\.)$//g;

			# Ensure we haven't already created this run
			unless ( exists $run_names{$run_name} ) {
				INFO "Creating paired run: $run_name" . "\n";
				$self->add_paired_run( $run_name, $file );
			}
			$run_names{$run_name} = 1;

		}

		# For everything else create one run per file
		else {
			$self->add_run($file);
		}

	}

}

sub add_paired_run {

	my ( $self, $run_name, $file ) = @_;

	my $xml       = $self->get_xml_writer;
	my $file_name = $file->get_uri;
	$file_name =~ s/^file://g;
	my $assay      = $self->get_assay_from_file($file);
	my $assay_name = $assay->get_name;
	my $performer  = $self->get_performer($assay);

	if ( !$performer ) {
		LOGDIE "No performer included in SDRF- run center cannot be added";
	}

	INFO
	  "Paired library with more than one raw data file per assay $assay_name";

	$xml->startTag(
		"RUN",
		alias      => $self->make_alias($run_name),
		run_center => $performer
	);
	$xml->emptyTag(
		"EXPERIMENT_REF",
		refname   => $self->make_alias($assay_name),
		refcenter => $self->get_center_name
	);

	if ( my $barcode = $self->get_comment( $file, "BARCODE" ) ) {

		# For barcoded find the associated sample
		my $sample = $self->get_sample_from_barcode( $assay, $barcode );
		my $sample_alias = $self->make_alias( $sample->get_name );
		$xml->startTag( "DATA_BLOCK", member_name => $sample_alias );
	}
	else {
		$xml->startTag("DATA_BLOCK");
	}

	$xml->startTag("FILES");

	my @raw_files = $self->get_file_from_assay_name($assay_name);

	my $forward_read;
	my $reverse_read;
	my $forward_qual;
	my $reverse_qual;

	my $forward_md5;
	my $reverse_md5;
	my $forward_qual_md5;
	my $reverse_qual_md5;

	my @reads;
	my $size = @raw_files;

	# Case where we have paired cfasta files
	if ( ( $raw_files[0]->get_uri ) =~ /(1|F)\.csfasta\.(gz|bz2)$/i ) {

		$forward_read = $raw_files[0]->get_uri;
		$forward_read =~ s/^file://g;
		$forward_md5 = $self->calculate_md5( $raw_files[0] );
		push @reads, $forward_read;

		foreach my $raw_files (@raw_files) {
			my $name = $raw_files->get_uri;
			$name =~ s/^file://g;
			if ( $name =~ /(2|R)\.csfasta\.gz$/i ) {
				$reverse_read = $name;
				$reverse_md5  = $self->calculate_md5($raw_files);
				push @reads, $reverse_read;
			}

			if ( $name =~ /(1|F)\.qual\.gz$/i ) {
				$forward_qual     = $name;
				$forward_qual_md5 = $self->calculate_md5($raw_files);

			}

			if ( $name =~ /(2|R)\.qual\.gz$/i ) {
				$reverse_qual     = $name;
				$reverse_qual_md5 = $self->calculate_md5($raw_files);
			}
		}

	}

	elsif ( $size > 2 ) {

		# this covers the case where we have an assay linked to mulitple files
		# which can happen if we have pooling/barcodes
		foreach my $rf (@raw_files) {
			if ( ( $rf->get_uri ) =~
/^file:$run_name(_|\.)(1|F)\.(_sequence.txt|fq|fastq)\.(gz|bz2)$/i
			  )
			{
				$forward_read = $rf->get_uri;
				$forward_read =~ s/^file://g;
				$forward_md5 = $self->calculate_md5($rf);
			}

			elsif ( ( $rf->get_uri ) =~
/^file:$run_name(_|\.)(2|R)\.(_sequence.txt|fq|fastq)\.(gz|bz2)$/i
			  )
			{
				$reverse_read = $rf->get_uri;
				$reverse_read =~ s/^file://g;
				$reverse_md5 = $self->calculate_md5($rf);

			}
		}

	}

	# Need to ensure _1 and _F are listed as the forward read
	elsif ( ( $raw_files[0]->get_uri ) =~
		/(1|F)\.(_sequence.txt|fq|fastq)\.(gz|bz2)$/i )
	{
		$forward_read = $raw_files[0]->get_uri;
		$forward_read =~ s/^file://g;
		$forward_md5 = $self->calculate_md5( $raw_files[0] );

		$reverse_read = $raw_files[1]->get_uri;
		$reverse_read =~ s/^file://g;
		$reverse_md5 = $self->calculate_md5( $raw_files[1] );
	}

	else {
		$forward_read = $raw_files[0]->get_uri;
		$forward_read =~ s/^file://g;
		$forward_md5 = $self->calculate_md5( $raw_files[0] );

		$reverse_read = $raw_files[1]->get_uri;
		$reverse_read =~ s/^file://g;
		$reverse_md5 = $self->calculate_md5( $raw_files[1] );

	}

	# Create our file blocks in xml
	$xml->startTag(
		"FILE",
		"filename"        => $forward_read,
		"filetype"        => $self->get_type($forward_read),
		"checksum_method" => "MD5",
		"checksum"        => $forward_md5
	);
	$xml->dataElement( "READ_LABEL", "F" );
	$xml->endTag;

	$xml->startTag(
		"FILE",
		"filename"        => $reverse_read,
		"filetype"        => $self->get_type($reverse_read),
		"checksum_method" => "MD5",
		"checksum"        => $reverse_md5
	);

	$xml->dataElement( "READ_LABEL", "R" );
	$xml->endTag;

	# For csfasta files find corresponding qual file and add

	if ($forward_qual) {
		$xml->startTag(
			"FILE",
			"filename"        => $forward_qual,
			"filetype"        => "SOLiD_native_qual",
			"checksum_method" => "MD5",
			"checksum"        => $forward_qual_md5
		);
		$xml->dataElement( "READ_LABEL", "F" );
		$xml->endTag;
	}

	if ($reverse_qual) {
		$xml->startTag(
			"FILE",
			"filename"        => $reverse_qual,
			"filetype"        => "SOLiD_native_qual",
			"checksum_method" => "MD5",
			"checksum"        => $reverse_qual_md5
		);
		$xml->dataElement( "READ_LABEL", "R" );
		$xml->endTag;
	}

	$xml->endTag;
	$xml->endTag;
	$xml->endTag;

}

sub add_run {
	my ( $self, $file ) = @_;
	my $xml = $self->get_xml_writer;

	my $file_name = $file->get_uri;
	$file_name =~ s/^file://g;
	my $assay      = $self->get_assay_from_file($file);
	my $assay_name = $assay->get_name;
	my $performer  = $self->get_performer($assay);

	$xml->startTag(
		"RUN",
		alias      => $self->make_alias($file_name),
		run_center => $performer
	);
	$xml->emptyTag(
		"EXPERIMENT_REF",
		refname   => $self->make_alias($assay_name),
		refcenter => $self->get_center_name
	);

	if ( my $barcode = $self->get_comment( $file, "BARCODE" ) ) {

		# For barcoded find the associated sample
		my $sample = $self->get_sample_from_barcode( $assay, $barcode );
		my $sample_alias = $self->make_alias( $sample->get_name );
		$xml->startTag( "DATA_BLOCK", member_name => $sample_alias );
	}
	else {
		$xml->startTag("DATA_BLOCK");
	}
	$xml->startTag("FILES");
	$xml->emptyTag(
		"FILE",
		"filename"        => $file_name,
		"filetype"        => $self->get_type($file_name),
		"checksum_method" => "MD5",
		"checksum"        => $self->calculate_md5($file)
	);

	# For csfasta files find corresponding qual file and add
	if ( $self->get_type($file_name) eq "SOLiD_native_csfasta" ) {
		my $qual_file = $self->find_file( "SOLiD_native_qual", $assay );
		my $qual_name = $qual_file->get_uri;
		$qual_name =~ s/^file://g;
		if ($qual_file) {
			$xml->emptyTag(
				"FILE",
				"filename"        => $qual_name,
				"filetype"        => "SOLiD_native_qual",
				"checksum_method" => "MD5",
				"checksum"        => $self->calculate_md5($qual_file)
			);
		}
	}

	$xml->endTag;
	$xml->endTag;
	$xml->endTag;

	# end of code for single reads

}

sub find_file {

	my ( $self, $type, $assay ) = @_;

	my $assay_name = $assay->get_name;
	INFO "Getting $type file for assay $assay_name";
	my @raw_files = $self->get_file_from_assay_name($assay_name);
	foreach my $raw_file (@raw_files) {
		my $name = $raw_file->get_uri;
		$name =~ s/^file://g;
		if ( $self->get_type($name) eq $type ) {
			return $raw_file;
		}

	}

	return;
}

sub get_type {
	my ( $self, $name ) = @_;

	my @accepted_types =
	  qw(srf sff fastq cram bam Illumina_native_qseq Illumina_native_scarf SOLiD_native_csfasta SOLiD_native_qual PacBio_HDF5 CompleteGenomics_native)
	  ;

	# Strip off .gz/bz2 before attempting to get type
	$name =~ s/\.gz//ig;
	$name =~ s/\.bz2//ig;
	my $type;

	if ( $name =~ /sequence.txt$/ ) {
		$type = "fastq";
	}

	else {
		$name =~ /.*\.([^\.]*)$/g;
		$type = $1;

		$type = lc($type);

		$type = "fastq"                if $type eq "fq";
		$type = "fastq"                if $type eq "sanfastq";
		$type = "SOLiD_native_csfasta" if $type eq "csfasta";
		$type = "SOLiD_native_qual"    if $type eq "qual";

		unless ( grep $type, @accepted_types ) {
			warn
"WARNING: file type $type not used by SRA, check the correct type is used";
		}
	}

	return $type;
}

sub get_sample_from_barcode {
	my ( $self, $assay, $barcode ) = @_;
	my $assay_name = $assay->get_name;
	my @extracts   = @{ $self->get_assay_to_extract->{$assay_name} || [] };

	foreach my $extract (@extracts) {
		my $bcode = $self->get_comment( $extract, "BARCODE" );
		if ( $bcode eq $barcode ) {
			my $samples = $self->get_extract_to_sample->{ $extract->get_name };

			# Script will already have died when creating ExperimentSet if
			# more than 1 sample per extract
			return $samples->[0];

		}
	}
	LOGDIE "No sample found for barcode $barcode";

}

1;
