#!/usr/bin/env perl
#
# Module to parse Affymetrix EXP files.
#
# Tim Rayner 2004, ArrayExpress team, European Bioinformatics Institute
#
# $Id: EXP.pm 1852 2007-12-13 10:14:27Z tfrayner $
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
	    <td class="pagetitle">Module detail: CDF.pm</td>
	  </tr>
      </table>
    </div>

=end html

=head1 NAME

ArrayExpress::Datafile::Affymetrix::EXP - EXP data file parsing

=head1 SYNOPSIS

 use ArrayExpress::Datafile::Affymetrix::EXP;

 my $exp = ArrayExpress::Datafile::Affymetrix::EXP->new({
     input => 'data1.EXP',
 });
 $exp->parse();

=head1 DESCRIPTION

This module implements parsing and export of data from Affymetrix EXP files.

Please see L<ArrayExpress::Datafile::Affymetrix::Parser> for
methods common to all the Affymetrix parser classes.

=head1 METHODS

=over 2

=item export($fh)

This method takes a filehandle and prints out the EXP file in its
original format. This method is not particularly useful and is really
for testing purposes only.

=item get_chip_lot()

The lot number of the chip.

=item get_operator()

The person who performed the procedure.

=item get_protocol()

The name of the hybridization protocol used (e.g. EukGE-WS2v4).

=item get_station()

The station number.

=item get_module()

The module number.

=item get_hyb_date()

The date on which the hybridization was performed. This is returned in
the same format as in the EXP file; no sanitization is performed.

=item get_pixel_size()

Pixel size (integer).

=item get_filter()

Filter (570nm).

=item get_scan_temp()

Scan temperature.

=item get_scan_date()

The date on which the scanning was performed. This is returned in
the same format as in the EXP file; no sanitization is performed.

=item get_scanner_id()

Scanner ID.

=item get_num_scans()

Number of scans performed.

=item get_scanner_type()

Scanner type.

=item get_hyb_parameters()

A reference to an array of named hybridization parameters. Each
parameter is coded as a separate hash with a single {name => value}
pair. Typically this method is not very useful; you should probably be
using the B<parameters> or B<add_parameters> methods instead.

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

package ArrayExpress::Datafile::Affymetrix::EXP;
use base 'ArrayExpress::Datafile::Affymetrix::Parser';

use strict;
use warnings;

use English qw( -no_match_vars );
use Carp;
use Scalar::Util qw( openhandle );
use IO::File;
use Class::Std;

use EBI::FGPT::Common qw(
    check_linebreaks
);

my %chip_lot       : ATTR( :name<chip_lot>,       :default<undef> );
my %operator       : ATTR( :name<operator>,       :default<undef> );
my %protocol       : ATTR( :name<protocol>,       :default<undef> );
my %station        : ATTR( :name<station>,        :default<undef> );
my %module         : ATTR( :name<module>,         :default<undef> );
my %hyb_date       : ATTR( :name<hyb_date>,       :default<undef> );
my %pixel_size     : ATTR( :name<pixel_size>,     :default<undef> );
my %filter         : ATTR( :name<filter>,         :default<undef> );
my %scan_temp      : ATTR( :name<scan_temp>,      :default<undef> );
my %scan_date      : ATTR( :name<scan_date>,      :default<undef> );
my %scanner_id     : ATTR( :name<scanner_id>,     :default<undef> );
my %num_scans      : ATTR( :name<num_scans>,      :default<undef> );
my %scanner_type   : ATTR( :name<scanner_type>,   :default<undef> );
my %hyb_parameters : ATTR( :name<hyb_parameters>, :default<[]>    );

