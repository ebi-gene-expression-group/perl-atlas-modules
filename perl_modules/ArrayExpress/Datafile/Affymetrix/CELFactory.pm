#!/usr/bin/env perl
#
# Module to parse Affymetrix binary data files.
#
# Tim Rayner 2004, ArrayExpress team, European Bioinformatics Institute
#
# $Id: CELFactory.pm 1984 2008-03-03 17:47:18Z tfrayner $
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
	    <td class="pagetitle">Module detail: CELFactory.pm</td>
	  </tr>
      </table>
    </div>

=end html

=head1 NAME

ArrayExpress::Datafile::Affymetrix::CELFactory - a factory class for generating
Affymetrix CEL file parsing objects.

=head1 SYNOPSIS

 use ArrayExpress::Datafile::Affymetrix::CELFactory;

 my $fac = ArrayExpress::Datafile::Affymetrix::CELFactory->new();

 my $cel = $fac->make_parser( 'Data1.CEL' );

 $cel->parse();

 $cel->export($output_filehandle);

=head1 DESCRIPTION

This module is a factory class used in to create data file parsers for
Affymetrix CEL files. Both old (GDAC) and new (GCOS/XDA) file formats
can be parsed.

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

package ArrayExpress::Datafile::Affymetrix::CELFactory;
use base 'ArrayExpress::Datafile::Affymetrix';

use strict;
use warnings;

use Carp;
use IO::File;
use Class::Std;

sub make_parser {

    my ( $self, $input ) = @_;

    my ( $magic, $fh ) = $self->read_magic( $input );

    # FIXME it would be good to derive this automatically from what's
    # available.
    my %dispatch = (
	1279607643 => 'ArrayExpress::Datafile::Affymetrix::CEL::CELv3',
	64         => 'ArrayExpress::Datafile::Affymetrix::CEL::CELv4',
	315        => 'ArrayExpress::Datafile::Affymetrix::Calvin::CEL',
    );

    my $class;
    unless ( $class = $dispatch{ $magic } ) {
	croak("Error: Unrecognized CEL file type: $magic");
    }

    # Return the appropriate parser object. Allow Perl::Critic to ignore this line:
    ## no critic ProhibitStringyEval
    eval "require $class";
    ## use critic ProhibitStringyEval
    if ( $@ ) {
	confess("Error loading subclass $class: $@");
    }
    return $class->new({
	filehandle => $fh,
    });
}

1;
