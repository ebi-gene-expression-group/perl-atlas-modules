#!/usr/bin/env perl
#
=pod

=head1 NAME

Atlas::Assay - store basic information about an Atlas assay. This should
generally be used via Atlas::AtlasAssayFactory.pm rather than directly.

=head1 SYNOPSIS

use Atlas::Assay;

my $assay = Atlas::Assay->new( name => $atlasAssayName, characteristics => $characteristicsHashRef );

=head1 DESCRIPTION

An Atlas::Assay object stores basic information from the MAGE-TAB about an
assay. This is the Atlas assay name (run accession for sequencing, assay name
plus label for 2-colour array), the characteristics and factors, and the array
design for microarray assays.

=cut

package Atlas::Assay;

use Moose;
use MooseX::FollowPBP;
use Moose::Util::TypeConstraints;
use Log::Log4perl;

my $logger = Log::Log4perl::get_logger;

=head1 ATTRIBUTES

=over 2

=item name

String with assay name. This is the same as the assay name from MAGETAB for
one-colour array assays. For two-colour array assays it is the MAGE-TAB assay
name with the label name appended e.g. "Assay1.Cy3". For RNA-seq data it is the
ENA run accession where available. If ENA run is not available the RUN_NAME
comment should be used. If this is also not available the Scan Name will be
used.

=cut

has 'name' => (
    is => 'rw',
    isa => 'Str',
    required => 1
);

=item characteristics

Hashref with characteristics for this assay. Keys are characteristic types
pointing to hashrefs of values e.g.
    $characteristics->{ "organism" }->{ "Oryza sativa" } = 1;
This structure is used in case a characteristic type has more than one value
(not currently allowed in Atlas).

=cut

has 'characteristics' => (
    is => 'rw',
    isa => 'HashRef',
    required => 1
);

=item factors

Hashref with factors for this assay. Keys are factor types
pointing to hashrefs of values e.g.
    $factors->{ "organism" }->{ "Oryza sativa" } = 1;
This structure is used in case a factor type has more than one value
(not currently allowed in Atlas).

=cut

has 'factors' => (
    is => 'rw',
    isa => 'HashRef',
    predicate => 'has_factors'
);

=item array_design

String with the ArrayExpress array design accession for a microarray assay.

=cut

has 'array_design' => (
    is => 'rw',
    isa => 'Str',
    predicate => 'has_array_design'
);

=item technology_type

String with the technology type of the assay.

=cut

has 'technology_type' => (
    is => 'rw',
    isa => 'Str',
    predicate => 'has_technology_type'
);

=item organism

The organism the biological material was taken from.

=cut

has 'organism' => (
    is => 'rw',
    isa => 'Str',
    predicate => 'has_organism'
);

=item technical_replicate_group

The ID of the technical replicate group the assay belongs to, if any.

=cut

has 'technical_replicate_group' => (
    is => 'rw',
    isa => 'Str',
    predicate => 'has_technical_replicate_group'
);

=item library_layout

For an RNA-seq assay, whether the sequencing library was paired-end or
single-end.

=cut

has 'library_layout' => (
    is => 'rw',
    isa => enum( [ qw/
        single
        paired
    /]),
    predicate => 'has_library_layout'
);

=item library_strand

For an RNA-seq assay, if the library was strand-specific, which strand of cDNA
was used to create the library? This is used in the arguments for the TopHat mapper.

=cut

has 'library_strand' => (
    is => 'rw',
    isa => enum( [ 
        'first strand',
        'second strand',
    ]),
    predicate => 'has_library_strand'
);

=item fastq_file_set

For an RNA-seq assay, the URIs of the FASTQ files in ENA. These are in the
FASTQ_URI comment of the Scan node. If these are not available, these are the
submitted file names instead.

=cut

has 'fastq_file_set' => (
    is => 'rw',
    isa => 'ArrayRef',
    predicate => 'has_fastq_file_set'
);

=item array_data_file

For a microarray assay, the filename of the raw data file. Only one per assay
is currently allowed.

=cut

has 'array_data_file' => (
    is => 'rw',
    isa => 'Str',
    predicate => 'has_array_data_file'
);


=back

=head1 METHODS

Each tribute has accessor (get_*), mutator (set_*), and predicate (has_*) methods.

=over 2

=item new

Instantiates a new Atlas::Assay object.

=back

=head1 AUTHOR

Expression Atlas team <arrayexpress-atlas@ebi.ac.uk>

=cut

1;
