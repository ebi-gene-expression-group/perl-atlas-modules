#!/usr/bin/env perl
#
# Module to parse Affymetrix data files.
#
# Tim Rayner 2005, ArrayExpress team, European Bioinformatics Institute
#
# $Id: Parser.pm 2021 2008-04-09 09:55:25Z tfrayner $
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
	    <td class="pagetitle">Module detail: Affymetrix/Parser.pm</td>
	  </tr>
      </table>
    </div>

=end html

=head1 NAME

ArrayExpress::Datafile::Affymetrix::Parser - an Affymetrix data file parsing
module.

=head1 SYNOPSIS

 use base qw( ArrayExpress::Datafile::Affymetrix::Parser );

=head1 DESCRIPTION

This module is an abstract superclass used in the parsing and export
of data from Affymetrix file formats. CEL, CHP and EXP formats are
supported, with limited CDF parsing. Both old (GDAC) and new
(GCOS/XDA) file formats can be parsed.

There is a set of methods common to all the Affymetrix file classes,
listed below. There are additional methods, specific to each class,
which are documented in the relevant pages.

=head1 METHODS

The following methods are common to all classes.

=over 2

=item new({ input => 'myfile.CEL' })

The class constructor. This method returns a an object of the
appropriate class, without performing any additional processing.

=item parse()

This method will take the value for the C<input> attribute and parse the
data into memory so that it can be interrogated using the methods below.

=back

=head2 Accessor methods

Each of these methods acts as both setter and getter for the
attributes in question. Typically these will be used to access the
data and metadata which was extracted using the B<parse>
method. Please see the respective subclass documentation for
information on the B<export> and B<get_ded> methods. Note that many of the
following will have no meaning for EXP file metadata.

=over 2

=item get_version()

The version number or string associated with the file. For CEL and CHP
files this should be either 3 or 4.

=item get_num_columns()

The number of columns on the array.

=item get_num_rows()

The number of rows on the array.

=item get_num_cells()

The number of cells on the array. For CEL files this corresponds to
the number of columns multiplied by the number of rows.

=item get_algorithm()

The name of the algorithm used to produce the data (e.g. "Percentile",
"ExpressionStat").

=item get_chip_type()

The type of chip used (e.g., HG-U133A). This is supported for EXP
files, CEL files, CHP files and GDAC format CDF files. Note that for
CEL files this relies on parsing a header tag which is not actually
documented by Affymetrix, and so it is possible that this method is
not to be trusted in such cases.

=item get_parameters()

A reference to a hash with parameter {name => value} pairs. Parameters
are grouped as follows:

 CEL: Feature extraction parameters
 CHP: Normalization parameters
 EXP: Hybridization parameters (numbered).

=item get_stats()

A reference to a hash with statistic {name => value} pairs. Statistics
are grouped as follows:

 CEL: Feature extraction summary statistics
 CHP: Normalization summary statistics

=item get_qtd()

A reference to an array listing the QuantitationType identifiers (long
form) in the column order that they are output by the B<export>
method. See also the B<headings> method below.

=item get_headings()

A reference to an array listing the QuantitationType names (short
form) in the column order that they are output by the B<export>
method. Using this method also populates the B<qtd> method data
structure, but not vice versa.

=cut

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

package ArrayExpress::Datafile::Affymetrix::Parser;

use strict;
use warnings;

use Class::Std;
use Carp;
use Readonly;
use Scalar::Util qw(openhandle);

use EBI::FGPT::Common qw(clean_hash);

my %input          : ATTR( :name<input>,          :default<undef> );
my %filehandle     : ATTR( :init_arg<filehandle>, :default<undef> );
my %magic          : ATTR( :name<magic>,          :default<undef> );
my %required_magic : ATTR( :name<required_magic>, :default<undef> );

my %num_columns  : ATTR( :name<num_columns>, :default<undef> );
my %num_rows     : ATTR( :name<num_rows>,    :default<undef> );
my %num_cells    : ATTR( :name<num_cells>,   :default<undef> );
my %version      : ATTR( :name<version>,     :default<undef> );
my %algorithm    : ATTR( :name<algorithm>,   :default<undef> );
my %chip_type    : ATTR( :name<chip_type>,   :default<undef> );
my %parameters   : ATTR( :get<parameters>,   :default<{}> );
my %stats        : ATTR( :get<stats>,        :default<{}> );
my %qtd          : ATTR( :name<qtd>,         :default<[]> );
my %headings     : ATTR( :get<headings>,     :default<[]> );
my %data_matrix  : ATTR( :default<[]> );
my %data_storage : ATTR( :name<data_storage>, :default<'ARRAY'> );

