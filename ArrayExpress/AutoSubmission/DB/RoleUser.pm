#!/usr/bin/env perl
#
# $Id: RoleUser.pm 1853 2007-12-13 17:53:43Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::RoleUser;
use base 'ArrayExpress::AutoSubmission::DB';
__PACKAGE__->table('roles_users');
__PACKAGE__->columns(
    Primary => qw(
        user_id
        role_id
        )
);
__PACKAGE__->has_a( role_id => 'ArrayExpress::AutoSubmission::DB::Role' );
__PACKAGE__->has_a( user_id => 'ArrayExpress::AutoSubmission::DB::User' );

1;
