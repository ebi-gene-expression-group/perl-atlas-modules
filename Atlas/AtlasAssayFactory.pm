#!/usr/bin/env perl
#
=pod

=head1 NAME

Atlas::AtlasAssayFactory - create Atlas::Assay objects from a Bio::MAGETAB::Assay object.

=head1 SYNOPSIS

use Atlas::AtlasAssayFactory

my @magetabAssays = $magetab->get_assays;

my $factory = Atlas::AtlasFactory->new( strict => 0 );

foreach my $magetabAssay ( @magetabAssays ) {

    my $atlasAssays = $factory->create_atlas_assays( $magetabAssay );

}

=head1 DESCRIPTION

An Atlas::AtlasAssayFactory object is used to create Atlas::Assay objects. The
default mode is strict, and means that assays must follow specific
Atlas-focused requirements. If this is turned off, the list of requirements to
be met is much shorter.

=cut

package Atlas::AtlasAssayFactory;

use 5.10.0;

use Moose;
use MooseX::FollowPBP;
use Log::Log4perl;
use URI::Escape;
use Data::Dumper;

use Atlas::Assay;

my $logger = Log::Log4perl::get_logger;

=head1 ATTRIBUTES

=over 2

=item strict

If this is set to 1: Ensure that each assay has at least one factor. Ensure
that each characteristic and factor only have one value per assay.

=cut

has 'strict' => (
    is => 'rw',
    isa => 'Bool',
    default => 1
);

=back

=head1 METHODS

=over 2

=item create_atlas_assays

Given a Bio::MAGETAB::Assay object, return an ArrayRef containing the relevant
Atlas::Assay objects, indexed by assay name.

=back

=cut

sub create_atlas_assays {

    my ( $self, $magetabAssay, $doNotModifyTechRepGroup ) = @_;

    my $atlasAssays;

    my $techType = $magetabAssay->get_technologyType->get_value;

    if( $techType =~ /hybridi[sz]ation/i ) {
        $techType = "array";
    }

    # Do different things depending on the tech type.
    if( $techType =~ /array/i  ) {

        $atlasAssays = _create_atlas_microarray_assays( $magetabAssay, "array" );
    }
    elsif( $techType =~ /sequencing/i ) {

        $atlasAssays = $self->_create_atlas_sequencing_assays( $magetabAssay, "sequencing" );
    }
    else {
        $atlasAssays = $self->_guess_type_and_create_atlas_assays( $magetabAssay, $techType );
    }

    # If we got no Atlas::Assay objects back, the MAGE-TAB assay wasn't
    # suitable (or something went wrong). Warn and return undef.
    unless( $atlasAssays ) {
        $logger->warn(
            "No Atlas::Assay objects were created for assay ",
            $magetabAssay->get_name,
        );

        return;
    }

    # Add the technical replicate group info, if any.
    $atlasAssays = _add_technical_replicate_info( $magetabAssay, $atlasAssays, $doNotModifyTechRepGroup );

    # Add the assay organism.
    $atlasAssays = _add_organism( $atlasAssays );

    # Sequencing assay specific information.
    if( $techType =~ /sequencing/i ) {

        $atlasAssays = _add_sequencing_specific_info( $magetabAssay, $atlasAssays );
    }
    elsif( $techType =~ /array/i ) {

        $atlasAssays = _add_array_data_file( $magetabAssay, $atlasAssays );
    }

    # Now the basic objects have been created, check if we are in strict mode
    # and if so run additional checks.
    if( $self->get_strict ) {

        # Check that the characteristics and factors only have one value per type.
        _check_strict_chars_and_factors( $atlasAssays );
    }

    unless( $atlasAssays ) {
        $logger->warn(
            "No Atlas::Assay objects were created for assay ",
            $magetabAssay->get_name,
        );

        return;
    }

    my @atlasAssaysArray = values %{ $atlasAssays };

    return \@atlasAssaysArray;
}


