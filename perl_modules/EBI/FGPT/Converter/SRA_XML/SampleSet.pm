#!/usr/bin/env perl
#
# SRA_XML/SampleSet.pm - create SRA xml from magetab
#
# Anna Farne, European Bioinformatics Institute, 2009
#
# $Id: SampleSet.pm 2359 2010-10-21 13:46:29Z farne $

package EBI::FGPT::Converter::SRA_XML::SampleSet;

use Moose;
use MooseX::FollowPBP;
use XML::Writer;
use Log::Log4perl qw(:easy);
use LWP::Simple qw($ua get);
use Data::Dumper;
use EBI::FGPT::Config qw($CONFIG);

extends 'EBI::FGPT::Converter::SRA_XML::XML';

has 'output_file'    => ( is => 'rw', isa => 'Str' );
has 'taxon_ids'      => ( is => 'rw', isa => 'HashRef', default => sub { {} } );
has 'sample_created' => ( is => 'rw', isa => 'HashRef', default => sub { {} } );

sub BUILD {

	my $self = shift;

	if ( my $proxy =$CONFIG->get_HTTP_PROXY ) {
		$ua->proxy( ['http'], $proxy );
	}

	# ensure output file have been supplied

	unless ( $self->get_output_file ) {
		LOGDIE "No output file supplied";
	}

	$self->set_schema_type("sample");

	my $xml = $self->get_xml_writer;
	$xml->startTag('SAMPLE_SET');

	$self->create_samples;
}

sub create_samples {
	my ($self) = @_;

	my %assay_to_fvs;

	# Find all samples and store assay to sample relationship
	my @assays = $self->get_assays;

	INFO "Creating samples..BEWARE Pooling is not handled by this script";

	# For each assay get its edge and then the edges node
	# Pooling is not handled by these scripts thus curator will have to
	# check xmls and ensure submission is represented correctly 
	foreach my $assay (@assays) {
		my $assay_name = $assay->get_name;
		my @inputEdges = $assay->get_inputEdges;

		foreach my $inputEdge (@inputEdges) {
			my $material = $inputEdge->get_inputNode;
			$self->get_sources_and_extracts( $assay_name, $material );

			#Get factor values for each row
			my @sdrfRows = $assay->get_sdrfRows;
			foreach my $sdrfRows (@sdrfRows) {
				$assay_to_fvs{$assay_name} = $sdrfRows->get_factorValues;
			}

		}

	}

	my $extract_to_sample = $self->get_extract_to_sample;
	my $assay_to_extract  = $self->get_assay_to_extract;

	foreach my $as ( keys %$assay_to_extract ) {
		my $fvs = $assay_to_fvs{$as};
		foreach my $extract ( @{ $assay_to_extract->{$as} } ) {
			foreach my $sample ( @{ $extract_to_sample->{ $extract->get_name } } ) {
				$self->add_sample($sample);
			}
		}
	}

	# Store assay to FV list for use in experiment xml
	$self->set_assay_to_fvs( \%assay_to_fvs );

	return;
}

sub get_sources_and_extracts {
	my ( $self, $assay_name, $material, $seen, $extract_name ) = @_;

	my $extract_to_sample = $self->get_extract_to_sample;
	my $assay_to_extract  = $self->get_assay_to_extract;

	$seen ||= {};
	my $id = ref($material) . ":" . $material->get_name;

	# Store any extracts used by the assay
	if ( $material->isa("Bio::MAGETAB::Extract") ) {
		$assay_to_extract->{$assay_name} ||= [];
		push @{ $assay_to_extract->{$assay_name} }, $material unless $seen->{$id};
		$extract_name = $material->get_name;
	}

	my $inputEdges = $material->get_inputEdges;

	unless ($inputEdges) {

		# If the object has no treatments it must be the source material
		$extract_to_sample->{$extract_name} ||= [];
		unless ( $seen->{$id} ) {

			# Check we've not already mapped the extract to sample when
			# processing a previous assay before adding to mapping hash
			unless ( grep { $_->get_name eq $material->get_name }
				@{ $extract_to_sample->{$extract_name} } )
			{
				push @{ $extract_to_sample->{$extract_name} }, $material;
				INFO( "Found source: " . $material->get_name . "\n" );
			}
		}
		$seen->{$id} = 1;
		return;
	}

	# Check for possible loops or repetitions using seen hashref
	if ( $seen->{$id} ) {

		# We've dealt with this already so skip it
		return;
	}
	else {
		$seen->{$id} = 1;
	}

	# Otherwise get source materials from treatment and search for their sources
	foreach my $edge (@$inputEdges) {
		my $material = $edge->get_inputNode;
		$self->get_sources_and_extracts( $assay_name, $material, $seen, $extract_name );
	}

	return;
}

