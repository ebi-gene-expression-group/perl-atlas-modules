#!/usr/bin/env perl
#
=pod

=head1 NAME

Atlas::AtlasConfig::FactorsConfigFactory - functions to create an Atlas::AtlasConfig::FactorsConfig object.

=head1 SYNOPSIS

use Atlas::AtlasConfig::FactorsConfigFactory qw( create_factors_config );

my $factorsConfig = create_factors_config(
    $atlasAssays    # Hash of Atlas::Assay objects
);

=head1 DESCRIPTION

This module exports a function to create the Atlas factors config for baseline
experiments, as a Moose object.

=cut

package Atlas::AtlasConfig::FactorsConfigFactory;

use strict;
use warnings;
use 5.10.0;

use Moose;
use MooseX::FollowPBP;
use Log::Log4perl qw( :easy );
use Data::Dumper;

use Atlas::AtlasConfig::FactorsConfig;


use base 'Exporter';
our @EXPORT_OK = qw(
    create_factors_config
);

my $logger = Log::Log4perl::get_logger;

=head1 METHODS

=over 2

=item create_factors_config

Takes a hash of Atlas::Assay object, and returns an
Atlas::AtlasConfig::FactorsConfig object, based on the factors it finds in the
assays.

=cut

sub create_factors_config {

    my ( $atlasAssays, $commandArgs ) = @_;

    # Get the user-specified default query factor, if any.
    my $defaultQueryFactor = $commandArgs->{ "default_query_factor" };

    my $displayName = $commandArgs->{ "display_name" };
    
    # Get a hash of all the factors in this set of assays.
    my $allFactors = _get_all_factors( $atlasAssays );

    # If we didn't get a default query factor from the user, decide one
    # automatically.
    unless( $defaultQueryFactor ) {
        $defaultQueryFactor = _decide_query_factor( $allFactors );
    }
    
    # Create the basic FactorsConfig object.
    my $factorsConfig = Atlas::AtlasConfig::FactorsConfig->new(
        default_query_factor_type => _convert_factor_type_case( $defaultQueryFactor ),
        landing_page_display_name => $displayName
    );

    # Check number of factors. If we have more than one, we need to set the
    # filter factors and decide default values for the filter factors (those
    # apart from the default query factor).
    if( scalar( keys %{ $allFactors } ) > 1 ) {

        # Create the menu filter factors.
        $factorsConfig->set_menu_filter_factor_types(
            _create_menu_filter_factors( $allFactors )
        );

        # Decide the filter factor values.
        $factorsConfig->set_default_filter_factors( 
            _decide_filter_factors( $atlasAssays, $defaultQueryFactor )
        );
    }
    
    # Add data provider information, if it was provided. This is only for
    # big consortia e.g. BLUEPRINT, Genentech, ...
    if( $commandArgs->{ "provider_url" } && $commandArgs->{ "provider_name" } ) {
        
        $factorsConfig->set_data_provider_url( $commandArgs->{ "provider_url" } );

        $factorsConfig->set_data_provider_description( $commandArgs->{ "provider_name" } );
    }

    # Add data usage agreement, if provided.
    if( $commandArgs->{ "agreement" } ) {
        $factorsConfig->set_data_usage_agreement( $commandArgs->{ "agreement" } );
    }
    
    # Add curated sequence flag, if provided.
    if( $commandArgs->{ "sequence" } ) {
        $factorsConfig->set_curated_sequence( 1 );
    }

    return $factorsConfig;
}
    

# Decide which factor to use as the default query factor. For now, this is the
# one with the most different values. If there is more than one factor to
# choose from after sorting, the default is just chosen by sorting
# alphanumerically.
sub _decide_query_factor {

    my ( $allFactors ) = @_;
    
    # Get all the factors and their values for all assays.
    # If there is only one factor, we can just return the type here.
    if( scalar( keys %{ $allFactors } == 1 ) ) {
    
        return ( keys %{ $allFactors } )[ 0 ];
    }
    
    # If we're still here, we must have more than one factor, so we need to
    # decide which one to use as the default query factor.
    # Count values for each type.
    my $factorTypeCounts = {};

    foreach my $type ( keys %{ $allFactors } ) {

        my $valueCount = scalar( keys %{ $allFactors->{ $type } } );

        $factorTypeCounts->{ $type } = $valueCount;
    }

    # Find the factor with the most values. Reading left to right, the first
    # "sort" clause sorts keys by values. The second "sort" clause sorts keys
    # alphanumerically.
    my @typesByNumValues = sort { $factorTypeCounts->{ $b } <=> $factorTypeCounts->{ $a } } ( sort keys %{ $factorTypeCounts } );
    
    # Return the first one. This is the one with the most values.
    return $typesByNumValues[ 0 ];
}


