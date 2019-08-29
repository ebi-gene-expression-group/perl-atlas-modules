#!/usr/bin/env perl
#
# $Id: Design.pm 1853 2007-12-13 17:53:43Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::Design;
use base 'ArrayExpress::AutoSubmission::DB';
__PACKAGE__->table('designs');
__PACKAGE__->columns(
    All => qw(
        id
        display_label
        ontology_category
        ontology_value
	design_type
        is_deleted
        )
);
__PACKAGE__->has_many(
    categories => [
        'ArrayExpress::AutoSubmission::DB::CategoryDesign' => 'category_id'
    ]
);
__PACKAGE__->has_many(
    experiments => [
        'ArrayExpress::AutoSubmission::DB::DesignInstance' => 'experiment_id'
    ]
);

1;
