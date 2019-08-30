#!/usr/bin/env perl

# POD
=pod

=head1 NAME

Atlas::Magetab4Atlas - fetch Atlas-relevant info from MAGETAB


=head1 SYNOPSIS
	
	use Atlas::Magetab4Atlas;
	my $magetab4atlas = Atlas::Magetab4Atlas->new( "idf_filename" => "/path/to/E-MTAB-1066.idf.txt" );

	print $magetab4atlas->get_experiment_type, "\n";
	my $atlasAssays = $magetab4atlas->get_assays;

	foreach my $assay (@{ $atlasAssays }) {
		
		print "Assay name: ", $assay->get_name, "\n";
		print "\tFactors:\n";
		my $factors = $atlasAssay->get_factors;
		foreach my $factorType (keys %{ $factors }) {
			print "\t\t$factorType -  ", ( keys %{ $factors->{ $factorType } } )[ 0 ], "\n";
		}
	}


=head1 DESCRIPTION

This package parses MAGETAB documents and collects information relevant to the
Expression Atlas. This consists of assay names, factor types and their values,
organism, technology type (hybridization or sequencing assay), array design(s)
for microarray data, European Nucleotide Archive (ENA) run accession numbers
for RNA-seq data. A Atlas::Magetab4Atlas object contains an array of Atlas::Assay
objects which store this data for each assay in the experiment.

=cut

package Atlas::Magetab4Atlas;

# Use Moose and MooseX::FollowPBP for object-oriented stuff. "FollowPBP" =
# "follow Perl best practice" -- enables automatic creation of methods get_*
# and set_* for attributes.
use Moose;
use MooseX::FollowPBP;
use File::Basename;
use Log::Log4perl;

use Bio::MAGETAB::Util::Reader;
use Atlas::AtlasAssayFactory;

=head1 ATTRIBUTES

=over 2

=item idf_filename (required)

The path to the IDF file of the experiment. The SDRF file should be present
in the same directory as the IDF.
=cut
has 'idf_filename' => (
	is => 'rw', 
	isa => 'Str',
	predicate => 'has_idf_filename',
	required => 1,
);

=item experiment_type

This is one of "one-colour array", "two-colour array", or "RNA-seq" and is
set during MAGETAB parsing. Currently RNA-seq and microarray data in the
same experiment is not supported.
=cut
has 'experiment_type' => ( 
	is => 'rw', 
	isa => 'Str',
	predicate => 'has_experiment_type',
); 

=item assays

This is a reference to an array of Atlas::Assay objects.
=cut
has 'assays' => (
	is => 'rw',
	isa => 'ArrayRef[ Atlas::Assay ]', 
	default => sub { [] },
	predicate => 'has_assays',
);

=item experiment_accession

Accession of the experiment (e.g. E-MTAB-1733)
=cut
has 'experiment_accession' => (
	is => 'rw',
	isa => 'Str',
	predicate => 'has_experiment_accession',
);

=item platforms_to_assays

Hashref mapping platforms ("rnaseq" or array design(s)) to arrays of
Atlas::Assay objects.
=cut
has 'platforms_to_assays' => (
	is => 'rw',
	isa => 'HashRef[ ArrayRef[ Atlas::Assay ] ]',
	lazy => 1,
	builder => '_build_platforms_to_assays',
	required => 1,
);

=item strict

Boolean -- whether to use strict Atlas::AtlasAssayFactory or not.

=cut

has 'strict' => (
    is => 'rw',
    isa => 'Bool',
    default => 1
);

=back

=cut

my $logger = Log::Log4perl::get_logger;

=head1 METHODS

Each attribute has accessor (get_*), mutator (set_*), and predicate (has_*) methods.

=over 2

=item new

