#!/usr/bin/env perl
#
# $Id: PermissionRole.pm 1853 2007-12-13 17:53:43Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::PermissionRole;
use base 'ArrayExpress::AutoSubmission::DB';
__PACKAGE__->table('permissions_roles');
__PACKAGE__->columns(
    Primary => qw(
        role_id
        permission_id
        )
);
__PACKAGE__->has_a( role_id => 'ArrayExpress::AutoSubmission::DB::Role' );
__PACKAGE__->has_a(
    permission_id => 'ArrayExpress::AutoSubmission::DB::Permission' );

1;
