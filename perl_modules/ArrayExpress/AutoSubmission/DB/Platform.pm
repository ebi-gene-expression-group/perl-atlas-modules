#!/usr/bin/env perl
#
# $Id: Platform.pm 1960 2008-02-21 12:03:19Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::Platform;
use base 'ArrayExpress::AutoSubmission::DB';

__PACKAGE__->table('platforms');
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
