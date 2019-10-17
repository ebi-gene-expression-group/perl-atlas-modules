#!/usr/bin/env perl
#
# EBI/FGPT/CheckSet/AEAtlas.pm
#
# Amy Tang 2012 ArrayExpress team, EBI
#
# $Id: AEAtlas.pm 26147 2014-11-21 15:20:30Z amytang $
#

=pod

=head1 NAME

EBI::FGPT::CheckSet::AEAtlas

=head1 SYNOPSIS
 
 use EBI::FGPT;
 
 my $check_sets = {
	'EBI::FGPT::CheckSet::AEAtlas'  => 'ae_atlas_eligibility',
 };

 my $idf = $ARGV[0];
 my $checker = EBI::FGPT::Reader::MAGETAB->new( 
    'idf'                  => $idf, 
    'check_sets'           => $check_sets,
 );
 $checker->parse();

=head1 DESCRIPTION

Additional MAGETAB checks to determine if experiment can be loaded
into the ArrayExpress Gene Expression Atlas.

All the checks must be passed for an experiment to be loaded into the 
ArrayExpress Gene Expression Atlas database.

=head1 IDF checks:

Experiment must be of specific types (e.g. sequencing experiments 
cannot be loaded yet), as specified in the Comment[AEExperimentType] field.

GEO SuperSeries experiments (each composed of mulitple GEO "Series" 
[experiments, in ArrayExpress terms]) also not eligible for Atlas.

The IDF must have accompanying SDRF(s).

=head1 SDRF checks:

For each experiment, at least one of the array designs must have at least three
biological replicates in at least two conditions.

Each source material can only be associated with one organism 
(i.e. has one "Characteristics[Organism]" or
"Characteristics[organism]" column in the SDRF).

All unit terms for measurements must come from the 
Experimental Factor Ontology (EFO).

All characteristic and factor type terms must come from a list of controlled
vocabulary.

Organism must match NCBI taxonomy scientific name.

Assay names must be "R-safe" i.e. must not be rendered identical by R when it
removes disallowed characters.

Technical replicate IDs must conform to agreed convention (e.g. "group 1").

For any sample associated with factor type "Dose", there must also 
be a factor type "compound" or "irradiate", or else it will not make
sense (dose of what?).

The experiment must not have a directory in $ATLAS_PROD/failedQC,
$ATLAS_PROD/failedCuration or $ATLAS_PROD/minPValGt0.5

Human disease experiments must have an organism part and/or cell type and/or
cell line annotated.

Microarray Experiments only:

All assays must have raw data files. Each Affymetrix assay in an experiment
must have a CEL raw data file. Each Agilent assay in an experiment must have a
.txt raw data file, presumably to be a feature extraction file

The ADF used in the microarray experiment must be supported by Atlas.

The organism in the SDRF must match the organism annotated to the ADF in the
Atlas site config.

Microarray assays must have label information, and this must be either
"biotin", "Cy3", or "Cy5".

Sequencing experiments only:

ENA_RUN or RUN_NAME must be present. ENA_RUN accessions must conform to ENA
standard. FASTQ_URI or SUBMITTED_FILE_NAME must be present. FASTQ_URI must
conform to known ENA URI pattern.

=head1 AUTHOR

Amy Tang (amytang@ebi.ac.uk), ArrayExpress team, EBI, 2012.
Eleanor Williams (ewilliam@ebi.ac.uk), ArrayExpress team, EBI, 2013.

Many of the experiment checks were implemented by Tim Rayner.

Acknowledgements go to the ArrayExpress curation team for feature
requests, bug reports and other valuable comments.

=cut

package EBI::FGPT::CheckSet::AEAtlas;

use Data::Dumper;

use Moose;
use MooseX::FollowPBP;
use Scalar::Util qw( looks_like_number );
use EBI::FGPT::Config qw($CONFIG);
#use EBI::FGPT::Resource::Database::GXA;
use URL::Encode qw( url_encode_utf8 );
use XML::Simple qw( :strict );

use Atlas::Common qw( 
    create_atlas_site_config 
    fetch_array_data_files    
    make_http_request
    fetch_ncbi_taxid
    http_request_successful
    get_array_design_name_from_arrayexpress
);

extends 'EBI::FGPT::CheckSet';

has 'atlas_fail_codes' => ( 
    is => 'rw', 
    isa => 'ArrayRef', 
    default => sub { [] } 
);


has 'atlas_site_config' => (
    is  => 'rw',
    isa => 'Config::YAML',
    builder => '_build_atlas_site_config'
);

has 'efetch_base_url'  => (
    is  => 'rw',
    isa => 'Str',
    default => "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?"
);

augment 'run_idf_checks' => sub {

	my ($self) = @_;

	$self->check_atlas_expt_type;
	$self->check_geo_superseries;
    $self->check_for_sdrf; 

};

# If we didn't find an SDRF, warn and set negative code for all the
# SDRF-specific checks.
after 'check_for_sdrf' => sub {

    my ( $self ) = @_;

    unless( $self->get_investigation->get_sdrfs ) {

        $self->warn( 
            "No SDRF, cannot perform any SDRF-specific checks.",
        );

        # Fail for all the SDRF-specific checks.
        foreach my $code ( -1, -2, -4, -6, -7, -8, -11, -12, -13, -14, -16, -17, -18, -19, -20, -21, -23, -24 ) {

            $self->_add_atlas_fail_code( $code );
        }
    }
};


augment 'run_sdrf_checks' => sub {

	my ($self) = @_;
    
    # All experiments.
    $self->check_count_biological_replicates;
    $self->check_organism_count;
    $self->check_atlas_unit_terms;
    $self->check_property_types;
    $self->check_factor_type_repetition;
    $self->check_organism_scientific_name;
    $self->check_Rsafe_assay_names;
    $self->check_technical_replicate_ids;
    $self->check_for_singleton_techreps;
    $self->check_dose;
    $self->check_previous_failure;
    $self->check_cttv_human_disease_characteristics;

    # Microarray only.
    $self->check_microarray_data_files;
    $self->check_microarray_adf_support;
    $self->check_microarray_source_organism_match_adf;
    $self->check_microarray_labels;
	
    # Sequencing only.
	$self->check_sequencing_runs_and_files;

    # Get rid of any negative fail codes for which we have the corresponding
    # positive fail code. Makes the output tidier. If the check has run and
    # failed in one case we don't care if it was unable to run for another. An
    # example is if there are two organisms, one produces an NCBI error and the
    # other does not, but doesn't match the NCBI scientific name. This gives
    # -18 and 18.
};


sub _build_atlas_site_config {

    my $atlasSiteConfig = create_atlas_site_config;
    
    return $atlasSiteConfig;
}


############################################
### List of Atlas fail codes             ###
############################################
# 1.  No raw data, or some Affymetrix or Agilent data file(s) are missing (microarray only)
# 2.  Array design in not in the Atlas (microarray only)
# 3.  Experiment has a type not eligible for the Atlas
# 4. **RETIRED** Two-channel experiment
# 5.  Experiment is mixed technology (microarray and sequencing)
# 6.  Experiment has less than 6 assays, or doesn't have at 3+ replicates for
# at least 2 factor value combinations in at least one array design (or single
# or paired library layout)
# 7.  Factor type or characteristics are not from controlled vocabulary
# 8.  Factor types are repeated
# 9.  Experiment is a GEO superseries
# 10. **RETIRED** experiment has too many (>4) factor types
# 11. Experiment has no factors at all
# 12. **RETIRED** Experiment has more than one source organism per source (now
# made redundant by counting total organisms in experiment (code 19 if more
# than one total for experiment).
# 13. Units are not in EFO
# 14. Sequencing specific checks (run accession, fastq URI, submitted file names (only if AE accession present, not for submission stage files)
# 15. **RETIRED** experiment is likely to have technical replicates
# 16. No label information, can't work out if this is a single or dual channel experiment, can't count factors properly
# 17. Species mismatch between source materials and ADF
# 18. Species in SDRF does not match NCBI taxonomy "scientific name".
# 19. Experiment has more than one organism in total.
# 20. Assay names or run accessions are not R-safe.
# 21. Technical replicate IDs do not conform to agreed convention (e.g. "group 1").
# 22. Experiment is present in failedCuration, failedQC, or minPvalGt0.5 directory.
# 23. Human disease experiment must have organism part and/or cell type and/or cell line.
# 24. Singleton technical replicate IDs found -- a technical replicate ID must
# have more than one assay/run associated.
# 
# 999. Checking didn't happen at all (e.g. due to invalid MAGE-TAB).
############################################

###                                      ###
### Atlas-specific IDF checks begin here ###
###                                      ###

sub check_atlas_expt_type {

	my ($self) = @_;
    
    my $controlledVocab = $self->get_aeatlas_controlled_vocab;

	my $approved_expt_types = $controlledVocab->get_atlas_experiment_types;

	my $atlas_fail_flag = $self->check_expt_type($approved_expt_types);

	if ($atlas_fail_flag) {
	    $self->error("Experiment has no experiment type, a (combination of) experiment type(s) not allowed, or more than 2 experiment types");
		$self->_add_atlas_fail_code( 3 );
	}

}

