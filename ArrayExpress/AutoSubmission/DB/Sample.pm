#!/usr/bin/env perl
#
# $Id: Sample.pm 2368 2010-11-25 19:22:38Z farne $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::Sample;
use base 'ArrayExpress::AutoSubmission::DB';
use base 'ArrayExpress::AutoSubmission::DB::Accessionable';

use EBI::FGPT::Common qw(date_now);

__PACKAGE__->table('samples');
__PACKAGE__->columns(
    All => qw(
        id
        accession
        user_accession
        submission_accession
        date_assigned
        date_last_processed
        comment
        is_deleted
        source_repository
        )
);

sub reassign_sample {    # Class method.

    my ( $class, $user_accession, $submission_accession) = @_;

    # Checks for (user_accession eq user_accession and 
    # submission_accession eq submission_accession). Creates a
    # new sample in db and assigns accession if not found.
    my $sample_accession;

	my $sample = ArrayExpress::AutoSubmission::DB::Sample->find_or_create(
	    user_accession => $user_accession,
		submission_accession => $submission_accession,
		is_deleted     => 0,
		);

	$sample_accession = $sample->get_accession();

    # Record that this sample has been used
	$sample->set(
	    date_last_processed => date_now(),
	);
	$sample->update();

    return $sample_accession;
}

1;