Instantiate a new Atlas::Magetab4Atlas object. This method parses the MAGETAB
documents corresponding to the supplied IDF filename and calls other methods to
extract and store Atlas-relevant information.
=cut
sub BUILD {
	
    my $self = shift;
	
	my $idf_filename = $self->get_idf_filename;
	
    (my $experimentAccession = basename($idf_filename)) =~ s/(E-\w{4}-\d+).*/$1/;
	
    $self->set_experiment_accession($experimentAccession) ;

	# Create a reader to parse the MAGE-TAB docs. This requires IDF filename. We
	# also set the "relaxed_parser" and "ignore_datafiles" options because we
	# assume that all checks on MAGE-TAB validity and data files will have been
	# carried out previously and everything is in order by the time the MAGE-TAB
	# reaches Atlas.
	my $reader = Bio::MAGETAB::Util::Reader->new({
			idf => $idf_filename,
			relaxed_parser => 1,
			ignore_datafiles => 1,
		}
    );

	my $magetab = $reader->parse;

	$self->add_experiment_type($magetab);

    # Amend the experiment types for one- or two-colour microarray data.
	if($self->get_experiment_type eq "microarray") {
		$self->check_labels($magetab);
	}
    
    # Create the Atlas::Assay objects for this MAGE-TAB and add them to the
    # object.
	$self->add_assays( $magetab );
}

# Get the experiment type and add it to the object. Dies if mixture of RNA-seq
# and microarray.

sub add_experiment_type {
	
    my ($self, $magetab) = @_;

	#An array of AEExperimentType terms that are allowed in Atlas.
	my @allowedAEExperimentTypes = (
        "antigen profiling",
        "proteomic profiling by mass spectrometer",
		"transcription profiling by array",
		"microRNA profiling by array",
		"RNA-seq of coding RNA",
		"RNA-seq of non coding RNA",
		"RNA-seq of coding RNA from single cells",
		"RNA-seq of non coding RNA from single cells"
	);

	# Extract the experiment ID
 	my $exptAcc = $self->get_experiment_accession;	

	# Reference to hash for the experiment type.
	# There could be more than one, e.g. RNA-seq and microarray in the same
	# experiment. For now we will die if we see more than one type in an
	# experiment.
	# The hash will have a key for whichever experiment type(s) it finds, either
	# "microarray" or "RNA-seq". The value will be 1 if the type was found, e.g.:
	# 	$experimentTypes->{ "microarray" } = 1
	my $experimentTypes = {};

	# Get the investigations from this experiment. The
	# investigation stores the information from the IDF.
	my @investigations = $magetab->get_investigations;

	# Go through investigations. We assume there's only one in the magetab
	# container.
	foreach my $investigation ( @investigations ) {
	
        # Get the comments -- this is where the experiment type is stored.
		my @investigationComments = $investigation->get_comments;

		# Go through each comment.
		foreach my $comment (@investigationComments) {
		
            # Find the AEExperimentType one.
			if($comment->get_name() eq "AEExperimentType") {
				
                # Make sure this AEExperimentType is in our list of allowed ones,
				# die if not.
				unless(grep $_ eq $comment->get_value(), @allowedAEExperimentTypes) {
					
                    my $allowedAEExperimentTypes = join "\n\t\t", @allowedAEExperimentTypes;
					
                    $logger->logdie( 
                        "Unknown AEExperimentType comment found in $exptAcc IDF: ", 
                        $comment->get_value, 
                        "\n\tAllowed types are:\n\t\t$allowedAEExperimentTypes" 
                    );
				}
				
				if( $comment->get_value =~ /by array/ ) { 
                    $experimentTypes->{ "microarray" } = 1; 
                }
				elsif( $comment->get_value =~ /RNA-seq/ ) { 
                    $experimentTypes->{ "RNA-seq" } = 1; 
                }
                elsif( $comment->get_value =~ /proteomic/ || $comment->get_value =~ /antigen profiling/ ) { 
                    $experimentTypes->{ "proteomics" } = 1; 
                }
                else {
                    $logger->warn( 
                        "Setting experiment type to ", 
                        $comment->get_value, 
                        ", this may cause problems later on." 
                    );
                }
			}
		}
	}

	# Check what we got from the AEExperimentType comment(s). Die if there's both rnaseq and microarray.
	if(keys %{ $experimentTypes } > 1) {
		$logger->logdie( 
            "$exptAcc has conflicting experiment types, don't know what to do." 
        );
	}
	
	# Set experiment type in object.
	$self->set_experiment_type((keys %{ $experimentTypes })[0]);
}

# Check the labels for microarray data, so we can remember if it's one- or
# two-colour. This information overwrites the experiment_type attribute of the
# Atlas::Magetab4Atlas object.

