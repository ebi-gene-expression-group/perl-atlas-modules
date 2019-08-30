#!/usr/bin/env perl
#
# $Id: Taxon.pm 1853 2007-12-13 17:53:43Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::Taxon;
use base 'ArrayExpress::AutoSubmission::DB';
__PACKAGE__->table('taxons');
__PACKAGE__->columns(
    All => qw(
        id
        scientific_name
        common_name
        accession
        is_deleted
        )
);
__PACKAGE__->has_many(
    organisms => 'ArrayExpress::AutoSubmission::DB::Organism' );
__PACKAGE__->has_many(
    categories => [
        'ArrayExpress::AutoSubmission::DB::CategoryTaxon' => 'category_id'
    ]
);

1;
