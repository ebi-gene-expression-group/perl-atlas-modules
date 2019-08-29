#!/usr/bin/env perl
#
# $Id: ExperimentQT.pm 1853 2007-12-13 17:53:43Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::ExperimentQT;
use base 'ArrayExpress::AutoSubmission::DB';
__PACKAGE__->table('experiments_quantitation_types');
__PACKAGE__->columns(
    All => qw(
        id
        quantitation_type_id
        experiment_id
        )
);
__PACKAGE__->has_a(
    experiment_id => 'ArrayExpress::AutoSubmission::DB::Experiment' );
__PACKAGE__->has_a(
    quantitation_type_id => 'ArrayExpress::AutoSubmission::DB::QuantitationType' );

1;
