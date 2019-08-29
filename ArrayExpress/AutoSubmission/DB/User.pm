#!/usr/bin/env perl
#
# $Id: User.pm 1853 2007-12-13 17:53:43Z tfrayner $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::User;
use base 'ArrayExpress::AutoSubmission::DB';
__PACKAGE__->table('users');
__PACKAGE__->columns(
    All => qw(
        id
        login
        name
        password
	email
        modified_at
        created_at
        access
        is_deleted
        )
);
__PACKAGE__->has_many(
    experiments => 'ArrayExpress::AutoSubmission::DB::Experiment' );
__PACKAGE__->has_many(
    roles => [ 'ArrayExpress::AutoSubmission::DB::RoleUser' => 'role_id' ] );

1;
