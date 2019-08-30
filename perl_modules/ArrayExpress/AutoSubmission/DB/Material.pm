#!/usr/bin/env perl
#
# $Id: Material.pm 1853 2007-12-13 17:53:43Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::Material;
use base 'ArrayExpress::AutoSubmission::DB';
__PACKAGE__->table('materials');
__PACKAGE__->columns(
    All => qw(
        id
        display_label
        ontology_category
        ontology_value
        is_deleted
        )
);
__PACKAGE__->has_many(
    categories => [
        'ArrayExpress::AutoSubmission::DB::CategoryMaterial' => 'category_id'
    ]
);
__PACKAGE__->has_many(
    experiments => [
        'ArrayExpress::AutoSubmission::DB::MaterialInstance' =>
            'experiment_id'
    ]
);

1;
