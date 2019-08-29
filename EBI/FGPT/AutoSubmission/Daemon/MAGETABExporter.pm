#!/usr/bin/env perl

=head1 NAME

EBI::FGPT::AutoSubmission::Daemon::MAGETABExporter
 
=head1 DESCRIPTION

To launch exporting of MAGE-TAB submissions

=head1 AUTHOR

Written by Anna Farne and updated by Emma Hastings (2014) , <emma@ebi.ac.uk>
 
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

package EBI::FGPT::AutoSubmission::Daemon::MAGETABExporter;

use Moose;
use MooseX::FollowPBP;
use namespace::autoclean;
use English qw( -no_match_vars );
use Carp;
use POSIX qw(:sys_wait_h);
use Socket;
use IO::Socket;
use IO::Select;
use Sys::Hostname;
use Log::Dispatch;
use Data::Dumper;

use EBI::FGPT::Config qw($CONFIG);
use EBI::FGPT::Common qw(date_now ae2_load_dir_for_acc);
use ArrayExpress::AutoSubmission::AE2Exporter;
require ArrayExpress::AutoSubmission::DB::Experiment;

extends 'EBI::FGPT::AutoSubmission::Daemon';

has 'keep_protocol_accns' => ( is => 'rw', isa => 'Bool', required => 1 );
has 'pipeline_subdir'     => ( is => 'rw', isa => 'Str',  required => 1 );

my $log = Log::Dispatch->new(
	outputs => [
		[
			'Screen',
			min_level => 'debug',
			newline   => 1
		]
	],
);

sub monitor_submissions {
	my $self = shift;

	# Loop forever
  EVENT_LOOP:
	while (1) {

		# Create the accession cache object.
		my $iterator = ArrayExpress::AutoSubmission::DB::Experiment->search(
			experiment_type => $self->get_experiment_type(),
			status          => $CONFIG->get_STATUS_PASSED(),
			is_deleted      => 0,
		);

	  SUBMISSION:
		while ( my $submission = $iterator->next() ) {

			# Skip submissions by test user, or submissions without any user.
			next SUBMISSION
			  if ( !$submission->user_id()
				|| $submission->user_id()->login() eq 'test' );

			# Start a transaction.
			my $dbh = ArrayExpress::AutoSubmission::DB::Experiment->db_Main();
			$dbh->begin_work();

			# Get current status and a row-level read lock.
			my $current_status =
			  ArrayExpress::AutoSubmission::DB::Experiment
			  ->sql_status_for_update()->select_val( $submission->id() ) || q{};

			# Double-check, in case something changes in the meantime.
			unless ( $current_status eq $CONFIG->get_STATUS_PASSED() ) {
				$dbh->commit();
				next SUBMISSION;
			}

			# Set the status so a parallel daemon doesn't pick up.
			$submission->set(
				status              => $CONFIG->get_STATUS_AE2_EXPORT(),
				date_last_processed => date_now(),
			);
			$submission->update();

			# End the transaction.
			$dbh->commit();

			# New code to handle export to ae2 load dirs
			my $start_time = date_now();
			my $rc         = $self->export_magetab($submission);
			my $end_time   = date_now();

			if ( !$rc ) {    # Test for export success.
				my $acc      = $submission->get_accession;
				my $idf_path = File::Spec->catfile(
					ae2_load_dir_for_acc($acc),
					$acc . ".idf.txt",
				);
				$submission->set(
					status              => $CONFIG->get_STATUS_AE2_COMPLETE(),
					migration_status    => "Exported directly to AE2",
					date_last_processed => $end_time,
					file_to_load        => $idf_path,
				);
				$submission->update();
			}
			else {    # Export failed
				$submission->set(
					status => $CONFIG->get_STATUS_AE2_EXPORT_ERROR(),
					date_last_processed => $end_time,
					comment             => $submission->comment() . "\n\n$rc\n",
				);

				$submission->update();
				next SUBMISSION;
			}

			# Add an event to record this run.
			$submission->add_to_events(
				{
					event_type     => 'AE2 Export',
					was_successful => ( $rc ? 0 : 1 ),
					source_db      => $submission->experiment_type(),
					start_time     => $start_time,
					end_time       => $end_time,
					machine        => hostname(),
					operator       => $submission->curator(),
					log_file       => $self->get_logfile(),
					is_deleted     => 0,
				}
			);

			last EVENT_LOOP if $self->get_quit_when_done();

		}

		sleep( $self->get_polling_interval() * 60 );

		last EVENT_LOOP if $self->get_quit_when_done();

	}

	return;
}

sub export_magetab {

	my ( $self, $submission ) = @_;

	# Set up our sockets for parent-child communication
	socketpair( CHILD, PARENT, AF_UNIX, SOCK_STREAM, PF_UNSPEC )
	  or $log->log_and_die(
		level   => 'alert',
		message => "Cannot create socketpair: $!" . "\n"
	  );

	CHILD->autoflush(1);
	PARENT->autoflush(1);

	my $pid;
	my $selector = IO::Select->new();
	$selector->add( \*CHILD );

	my $exporter_signal;

	if ( $pid = fork ) {

		# Parent process code
		close PARENT;

		while ( my @handles = $selector->can_read ) {
			foreach my $handle (@handles) {
				recv( $handle, $exporter_signal, 1024, 0 );
			}
			last;
		}
		chomp $exporter_signal;

		close CHILD;
		waitpid( $pid, 0 );
	}

	else {

		# Child process code; must end with an exit

		$log->log_and_die(
			level   => 'alert',
			message => "Error: Cannot fork: $!" . "\n"
		  )
		  unless defined $pid;
		close CHILD;
		$PROGRAM_NAME .= '_child';

		my $spreadsheet = $submission->spreadsheets( is_deleted => 0 )->next();

		# Do some sanity checking on spreadsheet
		unless ($spreadsheet) {
			print PARENT "Error: No spreadsheet file provided for submission\n";
			close PARENT;
			exit;
		}
		my $ss_path = File::Spec->catfile( $submission->filesystem_directory(),
			$spreadsheet->name );
		unless ( -r $ss_path ) {
			print PARENT
			  "Error: Spreadsheet $ss_path not found or unreadable\n";
			close PARENT;
			exit;
		}

		# Create the MAGE-TAB exporter object for AE2
		my $exporter;
		$exporter = $self->create_ae2_exporter($submission);
		eval { $exporter->export(); };

		print PARENT ("$EVAL_ERROR\n");
		close PARENT;

		exit;
	}

	return $exporter_signal;    # non-zero is failure
}

sub create_ae2_exporter {
	my ( $self, $submission ) = @_;

	my $dir     = $submission->filesystem_directory;
	my $log     = File::Spec->catfile( $dir, "ae2_export.log" );
	my $tmp_dir = File::Spec->catdir( $dir, "ae2export" );

	my $spreadsheet = $submission->spreadsheets( is_deleted => 0 )->next();

	my $exporter = ArrayExpress::AutoSubmission::AE2Exporter->new(
		{
			accession        => $submission->get_accession,
			type             => "magetab",
			log_path         => $log,
			spreadsheet      => $spreadsheet->filesystem_path,
			data_dir         => $submission->unpack_directory,
			temp_dir         => $tmp_dir,
			keep_prot_accns  => $self->get_keep_protocol_accns(),
			prot_accn_prefix => "P-MTAB-",
		}
	);

	return $exporter;
}

__PACKAGE__->meta->make_immutable;
1;

