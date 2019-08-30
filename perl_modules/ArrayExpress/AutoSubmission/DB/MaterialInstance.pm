#!/usr/bin/env perl
#
# $Id: MaterialInstance.pm 1853 2007-12-13 17:53:43Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::MaterialInstance;
use base 'ArrayExpress::AutoSubmission::DB';
__PACKAGE__->table('material_instances');
__PACKAGE__->columns(
    All => qw(
        id
        material_id
        experiment_id
        )
);
__PACKAGE__->has_a(
    material_id => 'ArrayExpress::AutoSubmission::DB::Material' );
__PACKAGE__->has_a(
    experiment_id => 'ArrayExpress::AutoSubmission::DB::Experiment' );

1;
