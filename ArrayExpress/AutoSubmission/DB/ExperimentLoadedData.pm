#!/usr/bin/env perl
#
# $Id: ExperimentLoadedData.pm 1936 2008-02-08 19:13:37Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::ExperimentLoadedData;
use base 'ArrayExpress::AutoSubmission::DB';
__PACKAGE__->table('experiments_loaded_data');
__PACKAGE__->columns(
    Primary => qw(
        loaded_data_id
        experiment_id
        )
);
__PACKAGE__->has_a( loaded_data_id => 'ArrayExpress::AutoSubmission::DB::LoadedData' );
__PACKAGE__->has_a( experiment_id  => 'ArrayExpress::AutoSubmission::DB::Experiment' );

1;