sub check_geo_superseries {

	my ($self) = @_;

# Data in GEO superseries cannot go into Atlas. The only way to detect them is in the experient description,
# which would contains this clause: "This SuperSeries is composed of the following subset Series"

	# Experiment description is not mandatory in MAGE-TAB 1.1 specification

	my $expt_desc        = $self->get_investigation->get_description;
	my $superseries_text =
	  "This SuperSeries is composed of";

	$self->debug("Checking whether experiment is part of a GEO SuperSeries");

	if ( ($expt_desc) && ( $expt_desc =~ /$superseries_text/ ) ) {
		$self->error("Experiment is a GEO SuperSeries.");
		$self->_add_atlas_fail_code( 9 );
	}

}


###                                                ###
### Atlas-specific SDRF and data checks begin here ###
###                                                ###

=item check_count_biological_replicates

Check to make sure that there are at least the minimum number of biological
replicates for at least two factor value combinations (assay groups). This
check is "per platform", i.e. array design and/or sequencing library strategy.

=cut

sub check_count_biological_replicates {

    my ( $self ) = @_;

    $self->info( "Counting biological replicates..." );

    # Minimum number of biological replicates allowed.
    my $minimumBiologicalReplicates = 3;
    
    my $magetab = $self->get_magetab;

    unless( $magetab->has_assays ) {
        
        $self->error( "Experiment has no assays" );

        $self->_add_atlas_fail_code( 6 );

        return;
    }

    my @magetabAssays = $magetab->get_assays;   

    # Map each assay to its platform. For microarray experiments this is the
    # array design accession. For sequencing experiments this is the library
    # strategy.
    my $platformsToAssays = $self->_map_platforms_to_assays( \@magetabAssays );

    # Make sure we got something back from the mapping. If not, we can't count
    # reps, so just fail here.
    unless( $platformsToAssays ) {
        
        $self->error( "No assays mapped to platforms. Cannot count replicates." );
        
        $self->_add_atlas_fail_code( 6 );

        return;
    }
    
    # If we're still here, attempt to count replicates based on the mapped
    # assays.

    # Flag to set if there are enough assay groups on any platforms.
    my $enoughAssayGroups = 0;

    foreach my $platform ( keys %{ $platformsToAssays } ) {

        my $platformAssays = $platformsToAssays->{ $platform };
    
        # First need to map assays to their biological replicate (technical
        # replicate group) IDs. If no technical replicate group comment use assay name.
        my $biorepNamesToAssays = _map_biorep_names_to_assays( $platformAssays );

        # Now sort the biological replicates by shared factors.
        # We will lose assays/bio reps that don't have factors here.
        # If we don't have any left after this, add error code and return.
        my $factorValuesToBiorepNames = $self->_map_factors_to_bioreps( $biorepNamesToAssays );

        unless( keys %{ $factorValuesToBiorepNames } ) {
            
            $self->error( "No factor values found." );

            $self->_add_atlas_fail_code( 11 );

            $self->warn( "Could not count biological replicates." );

            $self->_add_atlas_fail_code( -6 );

            return;
        }

        # Count "assay groups" (i.e. factor value string concatenations) with
        # enough bio reps.
        my $assayGroupCount = 0;

        foreach my $factorValueString ( keys %{ $factorValuesToBiorepNames } ) {
            
            my $biorepCount = scalar ( keys %{ $factorValuesToBiorepNames->{ $factorValueString } } );

            if( $biorepCount >= $minimumBiologicalReplicates ) { $assayGroupCount++; }
        }
        
        # If there are at least two assay groups with enough replicates on this
        # platform, increment the flag.
        if( $assayGroupCount >= 2 ) { $enoughAssayGroups++; }
    }

    # If we haven't got at least two assay groups with enough bio reps, won't
    # be able to make any comparisons.
    unless( $enoughAssayGroups ) {

        $self->error( 
            "Did not find at least two assay groups with at least ", 
            $minimumBiologicalReplicates,
            " biological replicates."
        );

        $self->_add_atlas_fail_code( 6 );
    }
    
    $self->info( "Finished counting biological replicates." );
}


=item check_organism_count

Check there is only one organism in this experiment.

=cut

sub check_organism_count {

	my ($self) = @_;

    $self->info( "Counting organisms..." );
	
    # Get the Sources from the MAGETAB.
    my @sources = $self->get_magetab->get_sources;

    my %totalOrganisms;

    # Go through the Sources...
	foreach my $source (@sources) {
		
        # Get the Source node name.
        my $source_name    = $source->get_name;
		
        # Get all the characteristics from the Source node.
        my @chars          = @{ $source->get_characteristics };
		
        # Find all the characteristic objects whose category matches /^organism$/i .
        my @organism_chars = grep { $_->get_category =~ /^organism$/i } @chars;
		
        foreach my $organismChar ( @organism_chars ) {
            $totalOrganisms{ $organismChar->get_value } = 1;
        }
	}
    
    # If there is more than one organism, fail.
    if( scalar ( keys %totalOrganisms ) > 1 ) {

        $self->error( "Experiment has more than one organism." );

        $self->_add_atlas_fail_code( 19 );
    }
    
    $self->info( "Finished counting organisms." );
}


=item check_atlas_unit_terms

Validate unit terms against EFO.

=cut

sub check_atlas_unit_terms {

	my ($self) = @_;

    $self->info( "Checking unit terms against EFO..." );
	# check all units are in EFO, if not add fail

	$self->debug("checking atlas units");
    
    # check_unit_terms method from parent class.
	my $atlas_unit_fail_flag = $self->check_unit_terms;

	if ($atlas_unit_fail_flag) {
		$self->_add_atlas_fail_code( 13 );
	}

    $self->info( "Finished checking unit terms against EFO." );
}


=item check_property_types

Check Characteristics and Factor types against controlled vocab.

=cut

sub check_property_types {

	my ($self) = @_;

    $self->info( "Checking property types against controlled vocab..." );
	
    my $controlledVocab = $self->get_aeatlas_controlled_vocab;

	my @approvedChars = map( 
        { $self->_dont_normalize_category($_) } 
        @{ $controlledVocab->get_atlas_property_types || [] }
    );
    
    # Make sure we got something from the controlled vocab.
	unless( scalar @approvedChars ) {

		$self->error(
            "Approved property types not found. Cannot validate property types."
		);
	}
    
    # Empty hash to store all property types (characteristics and factors).
    my $allPropertyTypes = {};
    
    my $magetab = $self->get_magetab;

    # Fail if we don't have sources.
    unless( $magetab->has_sources ) {

        $self->warn( 
            "No Source nodes detected. Cannot validate property types."
        );

        $self->_add_atlas_fail_code( -7 );

        return;
    }

    # If we're still here, go through the sources and collect all
    # characteristic and factor types.
    foreach my $source ( $magetab->get_sources ) {

        if( $source->has_characteristics ) {

            $allPropertyTypes = $self->_add_characteristic_types( $allPropertyTypes, $source );
        }

        # Get the SDRFRows for this Source.
        unless( $source->has_sdrfRows ) {
            $self->warn(
                "No sdrfRows found for source ",
                $source->get_name,
                " -- cannot access factors."
            );
        }
        else {

            my @sdrfRows = $source->get_sdrfRows;

            foreach my $sdrfRow ( @sdrfRows ) {

                # Get all the nodes for this row.
                my @nodes = $sdrfRow->get_nodes;

                # Index the nodes by their class ID.
                my %mappedNodes = map { ref( $_ ) => $_ } @nodes;

                # See if we have a Sample node -- these can also have characteristics.
                if( $mappedNodes{ "Bio::MAGETAB::Sample" } ) {

                    my $sample = $mappedNodes{ "Bio::MAGETAB::Sample" };

                    $allPropertyTypes = $self->_add_characteristic_types( $allPropertyTypes, $sample );
                }

                # Get the factors, if any.
                if( $sdrfRow->has_factorValues ) {
                    
                    foreach my $factorValue ( $sdrfRow->get_factorValues ) {

                        my $type = $self->_dont_normalize_category(
                            $factorValue->get_factor->get_factorType->get_value
                        );

                        $allPropertyTypes->{ $type } = 1;
                    }
                }
            }
        }
    }

    # Now check that we have some types in the hash. If not, just fail here.
    unless( keys %{ $allPropertyTypes } ) {
        
        $self->warn(
            "No characteristic or factor types found. Cannot validate property types."
        );

        $self->_add_atlas_fail_code( -7 );

        return;
    }

    # If we're still here, validate the types we found against the controlled
    # vocab.
    my $disallowedTypes = [];

    foreach my $type ( keys %{ $allPropertyTypes } ) {

        unless( grep { $type eq $_ } @approvedChars ) {

            push @{ $disallowedTypes }, $type;
        }
    }
    
    # If any disallowed property types were found, join them together, log
    # them, and set the fail code.
    if( @{ $disallowedTypes } ) {

        my $disallowedTypesString = join ", ", @{ $disallowedTypes };

        $self->error(
            "Experiment has property types not in controlled vocabulary: ",
            $disallowedTypesString
        );

        $self->_add_atlas_fail_code( 7 );
    }

    $self->info( "Finished checking property types against controlled vocab." );
}


=item check_factor_type_repetition

Make sure each factor type only appears once.

