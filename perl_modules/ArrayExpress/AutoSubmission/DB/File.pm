#!/usr/bin/env perl
#
# $Id: File.pm 1853 2007-12-13 17:53:43Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::File;

# Abstract package without corresponding DB table
use File::Spec;
use Carp;

sub filesystem_path {
    my $self = shift;

    my $experiment;
    unless ( $experiment = $self->experiment_id() ) {
	croak(
	    sprintf(
		"Error: Orphaned file has no experiment: %s",
		$self->name()
	    )
	);
    }

    my $path = File::Spec->catfile(
	$experiment->filesystem_directory(),
	$self->name()
    );

    return $path;
}

1;