sub _create_atlas_microarray_assays {

    my ( $magetabAssay, $techType ) = @_;

    my $atlasAssays = {};

    # Get array design accession, if any.
    my $arrayDesign;

    if( $magetabAssay->has_arrayDesign ) {

        $arrayDesign = $magetabAssay->get_arrayDesign->get_name;

        unless( $arrayDesign ) {
            $logger->logdie(
                "No array design found for assay ",
                $magetabAssay->get_name,
                ". Cannot continue."
            );
        }
    }

    # Count the incoming edges -- this tells us if it's a one- or two-colour
    # assay. Currently we don't handle any more than two colours.
    my @inputEdges = $magetabAssay->get_inputEdges;

    unless( @inputEdges ) {
        $logger->logdie(
            "Array assay ",
            $magetabAssay->get_name,
            " has no nodes pointing to it in SDRF. Cannot continue."
        );
    }
    if( @inputEdges > 2 ) {
        $logger->logdie(
            "Array assay ",
            $magetabAssay->get_name,
            " has more than two nodes pointing to it in SDRF. Can only handle one- or two-colour microarray data."
        );
    }

    if( @inputEdges == 2 ) {

        foreach my $edge ( @inputEdges ) {

            my $inputNode = $edge->get_inputNode;

            unless( $inputNode ) {
                $logger->logdie(
                    "Could not access node upstream of ",
                    $magetabAssay->get_name,
                    ". Cannot continue."
                );
            }

            my $atlasAssayName = _create_twocolour_assay_name( $inputNode, $magetabAssay );

            my $characteristics = _create_characteristics( $inputNode );

            my $atlasAssay = Atlas::Assay->new(
                name            => $atlasAssayName,
                characteristics => $characteristics,
                technology_type => $techType
            );

            if( $arrayDesign ) {
                $atlasAssay->set_array_design( $arrayDesign );
            }

            my $factors = _create_factors( $inputNode );

            # Add the factors to the Assay if we got some.
            if( keys %{ $factors } ) {
                $atlasAssay->set_factors( $factors );
            }

            # Add the new assay to the array.
            $atlasAssays->{ $atlasAssay->get_name } = $atlasAssay;
        }
    }
    # For one-colour array assays.
    else {

        my $characteristics = _create_characteristics( $magetabAssay );

        my $atlasAssay = Atlas::Assay->new(
            name            => $magetabAssay->get_name,
            characteristics => $characteristics,
            technology_type => $techType
        );

        if( $arrayDesign ) {
            $atlasAssay->set_array_design( $arrayDesign );
        }

        my $factors = _create_factors( $magetabAssay );

        if( keys %{ $factors } ) {
            $atlasAssay->set_factors( $factors );
        }

        $atlasAssays->{ $atlasAssay->get_name } = $atlasAssay;
    }

    return $atlasAssays;
}


sub _create_atlas_sequencing_assays {

    my ( $self, $magetabAssay, $techType ) = @_;

    my $atlasAssays = {};

    my @outputEdges = $magetabAssay->get_outputEdges;

    unless( @outputEdges ) {
        $logger->warn(
            "Skipping assay ",
            $magetabAssay->get_name,
            " because it has no Scan node."
        );

        return;
    }

    foreach my $edge ( @outputEdges ) {

        my $outputNode = $edge->get_outputNode;

        unless( $outputNode->isa( "Bio::MAGETAB::DataAcquisition" ) ) {

            # Skip assays with no Scan node, there's no sequencing run information.
            $logger->warn(
                "Skipping assay ",
                $magetabAssay->get_name,
                " because it has no Scan node."
            );

            next;
        }

        my $atlasAssayName = _create_sequencing_assay_name( $outputNode );

        my $characteristics = _create_characteristics( $outputNode );

        my $atlasAssay = Atlas::Assay->new(
            name            => $atlasAssayName,
            characteristics => $characteristics,
            technology_type => $techType
        );

        my $factors = _create_factors( $outputNode );

        if( keys %{ $factors } ) {
            $atlasAssay->set_factors( $factors );
        }

        $atlasAssays->{ $atlasAssay->get_name } = $atlasAssay;
    }

    return $atlasAssays;
}


