#!/usr/bin/env perl
#
# $Id: CategoryTaxon.pm 1853 2007-12-13 17:53:43Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::CategoryTaxon;
use base 'ArrayExpress::AutoSubmission::DB';
__PACKAGE__->table('categories_taxons');
__PACKAGE__->columns(
    Primary => qw(
        category_id
        taxon_id
        )
);
__PACKAGE__->has_a(
    category_id => 'ArrayExpress::AutoSubmission::DB::Category' );
__PACKAGE__->has_a( taxon_id => 'ArrayExpress::AutoSubmission::DB::Taxon' );

1;
