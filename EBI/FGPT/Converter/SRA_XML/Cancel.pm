#!/usr/bin/env perl
#
# SRA_XML/Submission.pm - create SRA xml from magetab
#
# Anna Farne, European Bioinformatics Institute, 2009
#
# $Id: Submission.pm 2384 2011-10-25 15:48:23Z farne $

package EBI::FGPT::Converter::SRA_XML::Cancel;

use Moose;
use MooseX::FollowPBP;
use XML::Writer;
use Log::Log4perl qw(:easy);
use Data::Dumper;
use List::MoreUtils qw(uniq);

Log::Log4perl->easy_init( { level => $INFO, layout => '%-5p - %m%n' } );

extends 'EBI::FGPT::Converter::SRA_XML::XML';

has 'output_file' => ( is => 'rw', isa => 'Str' );

sub BUILD
{

	my $self = shift;

	# ensure output file have been supplied
	unless ( $self->get_output_file )
	{
		LOGDIE "No output file supplied";
	}

	$self->set_schema_type("submission");

	my $xml = $self->get_xml_writer;
	$xml->startTag(
		'SUBMISSION',
		alias       => $self->get_accession . "_cancel",
		center_name => $self->get_center_name,

	);
	$self->create_actions;

}

sub create_actions
{
	my ($self) = @_;

	# Cancel study
	my $experiment    = $self->get_experiment;
	my @study_acc     = $self->get_comment( $experiment, "SecondaryAccession" );
	my @ena_study_acc = grep ( /^ERP/, @study_acc );
	my @actions;

	if (@ena_study_acc)
	{
		foreach my $ena_study_acc (@ena_study_acc)
		{
			push @actions, [ 'CANCEL', target => $ena_study_acc ];
		}

	}

	else
	{
		LOGDIE "No ERP style study accession found in MAGE-TAB";
	}

	# Cancel samples
	my @sources = $self->get_biomaterials;
	my @sample_accs;

	if (@sources)
	{
		foreach my $source (@sources)
		{
			my @sample_acc_comment = $self->get_comment( $source, "ENA_SAMPLE" );
			push @sample_accs, @sample_acc_comment;

		}
		my @uniq_sample_accs = uniq(@sample_accs);
		foreach my $sample_acc (@uniq_sample_accs)
		{
			push @actions, [ 'CANCEL', target => $sample_acc ];
		}
	}

	else
	{
		LOGDIE "No sources found in MAGE-TAB, cannot get sample accessions";
	}

	# Cancel experiments
	my @assays = $self->get_assays;
	my @experiment_accs;
	if (@assays)
	{
		foreach my $assay (@assays)
		{
			my @assay_acc_comment = $self->get_comment( $assay, "ENA_EXPERIMENT" );
			push @experiment_accs, @assay_acc_comment;

		}

		my @uniq_exp_accs = uniq(@experiment_accs);
		foreach my $experiment_acc (@uniq_exp_accs)
		{
			push @actions, [ 'CANCEL', target => $experiment_acc ];
		}
	}

	else
	{
		LOGDIE "No assays found in MAGE-TAB, cannot get experiment accessions";
	}

	# Cancel runs
	my @scans = $self->get_scans;
	my @run_accs;

	if (@scans)
	{
		foreach my $scan (@scans)
		{
			my @scan_acc_comment = $self->get_comment( $scan, "ENA_RUN" );
			push @run_accs, @scan_acc_comment;

		}
		my @uniq_run_accs = uniq(@run_accs);
		foreach my $run_acc (@uniq_run_accs)
		{
			push @actions, [ 'CANCEL', target => $run_acc ];
		}
	}

	else
	{
		LOGDIE "No scans found in MAGE-TAB, cannot get run accessions";
	}

	$self->get_xml_writer->startTag('ACTIONS');

	foreach my $action (@actions)
	{
		$self->add_action($action);
	}

	$self->get_xml_writer->endTag;
}

sub add_action
{
	my ( $self, $action_ref ) = @_;

	$self->get_xml_writer->startTag('ACTION');

	$self->get_xml_writer->emptyTag(@$action_ref);

	$self->get_xml_writer->endTag;

}

1;
