#!/usr/bin/env perl
#
# Module to parse Affymetrix data files.
#
# Tim Rayner 2005, ArrayExpress team, European Bioinformatics Institute
#
# $Id: Affymetrix.pm 1857 2007-12-16 19:53:50Z tfrayner $
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
	    <td class="pagetitle">Module detail: Affymetrix.pm</td>
	  </tr>
      </table>
    </div>

=end html

=head1 NAME

ArrayExpress::Datafile::Affymetrix - a factory class for generating
Affymetrix data file parsing objects.

=head1 SYNOPSIS

 use ArrayExpress::Datafile::Affymetrix;

 my $fac = ArrayExpress::Datafile::Affymetrix->new();

 my $cel = $fac->make_parser( 'Data1.CEL' );

 $cel->parse();

 $cel->export($output_filehandle);

=head1 DESCRIPTION

This module is a factory class used in to create data file parsers for
Affymetrix file formats. CEL, CHP and EXP formats are supported, with
limited CDF parsing. Both old (GDAC) and new (GCOS/XDA) file formats
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

package ArrayExpress::Datafile::Affymetrix;

use strict;
use warnings;

use Class::Std;
use Carp;
use Scalar::Util qw(openhandle);

use ArrayExpress::Datafile::Binary qw(
    get_integer
);

sub make_parser {

    my ( $self, $file ) = @_;

    unless ( -r $file ) {
	croak(qq{Error: Cannot read input file "$file".});
    }

    my %dispatch = (
	qr/\.CEL \z/ixms => 'ArrayExpress::Datafile::Affymetrix::CELFactory',
	qr/\.CDF \z/ixms => 'ArrayExpress::Datafile::Affymetrix::CDFFactory',
	qr/\.CHP \z/ixms => 'ArrayExpress::Datafile::Affymetrix::CHPFactory',
	qr/\.EXP \z/ixms => 'ArrayExpress::Datafile::Affymetrix::EXPFactory',
    );

    my $class;
    DISPATCH:
    while ( my ( $ext, $target ) = each %dispatch ) {
	if ( $file =~ $ext ) {
	    $class = $target;
	    last DISPATCH;
	}
    }
    unless ( $class ) {
	croak("Error: Unrecognized filename extension: $file");
    }

    # Hand off to the appropriate subclass. Allow Perl::Critic to ignore this line:
    ## no critic ProhibitStringyEval
    eval "require $class";
    ## use critic ProhibitStringyEval
    if ( $@ ) {
	confess("Error loading subclass $class: $@");
    }
    my $fac = $class->new();

    return $fac->make_parser($file);
}

sub read_magic : RESTRICTED {

    my ( $self, $input ) = @_;

    my $fh;
    if ( openhandle($input) ) {
        $fh = $input;
    }
    else {
        $fh = IO::File->new( $input, '<' )
            or croak("Unable to open CDF file $input : $!\n");
    }

    binmode($fh);
    sysseek( $fh, 0, 0 )
        or croak(
        qq{Error rewinding filehandle for "magic" integer check : $!\n});

    my $magic = get_integer($fh);

    return wantarray ? ( $magic, $fh ) : $magic;
}

1;