# Prefix used in the construction of QT identifiers
Readonly my $AFFY_QT_PREFIX => 'Affymetrix:QuantitationType:';

sub START {

    my ( $self, $id, $args ) = @_;

    unless ( $input{ ident $self } || $filehandle{ ident $self } ) {
	confess("Error: no input to parsing module.");
    }

    return;
}

sub get_filehandle : RESTRICTED {

    my ( $self ) = @_;

    my $input = $self->get_input();
    if ( ! $filehandle{ ident $self } && $input ) {
	if ( openhandle( $input ) ) {
	    $filehandle{ ident $self } = $input;
	}
	else {
	    $filehandle{ ident $self } = IO::File->new( $input, '<' )
		or croak(qq{Unable to open file "$input" : $!\n});
	}
    }

    return $filehandle{ ident $self };
}

sub parse {
    confess("Error: Stub method called in abstract superclass.");
}

sub set_parameters : RESTRICTED {

    my ( $self, $hashref ) = @_;

    ref $hashref eq 'HASH'
	or confess( 'Bad parameters passed to method' );

    # strip out undef or empty string values
    my $cleaned = clean_hash($hashref);

    $parameters{ident $self} = $cleaned;

    return;
}

sub add_parameters : RESTRICTED {

    # When called with a reference to a hash of parameter {name =>
    # value} pairs this method adds those parameters to any
    # pre-existing ones. Parameters having the same name are
    # overwritten.

    my ( $self, $hashref ) = @_;

    ref $hashref eq 'HASH'
	or confess( 'Bad parameters passed to method' );

    # strip out undef or empty string values
    my $cleaned = clean_hash($hashref);

    @{ $parameters{ident $self} }{ keys %$cleaned } = values %$cleaned;

    return;
}

sub set_stats : RESTRICTED {

    my ( $self, $hashref ) = @_;

    ref $hashref eq 'HASH'
	or confess( 'Bad parameters passed to method' );

    # strip out undef or empty string values
    my $cleaned = clean_hash($hashref);

    $stats{ident $self} = $cleaned;

    return;
}

sub add_stats : RESTRICTED {

    # When called with a reference to a hash of statistic {name =>
    # value} pairs this method adds those statistics to any
    # pre-existing ones. Statistics having the same name are
    # overwritten.

    my ( $self, $hashref ) = @_;

    ref $hashref eq 'HASH'
	or confess( 'Bad parameters passed to method' );

    # strip out undef or empty string values
    my $cleaned = clean_hash($hashref);

    @{ $stats{ident $self} }{ keys %$cleaned } = values %$cleaned;

    return;
}

sub set_headings : RESTRICTED {    # arrayref (replaces old qtd); CEL and CHP only
    my ( $self, $list ) = @_;

    ref $list eq 'ARRAY'
	or confess( 'Bad parameters passed to method' );
    $headings{ident $self} = $list;

    my @qtd;
    foreach my $heading ( @{ $list } ) {
	push( @qtd, $AFFY_QT_PREFIX . $heading );
    }
    $qtd{ident $self} = \@qtd;

    return;
}

# set/get_data is a restricted method used in the Affymetrix subclasses
# only. It provides access to the parsed data.

sub set_data : RESTRICTED {

    # Arrayref by default; CEL.pm however uses a hashref. We make this
    # restricted to hide this complexity.

    my ( $self, $data ) = @_;

    # Subclasses using non-arrayref storage need to set_data with
    # e.g. an empty hashref before calling this.
    ref $data eq $self->get_data_storage()
	or confess( 'Bad parameters passed to method' );

    $data_matrix{ident $self} = $data;

    return;
}

sub get_data : RESTRICTED {

    my ( $self, $data ) = @_;

    return $data_matrix{ident $self};
}

sub _get_line : RESTRICTED {

    my ( $self, $fh ) = @_;

    openhandle($fh) or confess( 'Bad parameters passed to method' );

    my $line = <$fh>;
    $line =~ s/[\r\n]* \z//xms if $line;
    return $line;
}

1;
