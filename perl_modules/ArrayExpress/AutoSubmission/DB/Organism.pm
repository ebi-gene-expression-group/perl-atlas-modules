#!/usr/bin/env perl
#
# $Id: Organism.pm 1853 2007-12-13 17:53:43Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::Organism;
use base 'ArrayExpress::AutoSubmission::DB';
__PACKAGE__->table('organisms');
__PACKAGE__->columns(
    All => qw(
        id
        scientific_name
        common_name
        accession
        taxon_id
        is_deleted
        )
);
__PACKAGE__->has_a( taxon_id => 'ArrayExpress::AutoSubmission::DB::Taxon' );
__PACKAGE__->has_many(
    experiments => [
        'ArrayExpress::AutoSubmission::DB::OrganismInstance' =>
            'experiment_id'
    ]
);
__PACKAGE__->has_many(
    array_designs => [
        'ArrayExpress::AutoSubmission::DB::ArrayDesignOrganism' => 'array_design_id'
    ]
);

1;
