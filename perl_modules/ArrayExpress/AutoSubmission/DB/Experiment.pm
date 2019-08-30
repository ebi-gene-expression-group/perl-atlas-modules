#!/usr/bin/env perl
#
# $Id: Experiment.pm 2396 2011-12-15 11:34:56Z farne $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::Experiment;
use base 'ArrayExpress::AutoSubmission::DB';
use base 'ArrayExpress::AutoSubmission::DB::Accessionable';
use ArrayExpress::AutoSubmission::DB::Pipeline;
use EBI::FGPT::Config qw($CONFIG);
use EBI::FGPT::Common qw(untaint);
use File::Spec;
use File::Path;
use File::Basename;
use Carp;

__PACKAGE__->table('experiments');
__PACKAGE__->columns(
    Primary => qw(
        id
        )
);

# These are columns used in the main submissions tracking system, so
# are generally essential.
__PACKAGE__->columns(
    Essential => qw(
        accession
        name
        user_id
	    date_last_edited
	    date_submitted
        date_last_processed
	    in_curation
        status
        experiment_type
	    is_affymetrix
	    is_uhts
        use_native_datafiles
        miamexpress_subid
        release_date
        is_released
        curated_name
        is_deleted
        has_gds
	)
);

# These are less-used columns which may be retrieved for more extended
# tracking purposes.
__PACKAGE__->columns(
    Others => qw(
        checker_score
	    miame_score
        software
        data_warehouse_ready
        in_data_warehouse
	    num_submissions
        curator
        miamexpress_login
	    is_mx_batchloader
        submitter_description
        num_samples
        num_hybridizations
	    has_raw_data
	    has_processed_data
        ae_miame_score
        atlas_fail_score
        comment
        migration_status
        migration_comment
        migration_source
        file_to_load
        )
);
__PACKAGE__->has_a( user_id => 'ArrayExpress::AutoSubmission::DB::User' );
__PACKAGE__->has_many(
    array_designs => [
        'ArrayExpress::AutoSubmission::DB::ArrayDesignExperiment' => 'array_design_id'
    ]
);
__PACKAGE__->has_many(
    array_design_instances => 
        'ArrayExpress::AutoSubmission::DB::ArrayDesignExperiment'
);
__PACKAGE__->has_many(
    designs => [
        'ArrayExpress::AutoSubmission::DB::DesignInstance' => 'design_id'
    ]
);
__PACKAGE__->has_many(
    materials => [
        'ArrayExpress::AutoSubmission::DB::MaterialInstance' => 'material_id'
    ]
);
__PACKAGE__->has_many(
    organisms => [
        'ArrayExpress::AutoSubmission::DB::OrganismInstance' => 'organism_id'
    ]
);
__PACKAGE__->has_many(
    design_instances => 
        'ArrayExpress::AutoSubmission::DB::DesignInstance'
);
__PACKAGE__->has_many(
    material_instances => 
        'ArrayExpress::AutoSubmission::DB::MaterialInstance'
);
__PACKAGE__->has_many(
    organism_instances => 
        'ArrayExpress::AutoSubmission::DB::OrganismInstance'
);
__PACKAGE__->has_many(
    data_files => 
        'ArrayExpress::AutoSubmission::DB::DataFile',
    # Order by ID so that more recent uploads are unpacked later.
    { order_by => 'id' }
);
__PACKAGE__->has_many(
    spreadsheets => 
        'ArrayExpress::AutoSubmission::DB::Spreadsheet'
);
__PACKAGE__->has_many(
    factors => [
        'ArrayExpress::AutoSubmission::DB::ExperimentFactor' => 'factor_id'
    ]
);
__PACKAGE__->has_many(
    factor_instances => 
        'ArrayExpress::AutoSubmission::DB::ExperimentFactor'
);
__PACKAGE__->has_many(
    quantitation_types => [
        'ArrayExpress::AutoSubmission::DB::ExperimentQT' => 'quantitation_type_id'
    ]
);
__PACKAGE__->has_many(
    quantitation_type_instances => 
        'ArrayExpress::AutoSubmission::DB::ExperimentQT'
);
__PACKAGE__->has_many(
    events => 'ArrayExpress::AutoSubmission::DB::Event'
);

__PACKAGE__->has_many(
    loaded_data => [
        'ArrayExpress::AutoSubmission::DB::ExperimentLoadedData' => 'loaded_data_id'
    ]
);
__PACKAGE__->has_many(
    loaded_data_instances => 'ArrayExpress::AutoSubmission::DB::ExperimentLoadedData'
);

__PACKAGE__->set_sql(
    status_for_update => "SELECT status FROM __TABLE__ WHERE id = ? FOR UPDATE",
);

sub update_designs {

    my ($self, $new_assns) = @_;

    my @old_assn_instances = $self->design_instances();

    my %new = map { $_->id()        => 1 } @$new_assns;
    my %old = map { $_->design_id() => 1 } @old_assn_instances;

    foreach my $assn (@old_assn_instances) {
	unless ($new{$assn->design_id()}) {
	    $assn->delete();
	}
    }
    foreach my $assn (@$new_assns) {
	unless ($old{$assn->id()}) {
	    $self->add_to_design_instances({
		design_id => $assn,
	    });
	}
    }
    $self->update;

    return;
}