sub _guess_type_and_create_atlas_assays {

    my ( $self, $magetabAssay, $techType ) = @_;

    # Try to guess the technology type first.
    # If the assay has an array design it's probably an array assay.
    if( $magetabAssay->has_arrayDesign ) {

        my $atlasAssays = _create_atlas_microarray_assays( $magetabAssay, "array" );

        return $atlasAssays;
    }
    # Otherwise, if it has an ENA_EXPERIMENT comment it's probably sequencing.
    else {

        my @comments = $magetabAssay->get_comments;

        my %mappedComments = map { $_->get_name => 1 } @comments;

        if( $mappedComments{ "ENA_EXPERIMENT" } ) {

            my $atlasAssays = $self->_create_atlas_sequencing_assays( $magetabAssay, "sequencing" );

            return $atlasAssays;
        }
    }

    # If we're still here, try to create a generic Assay, with just name,
    # characteristics, and factors (if any) for assays for which we couldn't
    # guess.
    $logger->warn(
        "Unrecognised technology type for assay ",
        $magetabAssay->get_name,
        ": ",
        $techType,
        ". Creating generic assay object for this assay."
    );

    my $atlasAssay = $self->_create_atlas_generic_assays( $magetabAssay, $techType );

    unless( $atlasAssay ) {

        $logger->warn(
            "Could not create generic assay for ",
            $magetabAssay->get_name,
            ". Skipping it."
        );

        return;
    }
    else {
        return { $atlasAssay->get_name => $atlasAssay };
    }
}


sub _create_atlas_generic_assays {

    my ( $self, $magetabAssay, $techType ) = @_;

    my $characteristics = _create_characteristics( $magetabAssay );

    my $atlasAssay = Atlas::Assay->new(
        name            => $magetabAssay->get_name,
        characteristics => $characteristics,
        technology_type => $techType
    );

    my $factors = _create_factors( $magetabAssay );

    if( keys %{ $factors } ) {
        $atlasAssay->set_factors( $factors );
    }

    return $atlasAssay;
}


sub _create_twocolour_assay_name {

    my ( $inputNode, $magetabAssay ) = @_;

    unless( $inputNode->isa( "Bio::MAGETAB::LabeledExtract" ) ) {
        $logger->logdie(
            "Node ",
            $inputNode->get_name,
            " upstream of assay ",
            $magetabAssay->get_name,
            " is not a Labeled Extract. Cannot continue."
        );
    }

    my $label = $inputNode->get_label->get_value;

    unless( $label ) {
        $logger->logdie(
            "Did not get a label name for Labeled Extract ",
            $inputNode->get_name,
            ". Cannot continue."
        );
    }

    return $magetabAssay->get_name . "." . $label;
}


sub _create_sequencing_assay_name {

    my ( $scanNode ) = @_;

    my $atlasAssayName;

    my @comments = $scanNode->get_comments;

    my %commentsMap = map { $_->get_name => $_ } @comments;

    if( $commentsMap{ "ENA_RUN" } ) {

        my $comment = $commentsMap{ "ENA_RUN" };

        $atlasAssayName = $comment->get_value;
    }
    # If there's no ENA_RUN comment, try to use the RUN_NAME comment.
    elsif( $commentsMap{ "RUN_NAME" } ) {

        my $comment = $commentsMap{ "RUN_NAME" };

        $atlasAssayName = $comment->get_value;
    }

     # If there's no ENA_RUN comment or RUN_NAME try use RUN comment.
    elsif( $commentsMap{ "RUN" } ) {

        my $comment = $commentsMap{ "RUN" };

        $atlasAssayName = $comment->get_value;
    }

    # If we didn't get an ENA_RUN or RUN_NAME, error and die.
    unless( $atlasAssayName ) {

        $logger->logdie(
            "No ENA_RUN or RUN_NAME Comment found for Scan node: \"",
            $scanNode->get_name,
            "\". For Atlas, all RNA-seq experiments must have a column named ",
            "\"Comment[ ENA_RUN ]\" or \"Comment[ RUN_NAME ]\" immediately to the right of the ",
            "\"Scan Name\" column in the SDRF, ",
            "containing ENA run accessions or unique names for each sequencing run in the experiment."
        );

        # Hack for paired data. Strip off _1 and _2 and common file extensions.
        #$atlasAssayName =~ s/\.(gz|bz2)$//ig;
        #$atlasAssayName =~ s/\.(fq|fastq)$//ig;
        #$atlasAssayName =~ s/_(1|2){1}$//ig;
    }

    return $atlasAssayName;
}


