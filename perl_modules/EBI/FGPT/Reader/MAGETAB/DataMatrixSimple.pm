#!/usr/bin/env perl
#
# EBI/FGPT/Reader/MAGETAB/DataMatrixSimple.pm
# 
# Anna Farne 2012 ArrayExpress team, EBI
#
# $Id$
#

=pod

=head1 NAME

EBI::FGPT::Reader::MAGETAB::DataMatrixSimple

=head1 DESCRIPTION

A custom Bio::MAGETAB::Util::Reader::DataMatrix which does not create Bio::MAGETAB
objects for every line of the matrix, but collects errors about missing design 
element REF values

=cut

package EBI::FGPT::Reader::MAGETAB::DataMatrixSimple;

use Moose;
use MooseX::FollowPBP;

use 5.008008;

use Carp;
use English qw( -no_match_vars );
use List::Util qw(first);
use Data::Dumper;

extends 'Bio::MAGETAB::Util::Reader::DataMatrix';

has 'logger'        => (is => 'rw', isa => 'Log::Log4perl::Logger', required => 1);

# Stripping whitespace from input accounted for almost half the run time 
# of the magetab parse in typical experiment with 1 matrix
# I think for the purposes of validation we can skip this for the matrix
override 'strip_whitespace' => sub{
	my ($self, $input) = @_;
	return $input;
};

sub parse{
	
	my ( $self ) = @_;

    # Find or create the target DataMatrix object.
    my $data_matrix;
    unless ( $data_matrix = $self->get_magetab_object() ) {

        # This is typically a stand-alone DM. FIXME consider type as
        # another attribute or argument to this reader object?
        my $type = $self->get_builder()->find_or_create_controlled_term({
            category => 'DataType',    # FIXME hard-coded.
            value    => 'unknown',
        });
        $data_matrix = $self->get_builder()->find_or_create_data_matrix({
            uri               => $self->get_uri(),
            dataType          => $type,
        });
        $self->set_magetab_object( $data_matrix );
    }

    my $ad = $self->_determine_array_design( $data_matrix );
    $self->_set_array_design( $ad ) if $ad;

    # This has to be set for Text::CSV_XS.
    local $/ = $self->get_eol_char();

    my $qts;
    my $nodes;
    my $row_identifier_type;
    my $de_authority = q{};
    my $de_namespace = q{};

    my $row_number = 1;

    FILE_LINE:
    while ( my $larry = $self->getline() ) {

        # Skip empty lines, comments.
        next FILE_LINE if $self->can_ignore( $larry );

        # Strip surrounding whitespace from each element.
        $larry = $self->strip_whitespace( $larry );

        if ( $row_number == 1 ) {
            $nodes = $self->_parse_node_heading( $larry );
        }
        elsif ( $row_number == 2 ) {
            ( $qts, $row_identifier_type, $de_namespace )
                = $self->_parse_qt_heading( $larry );

            # If namespace isn't explicitly given in the matrix
            # header, set it to the name of the enclosing array
            # design.
            if ( my $ad = $self->_get_array_design() ) {
                $de_authority = $ad->get_authority();
                unless ( defined $de_namespace ) {
                    $de_namespace = $ad->get_name();
                }
            }
        }
        else {
            # Instead of creating the matrix row object we just report
            # missing design element REF values
            unless ($larry->[0]){
            	$self->get_logger->error("$row_identifier_type missing on row $row_number of ",$self->get_uri);
            }
        }

        $row_number++;
    }

    # Confirm we've read to the end of the file.
    $self->confirm_full_parse();

    # Sanity check.
    unless ( scalar @{ $qts } == scalar @{ $nodes } ) {
        croak(qq{Error: Mismatch in number of nodes and qt column headings.\n});
    }

    # Create the MatrixColumn objects.
    my @matrix_columns;
    for ( my $col_number = 0; $col_number < scalar @{ $qts }; $col_number++ ) {
        push @matrix_columns, $self->get_builder()->find_or_create_matrix_column({
            columnNumber     => $col_number,
            quantitationType => $qts->[ $col_number ],
            referencedNodes  => $nodes->[ $col_number ],
            data_matrix      => $data_matrix,
        });

    }

    $data_matrix->set_rowIdentifierType( $row_identifier_type );	
    $data_matrix->set_matrixColumns( \@matrix_columns );

    $self->get_builder()->update( $data_matrix );

    return $data_matrix;
}

1;