sub update_materials {

    my ($self, $new_assns) = @_;

    my @old_assn_instances = $self->material_instances();

    my %new = map { $_->id()          => 1 } @$new_assns;
    my %old = map { $_->material_id() => 1 } @old_assn_instances;

    foreach my $assn (@old_assn_instances) {
	unless ($new{$assn->material_id()}) {
	    $assn->delete();
	}
    }
    foreach my $assn (@$new_assns) {
	unless ($old{$assn->id()}) {
	    $self->add_to_material_instances({
		material_id => $assn,
	    });
	}
    }
    $self->update;

    return;
}

sub update_organisms {

    my ($self, $new_assns) = @_;

    my @old_assn_instances = $self->organism_instances();

    my %new = map { $_->id()          => 1 } @$new_assns;
    my %old = map { $_->organism_id() => 1 } @old_assn_instances;

    foreach my $assn (@old_assn_instances) {
	unless ($new{$assn->organism_id()}) {
	    $assn->delete();
	}
    }
    foreach my $assn (@$new_assns) {
	unless ($old{$assn->id()}) {
	    $self->add_to_organism_instances({
		organism_id => $assn,
	    });
	}
    }
    $self->update;

    return;
}

sub ae1_load_directory {
   
   # Returns the directory where MAGE-ML for this submission
   # should be
   my ($self) = @_;
   
   my $id = $self->id;
   my $acc = $self->accession;
   my $subdir;
   
   # Experiment must have an accession
   unless($acc){
      croak("Error: cannot construct load directory path for experiment id $id."
           ."Experiment has no accession.");	
   }
   
   # If experiment has type try to get subdir from pipelines table
   if (my $type = $self->get_experiment_type){
      my ($pipeline) = ArrayExpress::AutoSubmission::DB::Pipeline->search(
          submission_type => $type
      );
      
      unless ($pipeline and $subdir = $pipeline->pipeline_subdir){
      	  # If subdir not defined in pipeline table fall back to 
      	  # using 4 letter code from accession
          $self->acc =~ /E-([A-Z]{4})-\d*/g;
          $subdir = $1;
      }
   }
   
   unless ($subdir){
   	   croak("Error: cannot construct load directory path for experiment $acc.");
   }
   
   my $load_dir = File::Spec->catdir(
       $CONFIG->get_AUTOSUBMISSIONS_TARGET,
       untaint($subdir),
       untaint($acc),
   );
   
   return $load_dir;	
}

sub filesystem_directory {
    
    # Returns the top-level submissions directory containing
    # spreadsheets and data file archives, having first created it.
    my $self = shift;

    # Check we have a valid experiment (MIAMExpress submissions are
    # handled separately, in MIAMExpress.pm).
    unless (    $self->user_id
	     && $self->user_id->login
	     && $self->experiment_type
	     && $self->id ) {
	croak("Error: Invalid Experiment object for filesystem directory creation.");
    }
    my $dir = File::Spec->catdir(
	$CONFIG->get_AUTOSUBMISSIONS_FILEBASE(),
	untaint( $self->user_id->login ),
	untaint( $self->experiment_type ) . "_" . untaint( $self->id ),
    );

    # Check for pre-existence because otherwise we can be stuck trying
    # to change permissions on a pre-existing directory which may not
    # belong to us.
    unless ( -e $dir ) {

	# Attempt to create submissions directory.
        eval {

	    # Handle the umask.
	    my $original_umask = umask;
	    umask(0);

	    # Needed because Webform.pm changes this to parse the
	    # filename; we however need this to be based on the server
	    # OS. File::Path::mkpath() uses File::Basename.
	    my $old_fstype = fileparse_set_fstype($^O);

	    # Do the deed.
	    mkpath($dir, undef, oct(777));
	    chmod(oct($CONFIG->get_DIR_PERMISSIONS()), $dir)
		or croak("Error changing permissions on $dir: $!");

	    # Reset the original settings.
	    fileparse_set_fstype($old_fstype) if $old_fstype;
	    umask($original_umask);
	};

	# If it failed, check whether we can at least rwx the dir.
	if ($@) {
	    unless ( -d $dir && -r _ && -w _ && -x _ ) {
		die("Error creating submissions directory.\n");
	    }
	}
    }

    return $dir;
}

sub unpack_directory {

    # Returns the directory into which the data archives will be
    # unpacked, having first created it.
    my $self = shift;

    my $dir = File::Spec->catdir(
	$self->filesystem_directory(), 'unpacked'
    );

    # Check for pre-existence because otherwise we can be stuck trying
    # to change permissions on a pre-existing directory which may not
    # belong to us.
    unless ( -e $dir ) {

	# Attempt to create unpacking directory.
        eval {
	    my $original_umask = umask;
	    umask(0);
	    mkpath($dir, undef, oct(777));
	    chmod(oct($CONFIG->get_DIR_PERMISSIONS()), $dir)
		or croak("Error changing permissions on $dir: $!");
	    umask($original_umask);
	};

	# If it failed, check whether we can at least rwx the dir.
	if ($@) {
	    unless ( -d $dir && -r _ && -w _ && -x _ ) {
		die("Error creating submissions directory.\n");
	    }
	}
    }

    return $dir;
}

1;