sub _create_characteristics {

    my ( $node ) = @_;

    my @sdrfRows = $node->get_sdrfRows;

    unless( @sdrfRows ) {
        $logger->logdie(
            "Could not get SDRF rows for ",
            ref( $node ),
            " node ",
            $node->get_name,
            ". Cannot continue."
        );
    }

    my $characteristics = {};

    foreach my $sdrfRow ( @sdrfRows ) {

        my @nodes = $sdrfRow->get_nodes;

        my %mappedNodes = map { ref( $_ ) => $_ } @nodes;

        unless( $mappedNodes{ "Bio::MAGETAB::Source" } ) {
            $logger->logdie(
                "No Source Node found, cannot continue."
            );
        }

        my $sourceNode = $mappedNodes{ "Bio::MAGETAB::Source" };

        my @magetabChars = $sourceNode->get_characteristics;

        my $sampleNode = $mappedNodes{ "Bio::MAGETAB::Sample" };

        if( $sampleNode ) {

            push @magetabChars, $sampleNode->get_characteristics;
        }

        foreach my $characteristic ( @magetabChars ) {

            my $type = $characteristic->get_category;

            unless( $type =~ /RNA/ || $type =~ /DNA/ ) {
                $type = lc( $type );
            }

            my $value = $characteristic->get_value;

            $characteristics->{ $type }->{ $value } = 1;
        }

        # Also handle measurements e.g. age.
        if( $sourceNode->has_measurements ) {
            $characteristics = _collect_measurement_values( $sourceNode, $characteristics );
        }

        if( $sampleNode ) {
            if( $sampleNode->has_measurements ) {
                $characteristics = _collect_measurement_values( $sampleNode, $characteristics );
            }
        }
    }

    unless( keys %{ $characteristics } ) {
        $logger->logdie(
            "No characteristics found on SDRF rows of ",
            ref( $node ),
            " node ",
            $node->get_name,
            ". Cannot continue."
        );
    }

    return $characteristics;
}


sub _create_factors {

    my ( $node ) = @_;

    my @sdrfRows = $node->get_sdrfRows;

    unless( @sdrfRows ) {
        $logger->logdie(
            "Could not get SDRF rows for ",
            ref( $node ),
            " node ",
            $node->get_name,
            ". Cannot continue."
        );
    }

    my $factors = {};

    foreach my $sdrfRow ( @sdrfRows ) {

        if( $sdrfRow->has_factorValues ) {

            foreach my $magetabFactorValue ( @{ $sdrfRow->get_factorValues } ) {

                my $type = $magetabFactorValue->get_factor->get_factorType->get_value;

                unless( $type =~ /RNA/ || $type =~ /DNA/ ) {
                    $type = lc( $type );
                }

                my $value;

                if( $magetabFactorValue->has_measurement ) {

                    my $measurement = $magetabFactorValue->get_measurement;

                    $value = $measurement->get_value;

                    if( $measurement->has_unit ) {

                        $value = $value . " " . $measurement->get_unit->get_value;
                    }
                }
                elsif( $magetabFactorValue->has_term ) {

                    my $term = $magetabFactorValue->get_term;

                    $value = $term->get_value;
                }
                else {
                    $logger->logdie(
                        "Factor of type \"$type\" has no term or measurement attribute. Cannot continue."
                    );
                }

                $factors->{ $type }->{ $value } = 1;
            }
        }
    }
    return $factors;
}


sub _collect_measurement_values {

    my ( $node, $characteristics ) = @_;

    my @measurements = $node->get_measurements;

    foreach my $measurement ( @measurements ) {

        my $type = lc( $measurement->get_measurementType );

        my $value = $measurement->get_value;

        if( $measurement->has_unit ) {

            $value = $value . " " . $measurement->get_unit->get_value;
        }

        $characteristics->{ $type }->{ $value } = 1;
    }

    return $characteristics;
}


