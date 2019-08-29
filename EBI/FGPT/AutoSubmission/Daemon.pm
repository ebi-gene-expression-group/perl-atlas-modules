#!/usr/bin/env perl

=head1 NAME

EBI::FGPT::AutoSubmission::Daemon
 
=head1 DESCRIPTION

Module used to construct checker and exporter object

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

package EBI::FGPT::AutoSubmission::Daemon;

use Moose;
use MooseX::FollowPBP;
use namespace::autoclean;
use MIME::Lite;
use Proc::Daemon;
use POSIX qw(:sys_wait_h);
use Socket;
use IO::Socket;
use IO::Select;
use IO::Handle;
use English qw( -no_match_vars );
use Sys::Hostname;
use Log::Dispatch;
use Data::Dumper;

use EBI::FGPT::Config qw($CONFIG);
require ArrayExpress::AutoSubmission::DB::Experiment;

# These are only set upon initialization
has 'polling_interval' => ( is => 'rw', isa => 'Int', required => 1 );
has 'experiment_type'  => ( is => 'rw', isa => 'Str', required => 1, );
has 'accession_prefix' => ( is => 'rw', default => 'undef' );
has 'autosubs_admin' => ( is => 'rw', isa => 'Str', required => 1, );

# Optional for exporter daemons; the checker daemons will check that
# this is defined.
has 'pidfile'           => ( is => 'rw', isa => 'Str', default => 'undef' );
has 'checker_threshold' => ( is => 'rw', isa => 'Str', default => 'undef' );

# The log file names are manipulated post-init.
has 'logfile' => ( is => 'rw', isa => 'Str', default => 'undef' );

# Attribute holding a flag notifying the process that it should quit
has 'quit_when_done' => ( is => 'rw', isa => 'Bool', default => '0' );

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
		message => "Error: no polling_interval set\n"
	  )
	  unless ( $self->get_polling_interval() );

	$log->log_and_die(
		level   => 'alert',
		message => "Error: no experiment_type set\n"
	  )
	  unless ( $self->get_experiment_type() );

	$log->log_and_die(
		level   => 'alert',
		message => "Error: no autosubs_admin email set\n"
	  )
	  unless ( $self->get_autosubs_admin() );

	return;
}

sub run {

	my ($self) = @_;
	my $message;

	if ( $self->get_accession_prefix ) {
		my $prefix = $self->get_accession_prefix;
		ArrayExpress::AutoSubmission::DB::Experiment->accession_prefix($prefix);
	}

	# Check that there are no other processes running, if a pidfile
	# has been provided. Typically the checker daemons have a pidfile,
	# but the exporter daemons do not.

	if ( $self->get_pidfile && -f $self->get_pidfile ) {
		$message =
		  "Old pidfile exists another checker daemon may be running: "
		  . $self->get_pidfile . "\n";
		$log->log_and_die(
			level   => 'warn',
			message => $message
		);
	}

# Check that the right user has launched the process
# User should be $admin_user i.e. AUTOSUBS_ADMIN_USERNAME in the site configuration file.
	my $admin_user = $CONFIG->get_AUTOSUBS_ADMIN_USERNAME();

	if ($admin_user) {
		$log->info( getpwuid($<) . " starting daemons" );
		unless ( getpwuid($<) eq $admin_user ) {
			$message =
			    "Non-admin user: "
			  . getpwuid($<)
			  . " attempting to launch daemon processes\n";
			$log->log_and_die(
				level   => 'alert',
				message => $message
			);
		}
	}
	else {
		$log->log_and_die(
			level   => 'alert',
			message =>
"AUTOSUBS_ADMIN_USERNAME must be set to an admin username in the site configuration file\n"
		);
	}

	# Run as a daemon
	$log->info(
		"Starting daemon: " . $self->get_experiment_type() . " " . ref($self) );
	Proc::Daemon::Init;

	##########################
	### Exception handlers ###
	##########################

	# SIGTERM signal is a generic signal used to cause program termination
	# SIGQUIT signal is similar to SIGINT
	# SIGINT (program interrupt) signal
	# SIGSEGV signal indicates that a segment violation has taken place.
	#
	# 12 Apr 2016: suppress reporting all signals, apart from the
	# INT one 

	# $SIG{TERM} = sub { $self->alert_on_signal(@_) };      # 15
	# $SIG{QUIT} = sub { $self->alert_on_signal(@_) };      # 3
	# $SIG{SEGV} = sub { $self->alert_on_signal(@_) };      # 11
	$SIG{INT}  = sub { $self->alert_on_signal(@_) };      # 2
	$SIG{USR1} = sub { $self->set_quit_when_done(1) };    # 16

	# From here, all die()s should mail us a notification.
	# (12 Apr 2016) We decided emails about perl checker crashes
	# are no longer needed, so the next line about $SIG{__DIE__}
	# is commented out.
	# $SIG{__DIE__} = sub { $self->alert_admin(@_) };

	if ( $self->get_pidfile ) {

		# Create a file containing the process id ($$). This has to
		# happen after daemon forking, above.
		$message =
		    "Unable to open pidfile %s: %s "
		  . $self->get_pidfile . " "
		  . $! . "\n";

		open( my $pid, ">", $self->get_pidfile )
		  or $log->log_and_die(
			level   => 'alert',
			message => $message
		  );

		print $pid "$PROCESS_ID\n";
		close $pid
		  or $log->log_and_die(
			level   => 'alert',
			message => "$!" . "\n"
		  );
	}

	# The daemon starts via this entry point method

	$self->monitor_submissions();

	return;
}

