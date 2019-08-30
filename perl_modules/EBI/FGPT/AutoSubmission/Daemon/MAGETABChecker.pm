#!/usr/bin/env perl

=head1 NAME

EBI::FGPT::AutoSubmission::Daemon::MAGETABChecker;
 
=head1 DESCRIPTION

To launch checking of MAGE-TAB submissions

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

package EBI::FGPT::AutoSubmission::Daemon::MAGETABChecker;

use Moose;
use MooseX::FollowPBP;
use namespace::autoclean;
use Archive::Tar;
use Archive::Zip;
use IO::Zlib;
use File::Spec;
use File::Find;
use File::Copy;
use Socket;
use IO::Socket;
use Cwd;
use English qw( -no_match_vars );
use Data::Dumper;
use Log::Dispatch;
use Sys::Hostname;
use Scalar::Util qw(looks_like_number);

use EBI::FGPT::Config qw($CONFIG);
use EBI::FGPT::Common qw(date_now);

require ArrayExpress::AutoSubmission::DB::Experiment;

extends 'EBI::FGPT::AutoSubmission::Daemon';

my $log = Log::Dispatch->new(
	outputs => [
		[
			'Screen',
			min_level => 'debug',
			newline   => 1
		]
	],
);

sub BUILD {
	my $self = shift;
	$log->log_and_die(
		level   => 'alert',
		message => "No checker_threshold set\n"
	  )
	  unless ( defined( $self->get_checker_threshold() ) );
	return;
}

