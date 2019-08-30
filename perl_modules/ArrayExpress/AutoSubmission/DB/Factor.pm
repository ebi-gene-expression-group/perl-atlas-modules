#!/usr/bin/env perl
#
# $Id: Factor.pm 1853 2007-12-13 17:53:43Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::Factor;
use base 'ArrayExpress::AutoSubmission::DB';
__PACKAGE__->table('factors');
__PACKAGE__->columns(
    All => qw(
        id
	name
        is_deleted
        )
);
__PACKAGE__->has_many(
    experiments => [
        'ArrayExpress::AutoSubmission::DB::ExperimentFactor' => 'experiment_id'
    ]
);

1;