=cut

sub check_factor_type_repetition {
    
    my ( $self ) = @_;
    
    my $magetab = $self->get_magetab;
    
    my $repeatedFactorTypes = {};

    foreach my $sdrfRow ( $magetab->get_sdrfRows ) {

        if( $sdrfRow->has_factorValues ) {

            my $rowFactorTypeCounts = {};

            foreach my $factorValue ( $sdrfRow->get_factorValues ) {

                my $factor = $factorValue->get_factor;

                if( $factor->has_factorType ) {
                    
                    my $factorType = $factor->get_factorType->get_value;

                    if( $rowFactorTypeCounts->{ $factorType } ) {
                        
                        $rowFactorTypeCounts->{ $factorType }++;
                    }
                    else {

                        $rowFactorTypeCounts->{ $factorType } = 1;
                    }
                }
            }

            foreach my $factorType ( keys %{ $rowFactorTypeCounts } ) {

                if( $rowFactorTypeCounts->{ $factorType } > 1 ) {

                    $repeatedFactorTypes->{ $factorType } = 1;
                }
            }
        }
    }

    if( keys %{ $repeatedFactorTypes } ) {

        my $joinedRepeats = join( ", ", ( keys %{ $repeatedFactorTypes } ) );

        $self->error(
            "The following factor type(s) are repeated: ",
            $joinedRepeats
        );

        $self->_add_atlas_fail_code( 8 );
    }
}


=item check_organism_scientific_name

Checks each organism's scientific name against the scientific name of the
matching species in NCBI taxonomy. This is to ensure that we use consitent
names for species in Atlas, to avoid e.g. having "Oryza sativa Japonica" in
some experiments, "Oryza sativa Japonica group" in others, and "Oryza sativa
Japonica group" in yet others.

=cut

sub check_organism_scientific_name {

    my ( $self ) = @_;
    
    $self->info( "Checking organisms against NCBI taxonomy..." );

    my $organisms = {};

    foreach my $source ( $self->get_magetab->get_sources ) {

        my %characteristics = map { lc( $_->get_category ) => $_ } $source->get_characteristics;

        $organisms->{ $characteristics{ "organism" }->get_value } = 1;
    }

    unless( keys %{ $organisms } ) {

        $self->warn(
            "No organism found in SDRF. Cannot check organism against NCBI taxonomy."
        );

        $self->_add_atlas_fail_code( -18 );

        return;
    }

    foreach my $organism ( keys %{ $organisms } ) {

        my $taxid = fetch_ncbi_taxid( $organism, $self->get_logger );

        unless( $taxid ) {

            $self->error(
                "Did not get a tax ID from NCBI taxonomy for \"$organism\". ",
                "Please verify that it is a valid species scientific name and re-try."
            );

            $self->_add_atlas_fail_code( 18 );

            next;
        }
        
        # TODO: this sometimes returns valid XML containing an error
        # message from NCBI. Add workaround if it is a commonly-recurring issue.
        # See: https://redmine.open-bio.org/issues/3361
        my $efetchResult = $self->_fetch_taxon_info_by_taxid( $taxid );

        unless( $efetchResult ) {
            $self->warn(
                "Cannot check that organism \"$organism\" matches NCBI taxonomy scientific name: ",
                "Could not fetch taxon information from NCBI taxonomy due to connection issues."
            );

            $self->_add_atlas_fail_code( -18 );

            next;
        }
        
        my $sciName = $efetchResult->{ "Taxon" }->{ $taxid }->{ "ScientificName" };

        unless( $organism eq $sciName ) {

            $self->error(
                "SDRF organism \"",
                $organism,
                "\" does not match NCBI taxonomy scientific name \"",
                $sciName,
                "\"."
            );

            $self->_add_atlas_fail_code( 18 );
        }
    }

    $self->info( "Finished checking organisms against NCBI taxonomy." );
}


=item check_Rsafe_assay_names

Checks that Assay names (microarray) and run accessions (sequencing) are safe
for R. This means, if any will be rendered the same as each other when
make.names() is applied, fail.

=cut

sub check_Rsafe_assay_names {

    my ( $self ) = @_;

    $self->info( "Checking that assay and/or run names are R-safe..." );

    # First check any microarray assays.
    my $microarrayAssays = $self->_collect_microarray_assays;

    # If we found some microarray assays, check their names.
    if( @{ $microarrayAssays } ) {
        
        # Hash to store assay names after converting them as in R.
        my $assayNamesToRsafe = {};

        foreach my $assay ( @{ $microarrayAssays } ) {

            $assayNamesToRsafe->{ $assay->get_name } = _to_r_safe( $assay->get_name );
        }
        
        $self->_check_r_safe_names( $assayNamesToRsafe );
    }

    # Next check any sequencing assays (run names -- ENA run accessions
    # unlikely to be an issue but Comment[ RUN_NAME ] is free-text and you
    # never know.
    my $sequencingAssays = $self->_collect_sequencing_assays;

    # If we got some sequencing assays...
    if( @{ $sequencingAssays } ) {

        # Hash to store "assay" names after converting them as in R.
        my $assayNamesToRsafe = {};

        foreach my $assay ( @{ $sequencingAssays } ) {

            # Get the Scan node(s) and collect the ENA_RUN or RUN_NAME comment.
            foreach my $sdrfRow ( $assay->get_sdrfRows ) {

                foreach my $node ( $sdrfRow->get_nodes ) {

                    if( $node->isa( "Bio::MAGETAB::DataAcquisition" ) ) {

                        my %comments = map { $_->get_name => $_->get_value } $node->get_comments;

                        # Check ENA_RUN first.
                        if( $comments{ "ENA_RUN" } ) {

                            $assayNamesToRsafe->{ $comments{ "ENA_RUN" } } = _to_r_safe( $comments{ "ENA_RUN" } );
                        }
                        # Check RUN_NAME if no ENA_RUN.
                        elsif( $comments{ "RUN_NAME" } ) {

                            $assayNamesToRsafe->{ $comments{ "RUN_NAME" } } = _to_r_safe( $comments{ "RUN_NAME" } );
                        }
                    }
                }
            }
        }

        $self->_check_r_safe_names( $assayNamesToRsafe );
    }

    $self->info( "Finished checking that assay and/or run names are R-safe." );
}


sub check_technical_replicate_ids {

    my ( $self ) = @_;

    $self->info(
        "Checking format of any technical replicate group IDs."
    );

    my $nonConformists = {};

    foreach my $assay ( $self->get_magetab->get_assays ) {

        my %comments = map { $_->get_name => $_->get_value } $assay->get_comments;

        if( $comments{ "technical replicate group" } ) {

            unless( $comments{ "technical replicate group" } =~ /^group\s*\d+$/ ) {
                
                $nonConformists->{ $comments{ "technical replicate group" } } = 1;
            }
        }
    }
    
    if( keys %{ $nonConformists } ) {

        my $nonConformingIDs = join ", ", ( keys %{ $nonConformists } );

        $self->error(
            "The following technical replicate group IDs do not conform to the agreed convention: ",
            $nonConformingIDs,
            ". Please use IDs such as \"group 1\", \"group 2\", etc.",
        );

        $self->_add_atlas_fail_code( 21 );
    }

    $self->info(
        "Finished checking format of technical replicate group IDs."
    );
}


sub check_for_singleton_techreps {

    my ( $self ) = @_;

    $self->info(
        "Checking for singleton technical replicate assays/runs..."
    );

    # Collect all microarray and/or sequencing assays in this experiment.
    # In Atlas, microarray assays use name of Assay node from MAGE-TAB, while
    # for sequencing data each "run" is considered a separate Atlas "assay".
    my $arrayAssays = $self->_collect_microarray_assays;
    my $seqAssays = $self->_collect_sequencing_assays;

    # Collect assay names by tech rep group ID in a hash.
    my $techRepGroups = {};

    # First collect microarray assay names, if any.
    if( @{ $arrayAssays } ) {

        foreach my $assay ( @{ $arrayAssays } ) {

            my %comments = map { $_->get_name => $_->get_value } $assay->get_comments;

            if( $comments{ "technical replicate group" } ) {

                $techRepGroups->{ $comments{ "technical replicate group" } }->{ $assay->get_name } = 1;
            }
        }
    }

    # Next collect sequencing run accessions, if any.
    if( @{ $seqAssays } ) {

        foreach my $assay ( @{ $seqAssays } ) {
            
            my %assayComments = map { $_->get_name => $_->get_value } $assay->get_comments;

            if( $assayComments{ "technical replicate group" } ) {

                # Get the Scan node(s) and collect the ENA_RUN or RUN_NAME comment.
                foreach my $sdrfRow ( $assay->get_sdrfRows ) {

                    foreach my $node ( $sdrfRow->get_nodes ) {

                        if( $node->isa( "Bio::MAGETAB::DataAcquisition" ) ) {

                            my %scanComments = map { $_->get_name => $_->get_value } $node->get_comments;

                            # Check ENA_RUN first.
                            if( $scanComments{ "ENA_RUN" } ) {
                                
                                $techRepGroups->{ $assayComments{ "technical replicate group" } }->{ $scanComments{ "ENA_RUN" } } = 1;
                            }
                            # Check RUN_NAME if no ENA_RUN.
                            elsif( $scanComments{ "RUN_NAME" } ) {
                                
                                $techRepGroups->{ $assayComments{ "technical replicate group" } }->{ $scanComments{ "RUN_NAME" } } = 1;
                            }
                        }
                    }
                }
            }
        }
    }

    # Now we have all the assay names indexed by technical replicate group ID.
    # Next, check if any technical replicate groups only have one assay.
    my $singletonTechRepGroups = {};
    
    if( keys %{ $techRepGroups } ) {

        foreach my $techRepGroup ( keys %{ $techRepGroups } ) {

            my $numAssays = scalar ( keys %{ $techRepGroups->{ $techRepGroup } } );

            if( $numAssays == 1 ) {

                $singletonTechRepGroups->{ $techRepGroup } = 1;
            }
        }
    }
    
    if( keys %{ $singletonTechRepGroups } ) {
        
        my $singletons = join ", ", ( keys %{ $singletonTechRepGroups } );
            
        $self->error(
            "The following technical replicate groups only contain one assay, this does not make sense: ",
            $singletons
        );

        $self->_add_atlas_fail_code( 24 );
    }

    $self->info(
        "Finished checking for singleton technical replicate assays/runs."
    );
}