sub monitor_submissions {
	my $self = shift;

	# Loop forever
  EVENT_LOOP:
	while (1) {

		# Get the list of all experiments in curation.
		my $new_results = ArrayExpress::AutoSubmission::DB::Experiment->search(
			in_curation     => 1,
			status          => $CONFIG->get_STATUS_PENDING(),
			experiment_type => $self->get_experiment_type(),
			is_deleted      => 0,
		);

		# Process the new submissions in order of id.
	  SUBMISSION:
		while ( my $submission = $new_results->next() ) {

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
			unless ( $current_status eq $CONFIG->get_STATUS_PENDING() ) {
				$dbh->commit();
				next SUBMISSION;
			}

			# Mark the submission as in checking.
			$submission->set(
				status              => $CONFIG->get_STATUS_CHECKING(),
				date_last_processed => date_now()
			);
			$submission->update();

			# End the transaction.
			$dbh->commit();

			# Iterate over all the data file archives, unpacking them.
			my $datafiles = $submission->data_files( is_deleted => 0 );

			# Note that data files are returned in order of their database id.
		  FILE:
			while ( my $file = $datafiles->next() ) {

				# Don't unpack a file more than once.
				next FILE if $file->is_unpacked();

				my $filepath = $file->filesystem_path();

				# If the file exists, do something with it.
				if ( -f $filepath ) {

				  # This area is prone to crashes, we want to trap them locally.
					local $EVAL_ERROR;

					# Process those files that Archive::Any can handle.

					if ( $filepath =~ m/\. (?:tar.gz|tgz|tar|zip) \z/ixms ) {
						eval { $self->unpack_archive( $file, $submission ) };
					}

					# Gzipped files can be mistaken for tarred
					# files. We handle them separately here.
					elsif ( my ($outfile) =
						( $filepath =~ m/(.*)\. (?:gz) \z/ixms ) )
					{
						eval {
							my $zlib_fh = new IO::Zlib;
							if ( $zlib_fh->open( $filepath, "rb" ) ) {
								open( my $output_fh, ">", $outfile )
								  or $log->error(
									"Opening gzip output file $outfile: $!");
								while ( my $line = <$zlib_fh> ) {
									print $output_fh $line;
								}

								$zlib_fh->close();
								close($output_fh)
								  or
								  $log->error("Error closing output file: $!");
							}
							move( $outfile, $submission->unpack_directory() )
							  or $log->error("Error moving file $outfile: $!");
						};
					}

					# All uncompressed or unrecognized files are just
					# copied to the unpack directory.
					else {
						eval {
							copy( $filepath, $submission->unpack_directory() )
							  or
							  $log->error("Error copying file $filepath: $!");
						};
					}

					# Check that there were no problems.
					if ($EVAL_ERROR) {
						$submission->set(
							status  => $CONFIG->get_STATUS_CRASHED(),
							comment => $submission->comment()
							  . "\n\nError: Unable to unpack file or archive: $filepath\n",
							date_last_processed => date_now(),
						);
						$submission->update();
						next SUBMISSION;
					}

					# Mark the file as unpacked in the database.
					$file->set( is_unpacked => 1 );
					$file->update();
				}
				else {

				 # File not found. Mark the submission as bad, skip to next one.
					$submission->set(
						status  => $CONFIG->get_STATUS_CRASHED(),
						comment => $submission->comment()
						  . "\n\nError: File in database not found on filesystem: $filepath\n",
						date_last_processed => date_now(),
					);
					$submission->update();
					next SUBMISSION;
				}
			} # while(my $file = $datafiles->next)

			# Only one spreadsheet per submission at this point.
			my $spreadsheet =
			  $submission->spreadsheets( is_deleted => 0 )->next();
            
			# Fail if no spreadsheet has been provided
			unless ($spreadsheet) {
				$submission->set(
					status  => $CONFIG->get_STATUS_CRASHED(),
					comment => $submission->comment()
					  . "\n\nError: No spreadsheet file provided for submission\n",
					date_last_processed => date_now(),
				);
				$submission->update();
				next SUBMISSION;
			}

			# Fail if spreadsheet is not found
			my $ss_name = $spreadsheet->name();
			my $ss_path =
			  File::Spec->catfile( $submission->filesystem_directory(),
				$ss_name );
			unless ( -r $ss_path ) {
				$submission->set(
					status  => $CONFIG->get_STATUS_CRASHED(),
					comment => $submission->comment()
					  . "\n\nError: Spreadsheet $ss_path not found or unreadable\n",
					date_last_processed => date_now(),
				);
				$submission->update();
				next SUBMISSION;
			}

			# Sort out the STDOUT logfile.
			my $logfile_string = $ss_name;
			$logfile_string =~ s/\.\w{3,4}$//;    # strip off the extension
			$self->set_logfile(
				File::Spec->catfile(
					$submission->filesystem_directory(),
					"expt_${logfile_string}_stdout.log"
				)
			);

			# Actually check the submission for errors. This also
			# updates the autosubs db.
			$self->check( $submission, $spreadsheet );

			last EVENT_LOOP if $self->get_quit_when_done();

		}

		sleep( $self->get_polling_interval() * 60 );

		last EVENT_LOOP if $self->get_quit_when_done();

	}

	return;
}

