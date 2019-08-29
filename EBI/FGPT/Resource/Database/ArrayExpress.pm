#!/usr/bin/env perl
#
# EBI/FGPT/Resource/Database/ArrayExpress.pm

package EBI::FGPT::Resource::Database::ArrayExpress;

use strict;
use warnings;

use Moose;
use MooseX::FollowPBP;

use EBI::FGPT::Config qw($CONFIG);

extends 'EBI::FGPT::Resource::Database';

sub BUILD {

	my ($self) = @_;

	$self->set_dsn( $CONFIG->get_AE2_DSN() );
	$self->set_username( $CONFIG->get_AE2_USERNAME() );
	$self->set_password( $CONFIG->get_AE2_PASSWORD() );

}

sub get_array_design_name_by_acc {

	my ( $self, $acc ) = @_;
	my $query = "select NAME from PLAT_DESIGN WHERE ACC = ?";
	my $dbh   = $self->get_dbh or die "Error: could not get AE dbh\n";

	my $sth = $dbh->prepare($query);
	$sth->execute($acc)
	  or die "Error retrieving array design for $acc: " . $sth->errstr;

	my $array_design_name;

	while ( my @row = $sth->fetchrow_array ) {
		$array_design_name = $row[0];
	}

	$sth->finish;
	$dbh->disconnect;

	return $array_design_name;
}

sub check_md5_in_database {

	my ( $self, $md5 ) = @_;
	my $query =
	  "select ACC, NAME, MD5SUM  from DATA where MD5SUM= ?";
	my $dbh = $self->get_dbh or die "Error: could not get AE dbh\n";
	my $sth = $dbh->prepare($query);
	$sth->execute($md5)
	  or die "Error retrieving accession, file name and MD5sum for MD5 $md5: "
	  . $sth->errstr;

	# Fetches all data returned by query
	# Sometimes more than one row is returned for query
	# this happens a lot with GEO
	my $md5_info = $sth->fetchall_arrayref();

	$sth->finish;
	$dbh->disconnect;

	return $md5_info;

}

1;

