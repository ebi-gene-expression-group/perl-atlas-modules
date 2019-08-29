#!/usr/bin/env perl
#
# $Id$

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::ExperimentQualityMetricInstance;
use base 'ArrayExpress::AutoSubmission::DB';
__PACKAGE__->table('experiment_quality_metrics');
__PACKAGE__->columns(
    All => qw(
 	    id
	    value
	    date_calculated
        experiment_id
        quality_metric_id
        status
        )
);
__PACKAGE__->has_a( experiment_id    => 'ArrayExpress::AutoSubmission::DB::Experiment' );
__PACKAGE__->has_a( quality_metric_id => 'ArrayExpress::AutoSubmission::DB::QualityMetric' );

1;