sub unpack_archive {

	my ( $self, $file, $submission ) = @_;

	my $filepath   = $file->filesystem_path();
	my $unpack_dir = $submission->unpack_directory();

	# Unpack the files into the appropriate directory. This should not
	# create a significant memory problem - files are written directly
	# to disk.
	my $starting_dir = getcwd();
	chdir $unpack_dir
	  or $log->error("Error changing to unpack directory $unpack_dir: $!");

	# Previously we used Archive::Any, however, memory requirements
	# necessitated that we make the selection ourselves. Maybe add
	# File::MMagic processing here as well as file extensions.
	if ( $filepath =~ m/\. (?:tar.gz|tgz|tar) \z/ixms ) {

		# Tar archive

		# In general the tar command suffers from fewer memory issues
		# than Archive::Tar, which loads each archived data file
		# completely into memory (not good for large files). We only
		# fall back to Archive::Tar when tar isn't available.
		my $rc = system("tar xvzf $filepath");

		if ($rc) {

			# Try again, using Archive::Tar. Trap any errors;
			# otherwise this daemon will crash silently.
			local $EVAL_ERROR;

			# Apparently this call dies quite a lot, presumably
			# trapped with an eval. However, to cut out the spurious
			# alert emails we temporarily deactivate the die signal
			# handler.
			my $sighandler = $SIG{__DIE__};
			delete $SIG{__DIE__};

			eval { Archive::Tar->extract_archive($filepath); };
			$SIG{__DIE__} = $sighandler if $sighandler;
			if ($EVAL_ERROR) {
				$log->error("Error extracting archive $filepath: $EVAL_ERROR");
			}
		}
	}
	elsif ( $filepath =~ m/\. (?:zip) \z/ixms ) {

		# Zip archive
		my $zip = Archive::Zip->new();
		my $rc  = $zip->read($filepath);
		if ($rc) {
			$log->error("Error reading zip file $filepath: $rc");
		}
		$rc = $zip->extractTree();
		if ($rc) {
			$log->error("Error extracting zip file $filepath: $rc");
		}
	}
	else {
		$log->error("Error: unrecognized file type for $filepath");
	}

	# We now want to flatten the directory structure.
	find(
		sub {
			if ( -f $_ && -o $_ ) {
				chmod( oct( $CONFIG->get_FILE_PERMISSIONS() ), $_ )
				  or $log->error("Error changing permissions on $_: $!");
				move( $_, $unpack_dir )
				  or $log->error("Error moving file $_: $!");
			}
			elsif ( -d $_ && -o $_ ) {
				chmod( oct( $CONFIG->get_DIR_PERMISSIONS() ), $_ )
				  or $log->error("Error changing permissions on $_: $!");
			}
		},
		$unpack_dir,
	);

	# Back out of the unpacking directory.
	chdir $starting_dir
	  or $log->error("Error changing back to original directory: $!");

	return;
}

sub check {
	my ( $self, $submission, $spreadsheet ) = @_;

	my $file = $spreadsheet->filesystem_path();
    
	# Some experiments need to be processed without parsing data files
	# Skip data file checks if use_native_datafiles flag is set
	my $skip_data = 1 if $submission->use_native_datafiles();

	# Parameters passed to checker
	my %checker_params;
	if ( $self->is_magetab_doc($file) ) {
		%checker_params = (
			magetab_doc      => $file,
			source_directory => $submission->unpack_directory(),
			skip_data_checks => $skip_data

		);
	}
	else {
		%checker_params = (
			idf              => $file,
			source_directory => $submission->unpack_directory(),
			skip_data_checks => $skip_data

		);
	}

	require EBI::FGPT::Reader::MAGETABChecker;

	$self->expt_check_submission( $submission,
		EBI::FGPT::Reader::MAGETABChecker->new( \%checker_params ) );

	return;
}