# Get a hash of all the factors in a set of assays.
sub _get_all_factors {
    
    my ( $atlasAssays ) = @_;

    my $allFactors = {};

    foreach my $assayName ( keys %{ $atlasAssays } ) {

        my $assay = $atlasAssays->{ $assayName };

        my $factors = $assay->get_factors;
        
        foreach my $type ( keys %{ $factors } ) {

            foreach my $value ( keys %{ $factors->{ $type } } ) {
                
                $allFactors->{ $type }->{ $value } = 1;
            }
        }
    }

    return $allFactors;
}


sub _convert_factor_type_case {

    my ( $factorType ) = @_;

    $factorType =~ s/ /_/g;

    $factorType = uc( $factorType );

    return $factorType;
}


sub _create_menu_filter_factors {

    my ( $allFactors ) = @_;
    
    my @factorTypes = sort keys %{ $allFactors };

    my @factorTypesForConfig = ();

    foreach my $factorType ( @factorTypes ) {

        push @factorTypesForConfig, _convert_factor_type_case( $factorType );
    }

    return \@factorTypesForConfig;
}


sub _decide_filter_factors {

    my ( $atlasAssays, $defaultQueryFactor ) = @_;

    # Need to find the combination of non-default-query-factor values which are
    # found in combination with the highest number of values from the default
    # query factor, so that the default query shows the largest heatmap
    # possible.

    # Collect the unique filter factor combinations and the default query
    # factor values they occur with.
    my $filterFactorCombinations = _collect_filter_factor_combinations( $atlasAssays, $defaultQueryFactor );
    
    # Now we have the filter factor combinations, find the one with the highest
    # number of default query factor values.
    my $filterFactorQueryValueCounts = {};

    foreach my $combination ( keys %{ $filterFactorCombinations } ) {

        my $defaultQueryValueCount = scalar( keys %{ $filterFactorCombinations->{ $combination }->{ "default_query_factor_values" } } );

        $filterFactorQueryValueCounts->{ $combination } = $defaultQueryValueCount;
    }

    # Find the combination with the most values. Reading left to right, the first
    # "sort" clause sorts keys by values (counts in this case). The second
    # "sort" clause sorts keys (combination names) alphanumerically.
    my @combinationsByNumValues = sort { 
        $filterFactorQueryValueCounts->{ $b } <=> $filterFactorQueryValueCounts->{ $a } 
    } ( sort keys %{ $filterFactorQueryValueCounts } );
    
    # The first element of the array created above is the string concatenation
    # of the values for the default filter factor combination.
    my $defaultFilterFactorCombination = $combinationsByNumValues[ 0 ];
    
    my @defaultFilterFactors = ();
    
    foreach my $type ( keys %{ $filterFactorCombinations->{ $defaultFilterFactorCombination }->{ "filter_factors" } } ) {

        my $value = ( keys %{ $filterFactorCombinations->{ $defaultFilterFactorCombination }->{ "filter_factors" }->{ $type } } )[ 0 ];
        
        my $filterFactor = { 
            "type"  => _convert_factor_type_case( $type ),
            "value" => $value
        };

        push @defaultFilterFactors, $filterFactor;
    }

    return( \@defaultFilterFactors );
}


# Collect the unique filter factor combinations and the default query
# factor values they occur with.
sub _collect_filter_factor_combinations {

    my ( $atlasAssays, $defaultQueryFactor ) = @_;

    my $filterFactorCombinations = {};

    foreach my $assay ( values %{ $atlasAssays } ) {

        my $assayFactors = $assay->get_factors;

        # Get the value for the default query factor for this assay.
        my $defaultQueryFactorValue = ( keys %{ $assayFactors->{ $defaultQueryFactor } } )[ 0 ];
        
        # Make a copy of the assay factors hash.
        my %assayFilterFactors = %{ $assayFactors };

        # Delete the default query factor as we don't want it in the filter
        # factors.
        delete $assayFilterFactors{ $defaultQueryFactor };

        my $factorValueString = _factor_values_to_string( \%assayFilterFactors );
        
        if( $filterFactorCombinations->{ $factorValueString } ) {

            unless( 
                $filterFactorCombinations->{ $factorValueString }->{ "default_query_factor_values" }->{ $defaultQueryFactorValue }
            ) {
                $filterFactorCombinations->{ $factorValueString }->{ "default_query_factor_values" }->{ $defaultQueryFactorValue } = 1;
            }
        }
        else {
            $filterFactorCombinations->{ $factorValueString }->{ "filter_factors" } = \%assayFilterFactors;
            $filterFactorCombinations->{ $factorValueString }->{ "default_query_factor_values" }->{ $defaultQueryFactorValue } = 1;
        }
    }

    return $filterFactorCombinations;
}


sub _factor_values_to_string {

    my ( $factors ) = @_;

    my @values = ();

    foreach my $type ( sort keys %{ $factors } ) {

        push @values, ( sort keys %{ $factors->{ $type } } );
    }

    my $fvString = join "; ", @values;

    return $fvString;
}














1;
