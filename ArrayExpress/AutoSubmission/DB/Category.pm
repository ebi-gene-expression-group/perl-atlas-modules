#!/usr/bin/env perl
#
# $Id: Category.pm 1853 2007-12-13 17:53:43Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::Category;
use base 'ArrayExpress::AutoSubmission::DB';
__PACKAGE__->table('categories');
__PACKAGE__->columns(
    All => qw(
        id
        ontology_term
        display_label
	is_common
	is_bmc
	is_fv
	is_deleted
        )
);
__PACKAGE__->has_many( taxons =>
        [ 'ArrayExpress::AutoSubmission::DB::CategoryTaxon' => 'taxon_id' ] );
__PACKAGE__->has_many( designs =>
        [ 'ArrayExpress::AutoSubmission::DB::CategoryDesign' => 'design_id' ]
);
__PACKAGE__->has_many(
    materials => [
        'ArrayExpress::AutoSubmission::DB::CategoryMaterial' => 'material_id'
    ]
);

1;
