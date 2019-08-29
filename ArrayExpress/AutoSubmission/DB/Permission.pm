#!/usr/bin/env perl
#
# $Id: Permission.pm 1853 2007-12-13 17:53:43Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::Permission;
use base 'ArrayExpress::AutoSubmission::DB';
__PACKAGE__->table('permissions');
__PACKAGE__->columns(
    All => qw(
        id
        name
        info
        is_deleted
        )
);
__PACKAGE__->has_many( roles =>
        [ 'ArrayExpress::AutoSubmission::DB::PermissionRole' => 'role_id' ] );

1;
