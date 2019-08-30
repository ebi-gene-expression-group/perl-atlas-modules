#!/usr/bin/env perl
#
# $Id: QualityMetric.pm 2332 2010-06-24 12:17:00Z farne $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::QualityMetric;
use base 'ArrayExpress::AutoSubmission::DB';

__PACKAGE__->table('quality_metrics');
__PACKAGE__->columns(
    All => qw(
        id
	    name
        description
        )
);

__PACKAGE__->has_many(
    loaded_data => [
        'ArrayExpress::AutoSubmission::DB::QualityMetricInstance' => 'loaded_data_id'
    ]
);
__PACKAGE__->has_many(
    quality_metric_instances => 'ArrayExpress::AutoSubmission::DB::QualityMetricInstance'
);

1;
