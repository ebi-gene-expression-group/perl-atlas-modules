#!/usr/bin/env perl
#
# $Id: Spreadsheet.pm 1853 2007-12-13 17:53:43Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::Spreadsheet;
use base 'ArrayExpress::AutoSubmission::DB';
use base 'ArrayExpress::AutoSubmission::DB::File';
__PACKAGE__->table('spreadsheets');
__PACKAGE__->columns(
    All => qw(
      id
      experiment_id
      name
      is_deleted
      )
);
__PACKAGE__->has_a( experiment_id => 'ArrayExpress::AutoSubmission::DB::Experiment' );

1;
