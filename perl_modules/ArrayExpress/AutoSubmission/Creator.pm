#!/usr/bin/env perl
#
# Module used to create new submissions in the absence of a Webform.
#
# Tim Rayner 2007, ArrayExpress team, European Bioinformatics Institute
#
# $Id: Creator.pm 2391 2011-12-06 13:42:07Z nata_courby $
#

package ArrayExpress::AutoSubmission::Creator;

use strict;
use warnings;

use Carp;
use Class::Std;
use File::Copy;
use File::Basename;
use File::Spec;
use MIME::Lite;
use English qw( -no_match_vars );
use Log::Log4perl qw(:easy);

use EBI::FGPT::Common qw(date_now);
use EBI::FGPT::Config qw($CONFIG);

require ArrayExpress::AutoSubmission::DB::Experiment;
require ArrayExpress::AutoSubmission::DB::User;
require ArrayExpress::AutoSubmission::DB::Organism;
require ArrayExpress::AutoSubmission::DB::DataFile;
require ArrayExpress::AutoSubmission::DB::Spreadsheet;

Log::Log4perl->easy_init( { level => $INFO, layout => '%-5p - %m%n' } );

my %login             : ATTR(:name<login>,             :init_arg<login>,             :default<undef>);
my %name              : ATTR(:name<name>,              :init_arg<name>,              :default<undef>);
my %spreadsheet       : ATTR(:name<spreadsheet>,       :init_arg<spreadsheet>,       :default<undef>);
my %data_files        : ATTR(:name<data_files>,        :init_arg<data_files>,        :default<[]>);
my %accession         : ATTR(:name<accession>,         :init_arg<accession>,         :default<undef>);
my %comment           : ATTR(:name<comment>,           :init_arg<comment>,           :default<undef>);
my %experiment_type   : ATTR(:name<experiment_type>,   :init_arg<experiment_type>,   :default<undef>);
my %clobber           : ATTR(:name<clobber>,           :init_arg<clobber>,           :default<0>);
my %notify            : ATTR(:name<notify>,            :init_arg<notify>,            :default<0>);
my %organisms         : ATTR(:name<organisms>,         :init_arg<organisms>,         :default<[]>);
my %user              : ATTR();
my %experiment        : ATTR();

sub START {
    my ( $self, $id, $args ) = @_;

    # Basic usage validation.
    croak("Error: no login set")
	unless ( $self->get_login() );

    croak("Error: no name set")
	unless ( $self->get_name() );

    croak("Error: no spreadsheet set")
	unless ( $self->get_spreadsheet() );

    croak("Error: no experiment_type set")
	unless ( $self->get_experiment_type() );

    croak("Error: data_files must be an array reference")
	unless ( ref( $self->get_data_files() ) eq 'ARRAY' );

    croak("Error: organisms must be an array reference")
	unless ( ref( $self->get_organisms() ) eq 'ARRAY' );

    return;
}

sub _get_user_approval : PRIVATE {

    my ( $self, $message ) = @_;

    #Natalja: sraimport is automated pipeline - skip all interaction with user
    if (!($self->get_login() eq "sraimport")){
    	print STDERR $message;
    	chomp( my $response = lc <STDIN> );

    	if ($response eq 'y') { return 1 }

    	return;
    }
    else {
	return 1;
    }
}

{   # Create a closure over this array.
    my @pass_chars = ( 'A'..'Z', 'a'..'z', 0..9 );

    sub mk_passwd {

	my $self = shift;

	# Simply returns a random string suitable for use as a
	# password. Can pass an optional length argument, otherwise
	# defaults to eight chars.

	my $length = shift || 8;

	my $password = q{};
	for ( 1..$length ) {
	    $password .= $pass_chars[int rand(scalar @pass_chars)];
	}
	return $password;
    }
}

