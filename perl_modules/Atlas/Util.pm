#!/usr/bin/env perl
#
=pod

=head1 NAME

Atlas::Util - basic accessory functions.

=head1 SYNOPSIS

	use Atlas::Util qw(
		get_supporting_file
	);

	# ...

    my $siteConfigPath = get_supporting_file("ArrayExpressSiteConfig.yml");

=head1 DESCRIPTION

This module exports functions that are used by multiple different scripts and
classes in Atlas Perl code.

=cut

package Atlas::Util;

use 5.10.0;

use File::Basename;
use File::Copy;

use base 'Exporter';
our @EXPORT_OK = qw(
    get_supporting_file
);


# Get the logger (if any).
my $logger = Log::Log4perl::get_logger;

=head1 METHODS

=over 2

=item _build_module_supporting_files_path

Return the path of the supporting_files dir from the repository

=cut

sub _build_module_supporting_files_path {
    
    # Deduce the path to the config file from the path to this module.
    # This module's location on the filesystem.
    my $thisModulePath = __FILE__;

    # The directory this module occupies.
    my $thisModuleDir = dirname( $thisModulePath );

    # First split the directories we have.
    my @directories = File::Spec->splitdir( $thisModuleDir );

    # Get up to the atlasprod directory.
    while( $directories[ -1 ] ne "atlasprod" ) {
        pop @directories;

        unless( @directories ) {
            die "ERROR - Cannot find atlasprod directory in path to Atlas::Common. Please ensure this module is installed under atlasprod.\n";
        }
    }

    # Stick the remaining directories back together, now pointing to atlasprod directory.
    # Check that the supporting_files dir is in the dir now in $atlasprodDir.
    $result = File::Spec->catfile( @directories, "supporting_files" );

    return $result
}


=item _build_supporting_files_path

Find where the supporting_files folder is, prioritising env var

=cut

sub _build_supporting_files_path {
    
    my $result = $ENV{'ATLAS_META_CONFIG'};
    if(! defined $result){
        $result =  _build_module_supporting_files_path();
    }

    unless( -d $result ) {
        die "ERROR - Cannot find $result -- cannot locate site config.\n";
    }

    return $result;
}

=item get_supporting_file

Returns a path to a file in supporting_files directory

=cut

sub get_supporting_file {
	my ($file_name) =  @_;
    my $supporting_files_dir = _build_supporting_files_path();
    my $result = File::Spec->catfile(
		$supporting_files_dir,
		$file_name
	);
    if ( ! -r $result ){
        my $module_supporting_file_dir = _build_module_supporting_files_path();
        my $result_template = File::Spec->catfile(
            $module_supporting_files_dir,
            "${file_name}.default"
        );

        if ( -r $result_template ){
            warn "$result not present, initialising from $result_template";
            copy( "${result}.default", ${result});
        }
        else {
            die "ERROR - Cannot read supporting file: $result or default $result_template -- please check it exists and is readable by your user ID.\n";
        }
    }
    return $result;
}

1;
