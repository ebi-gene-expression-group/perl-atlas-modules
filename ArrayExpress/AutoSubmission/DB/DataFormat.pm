#!/usr/bin/env perl
#
# $Id: DataFormat.pm 1936 2008-02-08 19:13:37Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::DataFormat;
use base 'ArrayExpress::AutoSubmission::DB';

__PACKAGE__->table('data_formats');
__PACKAGE__->columns(
    All => qw(
        id
	name
        )
);

__PACKAGE__->has_many(
    loaded_data => 'ArrayExpress::AutoSubmission::DB::LoadedData'
);

1;
