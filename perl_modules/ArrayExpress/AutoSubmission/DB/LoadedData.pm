#!/usr/bin/env perl
#
# $Id: LoadedData.pm 1960 2008-02-21 12:03:19Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::LoadedData;
use base 'ArrayExpress::AutoSubmission::DB';

__PACKAGE__->table('loaded_data');
__PACKAGE__->columns(
    All => qw(
        id
	identifier
	md5_hash
	data_format_id
	platform_id
	needs_metrics_calculation
	date_hashed
	is_deleted
        )
);

__PACKAGE__->has_a( data_format_id => 'ArrayExpress::AutoSubmission::DB::DataFormat' );
__PACKAGE__->has_a( platform_id    => 'ArrayExpress::AutoSubmission::DB::Platform' );
__PACKAGE__->has_many(
    experiments => [
        'ArrayExpress::AutoSubmission::DB::ExperimentLoadedData' => 'experiment_id'
    ]
);
__PACKAGE__->has_many(
    loaded_data_instances => 'ArrayExpress::AutoSubmission::DB::ExperimentLoadedData'
);
__PACKAGE__->has_many(
    quality_metrics => [
        'ArrayExpress::AutoSubmission::DB::QualityMetricInstance' => 'quality_metric_id'
    ]
);
__PACKAGE__->has_many(
    quality_metric_instances => 'ArrayExpress::AutoSubmission::DB::QualityMetricInstance'
);

1;
