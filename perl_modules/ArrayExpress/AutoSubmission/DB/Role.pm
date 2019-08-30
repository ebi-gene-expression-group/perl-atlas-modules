#!/usr/bin/env perl
#
# $Id: Role.pm 1853 2007-12-13 17:53:43Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::Role;
use base 'ArrayExpress::AutoSubmission::DB';
__PACKAGE__->table('roles');
__PACKAGE__->columns(
    All => qw(
        id
        name
        info
        is_deleted
        )
);
__PACKAGE__->has_many(
    users => [ 'ArrayExpress::AutoSubmission::DB::RoleUser' => 'user_id' ] );
__PACKAGE__->has_many(
    permissions => [
        'ArrayExpress::AutoSubmission::DB::PermissionRole' => 'permission_id'
    ]
);

1;
