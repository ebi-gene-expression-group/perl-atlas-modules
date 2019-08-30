#!/usr/bin/env perl
#
# $Id: ArrayDesignExperiment.pm 1853 2007-12-13 17:53:43Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::ArrayDesignExperiment;
use base 'ArrayExpress::AutoSubmission::DB';
__PACKAGE__->table('array_designs_experiments');
__PACKAGE__->columns(
    All => qw(
        id
        experiment_id
        array_design_id
        )
);
__PACKAGE__->has_a(
    experiment_id => 'ArrayExpress::AutoSubmission::DB::Experiment' );
__PACKAGE__->has_a(
    array_design_id => 'ArrayExpress::AutoSubmission::DB::ArrayDesign' );

1;
