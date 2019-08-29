#!/usr/bin/env perl
#
# SRA_XML/Study.pm - create SRA xml from magetab
#
# Anna Farne, European Bioinformatics Institute, 2009
#
# $Id: Study.pm 2346 2010-09-27 08:34:52Z farne $

package EBI::FGPT::Converter::SRA_XML::Study;

use Moose;
use MooseX::FollowPBP;
use XML::Writer;
use Log::Log4perl qw(:easy);
use Data::Dumper;

extends 'EBI::FGPT::Converter::SRA_XML::XML';

has 'output_file' => ( is => 'rw', isa => 'Str' );

sub BUILD {

	my $self = shift;

	# ensure output file have been supplied
	unless ( $self->get_output_file ) {
		LOGDIE "No output file supplied";
	}

	$self->set_schema_type("study");

	my $xml = $self->get_xml_writer;
	$xml->startTag('STUDY_SET');

	$self->add_study;

}

sub add_study {
	my ($self) = @_;

	my $xml = $self->get_xml_writer;
	$xml->startTag( 'STUDY', alias => $self->get_accession );

	$self->create_descriptor;
	$self->create_links;
	$xml->endTag;
}

sub create_descriptor {
	my ($self) = @_;

	my $experiment = $self->get_experiment;

	my $title = $experiment->get_title;
	my ( $type, $descr ) = $self->get_study_type_and_descr;

	if ( $type eq "Other" ) { WARN "Other added as design type to study xml"; }

	my $xml = $self->get_xml_writer;

	$xml->startTag('DESCRIPTOR');

	$xml->dataElement( 'STUDY_TITLE', $title );

	$xml->emptyTag( 'STUDY_TYPE', existing_study_type => $type );

	$xml->dataElement( 'STUDY_ABSTRACT', $descr );

	$xml->dataElement( 'CENTER_NAME', $self->get_center_name );

	$xml->dataElement( 'CENTER_PROJECT_NAME', $title );

	$xml->dataElement( 'PROJECT_ID', "0" );

	$xml->dataElement( 'STUDY_DESCRIPTION', $descr );

	$xml->endTag()

}

sub create_links {
	my ($self) = @_;

	# Create link back to AE
	my $ae_link = "http://www.ebi.ac.uk/arrayexpress/experiments/" . $self->get_accession;

	# Attempt to get pubmed and doi IDs
	my ( $pubmed, $doi ) = $self->get_pubmed_and_doi;
	my $doi_link;
	if ($doi) {
		$doi_link = "http://dx.doi.org/" . $doi;
	}

	$self->get_xml_writer->startTag("STUDY_LINKS");

	# Add available links
	INFO "Adding links to study xml";
	$self->add_link( $self->get_accession . " in ArrayExpress", $ae_link );
	$self->add_link( "Publication DOI", $doi_link ) if $doi;
	$self->add_xref_link( "PUBMED", $pubmed ) if $pubmed;

	$self->get_xml_writer->endTag();

}

sub get_pubmed_and_doi {
	my ($self) = @_;
	my $experiment = $self->get_experiment;
	my $pubmed;
	my $doi;

	INFO "Checking for publication details- if found will be added to study xml";
	foreach my $publication ( @{ $experiment->get_publications || [] } ) {

		$pubmed = $publication->get_pubMedID;
		$doi    = $publication->get_DOI;

	}

	# TODO: if there are mutliple pubmed accs or DOIs then only the last
	# one found will be returned

	return $pubmed, $doi;
}

sub add_link {
	my ( $self, $label, $url ) = @_;

	my $xml = $self->get_xml_writer;

	# Add URL_LINK xml
	$xml->startTag("STUDY_LINK");
	$xml->startTag("URL_LINK");

	$xml->dataElement( "LABEL", $label );

	$xml->dataElement( "URL", $url );

	$xml->endTag();
	$xml->endTag();
}

sub add_entrez_link {
	my ( $self, $db, $id ) = @_;

	my $xml = $self->get_xml_writer;

	# Add ENTREZ_LINK xml
	$xml->startTag("STUDY_LINK");
	$xml->startTag("ENTREZ_LINK");

	$xml->dataElement( "DB", $db );

	$xml->dataElement( "ID", $id );

	$xml->endTag();
	$xml->endTag();

}

sub add_xref_link {
	my ( $self, $db, $id ) = @_;

	my $xml = $self->get_xml_writer;

	$xml->startTag("STUDY_LINK");
	$xml->startTag("XREF_LINK");

	$xml->dataElement( "DB", $db );

	$xml->dataElement( "ID", $id );

	$xml->endTag();
	$xml->endTag();

}

sub get_study_type_and_descr {
	my ($self) = @_;
	INFO "Mapping study type";

	# Map of EFO design types to SRA study types
	#	my %oe_to_type = (
	#		"co-expression_design"               => "RNASeq",
	#		"binding_site_identification_design" => "Gene Regulation Study",
	#	);

	my %oe_to_type = (
		"RNA-seq of coding RNA"     => "RNASeq",
		"RNA-seq of non coding RNA" => "RNASeq",
		"ChIP-seq"                  => "Gene Regulation Study",
		"CLIP-seq"                  => "Gene Regulation Study"
	);

	my $experiment = $self->get_experiment;

	# Store experiment description text (we assume only 1 description has text)
	my $description = $experiment->get_description;

	# If design type maps to SRA study type return the study type
	my @types = @{ $experiment->get_comments || [] };
	foreach my $oe (@types) {
		my $value = $oe->get_value;
		if ( my $study_type = $oe_to_type{$value} ) {
			return $study_type, $description;
		}
	}

	# If design type not mapped then use Other
	return "Other", $description;
}

1;
