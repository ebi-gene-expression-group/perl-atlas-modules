#!/usr/bin/env perl
#
# SRA_XML/Analysis.pm - create SRA xml from magetab
#
# Emma Hastings, European Bioinformatics Institute, 2013
#

package EBI::FGPT::Converter::SRA_XML::Analysis;

use Moose;
use MooseX::FollowPBP;
use XML::Writer;
use File::Spec;
use Log::Log4perl qw(:easy);
use Data::Dumper;

extends 'EBI::FGPT::Converter::SRA_XML::XML';

has 'output_file'       => ( is => 'rw', isa => 'Str' );
has 'extract_to_sample' => ( is => 'rw', isa => 'HashRef', default => sub { {} } );
has 'assay_to_extract'  => ( is => 'rw', isa => 'HashRef', default => sub { {} } );
has 'skip_data' => ( is => 'rw', default => 'undef' );
has 'processed_datafiles' => ( is => 'rw', isa => 'ArrayRef', default => sub { [] } );

sub BUILD {
	my $self = shift;

	# ensure output file have been supplied

	unless ( $self->get_output_file ) {
		LOGDIE "No output file supplied";
	}

	$self->set_schema_type("analysis");

	my $xml = $self->get_xml_writer;
	$xml->startTag('ANALYSIS_SET');

	$self->create_analysis;
}

sub create_analysis {
	my ($self) = @_;
	my %analysis_names;

	#for each processed file
	foreach my $file ( @{ $self->get_processed_datafiles || [] } ) {

		my $norm = $self->get_norm_from_file($file);
		$self->add_analysis( $file, $norm );
	}
}

sub add_analysis {
	my ( $self, $file, $norm ) = @_;

	my $xml       = $self->get_xml_writer;
	my $file_name = $file->get_uri;
	$file_name =~ s/^file://g;
	my $norm_name = $norm->get_name;

	INFO("Creating analysis for file:$file_name and normalization:$norm_name");

	my $performer = $self->get_performer($norm);
	my $date      = $self->get_protocol_date($norm);

	$xml->startTag(
		"ANALYSIS",
		alias           => $self->make_alias($norm_name),
		center_name     => $self->get_center_name,
		broker_name     => "ArrayExpress",
		analysis_center => $performer,
		analysis_date   => $date
	);

	my ( $description, $title ) = $self->get_protocol_text($norm);

	$xml->dataElement( 'TITLE',       $title );
	$xml->dataElement( 'DESCRIPTION', $description );
	$xml->emptyTag(
		"STUDY_REF",
		refname   => $self->get_accession,
		refcenter => $self->get_center_name
	);

	my @samples = $self->get_samples($norm);
	foreach my $sample (@samples) {
		my @sample_for_norm = @$sample;
		foreach my $sample_for_norm (@sample_for_norm) {
			$xml->emptyTag(
				"SAMPLE_REF",
				refname   => $self->make_alias( $sample_for_norm->get_name ),
				refcenter => $self->get_center_name
			);

		}

	}
	WARN("Curator must add ANALYSIS_TYPE information");
	$xml->startTag("ANALYSIS_TYPE");

	my $file_type = $self->get_type($file_name);

	if ( $file_type eq "bam" ) {
		$xml->startTag("REFERENCE_ALIGNMENT");
	}

	if ( $file_type eq "vcf" ) {
		$xml->startTag("SEQUENCE_VARIATION");
	}

	$xml->startTag("ASSEMBLY");
	$xml->emptyTag(
		"STANDARD",
		"refname"   => "CURATOR ADD",
		"accession" => "CURATOR ADD"
	);

	$xml->endTag;

	$xml->emptyTag(
		"SEQUENCE",
		"accession" => "CURATOR ADD",
		"label"     => "CURATOR ADD"
	);

	$xml->endTag;
	$xml->endTag;

	$xml->startTag("FILES");
	$xml->emptyTag(
		"FILE",
		"filename"        => $file_name,
		"filetype"        => $self->get_type($file_name),
		"checksum_method" => "MD5",
		"checksum"        => $self->calculate_md5($file)
	);

	$xml->endTag;
	$xml->endTag;

}

sub get_protocol_date {

	my ( $self, $norm ) = @_;

	# Obtain sequecning protocol for assay
	my @inputEdges = $norm->get_inputEdges
	  or LOGDIE( "No Protocol application found for " . $norm->get_name );

	my $date;
	foreach my $inputEdge (@inputEdges) {
		my @prot_app = $inputEdge->get_protocolApplications;
		foreach my $prot_app (@prot_app) {
			$date = $prot_app->get_date;
		}

	}
	if ($date) { return $date; }

	else {
		WARN("No date for analysis found");
		return;
	}

}

sub get_type {
	my ( $self, $name ) = @_;

	my @accepted_types = qw(bam vcf);

	$name =~ /.*\.([^\.]*)$/g;
	my $type = $1;
	$type = lc($type);
	unless ( grep $type, @accepted_types ) {
		LOGDIE("File type $type not used by SRA for analysis xml");
	}
	return $type;
}

sub get_samples {
	my ( $self, $norm ) = @_;

	my $norm_name  = $norm->get_name;
	my @inputEdges = $norm->get_inputEdges;
	my $file;
	my @assay_names;
	my $assay;
	my $assay_name;
	INFO( "Getting samples linked to " . $norm_name );

	# Foreach nomalization we need to find the attahced
	# sample. Thus we find the assay and then work backwards
	# to extracts and then samples

	foreach my $inputEdge (@inputEdges) {

		my $node = $inputEdge->get_inputNode;

		if ( $node->isa("Bio::MAGETAB::DataFile") ) {
			$file       = $node;
			$assay      = $self->get_assay_from_file($file);
			$assay_name = $assay->get_name;
			push @assay_names, $assay_name;

		}

		else {
			$assay = $node;
			my $assay_name = $assay->get_name;
			push @assay_names, $assay_name;
		}

	}

	my @all_extracts;
	foreach my $a (@assay_names) {
		my @extracts = @{ $self->get_assay_to_extract->{$a} || [] };
		push @all_extracts, @extracts;
	}

	my @all_samples;
	foreach my $extract (@all_extracts) {
		my @samples = $self->get_extract_to_sample->{ $extract->get_name };
		push @all_samples, @samples;
	}
	return @all_samples;

}

1;