sub add_sample {
	my ( $self, $sample ) = @_;

	$sample->isa("Bio::MAGETAB::Material")
	  or LOGDIE "Argument passed to add_sample must be a BioMaterial object - this is a "
	  . ref($sample);

	my $alias = $self->make_alias( $sample->get_name );

	# Keep track of samples that have already been created to avoid
	# creating duplicates
	if ( $self->get_sample_created->{$alias} ) {
		INFO "Sample $alias has already been created - skipping";
		return;
	}
	$self->get_sample_created->{$alias} = 1;

	my $xml = $self->get_xml_writer;

	$xml->startTag( "SAMPLE", alias => $alias );
	$xml->dataElement( "TITLE", $sample->get_name );

	# Get description
	my $descr_text = $sample->get_description;

	# Add protocol text to description
	my $prot_text = $self->get_sample_protocol_text($sample);
	if ($prot_text) {
		$descr_text .= " Protocols:" . $prot_text;
	}
	
	# Store list of characteristics and measurements associated with material
	my @char_atts        = @{ $sample->get_characteristics || [] };
	my @measurement_atts = @{ $sample->get_measurements    || [] };

	if (@char_atts) {

		# Find and add species information
		my @org_atts = grep { $_->get_category =~ /^Organism$/i } @char_atts;
		if ( $org_atts[0] ) {
			my $name = $org_atts[0];
			$xml->startTag("SAMPLE_NAME");
			$xml->dataElement( "TAXON_ID",        $self->get_species_id($name) );
			$xml->dataElement( "SCIENTIFIC_NAME", $name->get_value );
			$xml->endTag;
		}

		# Add description if available
		if ($descr_text) {
			$xml->dataElement( "DESCRIPTION", $descr_text );
		}

		# Add characteristics as sample attributes
		$xml->startTag("SAMPLE_ATTRIBUTES");

		foreach my $char_att (@char_atts) {
			$self->add_sample_attribute( $char_att->get_category, $char_att->get_value );
		}
		
		# Add measurements as sample attributes i.e. age 
		if (@measurement_atts) {
			foreach my $measurement_atts (@measurement_atts) {
				my $value=$measurement_atts->get_value;
				my $unit=$measurement_atts->get_unit->get_value;
				my $measurement=$value." ".$unit;
				$self->add_sample_attribute( $measurement_atts->get_measurementType, $measurement );
			}
		}

		$xml->endTag;
	}
	else {

		# Add description if available
		if ($descr_text) {
			$xml->dataElement( "DESCRIPTION", $descr_text );
		}

		WARN( "No characteristics identified for sample " . $sample->get_name . "\n" );
	}

	$xml->endTag();
}

sub get_sample_protocol_text {
	my ( $self, $sample ) = @_;
	my $prot_text;

	if ( $sample->isa("Bio::MAGETAB::Sample") ) {

		my @inputEdges = $sample->get_inputEdges;
		foreach my $inputEdge (@inputEdges) {
			my $material = $inputEdge->get_inputNode;

			if ( $material->isa("Bio::MAGETAB::Source")
				and ( $material->get_name eq $sample->get_name ) )
			{

				# Get protocols associated with created biomaterial
				$prot_text = $self->get_protocol_text($material);
				return $prot_text;
			}

		}
	}

	elsif ( $sample->isa("Bio::MAGETAB::Source") ) {
		$prot_text = $self->get_protocol_text($sample);
		return $prot_text;
	}

	else {
		return undef;
		WARN "No sample protocol identified";
	}

}

sub add_sample_attribute {
	my ( $self, $tag, $value ) = @_;
	my $xml = $self->get_xml_writer;

	$xml->startTag("SAMPLE_ATTRIBUTE");

	$xml->dataElement( "TAG",   $tag );
	$xml->dataElement( "VALUE", $value );

	$xml->endTag();
}

sub get_species_id {
	my ( $self, $name ) = @_;
	my $id;

	my $species = $name->get_value;

	# See if we've already done this search
	my %taxon_ids = %{ $self->get_taxon_ids };
	if ( exists $taxon_ids{$species} ) {
		return $taxon_ids{$species};
	}

	my $uri =
	  "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=taxonomy&term="
	  . $species;
	my $result = get($uri);
	if ($result) {
		$_ = $result;
		my @ids = /<Id>(\d*)<\/Id>/g;
		$id = $ids[0];
		if ($#ids) {
			WARN( "more than 1 taxon id found for species " . $name->get_value );
		}
	}
	else {
		WARN("eutils taxonomy query failed");
	}

	unless ($id) {
		WARN( "no taxon id found for species " . $name->get_value );
	}

	$self->get_taxon_ids->{$species} = $id;
	return $id;
}

1;
