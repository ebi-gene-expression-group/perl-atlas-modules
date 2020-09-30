#!/usr/bin/env perl
#
# EBI/FGPT/Resource/pgDatabase/pgSCXA.pm
#
# pgSCXA.pm suhaib mohammed
# Adapted and modified from pgGXA.pm

package EBI::FGPT::Resource::Database::pgSCXA;

use strict;
use warnings;
use 5.10.0;

use Moose;
use MooseX::FollowPBP;

use Encode qw( encode );

use EBI::FGPT::Config qw($CONFIG);

extends 'EBI::FGPT::Resource::pgDatabase';

sub BUILD{

    my ($self) = @_;
    $self->set_dsn( $CONFIG->get_AE_SC_PG_DSN() );
    $self->set_username ( $CONFIG->get_AE_SC_PG_USERNAME() );
    $self->set_password ( $CONFIG->get_AE_SC_PG_PASSWORD() );

}


sub fetch_experiment_celltypes_from_sc_atlasdb {

    my ( $self, $accessions, $logger ) = @_;

    my $accessions4query = "'" . join( "', '", @{ $accessions } ) . "'";

    my $query = "
        SELECT distinct EXPERIMENT_ACCESSION, VALUE FROM SCXA_CELL_GROUP
        WHERE EXPERIMENT_ACCESSION=($accessions) and 
        VARIABLE like '%cell%' and VALUE !='Not available'";

    # Get the database handle.
    my $atlasDBH = $self->get_dbh
        or $logger->logdie( "Could not get database handle: $DBI::errstr" );

    $logger->info( "Querying SC Atlas database for experiment cell types..." );

    # Prepare the query, returns statement handler.
    my $atlasSH = $atlasDBH->prepare( $query )
        or $logger->logdie( "Could not prepare query: ", $atlasDBH->errstr );

    # Execute the query.
    $atlasSH->execute or $logger->logdie( "Could not execute query: ", $atlasSH->errstr );

    # Empty hash for the results.
    my $expAcc2celltypes = {};

    # Go through the results and get the accessions and values.
    while( my $row = $atlasSH->fetchrow_arrayref ) {

        my ( $expAcc, $expCellTypes ) = @{ $row };

        $expAcc2celltypes->{ $expAcc } = $expCellTypes;
    }

    # Disconnect from the database.
    $atlasSH->finish;

    $logger->info( "Query successful." );

    return $expAcc2celltypes;
}


sub fetch_last_processing_dates_from_sc_atlasdb {

    my ( $self, $accessions, $logger ) = @_;

    my $accessions4query = "'" . join( "', '", @{ $accessions } ) . "'";

    my $query = "
        select ACCESSION, to_char( LAST_UPDATE, 'YYYY-MM-DD HH24:MI:SS' )
        from EXPERIMENT
        where ACCESSION in ($accessions4query)
        and PRIVATE = 'F'";

    my $atlasDBH = $self->get_dbh
        or $logger->logdie( "Could not get database handle: $DBI::errstr" );

    $logger->info( "Querying SC Atlas database for last processing date of experiments..." );

    # Get statement handle by preparing query.
    my $atlasSH = $atlasDBH->prepare( $query )
        or $logger->logdie( "Could not prepare query: ", $atlasDBH->errstr );

    # Execute the query.
    $atlasSH->execute or $logger->logdie( "Could not execute query: ", $atlasSH->errstr );

    my $expAcc2date = {};

    while( my $row = $atlasSH->fetchrow_arrayref ) {

        my ( $expAcc, $procDate ) = @{ $row };

        # Add the dates to the hash.
        unless( $expAcc2date->{ $expAcc } ) {
            $expAcc2date->{ $expAcc } = $procDate;
        }
    }

    $atlasSH->finish;

    $logger->info( "Query successful." );

    return $expAcc2date;
}


sub fetch_pmids_from_sc_atlasdb {

    my ( $self, $accessions, $logger ) = @_;

    my $accessions4query = "'" . join( "', '", @{ $accessions } ) . "'";

    my $query = "select ACCESSION, PUBMED_IDS from EXPERIMENT where ACCESSION in ($accessions4query)";

    my $atlasDBH = $self->get_dbh
        or $logger->logdie( "Could not get database handle: $DBI::errstr" );

    $logger->info( "Querying SC Atlas database for PubMed IDs..." );

    # Get statement handle by preparing query.
    my $atlasSH = $atlasDBH->prepare( $query )
        or $logger->logdie( "Could not prepare query: ", $atlasDBH->errstr );

    # Execute the query.
    $atlasSH->execute or $logger->logdie( "Could not execute query: ", $atlasSH->errstr );

    my $expAcc2pmids = {};

    while( my $row = $atlasSH->fetchrow_arrayref ) {

        my ( $expAcc, $pmidString ) =  @{ $row };

        my $pmids = [];

        if( $pmidString ) {
            my @splitString = split( ", ", $pmidString );

            push @{ $pmids }, @splitString;
        }

        $expAcc2pmids->{ $expAcc } = $pmids;
    }

    $atlasSH->finish;

    $logger->info( "Query successful." );

    return $expAcc2pmids;
}



sub fetch_experiments_collections_from_sc_atlasdb {

    my ( $self, $logger ) = @_;

    my $query = "
        SELECT distinct EXP_ACC, COLL_ID FROM EXPERIMENT2COLLECTION 
        order by EXP_ACC, COLL_ID";

    my $atlasDBH = $self->get_dbh;

    $logger->info( "Querying SC Atlas database for experiment collections..." );

    # Get statement handle by preparing query.
    my $atlasSH = $atlasDBH->prepare( $query )
        or $logger->logdie( "Could not prepare query: ", $atlasDBH->errstr );

    # Execute the query.
    $atlasSH->execute or $logger->logdie( "Could not execute query: ", $atlasSH->errstr );

    my $expAcc2collections = {};

    while( my $row = $atlasSH->fetchrow_arrayref ) {

        my ( $expAcc, $collectionString ) =  @{ $row };

        my $collections = [];

        if( $pmidString ) {
            my @splitString = split( ", ", $collectionString );

            push @{ $collections }, @splitString;
        }

        $expAcc2collections->{ $expAcc } = $collections;
    }

    $atlasSH->finish;

    $logger->info( "Query successful." );

    return $expAcc2collections;
}


1;
