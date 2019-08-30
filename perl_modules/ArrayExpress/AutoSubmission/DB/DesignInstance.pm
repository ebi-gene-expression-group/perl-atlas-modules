#!/usr/bin/env perl
#
# $Id: DesignInstance.pm 1853 2007-12-13 17:53:43Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::DesignInstance;
use base 'ArrayExpress::AutoSubmission::DB';
__PACKAGE__->table('design_instances');
__PACKAGE__->columns(
    All => qw(
        id
        design_id
        experiment_id
        )
);
__PACKAGE__->has_a( design_id => 'ArrayExpress::AutoSubmission::DB::Design' );
__PACKAGE__->has_a(
    experiment_id => 'ArrayExpress::AutoSubmission::DB::Experiment' );

1;
