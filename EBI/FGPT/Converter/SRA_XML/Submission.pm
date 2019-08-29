#!/usr/bin/env perl
#
# SRA_XML/Submission.pm - create SRA xml from magetab
#
# Anna Farne, European Bioinformatics Institute, 2009
#
# $Id: Submission.pm 2384 2011-10-25 15:48:23Z farne $

package EBI::FGPT::Converter::SRA_XML::Submission;

use Moose;
use MooseX::FollowPBP;
use XML::Writer;
use Log::Log4perl qw(:easy);

Log::Log4perl->easy_init( { level => $INFO, layout => '%-5p - %m%n' } );

extends 'EBI::FGPT::Converter::SRA_XML::XML';

has 'output_file' => ( is => 'rw', isa => 'Str' );
has 'analysis' => ( is => 'rw', default => 'undef' );

sub BUILD {

	my $self = shift;

	# ensure output file have been supplied

	unless ( $self->get_output_file ) {
		LOGDIE "No output file supplied";
	}

	$self->set_schema_type("submission");

	my $xml = $self->get_xml_writer;
	$xml->startTag(
		'SUBMISSION',
		alias       => $self->get_accession,
		center_name => $self->get_center_name,
		broker_name => "ArrayExpress"

	);
	$self->create_contacts;
	$self->create_actions;

}

sub create_contacts {

	my ($self)          = @_;
	my $submitter_found = 0;
	my @contacts        = $self->get_magetab->get_contacts;
	if (@contacts) {
		$self->get_xml_writer->startTag('CONTACTS');

		#Only create contact if its a submitter
		foreach my $contact (@contacts) {
			my @roles = $contact->get_roles;

			foreach my $role (@roles) {

				if ( $role->get_value eq "submitter" ) {
					$self->add_contact($contact);
					$submitter_found = 1;
					INFO "Adding submitter contact details";
				}

			}

		}

		if ( $submitter_found == 0 ) {
			WARN "Submitter not identified check contact added to submission xml";
		}
		$self->get_xml_writer->endTag();
	}

}

sub add_contact {
	my ( $self, $contact ) = @_;

	my ( $name, $email );

	if ( ( $contact->get_firstName ) && ( $contact->get_lastName ) ) {

		if ( $contact->get_midInitials ) {
			$name = join " ", $contact->get_firstName, $contact->get_midInitials,
			  $contact->get_lastName;
			$name =~ s/\s{2,}/ /g;
		}
		else {
			$name = join " ", $contact->get_firstName, $contact->get_lastName;
			$name =~ s/\s{2,}/ /g;
		}

	}

	else {
		$name = $contact->get_organization;
	}

	$self->get_xml_writer->emptyTag( 'CONTACT', name => $name );
}

sub create_actions {
	my ($self) = @_;

	my @actions = (
		[ 'ADD', source => $self->get_accession . "_study.xml",  schema => "study" ],
		[ 'ADD', source => $self->get_accession . "_sample.xml", schema => "sample" ],
		[
			'ADD',
			source => $self->get_accession . "_experiment.xml",
			schema => "experiment"
		],
		[ 'ADD', source => $self->get_accession . "_run.xml", schema => "run" ]
	);

	my $experiment   = $self->get_experiment;
	my $release_date = $experiment->get_publicReleaseDate;

	#remove time from date
	$release_date =~ s/T.+$//g;

	if ($release_date) {
		push @actions, [ 'HOLD', HoldUntilDate => $release_date ];
	}
	else {
		WARN "No release date set\n";
	}

	$self->get_xml_writer->startTag('ACTIONS');

	if ( $self->get_analysis ) {
		push @actions,
		  [
			'ADD',
			source => $self->get_accession . "_analysis.xml",
			schema => "analysis"
		  ];
	}
	foreach my $action (@actions) {
		$self->add_action($action);
	}

	$self->get_xml_writer->endTag;
}

sub add_action {
	my ( $self, $action_ref ) = @_;

	$self->get_xml_writer->startTag('ACTION');

	$self->get_xml_writer->emptyTag(@$action_ref);

	$self->get_xml_writer->endTag;

}

1;