sub _check_strict_chars_and_factors {

    my ( $atlasAssays ) = @_;

    # Make sure each assay has factors.
    foreach my $atlasAssay ( values %{ $atlasAssays } ) {

        unless( $atlasAssay->has_factors ) {
            $logger->logdie(
                "Atlas::Assay object ",
                $atlasAssay->get_name,
                " has no factors. Cannot continue."
            );
        }
    }

    # Make sure each characteristic and factor only has one value per assay.
    foreach my $atlasAssay ( values %{ $atlasAssays } ) {

        foreach my $attributeHash ( $atlasAssay->get_characteristics, $atlasAssay->get_factors ) {

            foreach my $type ( keys %{ $attributeHash } ) {

                if( ( keys %{ $attributeHash->{ $type } } ) > 1 ) {

                    my @values = keys %{ $attributeHash->{ $type } };
                    my $valueString = join ", ", @values;

                    $logger->logdie(
                        "An assay cannot have more than one value for a characteristic or factor.\n",
                        "Atlas assay: ",
                        $atlasAssay->get_name,
                        "\nType: $type",
                        "\nValues: $valueString"
                    );
                }
            }
        }
    }
}


sub _add_organism {

    my ( $atlasAssays ) = @_;

    my $atlasAssaysWithOrganism = {};

    foreach my $atlasAssay ( values %{ $atlasAssays } ) {

        my $characteristics = $atlasAssay->get_characteristics;

        my $organism = ( keys %{ $characteristics->{ "organism" } } )[ 0 ];

        unless( $organism ) {
            $logger->warn(
                "No organism found for Atlas assay ",
                $atlasAssay->get_name
            );
        }
        else {
            $atlasAssay->set_organism( $organism );
        }

        $atlasAssaysWithOrganism->{ $atlasAssay->get_name } = $atlasAssay;
    }

    return $atlasAssaysWithOrganism;
}


sub _add_technical_replicate_info {

    my ( $magetabAssay, $atlasAssays, $doNotModifyTechRepGroup ) = @_;

    my @magetabAssayComments = $magetabAssay->get_comments;

    my %mappedComments = map { $_->get_name => $_ } @magetabAssayComments;

    if( $mappedComments{ "technical replicate group" } ) {

        my $atlasAssaysWithTechRepInfo = {};

        my $techRepGroupComment = $mappedComments{ "technical replicate group" };

        my $techRepGroup = $techRepGroupComment->get_value;

        if( ! $doNotModifyTechRepGroup ) {
          $techRepGroup =~ s/^\D+/t/g;
          $techRepGroup =~ s/\D+$//g;

          unless( $techRepGroup =~ /[a-zA-Z]/ ) {
            $techRepGroup = "t" . $techRepGroup;
          }
        }

        foreach my $atlasAssay ( values %{ $atlasAssays } ) {

            $atlasAssay->set_technical_replicate_group( $techRepGroup );

            $atlasAssaysWithTechRepInfo->{ $atlasAssay->get_name } = $atlasAssay;
        }

        return $atlasAssaysWithTechRepInfo;
    }
    else {

        return $atlasAssays;
    }
}