sub check_dose {

    my ( $self ) = @_;

    $self->info(
        "Checking for presence of dose without compound or irradiate."
    );
    
    my $doseError = 0;

    foreach my $assay ( $self->get_magetab->get_assays ) {

        foreach my $sdrfRow ( $assay->get_sdrfRows ) {

            my %factors = map { $_->get_factor->get_name => 1 } $sdrfRow->get_factorValues;

            if( $factors{ "dose" } ) {

                unless( $factors{ "compound" } || $factors{ "irradiate" } ) {
                    
                    $doseError++;
                }
            }
        }
    }

    if( $doseError ) {

        $self->error(
            "Cannot use \"dose\" factor without \"compound\" or \"irradiate\"."
        );

        $self->_add_atlas_fail_code( 22 );
    }

    $self->info(
        "Finished checking for presence of dose without compound or irradiate."
    );
}


sub check_previous_failure {

    my ( $self ) = @_;

    $self->info( 
        "Checking for presence of experiment in failedQC, minPValGt0.5, and failedCuration directories." 
    );

    my $atlasSiteConfig = $self->get_atlas_site_config;
    
    my $failedQCdir = $atlasSiteConfig->get_failed_qc_dir;
    my $minPvalDir = $atlasSiteConfig->get_min_pval_dir;
    my $failedCurationDir = $atlasSiteConfig->get_failed_curation_dir;

    # Ensure that the above paths are defined before continuing.
    my $dirNotDefined = 0;
    foreach my $directory ( $failedQCdir, $minPvalDir, $failedCurationDir ) {
        unless( $directory ) {
            $dirNotDefined++;
        }
    }

    # Return without trying to check if not.
    if( $dirNotDefined ) {
        $self->warn(
            "Can't find path(s) of failedQC, minPValGt0.5, or failedCuration directories. Please check Atlas site config."
        );

        $self->_add_atlas_fail_code( -22 );

        return;
    }
    
    my %mappedComments = map { $_->get_name => $_->get_value } $self->get_investigation->get_comments;

    if( $mappedComments{ "ArrayExpressAccession" } ) {

        my $aeAcc = $mappedComments{ "ArrayExpressAccession" };

        if( -e File::Spec->catfile( 
                $failedCurationDir,
                $aeAcc
            ) ) {

            $self->error(
                "Experiment is present in failedCuration directory."
            );

            $self->_add_atlas_fail_code( 22 );
        }

        if( -e File::Spec->catfile(
                $failedQCdir,
                "microarray",
                $aeAcc
            ) ||
            -e File::Spec->catfile(
                $failedQCdir,
                "rna-seq",
                $aeAcc
            ) ) {

            $self->error(
                "Experiment is present in failedQC directory."
            );

            $self->_add_atlas_fail_code( 22 );
        }

        if( -e File::Spec->catfile(
                $minPvalDir,
                "microarray",
                $aeAcc
            ) ||
            -e File::Spec->catfile(
                $minPvalDir,
                "rna-seq",
                $aeAcc
            ) ) {

            $self->error(
                "Experiment is present in minPValGt0.5 directory."
            );

            $self->_add_atlas_fail_code( 22 );
        }
    }

    $self->info( 
        "Finished checking for presence of experiment in failedQC, minPValGt0.5, and failedCuration directories."
    );
}


sub check_cttv_human_disease_characteristics {

    my ( $self ) = @_;

    my $missingCTTVInfo = {};

    foreach my $source ( $self->get_magetab->get_sources ) {

        my %characteristics = map { lc( $_->get_category ) => $_->get_value } $source->get_characteristics;
        

        if( $characteristics{ "organism" } =~ /homo sapiens/i 
            && $characteristics{ "disease" }
        ) {

            unless( $characteristics{ "organism part" }
                || $characteristics{ "cell type" }
                || $characteristics{ "cell line" }
            ) {
                
                # If no matching properties were found in the Source node,
                # there could be a Sample node so check for this.
                foreach my $sdrfRow ( $source->get_sdrfRows ) {

                    # Get all the nodes for this row.
                    my @nodes = $sdrfRow->get_nodes;

                    # Index the nodes by their class ID.
                    my %mappedNodes = map { ref( $_ ) => $_ } @nodes;

                    # See if we have a Sample node -- these can also have characteristics.
                    if( $mappedNodes{ "Bio::MAGETAB::Sample" } ) {

                        my $sample = $mappedNodes{ "Bio::MAGETAB::Sample" };

                        my %sampleChars = map  { lc( $_->get_category ) => $_->get_value } $sample->get_characteristics;

                        # If we still don't have the requisite info in the
                        # Sample node characteristics, add the Source name to
                        # the hash.
                        unless( $sampleChars{ "organism part" }
                            || $sampleChars{ "cell type" }
                            || $sampleChars{ "cell line" }
                        ) {

                            $missingCTTVInfo->{ $source->get_name } = 1;
                        }
                    }
                    # If there was no Sample node and none of the required
                    # types in the Source characteristics, save the Source
                    # name.
                    else {
                       
                        $missingCTTVInfo->{ $source->get_name } = 1;
                    }
                }
            }
        }
    }

    # Check if we got any Sources missing CTTV info, and fail if so.
    if( keys %{ $missingCTTVInfo } ) {

        $self->error(
            "The following human disease Sources (or their Samples) are missing ",
            "\"organism part\", \"cell type\" or \"cell line\" (CTTV requirement) : ",
            join ", ", ( keys %{ $missingCTTVInfo } )
        );

        $self->_add_atlas_fail_code( 23 );
    }
}



# MICROARRAY

=item check_microarray_data_files

Checks the following:
    - Assays have raw data files
    - Raw data file extensions match those expected for array design (i.e. CEL
    for Affymetrix, txt for Agilent).

=cut

sub check_microarray_data_files {

	my ($self) = @_;

    $self->info( "Checking data files for microarray assays..." );

    # Get all the microarray assays.
    my $microarrayAssays = $self->_collect_microarray_assays;

    # If there are no microarray assays, just return here.
    unless( @{ $microarrayAssays } ) {
        
        $self->info( "No microarray assays found." );

        return;
    }
    
    my $assaysWithAdfs = {};

    foreach my $assay ( @{ $microarrayAssays } ) {

        unless( $assay->has_arrayDesign ) {

            $self->warn(
                "No array design found for assay \"",
                $assay->get_name,
                "\" -- cannot assess raw data files."
            );

            $self->_add_atlas_fail_code( -1 );

            next;
        }
        else { 
            $assaysWithAdfs->{ $assay->get_name } = $assay;
        }
    }
    
    unless( keys %{ $assaysWithAdfs } ) {

        $self->error(
            "No assays with array designs found."
        );

        return;
    }

    # Map array design accessions to array design names.
    my $adfAccessionToName = $self->_map_adf_accs_to_names( $assaysWithAdfs );
    
    # If the mapping failed, log an error and fail.
    unless( $adfAccessionToName ) {

        $self->warn(
            "Did not get mapping of ADF accessions to names. Cannot determine required raw data file type."
        );

        $self->_add_atlas_fail_code( -1 );

        return;
    }
    
    # Now go through the assays and check the data files.
    foreach my $assay ( @{ $microarrayAssays } ) {

        my $assayName = $assay->get_name;

        my @sdrfRows = $assay->get_sdrfRows;

        my $dataFiles = fetch_array_data_files( \@sdrfRows );

        unless( @{ $dataFiles } ) {

            $self->error( "Assay $assayName does not have any raw data files." );

            $self->_add_atlas_fail_code( 1 );

            next;
        }
        
        # Skip if this assay doesn't have an array design.
        unless( $assaysWithAdfs->{ $assayName } ) { next; }

        my $adfAcc = $assay->get_arrayDesign->get_name;

        my $adfName = $adfAccessionToName->{ $adfAcc };
        
        unless( $adfName ) {

            $self->warn(
                "Cannot check that raw data file type is Atlas eligible for assay \"",
                $assayName,
                "\" because no name was found for ADF accession \"",
                $adfAcc,
                "\"."
            );

            $self->_add_atlas_fail_code( -1 );

            next;
        }

        # If it's Affy, check for CEL files.
        if( $adfName =~ /affymetrix/i ) {
            
            foreach my $dataFile ( @{ $dataFiles } ) {
                
                unless( $dataFile =~ /\.cel$/i ) {

                    $self->error( 
                        "File \"",
                        $dataFile,
                        "\" for Affymetrix assay \"",
                        $assayName,
                        "\" does not look like a CEL file.",
                    );

                    $self->_add_atlas_fail_code( 1 );
                }
            }
        }

        # If it's Agilent, check for .txt files.
        elsif( $adfName =~ /agilent/i ) {

            foreach my $dataFile ( @{ $dataFiles } ) {

                unless( $dataFile =~ /\.txt/i ) {

                    $self->error( 
                        "File \"",
                        $dataFile,
                        "\" for Agilent assay \"",
                        $assayName,
                        "\" does not look like a plain text file.",
                    );

                    $self->_add_atlas_fail_code( 1 );
                }
            }

        }

        # If it's something else, fail.
        else {
            $self->error(
                "Unable to determine whether array is Affymetrix or Agilent based on name: \"",
                $adfName,
                "\" -- cannot check that raw data file type is Atlas eligible for assay \"",
                $assayName,
                "\""
            );
            
            $self->_add_atlas_fail_code( -1 );
        }
    }
}


