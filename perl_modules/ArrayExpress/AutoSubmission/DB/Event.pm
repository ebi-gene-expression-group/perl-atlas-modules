#!/usr/bin/env perl
#
# $Id: Event.pm 1853 2007-12-13 17:53:43Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::Event;
use base 'ArrayExpress::AutoSubmission::DB';
__PACKAGE__->table('events');
__PACKAGE__->columns(
    Primary => qw(
        id
	)
);
__PACKAGE__->columns(
    Essential => qw(
        array_design_id
        experiment_id
        event_type
        jobregister_dbid
        is_deleted
        )
);
__PACKAGE__->columns(
    Others => qw(
        was_successful
        source_db
        target_db
        start_time
        end_time
        machine
        operator
        log_file
        comment
	)
);
__PACKAGE__->has_a(
    array_design_id => 'ArrayExpress::AutoSubmission::DB::ArrayDesign',
);
__PACKAGE__->has_a(
    experiment_id => 'ArrayExpress::AutoSubmission::DB::Experiment',
);

__PACKAGE__->set_sql(
    last_jobid => "SELECT MAX(jobregister_dbid) FROM __TABLE__ WHERE %s = ?",
);

1;
