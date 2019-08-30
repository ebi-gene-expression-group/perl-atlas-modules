#!/usr/bin/env perl
#
# $Id: QualityMetricInstance.pm 1960 2008-02-21 12:03:19Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::QualityMetricInstance;
use base 'ArrayExpress::AutoSubmission::DB';
__PACKAGE__->table('loaded_data_quality_metrics');
__PACKAGE__->columns(
    All => qw(
	id
	value
	date_calculated
        loaded_data_id
        quality_metric_id
        )
);
__PACKAGE__->has_a( loaded_data_id    => 'ArrayExpress::AutoSubmission::DB::LoadedData' );
__PACKAGE__->has_a( quality_metric_id => 'ArrayExpress::AutoSubmission::DB::QualityMetric' );

1;
