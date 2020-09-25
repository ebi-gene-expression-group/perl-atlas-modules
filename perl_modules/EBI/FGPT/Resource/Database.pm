#!/usr/bin/env perl
#
# EBI/FGPT/Resource/Database.pm


=pod

=head1 NAME

EBI::FGPT::Resource::Database

=head1 SYNOPSIS
 
 use EBI::FGPT::Resource::Database;
 
 my $ae_db = EBI::FGPT::Resource::Database::ArrayExpress->new(
     'dsn'                => $dns,
     'username'           => $username,
     'password'           => $password,
 );
     
 my $ae_dbh = $ae_db->get_dbh;
 

=head1 DESCRIPTION

A module providing basic method(s) for connecting to a database

=cut


package EBI::FGPT::Resource::Database;

use strict;
use warnings;

use Moose;
use MooseX::FollowPBP;
use DBI;
#use DBD::Oracle;

use Log::Log4perl qw(:easy);

# Can't set attributes as "required" as the new database object is created like an
# empty shell before we have the attribute values to fill the shell!

has 'dsn'        => (is => 'rw', isa => 'Str');
has 'username'   => (is => 'rw', isa => 'Str');
has 'password'   => (is => 'rw', isa => 'Str');
has 'dbh'        => (is => 'rw', lazy => 1, builder => '_connect_to_database');


sub _connect_to_database {

    my ($self) = @_;
    
    # Do some sanity checks first!
        
    if (!$self->get_dsn || !$self->get_username || !$self->get_password) {
        LOGDIE ("Either DNS, username or password is missing. Cannot connect to ".ref($self). " database.\n");       
    }
    
    my $dbh = DBI->connect( $self->get_dsn, $self->get_username, $self->get_password )
        or LOGDIE "Error: Cannot connect to database instance: $DBI::errstr\n";

    return $dbh;
}

1;