# Signal handling subroutines
sub alert_admin {

	my ( $self, $error ) = @_;

	my $mailbody =
	    "The automatic experiment checking system ($PROCESS_ID) "
	  . "has crashed with the following error message: \n\n  $error\n\n";

	my $mail = MIME::Lite->new(
		From     => $self->get_autosubs_admin(),
		To       => $self->get_autosubs_admin(),
		Subject  => 'Crash notification',
		Type     => 'text/plain',
		Encoding => 'quoted-printable',
		Data     => $mailbody,
	);
	$mail->send();

	return;
}

sub alert_on_signal {

	my ( $self, $signal ) = @_;

	# Delete our PID file, if we're using one.
	my $pidfile = $self->get_pidfile;
	unlink $pidfile if ( defined $pidfile );

	# Call for help. NB if we die here we get two emails instead of
	# one. I assume that when this signal handler returns a die() is
	# invoked, not sure about that though.
	$self->alert_admin("Error: Signal SIG$signal received");

	# FIXME this is currently undetected by any parent processes.
	exit(255);
}

sub is_magetab_doc {

	# Tests for combined MAGETAB IDF+SDRF document versus IDF only,
	# returns true in the former case, false for the latter. Used in
	# both Daemon::Checker and Daemon::Exporter subclasses.

	my ( $self, $doc ) = @_;

	my $message = "Unable to open document " . $doc . ": $!" . "\n";
	open( my $fh, '<', $doc )
	  or $log->log_and_die(
		level   => 'alert',
		message => $message
	  );
	my ( $idf_found, $sdrf_found );
	while ( my $line = <$fh> ) {
		$idf_found++  if ( $line =~ m/\A \s* \"? \s* \[IDF\]/ixms );
		$sdrf_found++ if ( $line =~ m/\A \s* \"? \s* \[SDRF\]/ixms );
	}

	$message = "Unable to close document: " . $doc . "$!" . "\n";
	close($fh) or $log->log_and_die(
		level   => 'alert',
		message => $message
	);

	if ( $idf_found && $sdrf_found ) {
		return 1;
	}

	return;
}

sub monitor_submissions {
	$log->log_and_die(
		level   => 'alert',
		message => "Stub method called in abstract parent class\n"
	);
}

{

	# Think this is so oldout and olderr are used by both
	# - redirect_stdout_to_file
	# - restore_stdout_from_file
	my ( $oldout, $olderr );

	sub redirect_stdout_to_file {

		my ( $self, $logfile ) = @_;

		unless ( defined($logfile) ) {

			$log->log_and_die(
				level   => 'alert',
				message => "Undefined log file name\n"
			);

		}

		open( $oldout, '>&', \*STDOUT ) and seek( $oldout, 0, 0 );
		open( $olderr, '>&', \*STDERR ) and seek( $olderr, 0, 0 );

		open( STDOUT, '>', $logfile )
		  or $log->log_and_die(
			level   => 'alert',
			message => "Can't redirect STDOUT to logfile $logfile: $!" . "\n"
		  );

		open( STDERR, '>&', \*STDOUT )
		  or $log->log_and_die(
			level   => 'alert',
			message => "Can't redirect STDERR to STDOUT\n"
		  );

		*STDERR->autoflush();    # make unbuffered
		*STDOUT->autoflush();    # make unbuffered

		return;
	}

	sub restore_stdout_from_file {

		my ($self) = @_;

		unless ( $oldout && $olderr ) {
			$log->log_and_die(
				level   => 'alert',
				message =>
"STDOUT and STDERR not cached have you called redirect_stdout_to_file() yet?\n"
			);

		}

		( close(STDOUT) and open( STDOUT, '>&', $oldout ) )
		  or $log->log_and_die(
			level   => 'alert',
			message => "Can't restore STDOUT: $!" . "\n"
		  );

		( close(STDERR) and open( STDERR, '>&', $olderr ) )
		  or $log->log_and_die(
			level   => 'alert',
			message => "Can't restore STDERR: $!" . "\n"
		  );

		return;
	}
}

__PACKAGE__->meta->make_immutable;

1;
