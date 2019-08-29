
=head1 NAME

Atlas::ExptFinder::Differetial.pm -- search ArrayExpress for differential Atlas candidates.

=head1 DESCRIPTION

This package extends Atlas::ExptFinder.pm to run checks specific to differential experiments.

=head1 SYNOPSIS
use Atlas::ExptFinder::Differential

# ...

my $searcher = Atlas::ExptFinder::Differential->new;
$searcher->find_candidates( "Zea mays" );
$searcher->write_candidates_to_file( "Zea mays" );

=head1 AUTHOR

Expression Atlas team <arrayexpress-atlas@ebi.ac.uk>

=cut

package Atlas::ExptFinder::Differential;

use Moose;
use MooseX::FollowPBP;
use File::Spec;
use Log::Log4perl;
use Bio::MAGETAB::Util::Reader;
use EBI::FGPT::Config qw( $CONFIG );
use Atlas::Common qw( create_atlas_site_config );
use EBI::FGPT::Reader::MAGETAB;

extends 'Atlas::ExptFinder';

has 'analysis_type' => (
	is		=> 'ro',
	isa		=> 'Str',
	default => 'differential'
);

has 'atlas_array_designs' => (
    is => 'rw',
    isa => 'HashRef',
    builder => '_build_atlas_array_designs'
);

my $logger = Log::Log4perl::get_logger;

sub remove_ineligible_experiments {

    my ( $self ) = @_;

    my $candidates = $self->get_candidates_hash;

    foreach my $expAcc ( keys %{ $candidates } ) {

        $logger->info( "Checking $expAcc ..." );

        ( my $pipeline = $expAcc ) =~ s/E-(\w{4})-\d+/$1/;

        # Get load dir.
        my $ae2loadDir = File::Spec->catfile( 
            $CONFIG->get_AE2_LOAD_DIR, 
            "EXPERIMENT",
            $pipeline,
            $expAcc,
        );
        
        my $ae2idfFile = File::Spec->catfile(
            $ae2loadDir,
            $expAcc . ".idf.txt"
        );
        
        # A parser to run the Atlas eligibility checks.
        #my $parser = EBI::FGPT::Reader::MAGETAB->new( 
        #    {
        #        'check_sets' => {
        #            'EBI::FGPT::CheckSet::AEAtlas' => 'ae_atlas_eligibility'
        #        },
        #        'skip_data_checks'  => 1,
        #        'idf'               => $ae2idfFile,
        #        'data_dir'          => $ae2loadDir
        #    }
        #);
        
        #$parser->parse;
        
        #$parser->print_checker_status;

        #my $atlasCheckSet = $parser->get_check_set_objects->{ 'EBI::FGPT::CheckSet::AEAtlas' };

        #unless( $atlasCheckSet ) {
        #    $logger->info( "No Atlas check set found for $expAcc." );
        #    next;
        #}
        
        #if( scalar @{ $atlasCheckSet->get_atlas_fail_codes } ) {

        #    my $failCodes = join ", ", @{ $atlasCheckSet->get_atlas_fail_codes };

        #    $logger->error(
        #        "$expAcc has Atlas fail codes: $failCodes"
        #    );

        #    delete $candidates->{ $expAcc };   
        #}
        #}

        #$self->set_candidates_hash( $candidates );
#}
    
        my $reader = Bio::MAGETAB::Util::Reader->new( {
                idf => $ae2idfFile,
                relaxed_parser => 1,
                ignore_datafiles => 1
            });
        
        my $magetab;

        eval {
            $magetab = $reader->parse;
        };

        if( $@ ) { 
            
            $logger->error( "Could not parse MAGETAB for $expAcc." );

           delete $candidates->{ $expAcc };
            
           next; 
        }
        
        my @assays = $magetab->get_assays;

        if( @assays < 6 ) {

            $logger->info( "Not enough assays in $expAcc" );

            delete $candidates->{ $expAcc };

            next;
        }

        # Collect the array designs.
        my $arrayDesigns = {};

        # $h->{ factorValueString }->{ assayname } = 1;
        my $factorValuesToAssays = {};

        foreach my $assay ( @assays ) {
            
            if( $assay->has_arrayDesign ) {
                # Save the array design to check against Atlas.
                my $arrayDesign = $assay->get_arrayDesign->get_name;
                $arrayDesigns->{ $arrayDesign } = 1;
            }
            
            # Check raw data files.
            my $rawDataForAssay = _check_raw_data_file( $assay );
            
            unless( $rawDataForAssay ) {

                $logger->info( 
                   "No raw data for assay ",
                   $assay->get_name,
                   " in $expAcc"
               );

               delete $candidates->{ $expAcc };
            
               last;
            }

            # FIXME: Check two-colour as don't want these at the moment....
            my $twoColour = _check_twocolour( $assay );

            if( $twoColour ) {
               $logger->info(
                   $assay->get_name,
                   " seems to have two-colour design."
               );
                
               delete $candidates->{ $expAcc };
            
               last;
            }
            
            my $factorValueString = _get_assay_factorvalue_string( $assay );
            
            if( $factorValueString ) {
                $factorValuesToAssays->{ $factorValueString }->{ $assay->get_name } = 1;
            }
        }
        
            if( keys %{ $arrayDesigns } ) {

            my $atlasArrayDesigns = $self->get_atlas_array_designs;
            
            foreach my $expArray ( keys %{ $arrayDesigns } ) {

                unless( $atlasArrayDesigns->{ $expArray } ) {

                    $logger->info( "$expAcc uses an array design which is not in Atlas ($expArray)." );
                    
                    delete $candidates->{ $expAcc };

                    last;
                }
            }
        }
        
        # If we found any factors, check if there are enough replicates.
        if( keys %{ $factorValuesToAssays } ) {
            # Now check that at least two factor value strings have at least three
            # assays.
               my $enoughReps = _check_reps( $factorValuesToAssays );

            unless( $enoughReps ) {

               $logger->info( "$expAcc doesn't have enough assay groups with enough replicates." );

               delete $candidates->{ $expAcc };
            }
        }
    }
    
    $self->set_candidates_hash( $candidates );
}


