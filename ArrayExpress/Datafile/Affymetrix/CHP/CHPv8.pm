#!/usr/bin/env perl
#
# Module to parse Affymetrix binary data files.
#
# Tim Rayner 2004, ArrayExpress team, European Bioinformatics Institute
#
# $Id: CHPv8.pm 1906 2008-01-23 10:05:42Z tfrayner $
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
	    <td class="pagetitle">Module detail: CHPv8.pm</td>
	  </tr>
      </table>
    </div>

=end html

=head1 NAME

ArrayExpress::Datafile::Affymetrix::CHP::CHPv8 - CHPv8 data file
parsing.

=head1 SYNOPSIS

 use ArrayExpress::Datafile::Affymetrix::CHP::CHPv8;

 my $chp = ArrayExpress::Datafile::Affymetrix::CHP::CHPv8->new({
     input => 'mydata.CHP',
 });

 $chp->parse_header();

=head1 DESCRIPTION

This module implements parsing and export of data from Affymetrix GDAC
CHP (v8) files. Note that only the data file header can be parsed
using this module.

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

package ArrayExpress::Datafile::Affymetrix::CHP::CHPv8;
use base 'ArrayExpress::Datafile::Affymetrix::CHP::GDAC_CHP';

use strict;
use warnings;
use Readonly;
use Carp;
use Class::Std;

###########################
# CHPv8-specific methods #
###########################

sub parse_chp : RESTRICTED {

    # N.B. CHP versions 8 and 12 are very similar in many respects,
    # but the v8 float format defeated me, which is why version 8 gets
    # such short shrift.

    # We can't parse CHPv8 files fully. See the GDAC_CHP superclass
    # for CHPv8 header parsing.

    my ( $self, $fh ) = @_;

    # Caller has to trap this in an eval. We really don't like these
    # files.
    croak("Error: CHP file version 8 not fully supported.\n");
}

1;
