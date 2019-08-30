#!/usr/bin/env perl
#
# $Id$

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::Pipeline;
use base 'ArrayExpress::AutoSubmission::DB';

__PACKAGE__->table('pipelines');
__PACKAGE__->columns(
    All => qw(
      id
      submission_type
      instances_to_start
      checker_daemon
      exporter_daemon
      polling_interval
      checker_threshold
      qt_filename
      keep_protocol_accns
      accession_prefix
      pipeline_subdir
      )
);

1;