sub _build_atlas_array_designs {

    my $atlasSiteConfig = create_atlas_site_config;

    return $atlasSiteConfig->get_atlas_supported_adfs;
}


sub _check_reps {

    my ( $factorValuesToAssays ) = @_;
    
    my $stringsWithEnoughReps = 0;

    foreach my $fvString ( keys %{ $factorValuesToAssays } ) {

        if( ( keys %{ $factorValuesToAssays->{ $fvString } } ) > 2 ) {
            $stringsWithEnoughReps++;
        }
    }
    
    if( $stringsWithEnoughReps >= 2 ) { return 1; }
    else { return 0; }
}
            
sub _get_assay_factorvalue_string {

    my ( $assay ) = @_;

    my @sdrfRows = $assay->get_sdrfRows;

    my $factors = {};

    foreach my $sdrfRow ( @sdrfRows ) {

        if( $sdrfRow->has_factorValues ) {

            my @factorValues = $sdrfRow->get_factorValues;

            foreach my $factorValue ( @factorValues ) {
                
                my $type = $factorValue->get_factor->get_factorType;

                my $value;

                if( $factorValue->has_term ) {

                    $value = $factorValue->get_term->get_value;
                }
                elsif( $factorValue->has_measurement ) {

                    $value = $factorValue->get_measurement->get_value;
                }
                else { next; }

                $factors->{ $type }->{ $value } = 1;
            }
        }
        else {
            return;
        }
    }

    # Now we have all the factors for this assay.
    my @factorValues = ();

    foreach my $type ( sort keys %{ $factors } ) {

        push @factorValues, keys %{ $factors->{ $type } };
    }

    return join "; ", @factorValues;
}

sub _check_twocolour {

    my ( $assay ) = @_;

    my @inputEdges = $assay->get_inputEdges;

    if( @inputEdges > 1 ) {
        return 1;
    }
    else {
        return 0;
    }
}


sub _check_raw_data_file {

    my ( $assay ) = @_;

    my @sdrfRows = $assay->get_sdrfRows;

    foreach my $sdrfRow ( @sdrfRows ) {

        my @nodes = $sdrfRow->get_nodes;

        foreach my $node ( @nodes ) {

            if( ref( $node ) eq "Bio::MAGETAB::DataFile" ) {

                if( $node->get_dataType->get_value eq "raw" ) {
                    return 1;
                }
            }
        }
    }
    
    # If we're still here, there must not have been any raw data.
    return 0;
}
   











1;