=item check_microarray_adf_supported

Checks ADF(s) against YAML config file to ensure they are supported by the Atlas pipeline.

=cut

sub check_microarray_adf_support {

	my ( $self ) = @_;

    $self->info( "Checking for array design support in Atlas..." );
	
    my $microarrayAssays = $self->_collect_microarray_assays;

    unless( @{ $microarrayAssays } ) {

        $self->debug( "No microarray assays found, not checking array design support." );

        return;
    }
    
    # Get the unique array design accessions from these assays.

    my $assaysWithAdfs = {};

    foreach my $assay ( @{ $microarrayAssays } ) {

        unless( $assay->has_arrayDesign ) {

            $self->warn(
                "No array design found for assay \"",
                $assay->get_name,
                "\" -- cannot check array design support."
            );

            $self->_add_atlas_fail_code( -2 );

            next;
        }
        else { 
            $assaysWithAdfs->{ $assay->get_name } = $assay;
        }
    }
    
    # If there are no assays with ADFs, quit here.
    unless( keys %{ $assaysWithAdfs } ) {

        $self->error(
            "No assays with array designs found."
        );

        return;
    }

    my %magetabAdfAccs = map { $_->get_arrayDesign->get_name => 1 } ( values %{ $assaysWithAdfs } );
    
    
    
    #######################################
    #######################################
    # TODO: can/should we consolidate files?
	my $adf_tracking_file_path = $CONFIG->get_ADF_CHECKED_LIST;

	my $expt_tracking_file_path = $CONFIG->get_ATLAS_EXPT_CHECKED_LIST;

	my ( %absent_adf_acc_count, @checked_expt_list );

	open( IN, $adf_tracking_file_path )
	  || $self->logdie(
"Can't open file $adf_tracking_file_path to fetch the list of ADFs which are not in the Atlas database."
	  );

	while (<IN>) {
		my ( $old_adf_acc, $count ) = $_ =~ /^(A-[A-Z]{4}-\d+)\t(\d+)$/;
		$absent_adf_acc_count{$old_adf_acc} = $count;
	}

	close IN;

	open( IN2, $expt_tracking_file_path )
	  || $self->logdie(
"Can't open file $expt_tracking_file_path to fetch the list of experiments already checked for Atlas eligibility."
	  );

	while (<IN2>) {
		chomp $_;
		push( @checked_expt_list, $_ );
	}

	close IN2;

# We need to keep track of whether this experiment has been checked before for Atlas eligibility
# If yes, and if the experiment's ADF is not in Atlas database, we don't increment the ADF count
# in adfs_not_in_atlas.txt file (or else many ADFs will be counted multiple times as the cause
# of failing Atlas eligiblity)

	my @acc_comments =
	  grep { $_->get_name eq "ArrayExpressAccession" }
	  @{ $self->get_investigation->get_comments || [] };
	my $expt_acc;
	if ( $acc_comments[0] )
	{ # In case the spreadsheet is in AE curation stage still and has no such comment yet
		$expt_acc = $acc_comments[0]->get_value if ( $acc_comments[0] );
	}
	else {
		$expt_acc = "dummy_expt_acc";
	}
    # TODO: end
    #######################################
    #######################################


    my $atlasSiteConfig = $self->get_atlas_site_config;

    my %supportedAdfs = map { $_ => 1 } ( keys %{ $atlasSiteConfig->get_atlas_supported_adfs } );

	foreach my $arrayDesignAcc ( keys %magetabAdfAccs ) {
        
		if ( $arrayDesignAcc =~ /A-[A-Z]{4}-\d+$/ ) {
		
			### FIXME: Need to get ADF synonyms and parse them too. get from AE2 DB?

			unless( $supportedAdfs{ $arrayDesignAcc } ) {
				
                $self->error(
					"Array design \"$arrayDesignAcc\" is not currently supported by Atlas."
                );
				
                $self->_add_atlas_fail_code( 2 );
				
				# if this experiment is checked for Atlas eligility for the first time
                if ( ( !grep $expt_acc eq $_, @checked_expt_list ) ) {

                    push( @checked_expt_list, $expt_acc );
					
					# if this ADF acc has been flagged before, increment the count
                    if ( $absent_adf_acc_count{ $arrayDesignAcc } ) {
						$absent_adf_acc_count{ $arrayDesignAcc }++;
					}
					else {
						# initiate a record of this ADF acc and start with count 1
						$absent_adf_acc_count{ $arrayDesignAcc } = 1;
					}
				}
			}
		}
        # Catch cases where non AE ADF accession is provided.
		else {

			$self->error(
                "Array design \"",
                $arrayDesignAcc,
                "\" is not a valid ArrayExpress array design accession and hence is not supported by Atlas."
			);

			$self->_add_atlas_fail_code( 2 );
		}
	}

	# TODO: investigate consolidating the two files.
    # Now update the tracking files
	open( OUT, ">$adf_tracking_file_path" )
	  || $self->logdie(
"Can't open file $adf_tracking_file_path to write the list of updated ADFs which are not supported by Atlas."
	  );
	foreach my $key ( keys %absent_adf_acc_count ) {
		print OUT "$key\t$absent_adf_acc_count{$key}\n";
	}
	close OUT;

	open( OUT2, ">$expt_tracking_file_path" )
	  || $self->logdie(
"Can't open file $expt_tracking_file_path to write the list of experiments already checked for Atlas eligiblity."
	  );
	foreach (@checked_expt_list) {
		print OUT2 "$_\n";
	}
	close OUT2;

    $self->info( "Finshed checking for Atlas array design support..." );
}


=item check_microarray_source_organism_match_adf

Make sure that the organism(s) in the SDRF match the organism(s) assigned to
the ADF in the Atlas information.

=cut

sub check_microarray_source_organism_match_adf {

	my ($self) = @_;

    $self->info( "Checking that source organism matches ADF organism..." );

    # Collect all the microarray assays.
    my $microarrayAssays = $self->_collect_microarray_assays;

    # Return if there weren't any microarray assays. This is probably a
    # sequencing experiment.
    unless( @{ $microarrayAssays } ) {

        $self->info( "No microarray assays found." );

        return;
    }
    
    # Map the MAGE-TAB array design accession(s) to the organism(s) they appear
    # with in the SDRF.
    my $magetabAdfToOrganism = $self->_map_array_designs_to_organisms( $microarrayAssays );       
    
    # Get the supported array designs and their organisms.
    my $supportedAdfs = $self->get_atlas_site_config->get_atlas_supported_adfs;

    # Go through the ADFs from the MAGE-TAB.
    foreach my $magetabAdf ( keys %{ $magetabAdfToOrganism } ) {

        # If this ADF is not supported by Atlas, we can't do the check.
        unless( $supportedAdfs->{ $magetabAdf } ) {

            $self->warn(
                "Cannot check for match between source and ADF organism annotations because array design \"",
                $magetabAdf,
                "\" is not supported by Atlas. "
            );

            $self->_add_atlas_fail_code( -17 );

            next;
        }
        
        # If we're still here, start looking for matches.
        foreach my $magetabOrg ( keys %{ $magetabAdfToOrganism->{ $magetabAdf } } ) {

            # Get the organism of the Atlas ADF.
            my $atlasAdfOrg = $supportedAdfs->{ $magetabAdf };

            # If we got a match, skip to the next one.
            if( $magetabOrg eq $atlasAdfOrg ) {

                $self->info( 
                    "MAGE-TAB organism (",
                    $magetabOrg,
                    ") and Atlas ADF organism (",
                    $atlasAdfOrg,
                    ") match."
                );

                next;
            }
            # If we did not get a match, check against the NCBI taxonomy
            # synonyms.
            else {
                
                my $taxid = fetch_ncbi_taxid( $atlasAdfOrg, $self->get_logger );

                unless( $taxid ) {

                    $self->warn(
                        "Cannot check for match between source and Atlas ADF organism annotation: ",
                        "Query against NCBI taxonomy unsuccessful."
                    );

                    $self->_add_atlas_fail_code( -17 );

                    return;
                }
                
                my $efetchResult = $self->_fetch_taxon_info_by_taxid( $taxid );

                unless( $efetchResult ) {

                    $self->warn(
                        "Cannot check for match between source and Atlas ADF organism annotation: ",
                        "Could not fetch taxon information from NCBI taxonomy."
                    );

                    $self->_add_atlas_fail_code( -17 );
                    
                    next;
                }

                my $ncbiTaxNames = { 
                    $efetchResult->{ "Taxon" }->{ $taxid }->{ "ScientificName" } => 1 
                };

                foreach my $synonym ( 
                    @{ $efetchResult->{ "Taxon" }->{ $taxid }->{ "OtherNames" }->{ "Synonym" } } 
                ) {

                    $ncbiTaxNames->{ $synonym } = 1;
                }

                # Now check the Source organism name against those found in NCBI taxonomy.
                unless( $ncbiTaxNames->{ $magetabOrg } ) {

                    $self->error(
                        "MAGE-TAB organism annotation \"",
                        $magetabOrg,
                        "\" for ADF \"",
                        $magetabAdf,
                        "\" does not match Atlas ADF organism annotation \"",
                        $atlasAdfOrg,
                        "\", or any of its synonyms found in NCBI taxonomy."
                    );

                    $self->_add_atlas_fail_code( 17 );
                }
            }
        }
    }

    $self->info( "Finished checking that source organism matches ADF organism." );
}