sub expt_check_submission {

	my ( $self, $submission, $checker ) = @_;

	my ( $checker_score, $consensus_software, $dw_score, $miame_score, $comment,
		$start_time, $end_time, )
	  = $self->run_checker($checker);

	#################################################################
	# Post-checking update of the database record for a submission. #
	#################################################################

	# Checker score 512 is reserved for checker crashes
	if ( $checker_score & $CONFIG->get_ERROR_CHECKERCRASH() ) {
		$submission->set(
			status  => $CONFIG->get_STATUS_CRASHED(),
			comment => $submission->comment()
			  . ( $comment ? "\n\n$comment\n" : q{} ),
			date_last_processed => $end_time,
		);
		$submission->update();

		# Give up at this point.
		return;
	}

	# Update the cache with the checker score etc.
	my $values = {
	   checker_score => $checker_score,
	   miame_score   => $miame_score,
	   comment       => $submission->comment()
	   . ( $comment ? "\n\n$comment\n" : q{} ),
	   date_last_processed => $end_time
	};
	$submission->set( %{ $values } );
	$submission->update();	

	# rpetry - Moved experiment accessioning out to the new Python process_subs.py script
	# Update the cache with the checker score etc.
	# my $accession = $submission->get_accession(
	#	{
	#		checker_score => $checker_score,
	#		miame_score   => $miame_score,
	#		comment       => $submission->comment()
	#		  . ( $comment ? "\n\n$comment\n" : q{} ),
	#		date_last_processed => $end_time,
	#	}
	#);
	# $submission->update();

	# Store software type only if we know it (to avoid overwriting
	# actual software type with "Unknown" when we have skipped data checks)
	if ($consensus_software) {
		$submission->set( software => $consensus_software );
		$submission->update();
	}

	# MAGETABChecker will return an atlas fail score from its
	# get_aedw_score method
	if ($dw_score) {
		$submission->set( atlas_fail_score => $dw_score );
		$submission->update;
	}

	# Add an event to record this run.
	$submission->add_to_events(
		{
			event_type     => 'Experiment Checker',
			was_successful =>
			  ( $checker_score & $CONFIG->get_ERROR_CHECKERCRASH() ? 0 : 1 ),
			source_db  => $submission->experiment_type(),
			start_time => $start_time,
			end_time   => $end_time,
			machine    => hostname(),
			operator   => $submission->curator(),
			log_file   => $self->get_logfile(),
			is_deleted => 0,
		}
	);

	# Check the returned info, act as necessary.
	if ( looks_like_number($checker_score)
		&& ( $checker_score <= $self->get_checker_threshold() ) )
	{

		# Submission passes checks - mark for export.
		$submission->set(
			status              => $CONFIG->get_STATUS_PASSED(),
			date_last_processed => $end_time,
		);
		$submission->update();
	}
	else {

		# Submission failed checks.
		$submission->set(
			status              => $CONFIG->get_STATUS_FAILED(),
			date_last_processed => $end_time,
		);
		$submission->update();
	}

	return;
}

sub run_checker {

	my ( $self, $checker, $validate ) = @_;

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

	# Launch a subprocess to check the submission and return a score.
	my ( $checker_score, $consensus_software, $dw_score, $miame_score,
		$comment );

	my $start_time = date_now();

	if ( $pid = fork ) {

		# Parent process code
		close PARENT;

		my $checker_signal;
		while ( my @handles = $selector->can_read ) {
			foreach my $handle (@handles) {
				recv( $handle, $checker_signal, 1024, 0 );
			}
			last;
		}

		# Post-process the child signal.
		chomp $checker_signal;
		(
			$checker_score, $consensus_software, $dw_score, $miame_score,
			$comment
		  )
		  = split /\t/, $checker_signal;

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

		$checker->set_clobber(1);

		# Redirect STDOUT and STDERR to our log file.
		my $logfile = $self->get_logfile()
		  or $log->error("Log file name not set");

		$self->redirect_stdout_to_file($logfile);

		# Run all the checks
		if ($validate) {
			eval { $checker->validate() };
		}
		else {
			eval { $checker->check(); };
		}

		# Communicate results with parent process
		if ($EVAL_ERROR) {

			# Checker score of 512 is reserved for checker crashes.
			print PARENT (
				join( "\t",
					$CONFIG->get_ERROR_CHECKERCRASH(),
					q{Unknown}, q{}, q{}, $EVAL_ERROR, ),
				"\n"
			);
		}
		else {

			my $result;

			if ($validate) {
				$result = $checker->get_validation_fail;
			}
			else {
				$result = $checker->get_error;
			}

			# Print out to the log.
			print STDOUT (
				"\n\nExperiment checker exit code: " . $result . "\n\n" );

			# Pass the results to parent.
			print PARENT (
				join( "\t",
					$result,
					$checker->get_miamexpress_software_type() || q{},
					$checker->get_aedw_score() ),
				"\n"
			);
		}
		close PARENT;

		# Restore STDOUT and STDERR.
		$self->restore_stdout_from_file();

		exit;    # quit the child

	}

	my $end_time = date_now();

	return ( $checker_score, $consensus_software, $dw_score, $miame_score,
		$comment, $start_time, $end_time, );

}

__PACKAGE__->meta->make_immutable;
1;
