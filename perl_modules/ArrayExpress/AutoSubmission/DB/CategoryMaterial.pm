#!/usr/bin/env perl
#
# $Id: CategoryMaterial.pm 1853 2007-12-13 17:53:43Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::CategoryMaterial;
use base 'ArrayExpress::AutoSubmission::DB';
__PACKAGE__->table('categories_materials');
__PACKAGE__->columns(
    Primary => qw(
        category_id
        material_id
        )
);
__PACKAGE__->has_a(
    category_id => 'ArrayExpress::AutoSubmission::DB::Category' );
__PACKAGE__->has_a(
    material_id => 'ArrayExpress::AutoSubmission::DB::Material' );

1;
