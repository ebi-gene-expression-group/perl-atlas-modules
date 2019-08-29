#!/usr/bin/env perl
#
# $Id: OrganismInstance.pm 1853 2007-12-13 17:53:43Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::OrganismInstance;
use base 'ArrayExpress::AutoSubmission::DB';
__PACKAGE__->table('organism_instances');
__PACKAGE__->columns(
    All => qw(
        id
        organism_id
        experiment_id
        )
);
__PACKAGE__->has_a(
    organism_id => 'ArrayExpress::AutoSubmission::DB::Organism' );
__PACKAGE__->has_a(
    experiment_id => 'ArrayExpress::AutoSubmission::DB::Experiment' );

1;