=item check_microarray_labels

Make sure that microarray assays have label information, and that this is
either "biotin" or one or both of "Cy3" and "Cy5". 

=cut

sub check_microarray_labels {

    my ( $self ) = @_;

    $self->info(
        "Checking microarray labels."
    );

    # Collect all the microarray assays.
    my $microarrayAssays = $self->_collect_microarray_assays;

    # Return if there weren't any microarray assays. This is probably a
    # sequencing experiment.
    unless( @{ $microarrayAssays } ) {

        $self->info( "No microarray assays found." );

        return;
    }
    
    # Go through the assays...
    foreach my $assay ( @{ $microarrayAssays } ) {
    
        foreach my $sdrfRow ( $assay->get_sdrfRows ) {

            foreach my $node ( $sdrfRow->get_nodes ) {

                if( $node->isa( "Bio::MAGETAB::LabeledExtract" ) ) {

                    unless( $node->has_label ) {

                        $self->error(
                            "Labeled extract \"",
                            $node->get_name,
                            "\" has no label."
                        );

                        $self->_add_atlas_fail_code( 16 );

                        next;
                    }

                    my $label = $node->get_label->get_value;

                    # Unless the label is biotin or Cy3 or Cy5, fail.
                    unless( 
                        $label =~ /^biotin$/i ||
                        $label =~ /^cy[3|5]$/i
                    ) {
                        $self->error(
                            "Unrecognised label \"",
                            $label,
                            "\" at labeled extract \"",
                            $node->get_name,
                            "\"."
                        );

                        $self->_add_atlas_fail_code( 16 );
                    }
                }
            }
        }
    }

    $self->info(
        "Finished checking microarray labels."
    );
}


sub check_sequencing_runs_and_files {

	my ($self) = @_;

    $self->info( "Checking sequencing runs and files..." );

    # Collect the sequencing assays.
    my $sequencingAssays = $self->_collect_sequencing_assays;

    unless( @{ $sequencingAssays } ) {

        $self->debug(
            "No sequencing assays found."
        );

        return;
    }

    
    # Then find out MAGE-TAB is at the submission stage, submissions stage with
    # ENA accessions added or loading stage by finding out if there is an AE
    # accession plus a Comment[SequenceDataURI]
	my $MAGETAB_stage = $self->_check_MAGETAB_stage;
	

	if( $MAGETAB_stage eq 'submission' ) {
		
        $self->info(
            "Skipping sequencing experiment checks as this is a sequencing experiment at submission stage."
		);
		
        return;
	}
    
    # Checks to do:
    #   - Presence of ENA run accessions and FASTQ URI and/or submitted file names.
    #   - Format of ENA run accessions
    #   - Format of FASTQ URIs
    foreach my $assay ( @{ $sequencingAssays } ) {
        
        # Get the Scan node(s) and collect the ENA_RUN or RUN_NAME comment.
        foreach my $sdrfRow ( $assay->get_sdrfRows ) {

            foreach my $node ( $sdrfRow->get_nodes ) {

                if( $node->isa( "Bio::MAGETAB::DataAcquisition" ) ) {

                    my %comments = map { $_->get_name => $_->get_value } $node->get_comments;

                    # Check ENA_RUNs.
                    if( $comments{ "ENA_RUN" } ) {
                        
                        # Check the format.
                        unless( $comments{ "ENA_RUN" } =~ /^[ESD]{1}RR[0-9]{6,}\b/ ) {

                            $self->error(
                                "ENA run accession \"",
                                $comments{ "ENA_RUN" },
                                "\" does not look like an ENA run accession."
                            );

                            $self->_add_atlas_fail_code( 14 );
                        }

                    }
                    # Check for RUN_NAME if no ENA_RUN.
                    else {
                        
                        unless( $comments{ "RUN_NAME" } ) {
                            
                            $self->error(
                                "Scan node \"",
                                $node->get_name,
                                "\" does not have an ENA_RUN or RUN_NAME associated with it."
                            );

                            $self->_add_atlas_fail_code( 14 );
                        }
                    }

                    # Check FASTQ URIs.
                    if( $comments{ "FASTQ_URI" } ) {

                        unless( 
                            $comments{ "FASTQ_URI" } =~ 
/^ftp\:\/\/ftp\.sra\.ebi\.ac\.uk\/vol[0-9]{1}\/fastq\/.{6}\/[ESD]{1}RR[0-9]{6}\/[ESD]{1}RR[0-9]{6}\_*[1-2]*\.fastq\.gz\b/ 
                        ) {
                            # If there was no match to the original style URIs,
                            # try the new style URL:
                            # ftp://ftp.sra.ebi.ac.uk/vol1/fastq/SRR105/005/SRR1055105/SRR1055105_2.fastq.gz
                            unless( 
                                $comments{ "FASTQ_URI" } =~ 
/^ftp\:\/\/ftp\.sra\.ebi\.ac\.uk\/vol[0-9]{1}\/fastq\/.{6}\/.{3}\/[ESD]{1}RR[0-9]{6,}\/[ESD]{1}RR[0-9]{6,}\_*[1-2]*\.fastq\.gz\b/
				            ) {
                            
                                # If it doesn't match the new style either, fail.
                                $self->error(
                                    "FASTQ URI ",
                                    $comments{ "FASTQ_URI" },
                                    " does not match the expected pattern."
                                );

                                $self->_add_atlas_fail_code( 14 );
                            }
                        }
                    }
                    else {
                        
                        unless( $comments{ "SUBMITTED_FILE_NAME" } ) {

                            $self->error(
                                "No FASTQ_URI or SUBMITTED_FILE_NAME comment found at scan node ",
                                $node->get_name
                            );

                            $self->_add_atlas_fail_code( 14 );
                        }
                    }
                }
            }
        }
    }
}




############################################
# Subroutines called by check_* subroutines.
############################################


sub _add_atlas_fail_code {

	my ( $self, $failCode ) = @_;

    unless( looks_like_number( $failCode ) ) {
        $self->logdie( "Atlas fail code $failCode is not a number!" );
    }
	
    my @oldFailCodes = @{ $self->get_atlas_fail_codes };
    
    my %failCodes = map { $_ => 1 } @oldFailCodes;

	$failCodes{ $failCode } = 1;

    my @newFailCodes = sort keys %failCodes;

	$self->set_atlas_fail_codes( \@newFailCodes );
}


# Some checks are only for microarray assays. Here is a subroutine to collect
# all the microarray assays from the MAGE-TAB.
sub _collect_microarray_assays {

    my ( $self ) = @_;

    my $magetab = $self->get_magetab;

    my $microarrayAssays = [];

    foreach my $assay ( $magetab->get_assays ) {

        my $techType = $assay->get_technologyType->get_value;
        
        # If there's a technology type with a microarray type, collect it.
        if( $techType =~ /array/i || $techType =~ /hybridi[sz]ation/i ) {
    
            push @{ $microarrayAssays }, $assay;
        }
        # If there's no technology type, but there is an array design (older
        # experiments), collect it.
        elsif( $assay->has_arrayDesign ) {

            push @{ $microarrayAssays }, $assay;
        }
        # Otherwise just log that we don't think it's a microarray assay.
        else {
            $self->debug(
                "Assay \"",
                $assay->get_name,
                "\" is not a microarray assay."
            );
        }
    }

    return $microarrayAssays;
}


sub _collect_sequencing_assays {

    my ( $self ) = @_;

    my $magetab = $self->get_magetab;

    my $sequencingAssays = [];

    foreach my $assay ( $magetab->get_assays ) {

        my $techType = $assay->get_technologyType->get_value;
     
        if( $techType =~ /sequencing/i ) {

            push @{ $sequencingAssays }, $assay;
        }
        else {
            $self->debug(
                "Assay \"",
                $assay->get_name,
                "\" is not a sequencing assay."
            );
        }
    }

    return $sequencingAssays;
}