sub insert_spreadsheet {

    my $self = shift;

    my $expt = $self->get_experiment();

    my $spreadsheet = basename($self->get_spreadsheet());

    my $target_file = File::Spec->catfile(
        $expt->filesystem_directory(),
        $spreadsheet,
    );

    # Ask what to do for preexisting files.
    if ( -e $target_file ) {

        if ( $self->get_clobber()
          || $self->_get_user_approval(
              "Warning: submission has pre-existing file $target_file. Overwrite [y/N] ? ") ) {

            unlink($target_file)
            or die("Error removing old spreadsheet $target_file: $!");
        }
        else{
            WARN("Skipping insertion of spreadsheet $spreadsheet.\n");
            return;
        }
    }

    # Make sure we don't end up with multiple spreadsheets mapped to
    # the submission. Note that we don't clean up the filesystem, just
    # the DB mapping.
    my $ss_iterator = $expt->spreadsheets(is_deleted => 0);
    while ( my $old_spreadsheet = $ss_iterator->next() ) {
        $old_spreadsheet->set('is_deleted' => 1);
        $old_spreadsheet->update();
    }

    # Write out the new spreadsheet, enter it into the DB and fix the
    # permissions (no basename on copy).
    INFO( "Copying MAGE-TAB to $target_file ..." );
    copy($self->get_spreadsheet(), $target_file)
        or LOGDIE( "Problem copying spreadsheet to submissions directory: $!");
    INFO( "MAGE-TAB copied successfully." );

    chmod(oct($CONFIG->get_FILE_PERMISSIONS()), $target_file)
        or WARN("Problem setting permissions on spreadsheet $target_file: $!");
    
    INFO( "Inserting MAGE-TAB to Submissions Tracking database..." );
    my $db_spreadsheet = ArrayExpress::AutoSubmission::DB::Spreadsheet->insert({
        experiment_id => $expt,
        name          => $spreadsheet,
        is_deleted    => 0,
    });
    INFO( "MAGE-TAB inserted successfully." );

    # Make a backup as well.
    INFO( "Backing up MAGE-TAB..." );
    my $backup = "$target_file.backup." . date_now();
    copy($target_file, $backup)
        or warn ("Error backing up spreadsheet $spreadsheet ($backup) in submissions directory: $!");
    chmod(oct('0444'), $backup)
        or warn ("Warning: problem setting permissions on backup $backup: $!");
    INFO( "Backup created successfully." );    

    return;
}

sub insert_data_files {

    my $self = shift;

    my $expt = $self->get_experiment();

    DATAFILE:
    foreach my $data_file ( @{ $self->get_data_files() } ) {

	my $target_file = File::Spec->catfile(
	    $expt->filesystem_directory(),
	    basename($data_file),
	);

	# Ask what to do for preexisting files.
	if ( -e $target_file ) {
	    if ( $self->get_clobber()
	      || $self->_get_user_approval(
		  "Warning: submission has pre-existing file $target_file. Overwrite [y/N] ? ") ) {

		unlink($target_file)
		    or die("Error removing old data file $target_file: $!");
	    }
	    else {
		print STDERR ("Skipping insertion of data file $data_file.\n");
		next DATAFILE;
	    }
	}

	# Write out the new data file, enter it into the DB and fix the permissions.
	copy($data_file, $target_file)
	    or die("Error copying data file $data_file to submissions directory: $!");
	chmod (oct($CONFIG->get_FILE_PERMISSIONS()), $target_file)
	    or warn("Warning: problem setting permissions on data archive $target_file: $!");
	my $db_file = ArrayExpress::AutoSubmission::DB::DataFile->find_or_create(
	    experiment_id => $expt,
	    name          => basename($data_file),
	    is_deleted    => 0,
	);
	$db_file->set(is_unpacked => 0);
	$db_file->update();
    }

    return;
}

sub get_user {

    my $self = shift;

    # Return any previously assigned user object.
    return $user{ident $self} if $user{ident $self};

    # Sort out our user account, creating one if necessary.
    $user{ident $self} = ArrayExpress::AutoSubmission::DB::User->retrieve(
        login      => $self->get_login(),
        is_deleted => 0,
    );
    unless ($user{ident $self}) {

        if (  $self->get_clobber()
           || $self->_get_user_approval(
               sprintf("Warning: user %s does not yet exist. Create [y/N] ? ",
                   $self->get_login()))) {

            INFO( 
                "Creating user ", 
                $self->get_login, 
                " with email address ", 
                $CONFIG->get_AUTOSUBS_CURATOR_EMAIL, 
                " ..." 
            );
            
            $user{ident $self} = ArrayExpress::AutoSubmission::DB::User->find_or_create(
                login      => $self->get_login(),
                name       => $self->get_login(),
                email      => $CONFIG->get_AUTOSUBS_CURATOR_EMAIL(),
                password   => $self->mk_passwd(),
                created_at => date_now(),
                is_deleted => 0,
            ) or LOGDIE(
                "Error creating user ",
                 $self->get_login(), 
                 " : $! "
            );

            INFO( "User ", $self->get_login, " created successfully." );
        }
        else {
            LOGDIE("Cannot insert a submission without a user account. Exiting.");
        }
    }

    return $user{ident $self};
}

