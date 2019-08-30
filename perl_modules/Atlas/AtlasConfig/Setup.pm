#!/usr/bin/env perl
#
=pod

=head1 NAME

Atlas::AtlasConfig::Setup - set up for Atlas XML config file generation.

=head1 SYNOPSIS
	
	use Atlas::AtlasConfig::Setup qw(
		create_factor_configs
		check_magetab4atlas_for_config
		create_atlas_experiment_type
	);

	# ...
	
	# Read file containing known reference factor values and factor types to ignore.
	my ($referenceFactorValues, $ignoreFactorTypes) = create_factor_configs($referencesIgnoreFile);

=head1 DESCRIPTION

This module contains functions to set up some variables needed prior to
creation of Atlas::AtlasConfig XML components. It checks a Atlas::Magetab4Atlas object
contains only the desired assays, and decides the experiment type string to
be placed at the top of the XML config file.

=cut

package Atlas::AtlasConfig::Setup;

use Moose;
use MooseX::FollowPBP;
use Atlas::Common qw( 
    create_atlas_site_config 
    make_ae_idf_path    
);
use EBI::FGPT::Config qw( $CONFIG );
use File::Spec;
use Log::Log4perl;
use XML::Simple;

use base 'Exporter';
our @EXPORT_OK = qw(
	create_factor_configs
	check_magetab4atlas_for_config
	create_atlas_experiment_type
);
	
my $logger = Log::Log4perl::get_logger;

my $atlasSiteConfig = create_atlas_site_config;

my $atlasProdDir = $ENV{ "ATLAS_PROD" };

=head1 METHODS

=over 2

=item create_factor_configs

Reads in an XML file containing factor values that are known references for
contrasts, and factor types that should be ignored when creating contrasts, and
returns two hashes mapping each value to 1.

=cut
sub create_factor_configs {
	my ($referencesIgnoreFile) = @_;
	
	# Read XML factor config file.
	my $xml = XMLin($referencesIgnoreFile, ForceArray => [ 'value', 'type' ]);
	
	# Turn arrays of factor values and factor types into hashes,
	# key=value/type, value=1. Makes checking for presence of value cleaner
	# later on, rather than using arrays.
	my $referenceFactorValues = { map { $_ => 1 }  @{ $xml->{ "reference_factor_values" }->{ "value" } } };
	my $ignoreFactorTypes = { map { $_ => 1 } @{ $xml->{ "ignore_factor_types" }->{ "type" } } };
	
	return($referenceFactorValues, $ignoreFactorTypes);
}

=item check_magetab4atlas_for_config

Takes a hash of command arguments from Atlas XML config generation script, the
hash of factors to ignore, and an Atlas::Magetab4Atlas object, and returns the
Atlas::Magetab4Atlas object containing the appropriate assays, e.g. only
paired- or single-end sequencing runs if the "-l" option was passed to the
script. Will die if baseline type or a library layout was passed for a
microarray experiment.

=cut
sub check_magetab4atlas_for_config {

	my ($args, $ignoreFactorTypes, $magetab4atlas) = @_;
	
    my $exptAcc = $args->{ "experiment_accession" };

    # Run some checks on the Magetab4Atlas object, to make sure the arguments
    # we were passed make sense for this experiment.  First, if we've been
    # passed the "baseline" analysis_type, check that this is not a microarray
    # experiment.
	if($args->{ "analysis_type" } eq "baseline" && $magetab4atlas->get_experiment_type =~ /array/) {
		$logger->logdie("$exptAcc is a microarray experiment, baseline expression calculation is not possible.");
	}


	# Next, some checks for if we've been passed a library_layout argument.
	if($args->{ "library_layout" }) {
		# First, library layouts don't make sense in a microarray experiment.
		if($magetab4atlas->get_experiment_type =~ /array/) {
			$logger->logdie("$exptAcc is a microarray experiment, don't know what to do with library layout information provided");
		}
		
		# Next, if we do have an RNA-seq experiment, we only want the assays
		# that have the correct library layout.
		my $wantedAssays = [];	# Empty array to fill.
		foreach my $assay4atlas (@{ $magetab4atlas->get_assays }) {
			if($assay4atlas->get_library_layout eq $args->{ "library_layout" }) {
				push @{ $wantedAssays }, $assay4atlas;
			}
		}
		$magetab4atlas->set_assays($wantedAssays);
	}


	# Go through the assays and remove any factors with types that
	# we should ignore.
    if( $ignoreFactorTypes ) {

        my $assaysNoIgnoreFactors = []; # empty array to fill
        foreach my $assay (@{ $magetab4atlas->get_assays }) {
            my $assayFactors = $assay->get_factors;
            
            foreach my $factorType (sort keys %{ $assayFactors }) {
                if($ignoreFactorTypes->{ $factorType }) {
                    $logger->debug("Removing factor $factorType from assay ", $assay->get_name);
                    delete $assayFactors->{ $factorType };
                }
            }

            # Replace the assay's factors with the new hash.
            $assay->set_factors($assayFactors);
            
            # Add the assay to the array of assays without ignore factors.
            push @{ $assaysNoIgnoreFactors }, $assay;
        }
        # Add the array of new assays to the Atlas::Magetab4Atlas object.
        $magetab4atlas->set_assays($assaysNoIgnoreFactors);
    }

	return $magetab4atlas;
}