sub _add_sequencing_specific_info {

    my ( $magetabAssay, $atlasAssays ) = @_;

    # We need to get the library layout and library strand info from the
    # Extract node (if available); and the FASTQ filenames from the Scan node.
    # The file names are required so if they're missing then die.

    # First get the FASTQ file info. This may be needed to work out the library
    # layout later.
    my $atlasAssayNameToFASTQ = _index_fastq_files_by_atlas_assay_name( $magetabAssay );

    # Next get the info from the Extract Node. This Node stores the library
    # layout and library strand information.
    my @inputEdges = $magetabAssay->get_inputEdges;

    unless( @inputEdges ) {
        $logger->warn(
            "No nodes upstream of sequencing assay ",
            $magetabAssay->get_name,
            ". Cannot find sequencing run accessions."
        );

        return $atlasAssays;
    }

    # We'll only allow one library layout and strand per assay, so die if there is more than one.
    my ( $libraryLayouts, $libraryStrands );

    foreach my $edge ( @inputEdges ) {

        my $inputNode = $edge->get_inputNode;

        unless( $inputNode ) {
            $logger->warn(
                "No nodes upstream of sequencing assay ",
                $magetabAssay->get_name,
                ". Cannot find sequencing run accessions."
            );

            next;
        }

        unless( $inputNode->isa( "Bio::MAGETAB::Extract" ) ) {
            $logger->warn(
                "Node upstream of sequencing assay ",
                $magetabAssay->get_name,
                " is not an Extract node. Cannot find sequencing run accessions."
            );
        }

        # Get the library layout, either from the comment or try to work it out
        # from the FASTQ file information if the comment is unavailable.
        my $libLayout = _find_library_layout( $inputNode, $atlasAssayNameToFASTQ );

        if( $libLayout ) {
            $libraryLayouts->{ $libLayout } = 1;
        }

        # Also get the library strand, if available.
        my @comments = $inputNode->get_comments;

        my %mappedComments = map { $_->get_name => $_ } @comments;

        if( $mappedComments{ "LIBRARY_STRAND" } ) {

            my $libStrandComment = $mappedComments{ "LIBRARY_STRAND" };

            my $libStrand = $libStrandComment->get_value;

            if( $libStrand =~ /first strand/i || $libStrand =~ /second strand/i ) {

                $libraryStrands->{ $libStrand } = 1;
            }
            elsif( $libStrand =~ /not applicable/i || $libStrand =~ /not strand specific/i ) {
                next;
            }
            else {
                $logger->logdie(
                    "Unrecognised library strand value: \"",
                    $libStrand,
                    "\". Please use \"first strand\" or \"second strand\" or \"not applicable\" or \"not strand specific\" or leave this column empty."
                );
            }
        }
    }

    my $libraryLayout;

    if( keys %{ $libraryLayouts } ) {
        # Make sure there's only one library layout.
        unless( ( keys %{ $libraryLayouts } ) == 1 ) {

            $logger->logdie(
                "More than one library layout found for assay ",
                $magetabAssay->get_name,
                ". Cannot continue."
            );
        }

        $libraryLayout = lc( ( keys %{ $libraryLayouts } )[ 0 ] );
    }

    my $libraryStrand;

    if( keys %{ $libraryStrands } ) {

        # If we got a library strand, make sure there's only one.
        if( ( keys %{ $libraryStrands } ) == 1 ) {

            $libraryStrand = lc( ( keys %{ $libraryStrands } )[ 0 ] );
        }
        else {

            $logger->warn(
                "More than one library strand found for assay ",
                $magetabAssay->get_name,
                ". Cannot decide which strand to use."
            );
        }
    }

    # Now we have all the info we need, populate the Atlas::Assay objects with it.
    my $atlasAssaysWithSeqInfo = {};

    foreach my $atlasAssayName ( keys %{ $atlasAssays } ) {

        my $atlasAssay = $atlasAssays->{ $atlasAssayName };

        my @fastqFiles = keys %{ $atlasAssayNameToFASTQ->{ $atlasAssayName } };

        if( scalar @fastqFiles ) {
            $atlasAssay->set_fastq_file_set( \@fastqFiles );
        }

        if( $libraryLayout ) {
            $atlasAssay->set_library_layout( $libraryLayout );
        }

        if( $libraryStrand ) {
            $atlasAssay->set_library_strand( $libraryStrand );
        }

        $atlasAssaysWithSeqInfo->{ $atlasAssayName } = $atlasAssay;
    }

    return $atlasAssaysWithSeqInfo;
}