sub get_experiment {

    my $self = shift;

    # Return any previously assigned experiment object.
    return $experiment{ident $self} if $experiment{ident $self};
    
    # Check pre-existing accession, update if needed.
    if ( $self->get_accession() ) {
        $experiment{ident $self} = ArrayExpress::AutoSubmission::DB::Experiment->retrieve(
            accession       => $self->get_accession(),
            is_deleted      => 0,
        );

        # Update pre-existing experiment.
        if ( $experiment{ident $self} ) {

            # We're now allowing experiments to switch between types,
            # but we don't want duplicated accessions. As a result, if
            # we try and create an experiment with a pre-existing
            # accession, but of the wrong type, we want to catch that
            # here.
            unless ( $experiment{ident $self}->experiment_type()
                 eq $self->get_experiment_type() ) {
                croak(
                    sprintf(
                    qq{Error: Pre-existing experiment in database is not of type "%s".\n},
                    $self->get_experiment_type(),
                    ),
                );
            }

            # Make sure it's okay to overwrite stuff.
            if ( $self->get_clobber()
              || $self->_get_user_approval(
              sprintf("Experiment with accession %s already exists. "
                . "Update this experiment (this may overwrite an old spreadsheet) [y/N] ? ",
                  $self->get_accession())
              ) ) {

                # postpone checking until insertion complete.
                $experiment{ident $self}->set(
                    in_curation    => 0,
                    date_submitted => date_now(),
                    name           => $self->get_name(),
                    user_id        => $self->get_user(),
                );

                # FIXME allow updates of e.g. organisms here.
                $experiment{ident $self}->update();
                $self->send_notification("Resubmission") if $self->get_notify;
            }
            else {
                die(sprintf(
                    "Will not create duplicate experiment %s. Quitting.\n",
                    $self->get_accession(),
                ));
            }
        }
    }

    # New experiment created here.
    unless ( $experiment{ident $self} ) {

        if ( ArrayExpress::AutoSubmission::DB::Experiment->retrieve(
            name       => $self->get_name(),
            is_deleted => 0,
        ) ) {
            die(qq{Error: pre-existing experiment in database with name "}
                . $self->get_name() . qq{". Exiting.\n});
        }

        INFO( "Inserting experiment to Submissions Tracking database...\n" );
        $experiment{ident $self} = ArrayExpress::AutoSubmission::DB::Experiment->insert({
            name            => $self->get_name(),
            user_id         => $self->get_user(),
            accession       => $self->get_accession(),
            in_curation     => 0,    # Don't start checking just yet!
            num_submissions => 0,
            experiment_type => $self->get_experiment_type(),
            comment         => $self->get_comment(),
            date_submitted  => date_now(),
            is_deleted      => 0,
        });
        INFO( "Experiment inserted successfully." );

        # Add any species that we know about.
        foreach my $species_name ( @{ $self->get_organisms() } ) {
            if ( my @organisms
                 = ArrayExpress::AutoSubmission::DB::Organism->search(
                 scientific_name => $species_name,
                 is_deleted      => 0, ) ) {

                if ( scalar @organisms == 1 ) {
                    $experiment{ident $self}->add_to_organism_instances({
                    experiment_id => $experiment{ident $self},
                    organism_id   => $organisms[0],
                    });
                }
                else {
                    croak(qq{Warning: Multiple organisms named "$species_name" found in database.\n});
                }
            }
            else {
                carp(qq{Warning: Organism name "$species_name" not found in database.\n});
            }
        }
        $experiment{ident $self}->update();
        $self->send_notification("New submission") if $self->get_notify;
    }

    return $experiment{ident $self};
}

sub send_notification{
	my ($self, $submission_status) = @_;
	
	my $subject = $self->get_experiment_type
	              ." "
	              .$submission_status
	              .": "
	              .$self->get_name;
	
	my $body = "Dear Curators,\n\n"
	           ."A new ".$self->get_experiment_type." experiment has just been submitted:\n"
	           ."\nName:      ".$self->get_name
	           ."\nDirectory: ".$self->get_experiment->filesystem_directory
	           ."\nUser:      ".$self->get_login
	           ."\nEmail:     ".$self->get_experiment->user_id->email
	           ."\n\nSubmission Date: ".date_now;
	           
	my $curator_mail = MIME::Lite->new(
		From     => $CONFIG->get_AUTOSUBS_ADMIN(),
		To       => $CONFIG->get_AUTOSUBS_CURATOR_EMAIL(),
		Subject  => $subject,
		Encoding => 'quoted-printable',
		Data     => $body,
		Type     => 'text/plain',
    );
    
    $curator_mail->send or die "Error sending curator notification email";
}
=pod

=begin html

    <div><a name="top"></a>
      <table class="layout">
	  <tr>
	    <td class="whitetitle" width="100">
              <a href="../../../index.html">
                <img src="../../T2M_logo.png"
                     border="0" height="50" alt="Tab2MAGE logo"></td>
              </a>
	    <td class="pagetitle">Module detail: Creator.pm</td>
	  </tr>
      </table>
    </div>

=end html

=head1 NAME

ArrayExpress::AutoSubmission::Creator - A class providing convenience
methods for experiment object creation and insertion into the
autosubmissions tracking database.

=head1 SYNOPSIS

 use ArrayExpress::AutoSubmission::Creator;
 my $creator = ArrayExpress::AutoSubmission::Creator->new({
    login           => $login,
    name            => $expt_name,
    spreadsheet     => $startfile,
    data_files      => \@datafiles,
    accession       => $accession,
    experiment_type => 'MAGE-TAB',
    comment         => 'Submission inserted manually',
    clobber         => 0,
 });

 # Create the experiment and insert the spreadsheet.
 my $expt = $creator->get_experiment();

 # Copy the files to the submissions directory.
 print STDERR ("Copying files...\n");
 $creator->insert_spreadsheet();
 $creator->insert_data_files();

=head1 DESCRIPTION

This module provides some basic convenience methods to automate error
handling when inserting new experiments into the tracking database.

=head1 METHODS

=over 2

=item C<new()>

Object constructor. Takes a hashref of options, including the following:

=over 4

=item C<login>

The login name of the user to which the experiment should be assigned.

=item C<name>

The name of the experiment

=item C<spreadsheet>

The path to spreadsheet file to be inserted.

=item C<data_files>

An arrayref listing the paths to the data files to be inserted.

=item C<accession>

The accession number for the experiment.

=item C<comment>

Any comments to be attached to the experiment.

=item C<experiment_type>

The experiment type. This should typically be one of the following:
MAGE-TAB, Tab2MAGE, MIAMExpress, GEO, MUGEN, Unknown.

=item C<notify>

A flag indicating whether to notify curator mailing list of the submission.

=item C<clobber>

A flag indicating whether to overwrite files without prompting the user.

=item C<organisms>

An arrayref of organism scientific names to associate with this
experiment.

=back

=item C<mk_passwd>

Returns a random string suitable for use as an account password. Can
pass an optional length argument, otherwise defaults to eight characters.

=item C<insert_spreadsheet>

Copy the spreadsheet file into the appropriate filesystem location and
insert a record into the database.

=item C<insert_data_files>

Copy the data files into the appropriate filesystem location and
insert records into the database.

=item C<get_user>

Returns the appropriate Class::DBI user object as retrieved from (or
inserted into) the database.

=item C<get_experiment>

Returns the appropriate Class::DBI experiment object as retrieved from
(or inserted into) the database.

=back

=head1 AUTHOR

Tim Rayner (rayner@ebi.ac.uk), ArrayExpress team, EBI, 2008.

Acknowledgements go to the ArrayExpress curation team for feature
requests, bug reports and other valuable comments. 

=begin html

<hr>
<a href="http://sourceforge.net">
  <img src="http://sourceforge.net/sflogo.php?group_id=120325&amp;type=2" 
       width="125" 
       height="37" 
       border="0" 
       alt="SourceForge.net Logo" />
</a>

=end html

=cut

1;
