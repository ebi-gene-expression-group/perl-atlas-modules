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

    my ( $self, $logger ) = @_;

    my $query = "
        SELECT distinct EXPERIMENT_ACCESSION, VALUE FROM SCXA_CELL_GROUP
        WHERE VARIABLE like '%cell%' and VALUE !='Not available'";

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
    my $expAcc;
    my $celltypes;

    # Go through the results and get the accessions and values.
    while( my $row = $atlasSH->fetchrow_arrayref ) {

        ($expAcc, $celltypes) = @{ $row }; 

        unless( exists( $expAcc2celltypes->{ $expAcc } ) ) {

                $expAcc2celltypes->{ $expAcc } = [ $celltypes ];
        }
        else {
            push @{ $expAcc2celltypes->{ $expAcc } }, $celltypes;
        } 
              
    }
    
    # Disconnect from the database.
    $atlasSH->finish;
    $logger->info( "Query successful." );

    return $expAcc2celltypes;
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
    my $expAcc;
    my $collection;

    # Go through the results and get the accessions and values.
    while( my $row = $atlasSH->fetchrow_arrayref ) {

        ($expAcc, $collection) = @{ $row };

        unless( exists( $expAcc2collections->{ $expAcc } ) ) {

                $expAcc2collections->{ $expAcc } = [ $collection ];
        }
        else {
            push @{ $expAcc2collections->{ $expAcc } }, $collection;
        }

    }


    $atlasSH->finish;

    $logger->info( "Query successful." );

    return $expAcc2collections;
}

sub fetch_experiment_genes_from_sc_atlasdb {

    my ( $self, $logger ) = @_;

    my $query = "
        SELECT distinct gene_id from scxa_cell_group_marker_gene_stats WHERE mean_expression >="."'$ENV{'CPM_THRESHOLD'}'"."and expression_type='0'
        UNION
        SELECT distinct gene_id from scxa_cell_group_marker_gene_stats WHERE mean_expression >="."'$ENV{'TPM_THRESHOLD'}'"."and expression_type='1' ORDER BY gene_id";

    my $atlasDBH = $self->get_dbh;

    $logger->info( "Querying SC Atlas database for gene information..." );

    # Get statement handle by preparing query.
    my $atlasSH = $atlasDBH->prepare( $query )
        or $logger->logdie( "Could not prepare query: ", $atlasDBH->errstr );

    # Execute the query.
    $atlasSH->execute or $logger->logdie( "Could not execute query: ", $atlasSH->errstr );

    my $gene2collections = [];
    my $gene;

    # Go through the results and get the accessions and values.
    while( my $row = $atlasSH->fetchrow_arrayref ) {

        ($gene) = @{ $row };

        if ( $gene )  {

            push @{ $gene2collections }, $gene;
        }

    }


    $atlasSH->finish;

    $logger->info( "Query successful." );

    return $gene2collections;
}

1;

