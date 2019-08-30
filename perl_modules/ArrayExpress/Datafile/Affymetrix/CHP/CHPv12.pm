#!/usr/bin/env perl
#
# Module to parse Affymetrix binary data files.
#
# Tim Rayner 2004, ArrayExpress team, European Bioinformatics Institute
#
# $Id: CHPv12.pm 1906 2008-01-23 10:05:42Z tfrayner $
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
	    <td class="pagetitle">Module detail: CHPv12.pm</td>
	  </tr>
      </table>
    </div>

=end html

=head1 NAME

ArrayExpress::Datafile::Affymetrix::CHP::CHPv12 - CHPv12 data file
parsing.

=head1 SYNOPSIS

 use ArrayExpress::Datafile::Affymetrix::CHP::CHPv12;

 my $chp = ArrayExpress::Datafile::Affymetrix::CHP::CHPv12->new({
     input => 'mydata.CHP',
 });

 $chp->parse();

=head1 DESCRIPTION

This module implements parsing and export of data from Affymetrix GDAC
CHP (v12) files.

Please see the L<ArrayExpress::Datafile::Affymetrix::Parser>
documentation for methods common to all the Affymetrix file classes.

=head1 METHODS

Most methods are implemented in the superclass. Please see
L<ArrayExpress::Datafile::Affymetrix::CHP::GDAC_CHP> for details.

=over 2

=pod

=back

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

package ArrayExpress::Datafile::Affymetrix::CHP::CHPv12;
use base 'ArrayExpress::Datafile::Affymetrix::CHP::GDAC_CHP';

use strict;
use warnings;
use Readonly;
use Carp;
use Scalar::Util qw( openhandle );
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
    get_hexadecimal
);

###########################
# CHPv12-specific methods #
###########################

# flag to reduce method call overhead.
my $comparison_data_found;

sub parse_expression_cell : RESTRICTED {

    # NB quite a lot of stuff is being discarded here. This relieves
    # memory overhead, but we may want to add some things back at some
    # stage.

    my ( $self, $fh, $cell ) = @_;

    openhandle($fh) or confess( 'Bad parameters passed to method' );

    $cell->{'CHPPairs'}     = get_integer($fh);
    $cell->{'CHPPairsUsed'} = get_integer($fh);

    # N.B. CHP versions 8 and 12 are interchangable throughout
    # this section, but the v8 float format defeated me, which
    # is why version 8 gets such short shrift.
    for ( 1 .. 5 ) { get_integer($fh); }    # Unused

    $cell->{'CHPDetectionPvalue'} = round( get_float($fh), 5 );

    get_float($fh);    # Unused

    $cell->{'CHPSignal'}    = round( get_float($fh), 1 );
    $cell->{'CHPDetection'} = get_integer($fh);
    
    #################################################################
    # ***** N.B. *****
    #
    # Most of the rest of the parsing below is unused, but is left
    # here for reference and because removing it would really screw
    # up the main data value parsing
    #################################################################

    # Pairs section is not used
    # Initialize the sub-array
    my $pairs;
    for ( my $pair = 0; $pair < $cell->{'CHPPairs'}; $pair++ ) {
	$pairs->[$pair] = {};
    }

    foreach my $pair (@$pairs) {

	get_float($fh);      # pair background
	get_integer($fh);    # 2 = used, 0 = not # pair used
	get_integer($fh);           # pair PM_Xcoord
	get_integer($fh);           # pair PM_Ycoord
	get_float($fh);             # pair PM_intensity
	get_float($fh);             # pair PM_stdev
	get_integer($fh);           # pair PM_pixels
	get_signed_char($fh);       # pair PM_masked
	get_signed_char($fh);       # pair PM_outlier
	get_integer($fh);           # pair MM_Xcoord
	get_integer($fh);           # pair MM_Ycoord
	get_float($fh);             # pair MM_intensity
	get_float($fh);             # pair MM_stdev
	get_integer($fh);           # pair MM_pixels
	get_signed_char($fh);       # pair MM_masked
	get_signed_char($fh);       # pair MM_outlier
    }

    # This part below has now been tested.

    my $comparison_exists = get_integer($fh);

    if ($comparison_exists) {

	# set the qtd for ExpressionStat data with comparison data
	$self->set_headings( $self->get_affy_qtd_chp_comparison() )
	    unless $comparison_data_found;
	$comparison_data_found++;

	$cell->{'CHPCommonPairs'} = get_integer($fh);

	for ( 1 .. 3 ) { get_integer($fh); }    # Unused

	$cell->{'CHPChange'} = get_integer($fh);

	# This is not actually exported at the moment
	$cell->{baseline_absent} = get_signed_char($fh);

	get_signed_char($fh);    # Unused
	get_integer($fh);        # Unused
	get_integer($fh);        # Unused

	my $signal_log_ratio_high_1000
	    = get_integer($fh);    # divide by 1000 to get float value
	$cell->{'CHPSignalLogRatioHigh'}
	    = round( ( $signal_log_ratio_high_1000 / 1000 ), 1 );

	get_integer($fh);          # Unused
	get_integer($fh);          # Unused

	my $signal_log_ratio_1000
	    = get_integer($fh);    # divide by 1000 to get float value
	$cell->{'CHPSignalLogRatio'}
	    = round( ( $signal_log_ratio_1000 / 1000 ), 1 );

	get_integer($fh);      # Unused

	my $signal_log_ratio_low_1000
	    = get_integer($fh);    # divide by 1000 to get float value
	$cell->{'CHPSignalLogRatioLow'}
	    = round( ( $signal_log_ratio_low_1000 / 1000 ), 1 );
	
	$cell->{'CHPChangePvalue'} = round( get_float($fh), 5 );
	
    }

    return;
}

1;
