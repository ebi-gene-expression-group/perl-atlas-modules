#!/usr/bin/env perl
=pod

=head1 NAME

Atlas::FPKMmatrix- aggegate expression values. Historical name.

=head1 SYNOPSIS

Main method is at the bottom.
It wants:
- the experiment config
- whether to aggregate into quartiles after also aggregating into technical replicates
- input and output streams
sub run {
    my ($experiment_config, $do_quartiles, $in, $out) = @_;
}

=cut

use 5.10.0;

package Atlas::FPKMmatrix;

use List::MoreUtils;
use List::Util;

#Adapted from: https://metacpan.org/source/SHLOMIF/Statistics-Descriptive-3.0612/lib/Statistics/Descriptive.pm#L620
# valid values of $QuantileNumber: 1,2,3
sub quantile_of_sorted_array {
    my ( $expressionsSorted, $QuantileNumber ) = @_;

    my @data = @$expressionsSorted;
    my $count = @data;

    my $K_quantile = ( ( $QuantileNumber / 4 ) * ( $count - 1 ) + 1 );
    my $F_quantile = $K_quantile - POSIX::floor($K_quantile);
    $K_quantile = POSIX::floor($K_quantile);

    # interpolation
    my $aK_quantile     = @data[ $K_quantile - 1 ];
    return $aK_quantile if ( $F_quantile == 0 );
    my $aKPlus_quantile = @data[$K_quantile];

    # Calcul quantile
    my $quantile = $aK_quantile
      + ( $F_quantile * ( $aKPlus_quantile - $aK_quantile ) );

    return $quantile;
}

sub calculate_rounded_quartiles {
    my ( $expressions ) = @_;

    my @expressionsSorted = sort {$a <=> $b} @$expressions;

    return join "," , map {round( $_ )} (
        @expressionsSorted[0],
        quantile_of_sorted_array(\@expressionsSorted, 1),
        quantile_of_sorted_array(\@expressionsSorted, 2),
        quantile_of_sorted_array(\@expressionsSorted, 3),
        @expressionsSorted[-1]
    );
}

#Adapted from: https://metacpan.org/source/SHLOMIF/Statistics-Descriptive-3.0612/lib/Statistics/Descriptive.pm#L237
sub calculate_median {
    my ( $expressions ) = @_;

    my @expressionsSorted = sort {$a <=> $b} @$expressions;
    my $count = @expressionsSorted;

    ##Even or odd
    if ($count % 2){
        return @expressionsSorted[($count-1)/2];
    } else {
        return (
            (@expressionsSorted[($count)/2] + @expressionsSorted[($count-2)/2] ) / 2
        );
    }
}

sub round {
    my ( $expression_value ) = @_;

    if( $expression_value > 1 ) {
        return int( $expression_value + 0.5 );
    }
    elsif( $expression_value > 0 ) {
        return int( ( 10 * $expression_value ) + 0.5 ) / 10;
    }
    elsif( $expression_value == 0 ) {
        return 0;
    }
    else {
        die "Don't know what to do with expression_value value \"$expression_value\"" ;
    }
}

sub group_row_with_indices {
	my ($row,$indices) = @_;
	my @result;
	for my $i (0 .. $#{$row}) {
        next unless exists($indices->{$i});
		my $j = $indices->{$i};
		$result[$j]//=[];
		push @{$result[$j]} , $row->[$i];
	}
	return \@result;
}

# Iterate through the config object. Make two hashes: one grouping assays by replicate id, and one grouping replicates into assay groups. 
sub groups_based_on_experiment_config {

    my ( $experiment_config ) = @_;

    my %replicates_for_assays;
    my %assay_groups_for_replicates;

    for my $analytics ( @{ $experiment_config->get_atlas_analytics } ) {
        for my $assay_group ( @{ $analytics->get_atlas_assay_groups } ) {
            for my $biological_replicate ( @{ $assay_group->get_biological_replicates } ) {
                my $replicate_id = $biological_replicate->get_technical_replicate_group;
                for my $assay (@{ $biological_replicate->get_assays } ) {
                    my $assay_id = $assay -> get_name;
                    # Is this assay part of technical replicate group?
                    # If so, use id of replicate group
                    # Otherwise use assay id
                    $replicates_for_assays{$assay_id} = $replicate_id // $assay_id;
                    $assay_groups_for_replicates{$replicate_id // $assay_id} = $assay_group -> get_assay_group_id;
                }
            }
        }
    }
    # Return references to the two hashes
    return (\%replicates_for_assays, \%assay_groups_for_replicates);
}

# Given the mappings from the config, prepare indices of what should go where and the new header
sub create_group {
    my ($mapping_value_per_heading, $column_headings) = @_;

    my @new_headings;
    my %mapping_indices;

    for my $i (0 .. $#{$column_headings}) {
        #Current and new heading
        my $column_heading = $column_headings->[$i];
        my $new_heading = $mapping_value_per_heading->{$column_heading};
        next unless $new_heading;
        #Where was this heading first seen?
        my $index = List::Util::first { $new_headings[$_] eq $new_heading } 0 .. $#new_headings;
        #If we're seeing it for the first time, add to the result
        unless (defined($index)){
            push @new_headings, $new_heading;
            $index = $#new_headings;
        }
        # Values under old heading should now go in position $index, under the new heading
        $mapping_indices{$i} = $index;
    }
    # Which values should go in which position plus the new heading
    return (\%mapping_indices, \@new_headings);
}

# Print in TSV format
sub print_output_line {
    ($out, $id, $row) = @_;
    print $out $id . "\t" . (join "\t", @$row ). "\n";
}

sub run {
    my ($experiment_config, $do_quartiles, $in, $out) = @_;

    #Read the line of input
    my ($first_column_label, @column_headings) = split /[\t\n]/, <$in>;


    # Get what we need from experiment config
    my ($replicates_for_assays, $assay_groups_for_replicates) = groups_based_on_experiment_config($experiment_config);

    # Based on the config and the heading, determine what should go where after aggregating by technical replicate
    my ($mapping_indices_to_tech_reps, $new_headings_to_tech_reps) = create_group($replicates_for_assays, \@column_headings);
    # Determine what should go where when after aggregating by technical replicate we will also aggegate into quartiles (only used if we're asked for the quartiles)
    my ($mapping_indices_to_quartiles, $new_headings_to_quartiles) = create_group($assay_groups_for_replicates, $new_headings_to_tech_reps);

    # Print the header
    if($do_quartiles){
        print_output_line($out, $first_column_label, $new_headings_to_quartiles);
    } else {
        print_output_line($out, $first_column_label, $new_headings_to_tech_reps);
    }

    # For each line of the input
    while( my ($id, @row) = split /[\t\n]/, <$in>) {

        #Group assays into biological replicates, and for each group calculate the median
        @row = map {calculate_median($_)} @{group_row_with_indices(\@row, $mapping_indices_to_tech_reps)};


        if($do_quartiles){
            #Take the row and group values for each biological replicate into assay groups they go into, and then represent these as quartiles
            @row = map {calculate_rounded_quartiles($_)} @{group_row_with_indices(\@row, $mapping_indices_to_quartiles)};
        } else {
            #Round the values
            @row = map {round($_)} @row;
        }
        #Print out the output
        print_output_line($out, $id, \@row);
    }
}
# This is a perl package, and it needs to finish with a true value as an ancient mechanism of determining whether the package loaded okay
# 1 is customary but any true value will do
1;