sub parse {

    my ( $self ) = @_;

    my $input = $self->get_input();

    my ( $fh, $linebreak );
    if ( openhandle($input) ) {
        $fh = $input;
    }
    else {
        my $counts;
        ( $counts, $linebreak ) = check_linebreaks($input);
        unless ($linebreak) {
            croak(    "Error: Unable to parse line endings in file $input: "
                    . "($counts->{unix} Unix, $counts->{dos} DOS, $counts->{mac} Mac)\n"
            );
        }
        $fh = IO::File->new( $input, '<' )
            or croak("Unable to open EXP file $input : $!\n");
    }

    # Localise our line ending variable to the scope of this subroutine.
    local $INPUT_RECORD_SEPARATOR = $linebreak;

    # Setting binmode here interferes with the linebreak processing, so
    # we don't.
    #  binmode($fh, ":crlf");
    seek( $fh, 0, 0 ) or croak("Error rewinding filehandle for input: $!\n");

    my $label = <$fh>;
    $label =~ s/[\r\n]* \z//xms;

    # Allow following whitespace - not in the Affy spec, but all too common.
    unless ( $label
        =~ m{\A Affymetrix\ GeneChip\ Experiment\ Information \s* \z}xms ) {

        # Strip out Mac line endings from the error message - they play
        # havoc with the terminal and obscure the error.
        $label =~ s/\r//g;
        croak("Error: Unrecognized EXP file format: $label\n");
    }

    my $version = <$fh>;
    $version =~ s{\A Version \t (\d+) [\r\n]*}{$1}xms;  # Just want the number
    $self->set_version($version);

    my $line = q{};

    until ( $line =~ m{\A \[Sample\ Info\]}xms ) {
        $line = <$fh>;
        $line =~ s/[\r\n]* \z//xms;
    }

    LINE:
    while ( my $line = <$fh> ) {
        $line =~ s/[\r\n]* \z//xms
            ;    # just to be sure about DOS-style line endings
        last LINE if ( $line =~ m/\A \s* \z/xms );
        my ( $parameter, $value ) = split /\t/, $line;

        SAMPLEINFO:
        {

            ( $parameter eq 'Chip Type' )
                && do { $self->set_chip_type($value); last SAMPLEINFO; };

            ( $parameter eq 'Chip Lot' )
                && do { $self->set_chip_lot($value); last SAMPLEINFO; };

            ( $parameter eq 'Operator' )
                && do { $self->set_operator($value); last SAMPLEINFO; };

        }
    }

    until ( $line =~ m{\A \[Fluidics\]}xms ) {
        $line = <$fh>;
        $line =~ s/[\r\n]* \z//xms;
    }
    my $param_count = 0;    # Hyb parameter numbering starts at zero

    LINE:
    while ( my $line = <$fh> ) {
        $line =~ s/[\r\n]* \z//xms
            ;               # just to be sure about DOS-style line endings
        last LINE if ( $line =~ m/\A \s* \z/xms );
        my ( $parameter, $value ) = split /\t/, $line;

        FLUIDICS:
        {

            ( $parameter eq 'Protocol' )
                && do { $self->set_protocol($value); last FLUIDICS; };

            ( $parameter eq 'Station' )
                && do { $self->set_station($value); last FLUIDICS; };

            ( $parameter eq 'Module' )
                && do { $self->set_module($value); last FLUIDICS; };

            ( $parameter eq 'Hybridize Date' )
                && do { $self->set_hyb_date($value); last FLUIDICS; };

            # Wash params here. We put the originals in hyb_parameters(),
            # and the mage-sanitized ones in parameters()
            my $mage_param
                = "HybridizationStep$param_count-" . $self->get_protocol();
            $self->add_parameters( { $mage_param => $value } );
            $self->add_hyb_parameters( { $parameter => $value } );
            $param_count++;
        }
    }

    until ( $line =~ m{\A \[Scanner\]}xms ) {
        $line = <$fh>;
        $line =~ s/[\r\n]* \z//xms;
    }

    LINE:
    while ( my $line = <$fh> ) {
        $line =~ s/[\r\n]* \z//xms
            ;    # just to be sure about DOS-style line endings
        last LINE if ( $line =~ m/\A \s* \z/xms );
        my ( $parameter, $value ) = split /\t/, $line;

        SCANNER:
        {

            ( $parameter eq 'Pixel Size' )
                && do { $self->set_pixel_size($value); last SCANNER; };

            ( $parameter eq 'Filter' )
                && do { $self->set_filter($value); last SCANNER; };

            ( $parameter eq 'Scan Temperature' )
                && do { $self->set_scan_temp($value); last SCANNER; };

            ( $parameter eq 'Scan Date' )
                && do { $self->set_scan_date($value); last SCANNER; };

            ( $parameter eq 'Scanner ID' )
                && do { $self->set_scanner_id($value); last SCANNER; };

            ( $parameter eq 'Number of Scans' )
                && do { $self->set_num_scans($value); last SCANNER; };

            ( $parameter eq 'Scanner Type' )
                && do { $self->set_scanner_type($value); last SCANNER; };

        }
    }

    return;
}

####################
# Accessor Methods #
####################

# The hyb_parameters accessor is a special case

sub add_hyb_parameters : PRIVATE {    # arrayref (adds to old params)

    my ( $self, $params ) = @_;
    
    ref $params eq 'HASH'
	or confess( 'Bad parameters passed to method' );
    push( @{ $hyb_parameters{ident $self} }, $params );

    return;
}

sub export {    # This is really only for checking purposes

    my ( $self, $fh ) = @_;

    openhandle($fh) or confess( 'Bad parameters passed to method' );

    print $fh (
        "Affymetrix GeneChip Experiment Information\n",
        "Version\t", $self->get_version, "\n",
        "\n",

        "[Sample Info]\n",
        "Chip Type\t", $self->get_chip_type, "\n",
        "Chip Lot\t",  $self->get_chip_lot,  "\n",
        "Operator\t",  $self->get_operator,  "\n"
    );
    print $fh ("\n");

    printf $fh ( "[Fluidics]\nProtocol\t%s\n", $self->get_protocol() );

    foreach my $parameter ( @{ $self->get_hyb_parameters() } ) {
        while ( my ( $key, $value ) = each %$parameter ) {
            print $fh ( "$key\t", $value, "\n" );
        }
    }

    printf $fh (
        "Station\t%s\nModule\t%s\nHybridize Date\t%s\n\n",
        $self->get_station,
        $self->get_module,
	$self->get_hyb_date,
    );

    printf $fh (
        "[Scanner]\nPixel Size\t%s\nFilter\t%s\nScan Temperature\t%s\n"
      . "Scan Date\t%s\nScanner ID\t%s\nNumber of Scans\t%s\nScanner Type\t%s\n",
        $self->get_pixel_size,
	$self->get_filter,
        $self->get_scan_temp,
	$self->get_scan_date,
        $self->get_scanner_id,
	$self->get_num_scans,
        $self->get_scanner_type,
    );

    return;
}

1;
