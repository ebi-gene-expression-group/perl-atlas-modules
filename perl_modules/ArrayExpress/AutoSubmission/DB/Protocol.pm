#!/usr/bin/env perl
#
# $Id: Protocol.pm 2379 2011-09-29 15:12:26Z farne $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::DB::Protocol;
use base 'ArrayExpress::AutoSubmission::DB';
use base 'ArrayExpress::AutoSubmission::DB::Accessionable';

use EBI::FGPT::Common qw(date_now);

use EBI::FGPT::Resource::Database::ArrayExpress;

__PACKAGE__->table('protocols');
__PACKAGE__->columns(
    All => qw(
        id
        accession
        user_accession
        expt_accession
        name
        date_last_processed
        comment
        is_deleted
        )
);

sub reassign_protocol {    # Class method.

    my ( $class, $user_accession, $expt_accession, $protocol_name ) = @_;

    # This is non-essential, but ends up in the database.
    $protocol_name ||= q{Unknown};

    # Search for (user_accession eq accession), then connects to AE if
    # $CONFIG allows it to check for (preloaded accession eq
    # user_accession). Finally checks for (user_accession eq
    # user_accession and expt_accession eq expt_accession). Creates a
    # new protocol in db and assigns accession if not found.
    my $prot_accession;

    # First look for simple reuse of DB accessions
    my $db_protocol
        = ArrayExpress::AutoSubmission::DB::Protocol->retrieve(
            accession  => $user_accession,
            is_deleted => 0,
	);

    if ( $db_protocol ) {
        $prot_accession = $db_protocol->accession();
    }
    else {

        # Otherwise, check that ArrayExpress doesn't already have the
        # protocol, if possible.
        if ( my $ae2 = EBI::FGPT::Resource::Database::ArrayExpress->new ){
            
            my $ae2dbh = $ae2->get_dbh;

            my $query = "select acc from protocol where acc = ?";

            my $ae2sh = $ae2dbh->prepare( $query )
                or die "Could not prepare query for protocol in AE2DB: ", $ae2dbh->errstr, "\n";
            
            print STDOUT (
            "Querying ArrayExpress 2 for protocol accession $user_accession\n"
            );

            # Query on protocol identifier, return the user
            # accession if it's found.
            $ae2sh->execute( $user_accession )
                or die "Could not execute query for protocol in AE2DB: ", $ae2sh->errstr() . " $DBI::errstr" ;

            my $arrayref = $ae2sh->fetchall_arrayref;

            if ( scalar @$arrayref ) {
            
                print STDOUT "Using preexisting ArrayExpress 2 protocol accession $user_accession\n";

                $prot_accession = $user_accession;
            }

            $ae2dbh->disconnect;
        }	
        
        # If no AE accession, check user and expt accessions,
        # creating a new protocol if necessary.
        unless ($prot_accession) {
            unless ($db_protocol) {
                $db_protocol
                    = ArrayExpress::AutoSubmission::DB::Protocol->find_or_create(
                    user_accession => $user_accession,
                    expt_accession => $expt_accession,
                    is_deleted     => 0,
                );
                unless ($db_protocol->name()) {
                    $db_protocol->set(
                    name => $protocol_name,
                    );
                }
            }
            $prot_accession = $db_protocol->get_accession();
        }
    }

    # If we're using a protocol from the autosubs system, set the date
    # to record its usage.
    if ( $db_protocol ) {
        $db_protocol->set(
            date_last_processed => date_now(),
        );
        $db_protocol->update();
    }

    return $prot_accession;
}

1;