# RNA-seq Atlas assay names are actually ENA run accessions or run names from a
# RUN_NAME comment if the ENA run doesn't exist.
sub _index_fastq_files_by_atlas_assay_name {

    my ( $magetabAssay ) = @_;

    my $atlasAssayNameToFASTQ = {};

    my @outputEdges = $magetabAssay->get_outputEdges;

    unless( @outputEdges ) {
        $logger->warn(
            "No nodes downstream of assay ",
            $magetabAssay->get_name,
            ". Can't get sequencing file info."
        );
    }

    foreach my $edge ( @outputEdges ) {

        my $outputNode = $edge->get_outputNode;

        unless( $outputNode ) {
            $logger->warn(
                "No nodes downstream of assay ",
                $magetabAssay->get_name,
                ". Can't get sequencing file info."
            );

            next;
        }

        unless( $outputNode->isa( "Bio::MAGETAB::DataAcquisition" ) ) {
            $logger->warn(
                "Node downstream of ",
                $magetabAssay->get_name,
                " is not a Scan node. Can't get sequencing file info."
            );

            next;
        }


        # Get the sequencing assay name for this scan node (ENA_RUN or RUN_NAME
        # or Scan Name).
        my $atlasAssayName = _create_sequencing_assay_name( $outputNode );

        # Find the FASTQ file -- this is FASTQ_URI or SUBMITTED_FILE_NAME.
        my @comments = $outputNode->get_comments;

        my %mappedComments = map { $_->get_name => $_ } @comments;

        my $foundFile = 0;

        if( $mappedComments{ "FASTQ_URI" } ) {

            my $fastqUriComment = $mappedComments{ "FASTQ_URI" };

            my $fastqUri = $fastqUriComment->get_value;

            if( $fastqUri ) {
                $atlasAssayNameToFASTQ->{ $atlasAssayName }->{ $fastqUri } = 1;
                $foundFile++;
            }
        }
        # Fall back on submitted filename if FASTQ_URI is unavailable.
        elsif( $mappedComments{ "SUBMITTED_FILE_NAME" } ) {

            my $submittedFileComment = $mappedComments{ "SUBMITTED_FILE_NAME" };

            my $fastqUri = $submittedFileComment->get_value;

            if( $fastqUri ) {
                $atlasAssayNameToFASTQ->{ $atlasAssayName }->{ $fastqUri } = 1;
                $foundFile++;
            }
        }
        else {
            $logger->warn(
                "No FASTQ_URI or SUBMITTED_FILE_NAME comments found at Scan node ",
                $outputNode->get_name,
                ". Cannot add sequencing filename."
            );
        }

        # Handle the case where the comment exists but is empty.
        unless( $foundFile ) {
            $logger->warn(
                "No FASTQ file found at Scan node ",
                $outputNode->get_name,
            );
        }
    }

    return $atlasAssayNameToFASTQ;
}


sub _find_library_layout {

    my ( $extractNode, $atlasAssayNameToFASTQ ) = @_;

    # First try to get the LIBRARY_LAYOUT comment value.
    my @comments = $extractNode->get_comments;

    my %mappedComments = map { $_->get_name => $_ } @comments;

    if( $mappedComments{ "LIBRARY_LAYOUT" } ) {

        my $libLayoutComment = $mappedComments{ "LIBRARY_LAYOUT" };

        my $libLayout = $libLayoutComment->get_value;

        if( $libLayout ) {
            return $libLayout;
        }
    }

    # If we're still here, we didn't get a library layout from the Extract node
    # comments, so try to figure it out from the number of FASTQ files.
    # Should only get one library layout for an assay, but store as keys of
    # hash and make sure there's only one afterwards.
    my $libLayouts = {};

    foreach my $atlasAssayName ( keys %{ $atlasAssayNameToFASTQ } ) {

        my @fastqFiles = keys %{ $atlasAssayNameToFASTQ->{ $atlasAssayName } };

        if( @fastqFiles == 1 ) {

            $libLayouts->{ "single" } = 1;
        }
        elsif( @fastqFiles == 2 ) {

            $libLayouts->{ "paired" } = 1;
        }
        else {
            if( @fastqFiles > 2 ) {
                $logger->warn(
                    "Too many FASTQ files found for Atlas assay ",
                    $atlasAssayName,
                    ". Cannot work out library layout."
                );

                next;
            }

            else {
                $logger->warn(
                    "No FASTQ files found for Atlas assay ",
                    $atlasAssayName,
                    ". Cannot work out library layout."
                );
                next;
            }
        }
    }

    # Now check we have exactly one library layout.
    if( ( keys %{ $libLayouts } ) > 1 ) {

        $logger->warn(
            "More than one library layout found for an assay. Cannot decide which one to use."
        );

        return;
    }
    elsif( !( keys %{ $libLayouts } ) ) {

        $logger->warn(
            "Could not determine library layout for an assay."
        );

        return;
    }
    else {
        # If we're still here, return the library layout we found.
        my $libLayout = ( keys %{ $libLayouts } )[ 0 ];

        return $libLayout;
    }

}


