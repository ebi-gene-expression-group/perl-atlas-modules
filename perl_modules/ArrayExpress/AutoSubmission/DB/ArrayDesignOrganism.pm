#!/usr/bin/env perl
#
# $Id: ArrayDesignOrganism.pm 1853 2007-12-13 17:53:43Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::ArrayDesignOrganism;
use base 'ArrayExpress::AutoSubmission::DB';
__PACKAGE__->table('array_designs_organisms');
__PACKAGE__->columns(
    All => qw(
        id
        organism_id
        array_design_id
        )
);
__PACKAGE__->has_a(
    organism_id => 'ArrayExpress::AutoSubmission::DB::Organism' );
__PACKAGE__->has_a(
    array_design_id => 'ArrayExpress::AutoSubmission::DB::ArrayDesign' );

1;
