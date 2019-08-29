#!/usr/bin/env perl
#
# $Id: QuantitationType.pm 1853 2007-12-13 17:53:43Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::QuantitationType;
use base 'ArrayExpress::AutoSubmission::DB';
__PACKAGE__->table('quantitation_types');
__PACKAGE__->columns(
    All => qw(
        id
	name
        is_deleted
        )
);
__PACKAGE__->has_many(
    experiments => [
        'ArrayExpress::AutoSubmission::DB::ExperimentQT' => 'experiment_id'
    ]
);

1;
