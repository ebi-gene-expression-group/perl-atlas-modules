#!/usr/bin/env perl
#
# Module to parse Affymetrix binary data files.
#
# Tim Rayner 2004, ArrayExpress team, European Bioinformatics Institute
#
# $Id: XDA_CDF.pm 2216 2009-04-30 08:48:48Z tfrayner $
#

=pod

=begin html

    <div><a name="top"></a>
      <table class="layout">
	  <tr>
	    <td class="whitetitle" width="100">
              <a href="../../../../index.html">
                <img src="../../../T2M_logo.png"
                     border="0" height="50" alt="Tab2MAGE logo"></td>
              </a>
	    <td class="pagetitle">Module detail: XDA_CDF.pm</td>
	  </tr>
      </table>
    </div>

=end html

=head1 NAME

ArrayExpress::Datafile::Affymetrix::CDF::XDA_CDF.pm - XDA CDF data
file parsing.

=head1 SYNOPSIS

 use ArrayExpress::Datafile::Affymetrix::CDF::XDA_CDF;

 my $cdf = ArrayExpress::Datafile::Affymetrix::CDF::XDA_CDF->new({
     input => 'HG-U133A.cdf',
 });
 $cdf->parse();

=head1 DESCRIPTION

This module implements parsing and export of data from Affymetrix XDA
CDF files.

Please see L<ArrayExpress::Datafile::Affymetrix::Parser> for
methods common to all the Affymetrix parser classes.

=head1 METHODS

Most parsing methods and accessors are implemented in the
superclasses. See L<ArrayExpress::Datafile::Affymetrix::CDF::GDAC_CDF> for
information.

=head1 AUTHOR

Tim Rayner (rayner@ebi.ac.uk), ArrayExpress team, EBI, 2005.

Acknowledgements go to the ArrayExpress curation team for feature
requests, bug reports and other valuable comments.

=begin html

<hr>
<a href="http://sourceforge.net">
  <img src="http://sourceforge.net/sflogo.php?group_id=120325&amp;type=2" 
       width="125" 
       height="37" 
       border="0" 
       alt="SourceForge.net Logo" />
</a>

=end html

=cut

package ArrayExpress::Datafile::Affymetrix::CDF::XDA_CDF;
use base 'ArrayExpress::Datafile::Affymetrix::CDF';

use strict;
use warnings;

use Carp;
use Scalar::Util qw(openhandle);
use IO::File;
use Class::Std;

use EBI::FGPT::Common qw(
    round
);

use ArrayExpress::Datafile::Binary qw(
    get_integer
    get_DWORD
    get_unsigned_short
    get_unsigned_char
    get_signed_char
    get_float
    get_ascii
);

sub START {
    my ( $self, $id, $args ) = @_;

    $self->set_required_magic(67);

    return;
}

############################
# XDA CDF specific methods #
############################

sub parse_cdf : RESTRICTED {

    # NB quite a lot of stuff is being discarded here. This relieves
    # memory overhead, but we may want to add some things back at some
    # stage.

    my ( $self, $fh ) = @_;

    openhandle($fh) or confess( 'Bad parameters passed to method' );

    binmode($fh);
    sysseek( $fh, 0, 0 )
        or croak("Error rewinding filehandle for input: $!\n");

    my $magic = get_integer($fh);
    unless ( $magic == 67 ) {
        croak("Error: Unrecognized CDF type: $magic\n");
    }

    # Header parsing
    $self->set_version( get_integer($fh) );
    $self->set_num_columns( get_unsigned_short($fh) );
    $self->set_num_rows( get_unsigned_short($fh) );
    $self->set_num_cells( get_integer($fh) );    # cells == probesets
    $self->set_num_qc_cells( get_integer($fh) );

    # header reseq_ref_seq
    my $reseq_ref_seq = get_ascii( $fh, get_integer($fh) );

    # Initialize $data. Points to an array of hashes
    my $data;
    if ( my $num_cells = $self->get_num_cells() ) {
        $data->[ $num_cells - 1 ] = {};
    }

    # Initialize $qc_data. Points to an array of hashes. FIXME discarded
    # at the moment.
    my $qc_data;
    if ( my $num_qc = $self->get_num_qc_cells() ) {
        $qc_data->[ $num_qc - 1 ] = {};
    }

    # Get probeset names. This is what we're mainly interested in here.
    foreach my $cell (@$data) {
        $cell->{name} = get_ascii( $fh, 64 );

        # Remove trailing zeroes (non-ASCII data).
        $cell->{name} =~ s/\x00* \z//xms;
    }

    foreach my $qc_cell (@$qc_data) {
        get_integer($fh);
    }    # qc_cell filepos
    foreach my $cell (@$data) { get_integer($fh) }    # cell filepos

    foreach my $qc_cell (@$qc_data) {
        get_unsigned_short($fh);                      # qc_cell type
        my $num_probes = get_integer($fh);            # qc_cell num_probes

        for ( 0 .. ( $num_probes - 1 ) ) { # We just discard all this for now.

            get_unsigned_short($fh);       # probe x
            get_unsigned_short($fh);       # probe y
            get_unsigned_char($fh);        # probe length

            # NB docs say this is unsigned but they appear to be wrong:
            get_signed_char($fh);          # probe match_flag
            get_unsigned_char($fh);        # probe bkd_flag

        }
    }

    foreach my $cell (@$data) {

        $cell->{type} = get_unsigned_short($fh);           # cell type
        get_unsigned_char($fh);            # cell direction
        get_integer($fh);                  # cell num_atoms
        my $num_blocks = get_integer($fh);
        $cell->{num_blocks} = $num_blocks;
        get_integer($fh);                  # cell num_cells
        $cell->{cell_no} = get_integer($fh); # corresponds to probe set number
        get_unsigned_char($fh);              # cell cells_per_atom

        foreach my $block ( @{ $cell->{block} }[ 0 .. ( $num_blocks - 1 ) ] )
        {

            get_integer($fh);                # block num_atoms
            my $num_cells = get_integer($fh);
            get_unsigned_char($fh);          # block cells_per_atom
            get_unsigned_char($fh);          # block direction
            get_integer($fh);                # block atom1_pos
            get_integer($fh);                # block atom2_pos
            $block->{name} = get_ascii( $fh, 64 );
            # Remove trailing zeroes (non-ASCII data).
            $block->{name} =~ s/\x00* \z//xms;
            
            my @cells;
            foreach ( 0 .. ( $num_cells - 1 ) ) {
                my %feature;
                $feature{atom} = get_integer($fh);            # cell atom_no
                $feature{x} = get_unsigned_short($fh);     # cell x
                $feature{y} = get_unsigned_short($fh);     # cell y

                # Relative to seq for reseq cells:
                $feature{pos} = get_integer($fh);            # cell index_pos
                $feature{pbase} = get_ascii( $fh, 1 );         # cell probe_base
                $feature{tbase} = get_ascii( $fh, 1 );         # cell target_base
                
                push @cells, \%feature;

            }
            $block->{coords} = \@cells;
        }
    }

    $self->set_data($data);

    return;
}

1;
