#!/usr/bin/env perl
#
# $Id: ArrayDesign.pm 2354 2010-10-19 12:10:10Z farne $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::ArrayDesign;
use base 'ArrayExpress::AutoSubmission::DB';
use base 'ArrayExpress::AutoSubmission::DB::Accessionable';
__PACKAGE__->table('array_designs');
__PACKAGE__->columns(
    Primary => qw(
        id
	)
);
__PACKAGE__->columns(
    Essential => qw(
        miamexpress_subid
        accession
	    name
        status
        date_last_processed
        release_date
        is_deleted
        )
);
__PACKAGE__->columns(
    Others => qw(
        miamexpress_login
	    miame_score
        data_warehouse_ready
        in_data_warehouse
        annotation_source
        annotation_version
        biomart_table_name
        is_released
        comment
        migration_status
        migration_comment
        file_to_load
	)
);
__PACKAGE__->has_many(
    organisms => [
        'ArrayExpress::AutoSubmission::DB::ArrayDesignOrganism' => 'organism_id'
    ]
);
__PACKAGE__->has_many(
    organism_instances => 
        'ArrayExpress::AutoSubmission::DB::ArrayDesignOrganism'
);
__PACKAGE__->has_many(
    experiments => [
        'ArrayExpress::AutoSubmission::DB::ArrayDesignExperiment' => 'experiment_id'
    ]
);
__PACKAGE__->has_many(
    events => 'ArrayExpress::AutoSubmission::DB::Event'
);

1;
