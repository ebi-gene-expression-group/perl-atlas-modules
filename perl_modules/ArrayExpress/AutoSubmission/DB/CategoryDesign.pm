#!/usr/bin/env perl
#
# $Id: CategoryDesign.pm 1853 2007-12-13 17:53:43Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::CategoryDesign;
use base 'ArrayExpress::AutoSubmission::DB';
__PACKAGE__->table('categories_designs');
__PACKAGE__->columns(
    Primary => qw(
        category_id
        design_id
        )
);
__PACKAGE__->has_a(
    category_id => 'ArrayExpress::AutoSubmission::DB::Category' );
__PACKAGE__->has_a( design_id => 'ArrayExpress::AutoSubmission::DB::Design' );

1;