sub _add_array_data_file {

    my ( $magetabAssay, $atlasAssays ) = @_;

    # Is this a one- or two-colour assay? Some types of two-colour assay have
    # two raw data files, one per channel (label).
    unless( $magetabAssay->has_inputEdges ) {

        $logger->warn(
            "No nodes upstream of assay ",
            $magetabAssay->get_name,
            ". Cannot find array data file name."
        );

        return $atlasAssays;
    }

    my @inputEdges = $magetabAssay->get_inputEdges;

    # For two-colour assays...
    if( @inputEdges == 2 ) {

        my $atlasAssayNamesToRawDataFiles = {};

        foreach my $edge ( @inputEdges ) {

            my $inputNode = $edge->get_inputNode;

            unless( $inputNode ) {
                $logger->warn(
                    "No nodes upstream of assay ",
                    $magetabAssay->get_name,
                    ". Cannot find array data file name."
                );

                return $atlasAssays;
            }

            my $atlasAssayName = _create_twocolour_assay_name( $inputNode, $magetabAssay );

            my @sdrfRows = $inputNode->get_sdrfRows;

            my $arrayDataFile = _retrieve_array_data_filename( \@sdrfRows );

            if( $arrayDataFile ) {
                $atlasAssayNamesToRawDataFiles->{ $atlasAssayName } = $arrayDataFile;
            }
        }

        # Now should have each labeled assay name plus its raw data file. Add
        # the raw data file name to the appropriate Atlas::Assay object(s) and
        # return them.
        my $atlasAssaysWithRawDataFiles = {};

        foreach my $atlasAssay ( values %{ $atlasAssays } ) {

            my $atlasAssayName = $atlasAssay->get_name;

            my $arrayDataFile = $atlasAssayNamesToRawDataFiles->{ $atlasAssayName };

            if( $arrayDataFile ) {
                $atlasAssay->set_array_data_file( $arrayDataFile );
            }

            $atlasAssaysWithRawDataFiles->{ $atlasAssayName } = $atlasAssay;
        }

        return $atlasAssaysWithRawDataFiles;
    }
    # Otherwise this is a one-colour assay.
    else {

        my @sdrfRows = $magetabAssay->get_sdrfRows;

        my $arrayDataFile = _retrieve_array_data_filename( \@sdrfRows );

        unless( $arrayDataFile ) { return $atlasAssays; }

        my $atlasAssaysWithFiles = {};

        foreach my $atlasAssay ( values %{ $atlasAssays } ) {

            $atlasAssay->set_array_data_file( $arrayDataFile );

            $atlasAssaysWithFiles->{ $atlasAssay->get_name } = $atlasAssay;
        }

        return $atlasAssaysWithFiles;
    }

    # If we're still here, die as something went wrong and we didn't get any
    # raw date files for this assay.
    $logger->warn(
        "No raw data files found for assay ",
        $magetabAssay->get_name,
    );

    return $atlasAssays;
}


sub _retrieve_array_data_filename {

    my ( $sdrfRows ) = @_;

    # Only allow one raw data file per label for two-colour data.
    my $arrayDataFiles = {};

    foreach my $sdrfRow ( @{ $sdrfRows } ) {

        my @nodes = $sdrfRow->get_nodes;

        foreach my $node ( @nodes ) {

            # Find the raw data file. There could be normalized data files as
            # well.
            if( ref( $node ) eq "Bio::MAGETAB::DataFile" ) {

                my $dataType = $node->get_dataType->get_value;

                unless( $dataType eq "raw" ) { next; }
                else {

                    my $arrayDataFile = $node->get_uri;

                    $arrayDataFile =~ s/^file\://;

                    $arrayDataFile = uri_unescape( $arrayDataFile );

                    $arrayDataFiles->{ $arrayDataFile } = 1;
                }
            }
        }
    }

    # Die if we got more than one raw data file for this scan.
    if( ( keys %{ $arrayDataFiles } ) > 1 ) {

        my $fileString = join ", ", ( keys %{ $arrayDataFiles } );

        $logger->warn(
            "Too many raw data files found for one Atlas assay ($fileString). Cannot decide which one to use.",
        );

        return;
    }
    elsif( !( keys %{ $arrayDataFiles } ) ) {

        $logger->warn(
            "No raw data files found for an Atlas assay.",
        );

        return;
    }
    else {
        return ( keys %{ $arrayDataFiles } )[ 0 ];
    }
}

1;

=head1 AUTHOR

Expression Atlas team <arrayexpress-atlas@ebi.ac.uk>

=cut