sub check_labels {
	my ($self, $magetab) = @_;

    # Extract the experiment ID
	my $exptAcc = $self->get_experiment_accession;

	# Check we have some LabeledExtracts -- if not we can't tell if this is one- or two-colour.
	unless($magetab->has_labeledExtracts) { 
        $logger->logdie( "No LabeledExtracts found in $exptAcc! Can't tell if this is a one- or two-colour experiment." ); 
    }
	
	# Get the LabeledExtracts.
	my @labeledExtracts = $magetab->get_labeledExtracts;
	
	# Empty array to put the labels we find into.
	my @labels = ();
	
    # Go through each LabeledExtract.
	foreach my $labeledExtract (@labeledExtracts) {
	
        # Get the label for this LabeledExtract.
		my $label = $labeledExtract->get_label;
		
		# Check if the label's value has already been seen, add it to the
		# @labels array if not.
		unless(grep $_ eq $label->get_value, @labels) {
			push @labels, $label->get_value;
		}
	}
	
	# Join the labels we've found.
	my $labelString = join ", ", @labels;

	# If there's one label, it's one-colour data.
	if(@labels == 1) { 
	
        # Amend experiment_type attribute.
		$self->set_experiment_type( "one-colour array" );
	}
	# If there are two labels, it's two-colour data.
	elsif(@labels == 2) {
		
        # Amend value in $experimentTypes.
		$self->set_experiment_type( "two-colour array" );
	}
	# Otherwise, we have more than two labels and for now we are not supporting
	# that case. This might be due to (a) one-colour and two-colour arrays in
	# the same experiment, or (b) a three-colour array (are more colours possible?).
	else {
		# Die and show what labels were found.
		$logger->logdie( 
            "Too many labels found in $exptAcc! Can only handle one-colour OR two-colour data.\n\tLabels found in this experiment: $labelString" 
        );
	}
}

# Create an Atlas::Assay object(s) for every assay and add them to the
# Atlas::Magetab4Atlas object in an array.

sub add_assays {
	my ($self, $magetab) = @_;
	
    # Create a new Atlas::AtlasAssayFactory object in strict mode.
    my $atlasAssayFactory = Atlas::AtlasAssayFactory->new(
        strict => $self->get_strict
    );

	# Reference to empty array to put Atlas::Assay objects in.
	my $atlasAssays = [];

	# Get all the assay nodes in this experiment.
	my @assayNodes = $magetab->get_assays;

	# Go through each one.
	foreach my $assayNode ( @assayNodes ) {

        my $thisNodeAtlasAssays = $atlasAssayFactory->create_atlas_assays( $assayNode );
	
        # Add the new object(s) to the array, if any.
        if( $thisNodeAtlasAssays ) {
            push @{ $atlasAssays }, @{ $thisNodeAtlasAssays };
        }
        else {
            $logger->warn(
                "No Atlas::Assay objects were created for assay ",
                $assayNode->get_name
            );
        }
	} # end foreach assayNode
    
    # If we got any assays...
    if( @{ $atlasAssays } ) {
        # Add the array of Atlas::Assay objects to the Atlas::Magetab4Atlas object.
        $self->set_assays( $atlasAssays );
    }
    # Otherwise, die as we can't do anything without any assays.
    else {
        $logger->logdie(
            "No Atlas::Assay objects were created. Cannot continue."
        );
    }
}

# Create hash of platforms mapping to arrays of assays.
# Platforms are "rnaseq" or the array design accession.

sub _build_platforms_to_assays {
	
    my ($self) = shift;

	my $platformsToAssays = {};

	foreach my $assay ( @{ $self->get_assays } ) {
		
        if( $assay->has_array_design ) {
			
            my $arrayDesign = $assay->get_array_design;

			$platformsToAssays = _add_assay_by_platform( $assay, $arrayDesign, $platformsToAssays );

		} else {
			
            $platformsToAssays = _add_assay_by_platform( $assay, "rnaseq", $platformsToAssays );
		}
	}

	sub _add_assay_by_platform {

		my ( $assay, $platform, $platformsToAssays ) = @_;

		if( $platformsToAssays->{ $platform } ) {
			push @{ $platformsToAssays->{ $platform } }, $assay;
		} else {
			$platformsToAssays->{ $platform } = [ $assay ];
		}
		return $platformsToAssays;
	}

	return $platformsToAssays;
}

1;

=back

=head1 AUTHOR

Expression Atlas team <arrayexpress-atlas@ebi.ac.uk>
=cut
