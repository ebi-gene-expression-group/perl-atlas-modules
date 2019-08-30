#!/usr/bin/env perl
#
# $Id$

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::SampleGroup;
use base 'ArrayExpress::AutoSubmission::DB';
use base 'ArrayExpress::AutoSubmission::DB::Accessionable';

use EBI::FGPT::Common qw(date_now);

__PACKAGE__->table('sample_groups');
__PACKAGE__->columns(
    All => qw(
        id
        accession
        user_accession
        submission_accession
        project_name
        source_repository
        linking_repositories
        date_assigned
        date_last_processed
        comment
        is_deleted
        source_repository
        )
);

sub reassign_sample_group {    # Class method.

    my ( $class, $user_accession, $submission_accession) = @_;

    # Checks for (user_accession eq user_accession and 
    # submission_accession eq submission_accession). Creates a
    # new sample group in db and assigns accession if not found.
    my $group_accession;

	my $group = ArrayExpress::AutoSubmission::DB::SampleGroup->find_or_create(
	    user_accession => $user_accession,
		submission_accession => $submission_accession,
		is_deleted     => 0,
		);

	$group_accession = $group->get_accession();

    # Record that this group has been used
	$group->set(
	    date_last_processed => date_now(),
	);
	$group->update();

    return $group_accession;
}