sub _to_r_safe {

    my ( $assayName ) = @_;

    # Replace anything that is not a letter, number, . or _ with a .
    ( my $safeName = $assayName ) =~ s/[^A-Za-z\d\._]/./g;

    # If the name starts with a number, add an "X" to the start.
    $safeName =~ s/^(\.?\d)/X$1/;
    
    # TODO: Also handle reserved words? Unlikely to be used as assay names...
    # if else repeat while function for in next break TRUE FALSE NULL Inf NaN
    # NA NA_integer_ NA_real_ NA_complex_ NA_character_

    return $safeName;
}


sub _check_r_safe_names {

    my ( $self, $assayNamesToRsafe ) = @_;

    # Check whether any of the converted names are the same.
    foreach my $thisAssayName ( keys %{ $assayNamesToRsafe } ) {
    
        my $thisRSafeName = $assayNamesToRsafe->{ $thisAssayName };

        foreach my $assayName ( keys %{ $assayNamesToRsafe } ) {

            if( $assayName eq $thisAssayName ) { next; }

            my $rSafeName = $assayNamesToRsafe->{ $assayName };
            
            if( $rSafeName eq $thisRSafeName ) {

                $self->error(
                    "Atlas assay names \"",
                    $thisAssayName,
                    "\" and \"",
                    $assayName,
                    "\" are the same when made R-safe. Both become \"",
                    $rSafeName,
                    "\"."
                );

                $self->_add_atlas_fail_code( 20 );
            }
        }

        delete $assayNamesToRsafe->{ $thisAssayName };
    }
}


sub _fetch_taxon_info_by_taxid {

    my ( $self, $taxid ) = @_;

    my $efetchURL = $self->get_efetch_base_url . "db=taxonomy&id=$taxid";

    my $efetchXML = make_http_request( $efetchURL, "xml", $self->get_logger );

    unless( http_request_successful( $efetchXML, $self->get_logger ) ) {

        return;
    }

    my $efetchResult = XMLin(
        $efetchXML,
        ForceArray  => [
            "Synonym",
            "Taxon"
        ],
        KeyAttr => {
            "Taxon" => "TaxId"
        }
    );

    return $efetchResult;
}

sub _add_characteristic_types {

    my ( $self, $allPropertyTypes, $node ) = @_;

    foreach my $characteristic ( $node->get_characteristics ) {

        my $type = $self->_dont_normalize_category( $characteristic->get_category );

        $allPropertyTypes->{ $type } = 1;
    }

    return $allPropertyTypes;
}


sub _map_adf_accs_to_names {

    my ( $self, $assays ) = @_;

    my $adfAccessionToName = {};

    my %magetabAdfAccs = map { $_->get_arrayDesign->get_name => 1 } ( values %{ $assays } );

    foreach my $adfAcc ( keys %magetabAdfAccs ) {

        $adfAccessionToName->{ $adfAcc } = get_array_design_name_from_arrayexpress( $adfAcc );
    }
    
    # If we didn't get any names, something went wrong. Return undef.
    unless( keys %{ $adfAccessionToName } ) {
        return;
    }

    return $adfAccessionToName;
}


sub _map_array_designs_to_organisms {

    my ( $self, $microarrayAssays ) = @_;
    
    my $magetabAdfToOrganism = {};

    foreach my $assay ( @{ $microarrayAssays } ) {

        # Fail and skip to next assay if no ADF (can't do check).
        unless( $assay->has_arrayDesign ) {

            $self->error(
                "No array design found for assay \"",
                $assay->get_name,
                "\" -- failing check for match between source and ADF organism annotations."
            );

            $self->_add_atlas_fail_code( 17 );

            next;
        }

        # If we're still here, get the array design accession.
        my $arrayDesign = $assay->get_arrayDesign->get_name;
        
        # Go through the SDRF rows...
        foreach my $sdrfRow ( @{ $assay->get_sdrfRows } ) {
            
            # Get all the nodes on this row.
            my @nodes = $sdrfRow->get_nodes;

            # Go through the nodes and get the organism from each Source node.
            # Note that there may be more than one Source node, e.g. in the
            # case of two-colour array data, so we can't do a simple mapping of
            # { ref($node) => $node } here.
            foreach my $node ( @nodes ) {

                if( $node->isa( "Bio::MAGETAB::Source" ) ) {

                    # Map Source characteristics by (lower case) category (property type).
                    my %mappedCharacteristics = map { lc( $_->get_category ) => $_ } @{ $node->get_characteristics };

                    # Get the organism.
                    my $organism = $mappedCharacteristics{ "organism" }->get_value;
                    
                    # Fail here if we didn't get an organism (unlikely!).
                    unless( $organism ) {

                        $self->error(
                            "No organism found for assay \"",
                            $assay->get_name,
                            "\" -- failing check for match between source and ADF organism annotations."
                        );

                        $self->_add_atlas_fail_code( 17 );

                        next;
                    }

                    # Add the mapping between array design and organism to the hash.
                    if( $magetabAdfToOrganism->{ $arrayDesign } ) {
                        
                        $magetabAdfToOrganism->{ $arrayDesign }->{ $organism } = 1;
                    }
                    else {
                        
                        $magetabAdfToOrganism->{ $arrayDesign } = {
                            $organism   => 1
                        };
                    }
                }
            }
        }
    }
    
    return $magetabAdfToOrganism;
}


# Create a hash mapping arrays of assay objects to their platform (array design
# and/or sequencing library strategy).
sub _map_platforms_to_assays {

    my ( $self, $assays ) = @_;

    my $platformsToAssays = {};

    foreach my $assay ( @{ $assays } ) {

        my $techType = $assay->get_technologyType->get_value;

        my $platform;

        if( $techType =~ /sequencing/i ) {
            
            # Get the extract node(s) for this assay via the SDRFRow(s).
            my @sdrfRows = $assay->get_sdrfRows;

            # If no sdrfRows, can't get to Extract node so just use
            # "NO_PLATFORM" as platform.
            unless( @sdrfRows ) {
                $self->warn( 
                    "No sdrfRows found for assay ",
                    $assay->get_name,
                    " -- cannot determine library strategy."
                );

                $platform = "NO_PLATFORM";
            }
            else {

                # Shouldn't have different extract library strategies going into the
                # same assay.
                my $libStrategies = $self->_get_library_strategies( \@sdrfRows, $assay->get_name );

                # Make sure there's only one library strategy for this assay.
                # If not, the assay is skipped and not included in the hash
                # mapping platforms to assays. This effectively excludes it from
                # being checked.
                unless( scalar keys( %{ $libStrategies } ) == 1 ) {
                    
                    $self->error( 
                        "Not exactly one library strategy for assay ",
                        $assay->get_name,
                        " -- not including it when counting biological replicates."
                    );

                    next;
                }

                # If we're still here, use the single library strategy as the platform.
                $platform = ( keys %{ $libStrategies } )[ 0 ];
            }
        }
        # Try getting the array design. Older experiments do not have a
        # technology type, and are probably microarray ones.
        else {
            
            # If no array design, warn and use "NO_ARRAY_DESIGN" as platform.
            unless( $assay->has_arrayDesign ) {

                $self->debug( 
                    "No array design found for array assay ", 
                    $assay->get_name
                );
                
                $platform = "NO_ARRAY_DESIGN";
            }
            else {
                $platform = $assay->get_arrayDesign->get_name;
            }
        }

        # Now we should have a platform. If not, warn and use "NO_PLATFORM".
        unless( $platform ) {
            $self->warn(
                "No array design or sequencing library strategy found for assay ",
                $assay->get_name
            );

            $platform = "NO_PLATFORM";
        }

        if( $platformsToAssays->{ $platform } ) {
            push @{ $platformsToAssays->{ $platform } }, $assay;
        }
        else {
            $platformsToAssays->{ $platform } = [ $assay ];
        }
    }
    
    # If there are no assays to return, log an error and return undef.
    unless( keys %{ $platformsToAssays } ) {
        
        $self->error(
            "No assays could be mapped to a platform (array design or sequencing library)"
        );

        return;
    }
    else {
        return $platformsToAssays;
    }
}


