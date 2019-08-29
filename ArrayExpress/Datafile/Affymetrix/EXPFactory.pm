#!/usr/bin/env perl
#
# Module to parse Affymetrix binary data files.
#
# Tim Rayner 2004, ArrayExpress team, European Bioinformatics Institute
#
# $Id: EXPFactory.pm 1808 2007-11-01 18:55:34Z tfrayner $
#

=pod

=begin html

    <div><a name="top"></a>
      <table class="layout">
	  <tr>
	    <td class="whitetitle" width="100">
              <a href="../../../index.html">
                <img src="../../T2M_logo.png"
                     border="0" height="50" alt="Tab2MAGE logo"></td>
              </a>
	    <td class="pagetitle">Module detail: EXPFactory.pm</td>
	  </tr>
      </table>
    </div>

=end html

=head1 NAME

ArrayExpress::Datafile::Affymetrix::EXPFactory - a factory class for generating
Affymetrix EXP file parsing objects.

=head1 SYNOPSIS

 use ArrayExpress::Datafile::Affymetrix::EXPFactory;

 my $fac = ArrayExpress::Datafile::Affymetrix::EXPFactory->new();

 my $exp = $fac->make_parser( 'Data1.EXP' );

 $exp->parse();

 $exp->export($output_filehandle);

=head1 DESCRIPTION

This module is a factory class used in to create data file parsers for
Affymetrix EXP files.

=head1 METHODS

=over 2

=item new()

The class constructor.

=item make_parser($file)

This method takes a filename argument and returns a parser object that
can then be used to process the data file and return interesting
values.

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

package ArrayExpress::Datafile::Affymetrix::EXPFactory;
use base 'ArrayExpress::Datafile::Affymetrix';

use strict;
use warnings;

use Class::Std;

sub make_parser {

    my ( $self, $input ) = @_;

    # There's only one EXP file type, making this extremely simple.
    require ArrayExpress::Datafile::Affymetrix::EXP;
    return ArrayExpress::Datafile::Affymetrix::EXP->new({
	input => $input,
    });
}

1;
