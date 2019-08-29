#!/usr/bin/env perl
#
# $Id$

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::DaemonInstance;
use base 'ArrayExpress::AutoSubmission::DB';

__PACKAGE__->table('daemon_instances');
__PACKAGE__->columns(
    All => qw(
      id
      pipeline_id
      daemon_type
      pid
      start_time
      end_time
      running
      user
      )
);

__PACKAGE__->has_a( pipeline_id => 'ArrayExpress::AutoSubmission::DB::Pipeline' );

1;