sub _get_library_strategies {

    my ( $self, $sdrfRows, $assayName ) = @_;

    my $libStrategies = {};

    foreach my $sdrfRow ( @{ $sdrfRows } ) {

        my @nodes = $sdrfRow->get_nodes;

        unless( @nodes ) {
            $self->warn(
                "No Nodes on SDRFRow for assay ",
                $assayName,
                " -- cannot determine library strategy."
            );

            $libStrategies->{ "NO_PLATFORM" } = 1;

            next;
        }

        # Map the nodes using their references.
        my %mappedNodes = map { ref( $_ ) => $_ } @nodes;

        # Skip if there isn't an Extract node.
        unless( $mappedNodes{ "Bio::MAGETAB::Extract" } ) {

            $self->warn(
                "No Extract node found for assay ",
                $assayName,
                " -- cannot determine library strategy."
            );

            $libStrategies->{ "NO_PLATFORM" } = 1;

            next;
        }

        # If we're still here, get the extract node.
        my $extractNode = $mappedNodes{ "Bio::MAGETAB::Extract" };

        my @comments = $extractNode->get_comments;

        # Get the comments of the Extract node, mapped by name.
        my %mappedComments = map { $_->get_name => $_ } @comments;

        # Skip if there isn't a LIBRARY_STRATEGY comment.
        unless( $mappedComments{ "LIBRARY_STRATEGY" } ) {
            $self->warn(
                "No LIBRARY_STRATEGY comment found on Extract Node for assay ",
                $assayName,
                " -- cannot determine library strategy."
            );

            $libStrategies->{ "NO_PLATFORM" } = 1;

            next;
        }

        # If we're still here, get the library strategy and add it
        # to the hash for counting.
        my $libStrategyComment = $mappedComments{ "LIBRARY_STRATEGY" };

        $libStrategies->{ $libStrategyComment->get_value } = 1;
    }

    return $libStrategies;
}


# Create a hash mapping unique combinations to the biological replicates they
# apply to.
sub _map_factors_to_bioreps {

    my ( $self, $biorepNamesToAssays ) = @_;
    
    # Empty hash to store mappings.
    my $factorValuesToBiorepNames = {};

    # Go through the hash mapping biological replicate names to assay objects.
    foreach my $biorepName ( keys %{ $biorepNamesToAssays } ) {

        # Verify that all assays for the biological replicate have the same
        # factor values as well.
        my $biorepFactorValues = {};
        
        # Go through the assays for this biological replicate name.
        foreach my $assay ( @{ $biorepNamesToAssays->{ $biorepName } } ) {

            # Concatenate the factor values into a string, so they can be used
            # as a key in the new hash.
            my $factorValueString = $self->_factor_values_to_string( $assay );
            
            # If we got a factor value string, add it to the hash.
            if( $factorValueString ) {
                $biorepFactorValues->{ $factorValueString } = 1;
            }
        }

        # Make sure that there's only one set of factor values for this
        # biological replicate.
        if( scalar keys %{ $biorepFactorValues } > 1 ) {
            
            # Log an error.
            $self->error( "Technical replicate group \"$biorepName\" has conflicting factor values." );
            
            # FIXME: add fail code for conflicting factor values inside a tech
            # rep group (i.e. bio rep).
            $self->_add_atlas_fail_code( 99 );

            # Return undef.
            return;
        }
        # Skip if we didn't get any factor values for this one.
        elsif( ! keys %{ $biorepFactorValues } ) {

            next;
        }
        # If we have the correct number (1) of factor value sets, add this to
        # the hash.
        else {

            my $thisBiorepFactorValueString = ( keys %{ $biorepFactorValues } )[ 0 ];

            $factorValuesToBiorepNames->{ $thisBiorepFactorValueString }->{ $biorepName } = 1;
        }
    }
    
    # Return the new hash mapping factor value combinations to biological replicate names.
    return $factorValuesToBiorepNames;
}


# In order to count biological replicates, it helps to be able to index assays by
# unique combinations of factor values. A way to do this is to use the factor
# value combinations as hash keys pointing to an array of the assays they are
# found in. In order to use them as keys they are concatenated into a string.
sub _factor_values_to_string {

    my ( $self, $assay ) = @_;
    
    # Get the factors for this assay.
    my $assayFactors = $self->_get_factors( $assay );
    
    # If we didn't get any factors, return here.
    unless( $assayFactors ) { return; }

    # Empty array for the factor values.
    my @factorValues = ();

    # Go through the assay's factors...
    foreach my $type ( sort keys %{ $assayFactors } ) {
        
        # Ignore "block", if any.
        unless( $type =~ /^block$/i ) {

            # Add the factor values to the array.
            push @factorValues, keys %{ $assayFactors->{ $type } };
        }
    }

    # Join the factor values with semi-colons.
    my $factorValueString = join "; ", @factorValues;
    
    # Return the new string.
    return $factorValueString;
}


# Create a hash of the factors for any given SDRF node.
#   $factors->{ $type }->{ $value } = 1
sub _get_factors {

    my ( $self, $node ) = @_;
    
    # Get the SDRFRow objects for this SDRF node.
    my @sdrfRows = $node->get_sdrfRows;

    # Die if there aren't any SDRFRow objects (these are where the factors
    # live).
    unless( @sdrfRows ) {
        
        $self->error( 
            "Cannot get SDRF rows for ",
            ref( $node ),
            " node ",
            $node->get_name,
            " -- cannot read Factors."
        );

        return;
    }
    
    # Empty hash to store the factors.
    my $factors = {};

    # Go through the SDRFRow objects.
    foreach my $sdrfRow ( @sdrfRows ) {
        
        # If there are no factors, just return here.
        unless( $sdrfRow->has_factorValues ) { return; }

        # Go through the FactorValue objects for this row...
        foreach my $magetabFactorValue ( @{ $sdrfRow->get_factorValues } ) {

            # Get the factor type.
            my $type = $magetabFactorValue->get_factor->get_factorType->get_value;

            # Initialize value for factor value.
            my $value;

            # If this is a measurement (i.e. something with units e.g. dose,
            # time, ...), get the measurement value and concatenate the unit
            # value.
            if( $magetabFactorValue->has_measurement ) {
                
                # Get the measurement object.
                my $measurement = $magetabFactorValue->get_measurement;

                # Get the numeric value of the measurement.
                $value = $measurement->get_value;

                # If this measurement has a unit...
                if( $measurement->has_unit ) {

                    # Concatenate the unit to the end of the value as well.
                    $value = $value . " " . $measurement->get_unit->get_value;
                }
            }
            # If this isn't a measurement, try to get the term instead.
            elsif( $magetabFactorValue->has_term ) {
                
                # Set the value as the value of this term.
                $value = $magetabFactorValue->get_term->get_value;
            }
            # If this wasn't a measurement or a term, skip it (not sure what
            # else it could be).
            else { next; }
            
            # Now we have a type and a value, add them to the hash.
            $factors->{ $type }->{ $value } = 1;
        }
    }

    # If we put things into the hash, return it.
    if( keys %{ $factors } ) {
        return $factors;
    } 
    # Otherwise, return undef (rather than an empty hash).
    else {
        return;
    }
}


# Create a hash mapping "biological replicate" names to assay objects. These
# names are usually the assay name, but may be the contents of the Comment[
# technical replicate group ], if this is present and filled in. This is to
# handle cases where more than one Assay is used for the same biological sample,
#i.e. in the case of technical replicates.
sub _map_biorep_names_to_assays {

    my ( $magetabAssays ) = @_;

    # Empty hash to store mappings.
    my $biorepNamesToAssays = {};
    
    # Go through the assays.
    foreach my $magetabAssay ( @{ $magetabAssays } ) {

        # Get assay comments to check for technical replicate group IDs.
        my @assayComments = $magetabAssay->get_comments;

        # Map the comments to their names.
        my %mappedComments = map { $_->get_name => $_ } @assayComments;

        # If there's a technical replicate group comment, map the assay using
        # this ID as the biological replicate name.
        if( $mappedComments{ "technical replicate group" } ) {

            # Get the technical replicate group ID.
            my $biorepName = $mappedComments{ "technical replicate group" }->get_value;

            # Add the assay to an array indexed by the technical replicate group ID.
            if( $biorepNamesToAssays->{ $biorepName } ) {
             
                push @{ $biorepNamesToAssays->{ $biorepName } }, $magetabAssay;
            
            }  else {

                $biorepNamesToAssays->{ $biorepName } = [ $magetabAssay ];
            }
        }
        # If there's no technical replicate group comment, index the assay by
        # the assay name.
        else {
            $biorepNamesToAssays->{ $magetabAssay->get_name } = [ $magetabAssay ];
        }
    }
    
    # Return the completed hash.
    return $biorepNamesToAssays;
}


sub _check_MAGETAB_stage {

	my ($self) = @_;

# There are 3 possible MAGETAB stages 1. initial submission, 2. submission with ENA accessions added and 3. load ready with AE accession added as well
# This subroutine finds out what stage we are at so we know which sequencing checks to do

	my $MAGETAB_stage;

	my $accession;
	my @acc_comments =
	  grep { $_->get_name eq "ArrayExpressAccession" }
	  @{ $self->get_investigation->get_comments || [] };
    


    # FIXME: are "loading" and "submission with ENA accessions" actually ever
    # used?
	if (@acc_comments) {

		# check to see if has an AE accession
		$accession = $acc_comments[0]->get_value;
		$self->debug("Accession number is $accession");
		$MAGETAB_stage = "loading";

	}
	else {

# check to see if at submission stage with ENA accessions added - if so treat as load ready for checks
		my @ENAacc_comments =
		  grep { $_->get_name eq "SequenceDataURI" }
		  @{ $self->get_investigation->get_comments || [] };
		if (@ENAacc_comments) {
			$MAGETAB_stage = "submission with ENA accessions";
		}
		else {

# has neither an AE accession or the SequenceDataURI so will be at the initial submission stage
			$MAGETAB_stage = "submission";
		}
	}

	return $MAGETAB_stage;

}


1;
