#!/usr/bin/env perl
#
# $Id: ExperimentFactor.pm 1853 2007-12-13 17:53:43Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::ExperimentFactor;
use base 'ArrayExpress::AutoSubmission::DB';
__PACKAGE__->table('experiments_factors');
__PACKAGE__->columns(
    All => qw(
        id
        factor_id
        experiment_id
        )
);
__PACKAGE__->has_a(
    experiment_id => 'ArrayExpress::AutoSubmission::DB::Experiment' );
__PACKAGE__->has_a(
    factor_id => 'ArrayExpress::AutoSubmission::DB::Factor' );

1;