=item create_atlas_experiment_type

Takes a Atlas::Magetab4Atlas object and an analysis type ("baseline" or
"differential"), returns the Atlas experiment type to be written to the XML
config file.

=cut
sub create_atlas_experiment_type {
    my ($magetab4atlas, $analysisType) = @_;

    unless(ref($magetab4atlas) eq "Atlas::Magetab4Atlas") {
		$logger->logdie("Cannot create experiment type for an object that isn't an Atlas::Magetab4Atlas");
    }

    # Is it array or RNA-seq?
    my $atlasExperimentType = _start_experiment_type( $magetab4atlas->get_experiment_type );

    # If it's array, is that one- or two-colour? And is it mRNA or miRNA?
    if($atlasExperimentType eq "microarray_") {
		$atlasExperimentType .= ($magetab4atlas->get_experiment_type =~ /one/) ? "1colour_" : "2colour_";
		$atlasExperimentType .= _rna_type_for_array($magetab4atlas->get_assays);
    } else {
		unless( $atlasExperimentType =~ /proteomics/ ) {
			$atlasExperimentType .= "mrna_";
		}
    }

    # Lastly, add the analysis type.
    $atlasExperimentType .= $analysisType;

    # Get allowed XML experiment types.
	my $allowedExperimentTypesArray = $atlasSiteConfig->get_allowed_xml_experiment_types;

	# Map the allowed experiment types to 1 in a hash.
	my $allowedExperimentTypes = { map {$_ => 1 } @{ $allowedExperimentTypesArray } };

    # Check that the type we created matched one of the allowed types, log and
    # die if not.
    unless(exists($allowedExperimentTypes->{ $atlasExperimentType })) {

		my $allowedTypes = join ", ", ( sort keys %{ $allowedExperimentTypes } );

		$logger->logdie("\"$atlasExperimentType\" is not an allowed Atlas experiment type. Allowed types are: $allowedTypes");
    }

    return $atlasExperimentType;
}


=item _start_experiment_type

Not exported. Takes an experiment type from a Magetab4Atlas object and returns
the appropriate word for the start of the Atlas XML experiment type.

=cut

sub _start_experiment_type {

	my ( $magetab4atlasExpType ) = @_;

	if( $magetab4atlasExpType =~ /array/i ) { return "microarray_"; }

	elsif( $magetab4atlasExpType =~ /rna-seq/i ) { return "rnaseq_"; }

	elsif( $magetab4atlasExpType =~ /proteomics/i ) { return "proteomics_"; }

	else { $logger->logdie( "Unrecognised experiment type: $magetab4atlasExpType" ); }
}


=item _rna_type_for_array

Not exported. Takes an array of Assay objects and checks if their array
designs are miRNA or mRNA, based on presence/absence of miRBase mapping file.

=cut
sub _rna_type_for_array {
    my ($assays4atlas) = @_;

    # A hash to keep the RNA type(s) found for this experiment. For an
    # experiment, all arrays must be either mRNA _or_ miRNA, we cannot allow
    # both types in one experiment at the moment.
    my $rnaTypes = {};

    # The location of the miRBase mapping files for miRNA array designs.
    my $miRBaseMappingDir = File::Spec->catdir( $atlasProdDir, $atlasSiteConfig->get_mirbase_mappings_directory );

	# All miRBase mapping files in an array.
    my @miRBaseMappingFiles = glob( "$miRBaseMappingDir/*.A-*.tsv" );

    # Create a hash of array designs for easy checking.
    my $miRBaseArrays = {};
    foreach my $miRBaseMappingFile (@miRBaseMappingFiles) {
		# Get the array design from the file name.
		(my $arrayDesign = $miRBaseMappingFile) =~ s/.*(A-\w{4}-\d+)\.tsv/$1/;

		# Add the array design as a key in the hash with value 1.
		$miRBaseArrays->{ $arrayDesign } = 1;
    }

    # Go through the assays and see if their array design matches a miRBase
    # one. If so, add "microrna" to the $rnaTypes hash. If not, add "mrna"
    # instead.
    foreach my $assay4atlas (@{ $assays4atlas }) {
		my $assayArrayDesign = $assay4atlas->get_array_design;

		if(exists($miRBaseArrays->{ $assayArrayDesign })) { $rnaTypes->{ "microrna_" } = 1; }
		else { $rnaTypes->{ "mrna_" } = 1; }
    }

    # Now check the $rnaTypes hash. If we have a single key, return that,
    # otherwise die.
    if(keys %{ $rnaTypes } == 1) {
		my $rnaType = (keys %{ $rnaTypes })[0];
		return $rnaType;
    } else {
		$logger->logdie("This experiment contains both mRNA and miRNA array designs. Not allowed.");
    }
}


1;

=back

=head1 AUTHOR

Expression Atlas team <arrayexpress-atlas@ebi.ac.uk>
