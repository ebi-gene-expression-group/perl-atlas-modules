#!/usr/bin/env perl
#
# Datafile.pm - an OO module derived from and used in the experiment
# checker script. Contains routines which might be useful elsewhere.
#
# Tim Rayner 2005 ArrayExpress team, EBI
#
# $Id: Datafile.pm 2312 2010-04-28 13:57:57Z farne $
#

package ArrayExpress::Datafile;

use strict;
use warnings;

use charnames qw( :full );

use Class::Std;
use English qw( -no_match_vars );
use Carp;
use File::Spec;
use Storable qw(dclone);
use IO::File;
use Scalar::Util qw(looks_like_number openhandle);
use List::Util qw(sum first);
use List::MoreUtils qw(any none);
use Digest::MD5 qw(md5_hex);

use EBI::FGPT::Common qw(
    strip_discards
    get_indexcol
    check_linebreaks
    $RE_EMPTY_STRING
    $RE_LINE_BREAK
    $RE_SURROUNDED_BY_WHITESPACE
    $RE_WITHIN_BRACKETS
);

use EBI::FGPT::Config qw($CONFIG);

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
	    <td class="pagetitle">Module detail: Datafile.pm</td>
	  </tr>
      </table>
    </div>

=end html

=head1 NAME

ArrayExpress::Datafile.pm - an OO module providing methods
for parsing data files.

=head1 SYNOPSIS

 use ArrayExpress::Datafile;
 my $file = ArrayExpress::Datafile->new({
     name            => 'data.txt',
     data_type       => 'raw',
     array_design_id => 'A-MEXP-123',
 });

=head1 DESCRIPTION

This is a module providing methods for data file parsing. See also
L<ArrayExpress::Datafile::Parser> for Datafile handler objects.

=cut

# Incrementable integer accessors
my %row_count            : ATTR( :name<row_count>,        :default<0> );
my %parse_errors         : ATTR( :name<parse_errors>,     :default<0> );
my %not_null             : ATTR( :name<not_null>,         :default<0> );

# Hash for further mutator construction (below).
my %incr_integer_attr = (
    row_count    => \%row_count,
    parse_errors => \%parse_errors,
    not_null     => \%not_null,
);

# Plain boolean flag accessors
my %is_miamexpress       : ATTR( :name<is_miamexpress>,   :default<0> );
my %is_exp               : ATTR( :name<is_exp>,           :default<0> );
my %is_binary            : ATTR( :default<0> );   # Autodetected
my %is_illumina_fgem     : ATTR( :default<undef> );

# String accessors
my %hyb_identifier       : ATTR( :name<hyb_identifier>,   :default<q{}> );
my %hyb_sysuid           : ATTR( :name<hyb_sysuid>,       :default<q{}> );
my %array_design_id      : ATTR( :set<array_design_id>, :init_arg<array_design_id>, :default<q{}> );
my %datamatrix_chip_type : ATTR( :set<dm_chip_type>,      :default<q{}> );
my %ded_identifier       : ATTR( :name<ded_identifier>,   :default<q{}> );
my %test_data_line       : ATTR( :name<test_data_line>,   :default<q{}> );
my %md5_digest           : ATTR( :set<md5_digest>,        :default<q{}> );
my %qt_type              : ATTR( :name<qt_type>,          :default<q{}> );
my %path                 : ATTR( :name<path>,             :default<undef> );
my %target_filename      : ATTR( :name<target_filename>,  :default<undef> );
my %sdrf_id_column       : ATTR( :name<sdrf_id_column>,   :default<undef> );

# Hashref accessors
my %data_metrics         : ATTR( :name<data_metrics>,     :default<{}> );
# my $intensity_vector     : ATTR( :name<intensity_vector>, :default<{}> );

# Arrayref accessors
my %index_columns        : ATTR( :name<index_columns>,    :default<[]> );
my %column_headings      : ATTR( :name<column_headings>,  :default<[]> );
my %heading_qts          : ATTR( :name<heading_qts>,      :default<[]> );
my %heading_hybs         : ATTR( :name<heading_hybs>,     :default<[]> );

# Accumulative hashref accessor hashes (mutator and accessor methods below)
my %fail_columns         : ATTR( :default<{}> );
my %fail_hybs            : ATTR( :default<{}> );

# Hash for further mutator construction (below).
my %accum_hashref_attr = (
    fail_columns => \%fail_columns,
    fail_hybs    => \%fail_hybs,
);

# More specialized cases; mutators below
my %factor_value         : ATTR( :get<factor_value>,      :default<{}> );
my %name                 : ATTR( :get<name>,              :default<undef>, :init_arg<name> );
my %exp_data             : ATTR( :get<exp_data>,          :default<{}> );
my %mage_qtd             : ATTR( :get<mage_qtd>,          :default<undef> );
my %mage_badata          : ATTR( :name<mage_badata>,      :default<undef> );
my %filehandle           : ATTR( :set<filehandle>,        :default<undef> );
my %mage_ba              : ATTR( :name<mage_ba>,          :default<undef> );

# Enumerated types with validating mutators (below)
my %ded_type             : ATTR( :get<ded_type>,          :default<q{}> );
my %format_type          : ATTR( :get<format_type>,       :default<q{}> );
my %data_type            : ATTR( :get<data_type>,         :default<q{}>,   :init_arg<data_type> );
my %linebreak_type       : ATTR( :set<linebreak_type>     :default<undef> );

# Occasionally useful as a dummy object, in which case turn off
# constructor argument validation. Particularly useful in unit testing.
my %is_dummy             : ATTR( :get<is_dummy>, :default<undef>, :init_arg<is_dummy> );

# Error filehandle, allowing STDERR messages to be captured.
my %error_fh             : ATTR( :name<error_fh>, :default<\*STDOUT> );

# ArrayDesign objects linked via this attribute.
my %array_design         : ATTR( :name<array_design>,     :default<undef> );

sub START {

    my ($self, $id, $args) = @_;

    # This sets the path as well, if not already initialized (this
    # must be done after default attribute initialization).
    $self->set_name($args->{name}) if $args->{name};

    # A little validation of attributes.
    if ( ! $self->get_is_dummy() ) {

	if ( ! $self->get_name() ) {
	    croak("Error: File name attribute not set.");
	}
	if ( ! $self->get_data_type() ) {
	    croak(
		sprintf(
		    "Error: File data_type attribute not set for file %s",
		    $self->get_name(),
		)
	    );
	}
	if ( ! $self->get_array_design_id() ) {
	    croak(
		sprintf(
		    "Error: File array_design_id attribute "
		  . "(e.g. accession number) not set for file %s",
		    $self->get_name(),
		)
	    );
	}
    }
}

#######################
# Main object methods #
#######################

sub parse_header {

    my ( $self ) = @_;

    local $INPUT_RECORD_SEPARATOR = $self->get_linebreak_type();

    my $input_fh = $self->get_filehandle()
	or croak("Error: Unable to retrieve filehandle.");

    openhandle($input_fh) or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );

    # Parse Data Matrix headers.
    if (   $self->get_data_type() eq $CONFIG->get_RAW_DM_FILE_TYPE()
	|| $self->get_data_type() eq $CONFIG->get_FGEM_FILE_TYPE() ) {

	if ( $self->get_mage_badata() ) {

	    # MAGE-TAB style data matrices.
	    $self->parse_data_matrix_header();
	}
	else {

	    # Old-style FGEMs.
	    $self->parse_fgem_header();
	}
    }
    else {

	# Check for raw/norm data file formats.
	$self->parse_header_with_indices( $CONFIG->get_T2M_INDICES() );
    }

    return $self->get_format_type();
}

sub get_linebreak_type {

    my ( $self ) = @_;

    unless ( defined $linebreak_type{ ident $self } ) {

	# Check the linebreaks and set the input record separator
	# accordingly
	my ( $count, $linebreak ) = check_linebreaks( $self->get_path() );

	unless ( defined $linebreak ) {

	    # If we couldn't decide on a line ending format, we arrive
	    # here. Set some defaults here:
	    $self->set_row_count(0);
	    $self->set_format_type('Unknown');

	    # Set the linebreak type so that we don't try getting it
	    # again should the following croak() be trapped in an eval().
	    $linebreak_type{ ident $self } = 'Unknown';

	    # Crash hard. Typically calls to this method are wrapped
	    # in an eval to capture this error.
	    my $filename = ( File::Spec->splitpath( $self->get_path() ) )[2];
	    croak(
		sprintf(
		    "ERROR: Cannot parse linebreaks for file %s (%s Unix, %s DOS, %s Mac)\n",
		    $filename,
		    $count->{'unix'},
		    $count->{'dos'},
		    $count->{'mac'},
		),
	    );
	}

	$linebreak_type{ ident $self } = $linebreak;
    }

    return $linebreak_type{ ident $self };
}

sub get_line_format {

    my ( $self ) = @_;

    my $linebreak = $self->get_linebreak_type();

    my %separator = (
	"\N{LINE FEED}"                    => 'Unix',
	"\N{CARRIAGE RETURN}\N{LINE FEED}" => 'DOS',
	"\N{CARRIAGE RETURN}"              => 'Mac',
	'Unknown'                          => 'Unknown',
    );

    if ( defined $separator{ $linebreak } ) {
	return $separator{ $linebreak };
    }
    else {

	# Failure here reflects an inconsistency in the linebreaks
	# supported here and in Common::check_linebreaks, so it
	# warrants a full confess().
	confess("Error: Unrecognized linebreaks.");
    }
}

sub parse_datafile {

    my ( $self, $QTs, $hyb_ids, $norm_ids, $scan_ids ) = @_;

    ref $QTs      eq 'HASH' or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );
    ref $hyb_ids  eq 'HASH' or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );
    ref $norm_ids eq 'HASH' or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );
    ref $scan_ids eq 'HASH' or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );

    # Rewind the file before running any checks.
    seek($self->get_filehandle, 0, 0)
	or croak("Error rewinding filehandle: $!");

    my $linebreak;
    eval {
	$linebreak = $self->get_linebreak_type();
    };
    if ( $EVAL_ERROR ) {

	# Skip this file if linebreak parsing failed.
	return ( [], $EVAL_ERROR );
    }
    local $INPUT_RECORD_SEPARATOR = $linebreak;

    # We now treat all datafiles as though they will be parsed by our
    # Datafile::Parser system (rather than the MIAMExpress datafile
    # parsers).
    $self->parse_header();
    my $rc = q{};
    unless ( scalar @{ $self->get_index_columns() } ) {
	$rc .= "Unable to detect supported data file column headings.\n";
    }

    if (   $self->get_format_type() =~ /^Illumina/
        && $self->is_illumina_fgem() ) {

	# Fix Illumina data matrix-style files.
	$self->rewrite_illumina_as_fgem();
    }
    else {

	# Rewrite non-Generic data formats into a temporary Generic
	# filehandle. This is now all handled within the
	# fix_known_text_format method.
	$self->fix_known_text_format();
    }

    my $ids_from_sdrf = {};
    # Allow Normalization IDs as column labels for data matrices.
    if (   $self->get_data_type() eq $CONFIG->get_RAW_DM_FILE_TYPE()
        || $self->get_data_type() eq $CONFIG->get_FGEM_FILE_TYPE() ) {

        # Set list of IDs to check against according to sdrf column
        # type referenced by fgem
        my $id_type = $self->get_sdrf_id_column;       
        if (!$id_type){
        	# if ID type is not available it must be an MX or t2m fgem
        	# so check against both hyb and norm IDs (but not scans?)
        	$ids_from_sdrf = { %{ $hyb_ids }, %{ $norm_ids } };
        	$id_type = qq{};
        }
        elsif ($id_type =~ /Hybridi(s|z)ation/ixms){
        	$ids_from_sdrf = $hyb_ids;
        }
        elsif ($id_type =~ /Scan/ixms ){ 
        	$ids_from_sdrf = $scan_ids; 
        }
        elsif($id_type =~ /Normali(s|z)ation/ixms ){ 
        	$ids_from_sdrf = $norm_ids; 
        }
        else{
        	$rc .= "ID REF column \"$id_type\" not recognized\n";       	
        }
    }

    # Check the column headings here. This populates %fail_columns and
    # %fail_hybs
    my $column_rc;  
    $column_rc = $self->check_column_headings( $QTs, $ids_from_sdrf )
        unless $rc;

    # feature_coords is an array of "1.1.1.1"-style coord strings.
    my ( $feature_coords, $parse_rc );
    ( $feature_coords, $parse_rc ) = $self->_parse_datarows()
        unless $rc;

    $rc .= $column_rc if $column_rc;
    $rc .= $parse_rc  if $parse_rc;

    close $self->get_filehandle;

    return ( $feature_coords, $rc );

}

sub is_ignored_qt {

    # Method returns true if the argument matches against the
    # Config.pm list of ignored QTs.
    my ( $self, $qt ) = @_;

    return ( first { $qt =~ m/\A\s*$_\s*\z/ms }
		 @{ $CONFIG->get_IGNORED_QTS() || [] } );
}

sub check_column_headings {

    # need lists of approved QTs, most likely on a per-datafile-format
    # basis.  also check QT types (MAGE spec; float, boolean, enum? If
    # standard, what?).  Make sure QTs are free of spaces and other
    # typos also need the hyb names here for combined data matrix
    # files.

    my ( $self, $QTs, $hyb_ids ) = @_;

    ref $QTs eq 'HASH' or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );

    $hyb_ids ||= {};

    # Figure out which software type best represents the column
    # headings; value will be returned as $self->get_qt_type.
    my $rc = $self->_derive_consensus_software($QTs);

    my $software_QTs = $self->get_data_metrics();

    HEADING:
    foreach my $heading ( @{ $self->get_heading_qts() } ) {

        # Skip common column headings (various index columns etc.)
        next HEADING if ( $self->is_ignored_qt($heading) );

        # Record a failing column if it's not represented in the consensus
        # software type (qt_type).
        unless ( $software_QTs && $software_QTs->{$heading} ) {
            $self->add_fail_columns($heading);
        }

    }

    # Deal with combined data files
    if (   $self->get_data_type() eq $CONFIG->get_FGEM_FILE_TYPE()
        || $self->get_data_type() eq $CONFIG->get_RAW_DM_FILE_TYPE() ) {

        HEADING:
        foreach my $column ( @{ $self->get_heading_hybs() } ) {
            foreach my $id (@$column) {
                $self->add_fail_hybs($id) unless $hyb_ids->{$id};
            }
        }

        # Internal consistency check
        croak(    "Error: Hyb and QT numbers differ for file "
                . $self->get_name()
                . "\n" )
            unless ( $#{ $self->get_heading_qts() } == $#{ $self->get_heading_hybs() } );

    }

    return $rc;
}

sub parse_exp_file {

    # Parse EXP file and capture the relevant metadata. Returns undef
    # on failure.
    my $self    = shift;
    my $section = 'header';

    local $INPUT_RECORD_SEPARATOR = $self->get_linebreak_type();

    my $expfile = $self->get_filehandle()
	or croak("Error: Unable to retrieve filehandle.");

    my $exp_data = {};

    EXP_LINE:
    while ( my $line = <$expfile> ) {
        chomp $line;

        # Just to be doubly sure about DOS-style line endings (FIXME
        # is this really necessary? chomp() should have done the
        # job...)
        $line =~ s/$RE_LINE_BREAK//xms;

        if ( $line =~ m/\A $RE_WITHIN_BRACKETS/xms ) {

            $section = $1;

        }
        else {

            my @linearray = split /\t/, $line;

            next EXP_LINE unless $linearray[0];    # lose the undefined rows

            $exp_data->{$section}{ $linearray[0] } = $linearray[1]
                if ( $#linearray == 1 );

        }
    }

    close $expfile or croak("Unable to close EXP filehandle: $!\n");

    $self->set_exp_data($exp_data);

    return $exp_data;
}

sub fix_known_text_format {    # This subroutine maps values in file
                               # format to the appropriate reformatting
                               # sub. To add a new format, edit the
                               # Constants.pm file to indicate the
                               # coordinate columns and set the format CV
                               # string, write the conversion sub and link
                               # the two here.

    my ( $self ) = @_;

    local $INPUT_RECORD_SEPARATOR = $self->get_linebreak_type();

    my $input_fh;

    my $format_type = $self->get_format_type();  

    my %dispatch = (
	'GenePix'           => '_fix_genepix',
	'ArrayVision'       => '_fix_arrayvision',
	'ArrayVision_lg2'   => '_fix_arrayvision_lg2',
	'Agilent'           => '_fix_agilent',
	'Scanalyze'         => '_fix_scanalyze',
	'ScanArray'         => '_fix_scanarray',
	'QuantArray'        => '_fix_scanarray',
	'Spotfinder'        => '_fix_spotfinder',
	'MEV'               => '_fix_mev',
	'BlueFuse'          => '_fix_bluefuse',
	'UCSFSpot'          => '_fix_ucsfspot',
	'CodeLink'          => '_fix_codelink',
	'NimbleScanFeature' => '_fix_nimblescanfeat',
	'NimbleScanNorm'    => '_fix_nimblescanfeat',
	'NimblegenNASA'     => '_fix_nimblegennasa',
	'AppliedBiosystems' => '_fix_appliedbiosystems',
	'Illumina'          => '_fix_illumina_perhyb',
	'ImaGene'           => '_fix_imagene',
	'ImaGene3'          => '_fix_imagene3',
	'ImaGene7'          => '_fix_genepix',
	'ImaGeneFields'     => '_fix_genepix',
	'CSIRO_Spot'        => '_fix_csiro_spot',
    );

    if ( my $method = $dispatch{$format_type} ) {
	$input_fh = $self->$method;
    }

    # Exchange the old filehandle for the new one.
    $self->set_filehandle($input_fh) if $input_fh;

    # return value is effectively a true = success return code (not always used).
    return $input_fh;

}

sub strip_and_sort {

    # Sub to rewrite a datafile, stripping out unwanted columns and
    # substituting null entries.

    my ( $self, $output_file, $new_headings ) = @_;

    local $INPUT_RECORD_SEPARATOR = $self->get_linebreak_type();

    my $input_fh = $self->get_filehandle()
	or croak("Error: Unable to retrieve filehandle.");

    openhandle($input_fh) or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );
    ref $output_file and confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );
    ref $new_headings eq 'ARRAY'
        or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );

    # Create a temporary file in MC/MR/C/R format; sorted on the fly.
    # We want to sort our output; here we do it on the fly using unix
    # sort (this is much faster than using perl).
    #
    # Windows support - omit the key flags. N.B. we also have to
    # explicitly close these filehandles for Windows, otherwise we
    # cannot delete the temporary files.  Win2000 ActiveState Perl 5.8.6
    # registers as "MSWin32"
    #
    my $sortkeys = q{};
    unless ( $^O =~ m/\A mswin/ixms ) {
        $sortkeys = ' -n ';
        my $columnno = 0;

        # We reorder the file below so that the first four columns are
        # index columns, regardless of where they are in the original
        # file.
        foreach my $index ( 0 .. $#{ $self->get_index_columns() } ) {

            # $index is 0..n; we need 1..(n+1)
            $sortkeys .= q{ -k } . ( $index + 1 ) . q{ };
        }
    }

    my @indexcols = @{ $self->get_index_columns() };

    my @original_headings = @{ $self->get_column_headings };

    my %is_heading_to_keep = map { $_ => 1 } @$new_headings;

    # Organize our new file information before we start
    # processing. This effectively reorders the columns so that the
    # indexcols come first.
    my @fixed_headings = @original_headings[@indexcols];
    my @fixed_qts;

    # This will be used as an array slice below to reorder
    # the column values on the fly.
    my @fixed_indices = @indexcols;

    # Here we sort the rest of the columns. This enables us to
    # generate a common QT Dimension for files such as GenePix which
    # are not always ordered identically.
    my %heading_to_index
        = map { $original_headings[$_] => $_ } ( 0 .. $#original_headings );

    # Check that the column headings are all unique (not true e.g. for FGEM).
    if ( scalar(@original_headings) == scalar( keys %heading_to_index ) ) {

        # If they are, sort using the lookup hash %heading_to_index
        foreach my $heading_name ( sort keys %heading_to_index ) {
            my $index = $heading_to_index{$heading_name};
            if ( $is_heading_to_keep{$heading_name}
                && ( none { $index == $_ } @indexcols ) ) {

                push( @fixed_headings, $heading_name );
                push( @fixed_qts,      $heading_name );
                push( @fixed_indices,  $index );
            }
        }
    }
    else {

        # Files with non-unique column headings can't be sorted.
        foreach my $index ( 0 .. $#original_headings ) {
            my $heading_name = $original_headings[$index];
            if ( $is_heading_to_keep{$heading_name}
                && ( none { $index == $_ } @indexcols ) ) {

                push( @fixed_headings, $heading_name );
                push( @fixed_qts,      $heading_name );
                push( @fixed_indices,  $index );
            }
        }
    }

    # Actually open the file as a pipe via the external "sort" utility.
    open( my $output_fh, q{|-}, qq{sort $sortkeys > "$output_file"} )
        or croak("Error opening output file $output_file: $!\n");

    # Read through the file, using @fixed_indices to decide what to
    # keep.
    DATA_LINE:
    while ( my $line = <$input_fh> ) {

        # Empty lines, especially at the end of files, can be a
        # problem. We just dump them here and carry on.
        if ( $line =~ $RE_EMPTY_STRING ) {
            print {$self->get_error_fh()} ("Warning: skipping empty line in data file.\n");
            next DATA_LINE;
        }

        # Strip all kinds of line ending
        $line =~ s/$RE_LINE_BREAK//xms;

        # We used to use Text::CSV_XS here, but this has to handle
        # non-validated data files which occasionally crashed it.
        my @line_array = split /\t/, $line, -1;

        # Strip whitespace on the fly here, create the new line from
        # the @fixed_indices array slice of the old one.
        my @new_line = map {
            my ( $value ) = defined $_ ? ( $_ =~ $RE_SURROUNDED_BY_WHITESPACE ) : q{};
            defined $value && ( $value ne q{} )
                ? $value
                : 'null'
        } @line_array[@fixed_indices];

        print $output_fh ( join( "\t", @new_line ), $INPUT_RECORD_SEPARATOR );

    }

    close($output_fh)
        or croak("Error: unable to close temporary filehandle: $!\n");

    # Set the new information for this object
    $self->set_index_columns( [ 0 .. $#indexcols ] );
    $self->set_column_headings( \@fixed_headings );
    $self->set_heading_qts( \@fixed_qts );
    $self->set_path($output_file);

    # Relink the filehandle.
    my $self_fh = IO::File->new( $output_file, '<' )
        or
        croak("Error: Unable to reopen temporary file after sorting: $!\n");
    $self->set_filehandle($self_fh);

    return;
}

sub percent_null {

    my ($self) = @_;

    my $data_metrics = $self->get_data_metrics();
    my $data_rowno   = $self->get_row_count();

    # We want to count the intersection between the QTs (heading_qts)
    # and the known QTs (data_metrics).
    my $data_colno
        = ( grep { exists $data_metrics->{$_} } @{ $self->get_heading_qts() } );

    my $total_notnull = $self->get_not_null;

    my $percent_null;
    if ( $data_colno && $data_rowno && $total_notnull ) {
        $percent_null
            = 100 * ( ( $data_colno * $data_rowno ) - $total_notnull )
            / ( $data_colno * $data_rowno );

	# Round to 5dp.
	return sprintf("%.5f", $percent_null);
    }

    else {
        return ("N/A");
    }
}

sub parse_header_with_indices {

    my ( $self, $indices ) = @_;

    ref $indices eq 'HASH' or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );

    local $INPUT_RECORD_SEPARATOR = $self->get_linebreak_type();

    my $input_fh = $self->get_filehandle()
	or croak("Error: Unable to retrieve filehandle.");
    openhandle($input_fh) or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );

    my $type = $self->get_data_type();

    my $linecount = 0;                     # Track the number of lines seen

    my $column_headings = [];
    my $indexcols       = [];
    my $format;
    
    my $in_field_info;
    my $field_index;
    my $num_fields = 0;

    HEADERLINE:
    while ( my $line = <$input_fh> ) {

        # Give up after we've seen a good chunk of the file (this is a
        # performance measure).
        last HEADERLINE if ( $linecount > 1000 );
        $linecount++;

        # Just to be doubly sure about DOS-style line endings
        $line =~ s/$RE_LINE_BREAK//xms;

        @$column_headings = split /\t/, $line, -1;

        # Strip off surrounding quotes; I assume our loader can cope with
        # QTs in quotes. Easy to change if not (but see parse_datafile for
        # another instance of this!!!).
        foreach my $heading (@$column_headings) {
            $heading =~ s/$RE_SURROUNDED_BY_WHITESPACE/$1/xms;
        }

        # See if we have any imagene field information
        if ($line =~ /End Field Dimensions/i){
        	$in_field_info = 0;
        }
        if ($in_field_info and defined $field_index){
        	$num_fields++ if @$column_headings[$field_index];
        }
        if ($in_field_info and not defined $field_index){
        	my @tmp = @$column_headings;
        	($field_index) = grep {$tmp[$_] eq "Field"} 0..$#tmp;
        }
        if ($line =~ /Begin Field Dimensions/i){
        	$in_field_info = 1;
        }
        # If we have imagene file with multiple fields then we must have
        # ImaGeneFields type headings in the file - we do not look for
        # anything else
        if ($num_fields > 1){
        	$format = "ImaGeneFields";
        	my $imagene_cols = $indices->{$format};
        	$indices = { $format => $imagene_cols };
        }

        # Here we do a check on column heading for our supported file
        # formats.

        # MX FGEM first. FIXME consider removing this special-case;
        # its only real effect is to limit FGEM files to single
        # indexcol formats; maybe we can remove this assumption
        # elsewhere in the code and simplify this.
        if ( $type && $type eq $CONFIG->get_FGEM_FILE_TYPE() ) {

            # Check for Reporter Identifier column, CS id or Affy Probe ID
            foreach my $col_format ( qw( FGEM FGEM_CS AffyNorm GEO Illumina ) ) {

                # FGEM only ever has one identifier column.
		my $heading = $CONFIG->get_T2M_INDICES()->{$col_format}[0];
                my $column = get_indexcol(
		    $column_headings,
                    qr/$heading/,
		);
                unless ( $column == -1 ) {

		    # Column found; we stop looking.
                    $indexcols  = [ $column ];
		    $format     = $col_format;
		    last HEADERLINE;
                }
            }

            # If no suitable identifier columns found, check the next line.
            next HEADERLINE;

        }

        # Non-FGEM files (everything else - raw, normalized)
        else {
           
	    # N.B. for ordered searches here use a Tie::IxHash to
	    # store the indices in Config.pm.

            COLUMNFORMAT:
            foreach my $col_format ( keys %$indices ) {

                # Some index sets don't have 'Generic' indices; we skip them
                # here to avoid autovivification bugs below
                next COLUMNFORMAT unless ( $indices->{$col_format} );

                foreach my $header ( @{ $indices->{$col_format} } ) {

		    # Empty string is special-cased.
                    my $column = get_indexcol(
			$column_headings,
			( $header eq q{} ? $header : qr/$header/ ),
		    );

                    if ( $column == -1 ) {

			# Column not found; reset $indexcols and skip
			# to the next format type.
                        $indexcols = [];
                        next COLUMNFORMAT;
                    }
		    else {

			# Column found; add to $indexcols.
			push( @{ $indexcols }, $column );
		    }
                }

		# All columns found, we stop looking.
		$format = $col_format;
		last HEADERLINE;
            }
        }
    }    # End of HEADERLINE

    # Put the results where we can find them later.
    if ( $format ) {
	$self->set_column_headings( $column_headings );
	$self->set_index_columns( $indexcols );
	$self->set_heading_qts( strip_discards( $indexcols, $column_headings ) );
    }
    $self->set_format_type( $format || 'Unknown' );

    return;
}

sub is_illumina_fgem {

    # Takes a parsed Datafile, checks column_headings to see whether
    # it's an FGEM as opposed to per-hyb data.

    my $self = shift;

    unless ( defined $is_illumina_fgem{ident $self} ) {
	unless ( $self->get_format_type =~ /Illumina/i ) {
	    croak("Can't call is_illumina_fgem() on non-Illumina file.\n");
	}

	# Start by assuming the negative.
	$is_illumina_fgem{ident $self} = 0;

	# Check the headings for repeated values.  Make sure we make a
	# copy of the array here, as we're going to modify it.
	my @headings = @{ $self->get_column_headings() };
	my %seen;

	HEADING:
	foreach my $heading (@headings) {

	    # Strip off everything before the last period, or return
	    # the whole thing. Assumes that Illumina QTs never contain
	    # periods.
	    if ( $heading =~ m/\A .* \. ([^\.]+) \z/gxms ) {
		$heading = $1;
	    }
	    if ( $heading && $seen{$heading}++ ){
		$is_illumina_fgem{ident $self} = 1;
		last HEADING;
	    }
	}
    }

    return $is_illumina_fgem{ident $self};
}

sub rewrite_illumina_as_fgem {

    my $self = shift;

    local $INPUT_RECORD_SEPARATOR = $self->get_linebreak_type();

    unless ( $self->get_format_type =~ /Illumina/i && $self->is_illumina_fgem ) {
	croak("File is not an Illumina multi-hyb data matrix.\n");
    }

    # Rewrite the file here (reuse _fix_illumina() code)
    my $input_fh = $self->_fix_illumina();

    # Exchange the old filehandle for the new one.
    $self->set_filehandle($input_fh);

    # Rewrite the headings as standard FGEM-style. Assumes that
    # Illumina QTs never contain periods.
    my ( @new_headings, @file_qts, @hyb_ids );
    foreach my $heading ( @{ $self->get_column_headings() } ) {
	my ($hyb, $qt) = ($heading =~ /\A (.*) \. ([^\.]+) \z/xms);
	if ( $qt && $hyb ) {
	    push @new_headings, $qt;
	    push @file_qts,     $qt;
	    push @hyb_ids,    [ $hyb ];
	}
	else {

	    # Index column.
	    push @new_headings, $heading;
	}
    }
    $self->set_format_type('FGEM');
    $self->set_column_headings(\@new_headings);
    $self->set_heading_qts(\@file_qts);
    $self->set_heading_hybs(\@hyb_ids);

    # If it's not already transformed data, set it as a measured data matrix.
    if ( $self->get_data_type() eq 'raw' ) {
	$self->set_data_type( $CONFIG->get_RAW_DM_FILE_TYPE() );
	$self->set_sdrf_id_column('Hybridization Name');
    }
    else {
	$self->set_data_type( $CONFIG->get_FGEM_FILE_TYPE() );
    $self->set_sdrf_id_column('Hybridization Name');
    }
    return;
}

sub get_dm_chip_type {

    # Return the chip_type associated with a data matrix file via its
    # MAGE BioAssayData association.
    my ( $self ) = @_;

    unless ( $datamatrix_chip_type{ ident $self } ) {
	if ( my $badata = $self->get_mage_badata() ) {

	    NVT:
	    foreach my $nvt ( @{ $badata->getPropertySets() || [] } ) {
		if ( $nvt->getName() =~ /\A CDF \z/ixms ) {
		    my $chip_type = $nvt->getValue();
		    $chip_type =~ s/\.CDF \z//ixms;
		    if ( $chip_type ) {
			$datamatrix_chip_type{ ident $self } = $chip_type;
			last NVT;
		    }
		}
	    }
	}
    }

    return $datamatrix_chip_type{ ident $self };
}

sub get_array_design_id {

    my ( $self ) = @_;

    return $self->get_dm_chip_type() || $array_design_id{ ident $self };
}

sub get_array_accno {
    my ($self) = @_;
    return $array_design_id{ ident $self };
}

sub parse_fgem_header : PRIVATE {

    my ( $self ) = @_;

    # Initial basic parse to get our header info.
    $self->parse_header_with_indices( $CONFIG->get_T2M_INDICES() );

    # Sort out column_headings, heading_qts and heading_hybs here.

    # Allow checks to omit already-recognized index columns, such
    # as the rather polymorphic ProbeSet ID for AffyNorm.
    my %is_index_heading = map { $_ => 1 }
	map { $self->get_column_headings()->[$_] }
           @{ $self->get_index_columns() };

    my ( @new_headings, @file_qts, @hyb_ids );

    COLUMN_HEADING:
    foreach my $heading ( @{ $self->get_column_headings() } ) {

	# Skip index column headings.
	if ( $is_index_heading{ $heading } ) {
	    push @new_headings, $heading;
	}
	else {

            # FIXME this regexp may need some work:
            if ( my ( $qt_heading, $hyb_string )
		     = ( $heading =~ m{\A \s* (.*?) \s* \( (.*) \) \s* \z}xms ) ) {

                push( @new_headings, $qt_heading );
                push( @file_qts,     $qt_heading );

		# Hyb ids split into paren-encapsulated list,
		# e.g. QT(Hyb1)(Hyb2)
                my @ids = split /\)\s*\(/, $hyb_string;
                push( @hyb_ids, \@ids );
            }

            else {

		# Failure to parse FGEM heading. Make plenty of noise
		# about this by dumping the full heading
		# everywhere. This will be picked up elsewhere ard
		# complained about.
		push( @new_headings, $heading );
		push( @file_qts,     $heading );
		push( @hyb_ids,    [ $heading ] );
            }
        }
    }

    $self->set_column_headings( \@new_headings );
    $self->set_heading_hybs( \@hyb_ids );
    $self->set_heading_qts( \@file_qts );

    return;
}

sub parse_data_matrix_header : PRIVATE {

    my ( $self ) = @_;

    unless ( ( $self->get_data_type() eq $CONFIG->get_RAW_DM_FILE_TYPE()
            || $self->get_data_type() eq $CONFIG->get_FGEM_FILE_TYPE() )
		&& $self->get_mage_badata() ) {
	croak("Error: Unsuitable Datafile object passed to rewrite method.");
    }

    # Make sure we know what our line format is.
    local $INPUT_RECORD_SEPARATOR = $self->get_linebreak_type();

    my $input_fh = $self->get_filehandle()
	or croak("Error: Unable to retrieve filehandle.");
    openhandle($input_fh) or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );

    # Parse the two-line header.  FIXME this assumes the rather rigid
    # two-line header is the first thing in the file. We should at
    # least allow comment lines (#...) here.
    my $header1 = <$input_fh>;
    chomp $header1;
    $header1 =~ s/\"//g;
    my $header2 = <$input_fh>;
    chomp $header2;
    $header2 =~ s/\"//g;
    my @harry1 = split /\t/, $header1;
    my @harry2 = split /\t/, $header2;

    # $harry1[0] should be an SDRF column reference, while $harry2[0]
    # has to be Reporter Identifier or CompositeSequence Identifier
    # (CompositeElement) at the moment.

    # Note the SDRF columns to use for later bioassay mapping.
    my $sdrf_colref = $harry1[0];
    $self->set_sdrf_id_column( $sdrf_colref );
    my @hyb_ids;
    for ( my $i = 1; $i <= $#harry1; $i++ ) {
	my @hybs = split /;/, $harry1[$i];
	push @hyb_ids, \@hybs;
    }
    $self->set_heading_hybs( \@hyb_ids );

    # Coerce the DesignElement identifier column into something we can
    # use for MAGEv1.
    my $de_type = $harry2[0];
    my $format;
    if ( $de_type =~ /Composite *Element(?: *REF)?/i ) {
	$de_type = 'CompositeSequence Identifier';
	$format  = 'FGEM_CS';
    }
    elsif ( $de_type =~ /Reporter(?: *REF)?/i ) {
	$de_type = 'Reporter Identifier';
	$format  = 'FGEM';
    }

    if ( $format ) {
	$self->set_index_columns( [ 0 ] );
	$self->set_column_headings( [ $de_type, @harry2[1..$#harry2] ] );
	$self->set_heading_qts( [ @harry2[1..$#harry2] ] );
    }
    $self->set_format_type( $format || 'Unknown' );

    return;
}

####################
# Accessor methods #
####################

#####################
# Generic accessors #
#####################

{
    ## no critic ProhibitNoStrict
    no strict qw(refs);
    ## use critic ProhibitNoStrict

    # Create the integer incrementors here
    while (my ($method, $hash) = each %incr_integer_attr) {
	*{"increment_$method"} = sub {
            my ( $self, $value ) = @_;
            $value = 1 unless defined($value);
            looks_like_number($value)
                or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );
            $hash->{ident $self} += $value;
            return $hash->{ident $self};
	};
    }

    # Create the accumulative arrayref accessors here
    while (my ($method, $hash) = each %accum_hashref_attr) {
	*{"get_$method"} = sub {    # Returns arrayref
            my $self = shift;
            return [ sort keys %{ $hash->{ident $self} } ];
	};
        *{"add_$method"} = sub {    # Push on assignment (i.e. add to
                                    # old).
            my $self = shift;

	    confess( $CONFIG->get_ERROR_MESSAGE_ARGS() ) unless scalar(@_);

	    foreach (@_) {
		$hash->{ident $self}{$_}++;
            }
            return [ sort keys %{ $hash->{ident $self} } ];
        };
    }
}

################################
# Specialized accessor methods #
################################

sub get_filehandle {

    my $self = shift;

    unless ( $filehandle{ident $self} ) {
	croak("Error: file path not set") unless $self->get_path();
	$filehandle{ident $self} = IO::File->new($self->get_path(), '<');
    }

    return $filehandle{ident $self};
}

sub get_is_binary {

    my $self = shift;

    if (! defined($self->get_path())) {
	croak("Error: Datafile path not set.\n");
    }
    elsif (! -r $self->get_path() ) {
	croak("Error: cannot read file " . $self->get_path . "\n");
    }
    $is_binary{ident $self} = -B $self->get_path() ? 1 : 0;

    return $is_binary{ident $self};
}

sub get_md5_digest {

    my $self = shift;

    unless ( $md5_digest{ident $self} ) {
	$self->set_md5_digest( $self->calculate_md5_digest() );
    }

    return $md5_digest{ident $self};
}

sub calculate_md5_digest : PRIVATE {

    my ( $self ) = @_;

    my $fh = $self->get_filehandle();

    my $pos = tell( $fh );

    # NOTE that we only ever use seek/read on binary files (don't mix
    # these with sysseek/sysread) because other operations use seek
    # elsewhere. Note that the Affymetrix file parsers use sys*
    # functions exclusively though.
    seek( $fh, 0, 0 )
	or croak("Error: Unable to rewind binary file for hashing.");

    my $md5 = Digest::MD5->new();
    my $chunk;
    my $chunksize = 65536;    # 64k for reasonable efficiency (untested though).
    while ( my $bytes = read( $fh, $chunk, $chunksize ) ) {
	$md5->add( $chunk );
    }

    seek( $fh, $pos, 0 )
	or croak("Error: Unable to reset binary filehandle after hashing.");

    return $md5->hexdigest();
}

sub add_factor_value {

    # Takes (category, value); returns hash ref; category => [value1, value2]
    my ( $self, $category, $value ) = @_;

    # Check the already-assigned FVs for this category, add if not
    # present.
    $factor_value{ident $self}{$category} ||= [];
    my $found = first { $value eq $_ }
	@{ $factor_value{ident $self}{$category} };
    push( @{ $factor_value{ident $self}{$category} }, $value )
	unless $found;

    return $factor_value{ident $self};
}

sub set_ded_type {    # string

    my ( $self, $type ) = @_;

    confess( $CONFIG->get_ERROR_MESSAGE_ARGS() ) unless defined($type);

    unless ( any { $type eq $_ }
		 qw(Feature Reporter CompositeSequence) ) {
	confess(qq{Unrecognized DesignElement class "$type".});
    }
    $ded_type{ident $self} = $type;

    return $ded_type{ident $self};
}

sub set_format_type {    # string (enum: various as set in Config.pm,
                         # "Affymetrix" and "Unknown")

    my ( $self, $type ) = @_;

    confess( $CONFIG->get_ERROR_MESSAGE_ARGS() ) unless defined($type);

    my @allowed_types = qw(Unknown Affymetrix);
    foreach my $constant (
	$CONFIG->get_T2M_INDICES()
    ) {
	push( @allowed_types, keys %$constant );
    }
    unless ( any { $type eq $_ } @allowed_types ) {
	confess("Unrecognized format type $type");
    }
    $format_type{ident $self} = $type;

    return $format_type{ident $self};
}

sub set_data_type {    # string (enum)

    my ( $self, $type ) = @_;

    confess( $CONFIG->get_ERROR_MESSAGE_ARGS() ) unless defined($type);

    my @allowed_types = (
	@{ $CONFIG->get_T2M_FILE_TYPES() },
	$CONFIG->get_FGEM_FILE_TYPE(),
	$CONFIG->get_RAW_DM_FILE_TYPE(),
	qw(EXP),
    );
    unless ( any { $type eq $_ } @allowed_types ) {
	confess("Unrecognized data type $type");
    }
    $data_type{ident $self} = $type;

    return $data_type{ident $self};
}

sub set_name {    # string; filename only. Sets path if not otherwise set

    my ( $self, $name ) = @_;

    confess( $CONFIG->get_ERROR_MESSAGE_ARGS() ) unless defined($name);

    ref $name and confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );
    $name{ident $self} = $name;
    $self->set_path( File::Spec->rel2abs( $name ) )
	unless $self->get_path();

    return $name{ident $self};
}

sub set_exp_data {    # complex hash ref
    my ( $self, $data ) = @_;

    confess( $CONFIG->get_ERROR_MESSAGE_ARGS() ) unless defined($data);

    ref $data eq 'HASH'
	or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );

    $exp_data{ident $self} = $data;

    $self->set_is_exp(1);
    $self->set_format_type('Affymetrix');
    $self->set_data_type('EXP');

    return $exp_data{ident $self};
}

sub set_mage_qtd {

    my ( $self, $qtd ) = @_;

    confess( $CONFIG->get_ERROR_MESSAGE_ARGS() ) unless defined($qtd);

    $qtd->isa('Bio::MAGE::BioAssayData::QuantitationTypeDimension')
	or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );
    $mage_qtd{ident $self} = $qtd;

    return $mage_qtd{ident $self};
}

###################
# Private methods #
###################

sub _get_blocks : PRIVATE {

    my ( $self ) = @_;

    local $INPUT_RECORD_SEPARATOR = $self->get_linebreak_type();

    my $input_fh = $self->get_filehandle()
	or croak("Error: Unable to retrieve filehandle.");

    openhandle($input_fh) or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );

    my $blocks = [];

    my $saved_position = tell($input_fh);

    # Text::CSV_XS not appropriate here - bad data can crash it too easily.
    while ( my $line = <$input_fh> ) {

        $line =~ s/$RE_LINE_BREAK//xms;
        next if ($line=~/^End Raw Data/i);
        next if ($line=~/^End of File/i);
        
        my @line_array = split /\t/, $line, -1;

        my $row_coords = $self->_get_row_coords( \@line_array );
        $blocks
            = _update_blocks( $blocks, \@line_array, $self->get_index_columns() );

    }

    seek( $input_fh, $saved_position, 0 );

    return $blocks;

}

sub _update_blocks : PRIVATE {    # Updated for Scanalyze

    my ( $blocks, $line_array, $indexcols ) = @_;

    ref $blocks eq 'ARRAY'
        or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );
    ref $line_array eq 'ARRAY'
        or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );
    ref $indexcols eq 'ARRAY'
        or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );

    my $block_num = $line_array->[ $indexcols->[0] ];
    # Remove extra text (e.g. from imagene files)
    $block_num =~ s/Block//ixms;
    
    my $x         = $line_array->[ $indexcols->[3] ];
    my $y         = $line_array->[ $indexcols->[4] ];
    $blocks->[$block_num]{max_x} ||= $x;
    $blocks->[$block_num]{max_x} = $x
        if ( $blocks->[$block_num]{max_x} < $x );

    $blocks->[$block_num]{min_x} ||= $x;
    $blocks->[$block_num]{min_x} = $x
        if ( $blocks->[$block_num]{min_x} > $x );

    $blocks->[$block_num]{max_y} ||= $y;
    $blocks->[$block_num]{max_y} = $y
        if ( $blocks->[$block_num]{max_y} < $y );

    $blocks->[$block_num]{min_y} ||= $y;
    $blocks->[$block_num]{min_y} = $y
        if ( $blocks->[$block_num]{min_y} > $y );

    return $blocks;

}

sub _get_row_coords : PRIVATE {

    my ( $self, $line_array ) = @_;

    ref $line_array eq 'ARRAY'
        or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );

    my $row_coords = [];
    my $format_type = $self->get_format_type();

    # Affy has yet to be sorted out FIXME - will probably use
    # composite/reporter IDs, not feature coordinates
    if ( $format_type eq 'Affymetrix' ) {
	return $row_coords;
    }

    # Strip out whitespace, initiate undef indices
    foreach my $index ( @{ $self->get_index_columns() } ) {

        # Prevent warnings about uninitiated indices
        $line_array->[$index] = q{} unless defined( $line_array->[$index] );
        $line_array->[$index] =~ s/$RE_SURROUNDED_BY_WHITESPACE/$1/xms
	    unless $self->get_is_miamexpress();
    }

    # Simple for Generic MetaColumn/MetaRow/Column/Row format files
    if ( first { $format_type eq $_ } qw(Generic
					 FGEM
					 FGEM_CS
					 GEO
					 AffyNorm) ) {

        foreach my $index ( @{ $self->get_index_columns() } ) {
            push @$row_coords, $line_array->[$index];
        }

        return $row_coords;    # MC/MR/C/R or FGEM
    }

    # Make preparations for converting GenePix/Scanalyze coordinates to
    # Generic ones.  @blocks is an array of hashes, $blocks[$block_num]
    # = {max_x => "highest x coordinate in the block"} This is processed
    # later in the subroutine
    if ( first { $format_type eq $_ } qw(GenePix Scanalyze ImaGene7 ImaGeneFields) ) {

        foreach my $index ( @{ $self->get_index_columns() }[ 0 .. 2 ] ) {
        	# Remove text from block number (imagene fields often include this)
        	$line_array->[$index] =~ s/Block//ixms;
            push @$row_coords, $line_array->[$index];
        }

        return $row_coords;
    }    # B/C/R; will convert below

    # This should never happen:
    croak(
	sprintf(
	    "Error: Unknown file type %s Internal script error in sub _get_row_coords.\n",
	    $format_type,
	)
    );
}

sub _parse_datarows : PRIVATE {    # Generic, Affymetrix and FGEM/FGEM_CS only

    my ( $self ) = @_;

    local $INPUT_RECORD_SEPARATOR = $self->get_linebreak_type();

    my $input_fh = $self->get_filehandle()
	or croak("Error: Unable to retrieve filehandle.");

    openhandle($input_fh) or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );

    my $rc = q{};

    # We do the data metrics thing on a hashref rather than using
    # expensive method calls.
    my $metrics     = $self->get_data_metrics();
    my $format_type = $self->get_format_type();
    my $headings    = $self->get_column_headings;

    # Initialise some values in our data summary hashref, $metrics
    foreach my $heading ( keys %{$metrics} ) {
        $metrics->{$heading}{max}     = -4294967295;    # 2^32 - 1
        $metrics->{$heading}{min}     = 4294967295;
        $metrics->{$heading}{benford} = 0;
    }

    # Now we process the remainder of the data lines. This while loop is
    # where the script spends the vast majority of its time so we want
    # to be quite careful here.

    # We may want to skip columns, e.g. if there's no heading at all:
    my %bad_column;
    my @feature_coords;

    # The line numbers to use for file-vs-file comparisons.
    my %selected_line_no = map {$_ => 1} (3, 4, 6, 7, 9, 31, 33, 35, 37, 39);

    # For Pearson and the like
    my %intensity_vector;
    my $notnull = 0;

    DATA_LINE:
    while ( my $line = <$input_fh> ) {

        # just to be doubly sure about DOS-style line endings
        $line =~ s/$RE_LINE_BREAK//xms;

        # Prevent run-on into the mask/outlier sections of Affy CEL files
        last DATA_LINE
            if ( $format_type eq 'Affymetrix'
            && ( $line =~ $RE_EMPTY_STRING ) );

        # Increment the counter, take a line where selected
	my $current_row = $self->increment_row_count();
        if ( $selected_line_no{$current_row} ) {
	    my $test_vector = $self->get_test_data_line()
		            . md5_hex($line);
	    $self->set_test_data_line($test_vector)
        }

        # Check for empty lines (typically the last one). These are
        # typically not major problems, so we just print to error_fh.
        if ( $line =~ $RE_EMPTY_STRING ) {
            printf {$self->get_error_fh()} (
		"Warning: Blank line at data row %s in file %s\n",
		$self->get_row_count(),
                $self->get_path(),
	    );
            next DATA_LINE;
        }

        # We skip column-wise checks (percent null, Benford's law,
        # Pearson's) checks for Affy CELv3. This gives an approx. 4x
        # increase in speed.
        next DATA_LINE if ( $format_type eq 'Affymetrix' );

        # Negative LIMIT preserves trailing empty values
        my @line_array = split /\t/, $line, -1;

        # Get the row coordinates. We will fix these below; we can't do it
        # on the fly because e.g. for GenePix we need some global data
        # before we can tell where the blocks fit into the
        # MetaColumn-MetaRow format.
        my $row_coords = $self->_get_row_coords( \@line_array );

        # Transform arrayref into .-delimited string (this is slightly
        # better memory-wise than an AoA).
        if (@$row_coords) {
            my $coord_string = join( '.', @$row_coords );
            push( @feature_coords, $coord_string );
        }

        # Now we take a look at the data

        my %measured_data;    # channel => intensity value
        my $colno = -1;       # kludgey but better than the alternative

        COLUMN_VALUE:
        foreach my $value (@line_array) {

            # Check we haven't already marked this column as bad.
            $colno++;    # first column is zero in the @column_headings array
            next COLUMN_VALUE if ( $bad_column{$colno} );

            my $heading = $headings->[$colno];

            # Quick check that we're not on the brink of disaster (data in
            # columns with no headings)
            if ( !defined($heading) && defined($value) ) {
                $rc .= "ERROR: data in column "
                    . ( $colno + 1 )
                    . " has no column heading!\n";
                $bad_column{$colno}++;
                next COLUMN_VALUE;
            }

            # Skip if the column has no attributes.
            next COLUMN_VALUE unless $metrics->{$heading};

            # We also skip if the column contains non-numeric values (and
            # flag up an error!)  This tests for the general form of a
            # number.

            # It's okay if this is meant to be a string, set error flag if not
            if ( $metrics->{$heading}{datatype}
                && ( $metrics->{$heading}{datatype} eq 'string_datatype' ) ) {
                $notnull++;
                next COLUMN_VALUE;    # no further analysis on string values.
            }

            # Screen out unexpected null and string values here.
            unless ( looks_like_number($value) ) {
                my $error_message;
                if ( $value eq q{} ) {
                    $error_message = 'Null in numeric data field';
                }
                else {
                    $error_message = 'Text in numeric data field';
                }
                $metrics->{$heading}{errors}{$error_message}++;
                next COLUMN_VALUE;
            }

            # Update maximum and minimum values on a per-column basis
            if ( $value < $metrics->{$heading}{min} ) {
                $metrics->{$heading}{min} = $value;
            }
            elsif ( $value > $metrics->{$heading}{max} ) {
                $metrics->{$heading}{max} = $value;
            }

            # Check that boolean values are 0 or 1
            if (   $metrics->{$heading}{datatype}
                && ( $metrics->{$heading}{datatype} eq 'boolean' )
                && ( $value != 1 )
                && ( $value != 0 ) ) {

                my $error_message = 'Boolean value not 0 or 1';
                $metrics->{$heading}{errors}{$error_message}++;

            }

            # These next few things need an actual value to work on
            # (i.e. not zero at this point)
            unless ( $value == 0 ) {

                $notnull++;    # We count zeroes as nulls, at least for now

                # Check for floats vs. integers.
                if (

                    # not integer or boolean; presumably a float
                    ( int($value) != $value )

                    # in a column where it's not supposed to be
                    && ( $metrics->{$heading}{datatype} ne 'float' )
                    ) {
                    my $error_message = 'Floats in non-float data field';
                    $metrics->{$heading}{errors}{$error_message}++;
                }

                # Do the Benford's Law thing.
                # N.B. we only do this for floats that are declared as such
                # New and Improved - uses vec() for greater efficiency.

                # We just do this on MeasuredSignal and DerivedSignal.
                my $subclass = $metrics->{$heading}{subclass};
                if ( $subclass && $subclass =~ m/Signal/oxms ) {

                    # Strip out leading whitespace, zeros, minuses and
                    # decimal points.
                    $value =~ s/\A \s* [0.-]*//oxms;
                    my $first_char = substr( $value, 0, 1 );
                    vec( $metrics->{$heading}{benford}, $first_char, 32 )++;

                    # get intensities by channel
                    # MeasuredSignal (raw data) only, for now
                    if ( $subclass eq 'MeasuredSignal' ) {
                        $measured_data{ $metrics->{$heading}{channel} } +=
                            $metrics->{$heading}{is_background}
                            ? -$value
                            : $value;
                    }
                }
            }
        }

      # FIXME intensity vector capture currently inactivated - we're not
      # using it at all yet, and it adds to the memory overhead.
      #
      #    # Vector for Pearson correlation coefficient calculations
      #    # Ignore this if no suitable data found
      #    if (my $num_channels = scalar (grep defined, keys %measured_data)){

        #      my $measured_signal;
        #      if ($num_channels == 2){ # two-channel is a special case
        #	my ($numerator, $denominator) = sort keys %measured_data;

#	# Avoid illegal division by zero; the Pearson routines later will ignore non-numbers
#	$measured_signal = $measured_data{$denominator} ?
#	  ($measured_data{$numerator} / $measured_data{$denominator}) : 'NaN';
#      }
#      else { # one channel or >2 channel data is simply averaged
#	$measured_signal = sum(values %measured_data) / $num_channels;
#      }
#      my $row_id = join('.',@$row_coords);
#      $intensity_vector{$row_id} = $measured_signal;
#    }
    }

    # FIXME - see above for intensity vec comments
    #  $self->set_intensity_vector(\%intensity_vector);

    $self->increment_not_null($notnull);

    $self->set_data_metrics($metrics);

    return ( \@feature_coords, $rc );

}

sub _derive_consensus_software : PRIVATE {

    my ( $self, $QTs ) = @_;

    ref $QTs eq 'HASH' or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );

    my ( @file_qts );
    my $rc = q{};

    # Allow checks to omit already-recognized index columns, such as
    # the rather polymorphic ProbeSet ID for AffyNorm.
    my %is_index_heading = map { $_ => 1 }
	map { $self->get_column_headings()->[$_] }
           @{ $self->get_index_columns() };

    COLUMN_HEADING:
    foreach my $heading ( @{ $self->get_column_headings() } ) {

	# Skip index column headings.
	push( @file_qts, $heading ) unless ( $is_index_heading{ $heading } );
    }

    # Initialize our counters
    my $consensus = 'Unknown';
    my %count;
    foreach my $software ( keys %{$QTs}, $consensus ) {
        $count{$software} = 0;
    }
    my %recognized;

    # Do the count
    SOFTWARE_TYPE:
    foreach my $software ( keys %{$QTs} ) {

        foreach my $qt (@file_qts) {
        	if ( $QTs->{$software}{$qt} ){
                $count{$software}++;
                $recognized{$qt} = 1;
        	}
            $consensus = $software
                if ( $count{$software} > $count{$consensus} );
        }
    }
   
    # Check for ambiguity
    SOFTWARE_TYPE:
    foreach my $software ( keys %{$QTs} ) {

        # same-scoring softwares will be summarized as 'Ambiguous'; this
        # is thought to be better than randomly picking one of the
        # alternatives.
        if (   ( $count{$software} == $count{$consensus} )
            && ( $software ne $consensus )
            && $count{$consensus} ) {
            $consensus = 'Ambiguous';

            last SOFTWARE_TYPE;
        }
    }

    if ($consensus eq 'Ambiguous'){
        # If more QTs are unknown than known and sw is ambiguous leave type as unknown
        # Will prevent ambiguity error for very common QTs like "Flag" in 
        # otherwise non-standard files
        my $total = @file_qts;
        my $recognized_count = keys %recognized;
        my $unknown_count = $total-$recognized_count;
        
        if ($unknown_count > $recognized_count){
        	$consensus = 'Unknown';
        }
        else{
            print STDERR ( "WARNING: Ambiguous software type for file "
                    . $self->get_name()
                    . "\n" );
            $rc .= "Ambiguous QuantitationTypes;"
                . " unable to determine software type.\n";        	
        }  	
    }
       
    # Note down the kind of QTs we have
    $self->set_qt_type($consensus);

    # We want all the known QTs in data_metrics, not just the headings,
    # because some manufacturers have ConfidenceIndicators mapped to QTs
    # which don't appear in the data file.
    # Make sure we're making a deep copy of the relevant QT_hash
    # portion; otherwise this comes back to bite us later!
    my $known_qts =
        ( $QTs->{$consensus} && ( ref( $QTs->{$consensus} ) eq 'HASH' ) )
        ? dclone $QTs->{$consensus}
        : {};
    $self->set_data_metrics($known_qts);

    return $rc;
}

sub _average_block_dimension : PRIVATE {

    my ($blocks, $maxdim, $mindim) = @_;

    ref $blocks eq 'ARRAY'
        or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );
    defined ($maxdim) or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );
    defined ($mindim) or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );

    my $count = 0;
    my $total = 0;
    for ( my $block_num = 1; $block_num <= $#{$blocks}; $block_num++ ) {
        my $delta_y = $blocks->[$block_num]{$maxdim}
            - $blocks->[$block_num]{$mindim};

        if ( $delta_y > 10 ) {    # 10 here is arbitrary; sometimes blocks on
                                  # the same row have slightly different
                                  # Y-coords, and here we attempt not to count
                                  # them. The real results should hopefully
                                  # drown out the errors.
            $total += $delta_y;
            $count++;
        }
    }

    return ( $count ? ( $total / $count ) : 0 );    # avoid divide-by-zero

}

sub _average_block_height : PRIVATE {

    my ($blocks) = @_;

    ref $blocks eq 'ARRAY'
        or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );

    return _average_block_dimension($blocks, 'max_y', 'min_y');

}

sub _average_block_width : PRIVATE {

    my ($blocks) = @_;

    ref $blocks eq 'ARRAY'
        or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );

    return _average_block_dimension($blocks, 'max_x', 'min_x');

}

sub _slice_minus_discards : PRIVATE {

    my ($self) = @_;

    my %discards = map { $_ => 1 } @{ $self->get_index_columns() };
    my @slice;
    my $lastheading = $#{ $self->get_column_headings() };
    foreach ( 0 .. $lastheading ) {
        push( @slice, $_ ) unless $discards{$_};
    }

    return ( \@slice, $lastheading );

}

sub _fix_scanalyze : PRIVATE {

    my ( $self ) = @_;

    local $INPUT_RECORD_SEPARATOR = $self->get_linebreak_type();

    my $input_fh = $self->get_filehandle()
	or croak("Error: Unable to retrieve filehandle.");

    openhandle($input_fh) or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );

    # Store the start of the data, for use in cases where the SPOT
    # line is not found.
    my $init_pos = tell($input_fh);

    seek($input_fh, 0, 0) or croak("Error seeking in filehandle: $!");

    my $fixed_fh = IO::File->new_tmpfile;

    # Scan through the REMARKs and empty lines, and parse out the
    # mapping from channel to fluor, if we can. The first SPOT line is
    # the start of the data; however if it's not present we want to be
    # able to parse these data anyway.
    my $pos  = tell($input_fh);
    my $line = <$input_fh>;

    my $info = {};

    LINE:
    until ( $line =~ m/\A SPOT \b/xms ) {
        $pos  = tell($input_fh);    # Store the last-but-one line position
        $line = <$input_fh>;

        # End of file (prevent infinite loops in files without SPOT).
        unless ( defined $line ) {
	    $pos = $init_pos;
	    last LINE;
	}

        # Only Cy3/Cy5 and Alexa555/647 supported for now FIXME.
	#
	# We default to Cy3 or Alexa555 in CH1; this is to match the usage seen in
	# Stanford submissions.
	my ($channel, $fluor);
        if ( ( $channel, $fluor )
            = ( $line =~ m{ \b(\w+)\b \s+ IMAGE \s+ .* Cy.*([35]) }ixms ) ) {

            $info->{ lc($channel) } = ( $fluor == 3 ) ? "CH1" : "CH2";
        }
        elsif ( ( $channel, $fluor )
            = ( $line =~ m{ \b(\w+)\b \s+ IMAGE \s+ .* Alexa(555|647) }ixms ) ) {

            $info->{ lc($channel) } = ( $fluor == 555 ) ? "CH1" : "CH2";
        }
    }

    $self->_map_channel_to_fluor($info);

    seek( $input_fh, $pos, 0 )
        or croak("Error seeking in data file: $!\n");    # Back up one line

    my $blocks = $self->_get_blocks();

    # Block height is used below as a margin of error to cope with the
    # real-world fact that spotters don't run in perfect grids.
    # Likewise this approach is also imperfect.
    my $block_height = _average_block_height($blocks);

    # Construct a block -> MC/MR lookup table (this takes into account
    # the Y coord as well as X). Numbering is from the top left corner
    # of the grid.
    my $last_max_x             = 0;
    my $last_max_y             = 0;
    my $metacolumn             = 0;
    my $metarow                = 1;
    my $populated_x_grid       = 0;
    my $populated_y_grid       = 0;
    my $populated_x_coordinate = 0;

    foreach my $block ( @{$blocks}[ 1 .. $#$blocks ] ) {   # blocks start at 1

        if ( $block->{max_x} < $last_max_x ) {
            if ( $block->{max_y} < ( $last_max_y - ( $block_height / 2 ) ) ) {
                print {$self->get_error_fh()}
		    ("Error: Overlapping blocks in ScanAlyze array.\n");
            }

            else {    # X is less than in previous block, but Y is not.

                # The following checks whether the current block x coord is
                # less than the previous metablock max x coord.
                if ( $block->{max_x}
                    < ( $populated_x_coordinate - ( $block_height / 2 ) ) ) {

                    # If so, reset back to zero (full carriage return).
                    $populated_x_grid       = 0;
                    $populated_x_coordinate = 0;
                    $populated_y_grid       = $metarow;
                }

                # Set the metacolumn back to the end of the last completed
                # metablock, move down a row.
                $metacolumn = $populated_x_grid + 1;
                $metarow++;

            }
        }
        else {

            # Move across to the next metacolumn as normal; skip if we're
            # moving across to the next block.
            $metacolumn++
                unless (
                $block->{max_y} < ( $last_max_y - ( $block_height / 2 ) ) );
        }

        if ( $block->{max_y} < ( $last_max_y - ( $block_height / 2 ) ) ) {
            if ( $block->{max_x} < $last_max_x ) {
                print {$self->get_error_fh()}
		    ("Error: Overlapping blocks in ScanAlyze array.\n");
            }

            else {    # Y is less than in previous block, but X is not.

                # Update the completed metablock column info
                $populated_x_grid       = $metacolumn;
                $populated_x_coordinate = $block->{max_x};

                # Back up the metarow to the last completed metablock row,
                # move over to the appropriate metacolumn
                $metarow = $populated_y_grid + 1;
                $metacolumn++;
            }
        }
        else {

            # metarow stays the same (simple move of one block to the
            # right). This space left blank intentionally.
        }

        $block->{metarow}    = $metarow;
        $block->{metacolumn} = $metacolumn;

        $last_max_x = $block->{max_x};
        $last_max_y = $block->{max_y};

    }

    # Convert the GRID/COL/ROW coords into MC/MR/R/C

    # Set up an array slice base to use for the stripped array (faster
    # than strip_discards()).
    my ( $slice, $lastheading ) = $self->_slice_minus_discards;

    while ( my $line = <$input_fh> ) {

        $line =~ s/$RE_LINE_BREAK//xms;
        my @line_array = split /\t/, $line;

        my $block_num = $line_array[ $self->get_index_columns()->[0] ];
        # Remove extra text (e.g. from imagene files)
        $block_num =~ s/Block//ixms;
        
        my $column    = $line_array[ $self->get_index_columns()->[1] ];
        my $row       = $line_array[ $self->get_index_columns()->[2] ];

        my @rowslice = ( @$slice, ( $lastheading + 1 ) .. $#line_array );
        my $new_line = [ @line_array[@rowslice] ];

        my $metacolumn = $blocks->[$block_num]{metacolumn};
        my $metarow    = $blocks->[$block_num]{metarow};

        unshift( @$new_line, $metacolumn, $metarow, $column, $row );

        {
            no warnings qw(uninitialized);
            print $fixed_fh ( join( "\t", @$new_line ), $INPUT_RECORD_SEPARATOR );
        }

    }

    seek( $fixed_fh, 0, 0 ) or croak("Error seeking in data file: $!\n");

    $self->_genericize_fileinfo();

    return $fixed_fh;

}

sub _fix_genepix : PRIVATE {

    my ( $self ) = @_;

    local $INPUT_RECORD_SEPARATOR = $self->get_linebreak_type();

    my $input_fh = $self->get_filehandle()
	or croak("Error: Unable to retrieve filehandle.");

    openhandle($input_fh) or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );

    my $fixed_fh = IO::File->new_tmpfile;

    my $blocks = $self->_get_blocks();

    # Block width is used below as a margin of error to cope with
    # array designs with only one MetaColumn, and the real-world fact
    # that spotters don't run in perfect grids.  Likewise this
    # approach is also imperfect.
    my $half_block_width = _average_block_width($blocks) / 2;

    # Construct a block -> MC/MR lookup table
    my $last_max_x = 0;
    my $metacolumn = 0;
    my $metarow    = 1;
    foreach my $block ( @{$blocks}[ 1 .. $#$blocks ] ) {   # Blocks start at 1

        if ( $block->{max_x} < ($last_max_x + $half_block_width) ) {

	    # New MetaRow, "carriage return" for MetaColumn.
	    $metarow++;
	    $metacolumn = 0;
	}
        $metacolumn++;

        $block->{metarow}    = $metarow;
        $block->{metacolumn} = $metacolumn;

        $last_max_x = $block->{max_x}

    }

    # Convert the BCR coords into MC/MR/R/C

    # Set up an array slice base to use for the stripped array (faster
    # than strip_discards()).
    my ( $slice, $lastheading ) = $self->_slice_minus_discards;

    while ( my $line = <$input_fh> ) {

        $line =~ s/$RE_LINE_BREAK//xms;
        next if ($line=~/^End Raw Data/i);
        next if ($line=~/^End of File/i);
        
        my @line_array = split /\t/, $line;

        my $block_num = $line_array[ $self->get_index_columns()->[0] ];
        # Remove extra text (e.g. from imagene files)
        $block_num =~ s/Block//ixms;
        
        my $column    = $line_array[ $self->get_index_columns()->[1] ];
        my $row       = $line_array[ $self->get_index_columns()->[2] ];

        my @rowslice = ( @$slice, ( $lastheading + 1 ) .. $#line_array );
        my $new_line = [ @line_array[@rowslice] ];

        my $metacolumn = $blocks->[$block_num]{metacolumn};
        my $metarow    = $blocks->[$block_num]{metarow};

        unshift( @$new_line, $metacolumn, $metarow, $column, $row );

        {
            no warnings qw(uninitialized);
            print $fixed_fh ( join( "\t", @$new_line ), $INPUT_RECORD_SEPARATOR );
        }
    }

    seek( $fixed_fh, 0, 0 ) or croak("Error seeking in data file: $!\n");

    $self->_genericize_fileinfo();

    return $fixed_fh;

}

sub _fix_arrayvision : PRIVATE {

    my ( $self ) = @_;

    local $INPUT_RECORD_SEPARATOR = $self->get_linebreak_type();

    my $input_fh = $self->get_filehandle()
	or croak("Error: Unable to retrieve filehandle.");

    openhandle($input_fh) or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );

    my $fixed_fh = IO::File->new_tmpfile;

    # Set up an array slice base to use for the stripped array (faster
    # than strip_discards()).
    my ( $slice, $lastheading ) = $self->_slice_minus_discards;

    while ( my $line = <$input_fh> ) {

        $line =~ s/$RE_LINE_BREAK//xms;
        my @line_array = split /\t/, $line;

        my $primary   = $line_array[ $self->get_index_columns()->[0] ];
        my $secondary = $line_array[ $self->get_index_columns()->[1] ];

        # This format supplied by Elizabeth Herbolsheimer (WMIT)
        my ( $metarow, $metacolumn ) = ( $primary   =~ m/(\d+) - (\d+)/ );
        my ( $row,     $column )     = ( $secondary =~ m/(\d+) - (\d+)/ );

        my @rowslice = ( @$slice, ( $lastheading + 1 ) .. $#line_array );
        my $new_line = [ @line_array[@rowslice] ];

        unshift( @$new_line, $metacolumn, $metarow, $column, $row );

        {
            no warnings qw(uninitialized);
            print $fixed_fh ( join( "\t", @$new_line ), $INPUT_RECORD_SEPARATOR );
        }

    }

    seek( $fixed_fh, 0, 0 ) or croak("Error seeking in data file: $!\n");

    $self->_genericize_fileinfo();

    return $fixed_fh;
}

sub _fix_arrayvision_lg2 : PRIVATE {

    my ( $self ) = @_;

    local $INPUT_RECORD_SEPARATOR = $self->get_linebreak_type();

    my $input_fh = $self->get_filehandle()
	or croak("Error: Unable to retrieve filehandle.");

    openhandle($input_fh) or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );
    my $fixed_fh = IO::File->new_tmpfile;

    # Set up an array slice base to use for the stripped array (faster
    # than strip_discards()).
    my ( $slice, $lastheading ) = $self->_slice_minus_discards;

    # Flag to indicate whether we've found features or not.
    my $is_feature_level;

    # Process the file.
    while ( my $line = <$input_fh> ) {

        $line =~ s/$RE_LINE_BREAK//xms;
        my @line_array = split /\t/, $line;

        my $spotlabels = $line_array[ $self->get_index_columns()->[0] ];

	my @rowslice = ( @$slice, ( $lastheading + 1 ) .. $#line_array );
	my $new_line = [ @line_array[@rowslice] ];

	# If we have feature-level data, handle it here.
	if ( my @coords
	    = ($spotlabels =~ m/(\w+) ?- ?(\w+) ?: ?(\w+)(?: ?- ?(\w+))?/) ) {

	    # Strip out "R" and "C" from block-level coords.
	    my ($metarow)    = ($coords[0] =~ m/(\d)+/);
	    my ($metacolumn) = ($coords[1] =~ m/(\d)+/);

	    # Convert text coords into numbers (whose idiotic idea was this, anyway?).
	    my $row        = ord(uc($coords[2])) - 64;
	    my $column     = ord(uc($coords[3])) - 64;

	    unshift( @$new_line, $metacolumn, $metarow, $column, $row );

	    $is_feature_level = 1;
	}
	# Otherwise, we assume reporter-level data.
	else {
	    unshift( @$new_line, $spotlabels );
	    $is_feature_level = 0;
	}

	# Print out the reconstructed line; quell undef warnings.
        {
            no warnings qw(uninitialized);
            print $fixed_fh ( join( "\t", @$new_line ), $INPUT_RECORD_SEPARATOR );
        }

    }

    seek( $fixed_fh, 0, 0 ) or croak("Error seeking in data file: $!\n");

    if ( $is_feature_level ) {
	$self->_genericize_fileinfo();
    }
    else {
	$self->_reporter_genericize_fileinfo();
    }

    return $fixed_fh;
}

sub _fix_agilent : PRIVATE {

    my ( $self ) = @_;

    local $INPUT_RECORD_SEPARATOR = $self->get_linebreak_type();

    my $input_fh = $self->get_filehandle()
	or croak("Error: Unable to retrieve filehandle.");

    openhandle($input_fh) or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );
    my $fixed_fh = IO::File->new_tmpfile;

    # Set up an array slice base to use for the stripped array (faster
    # than strip_discards()).
    my ( $slice, $lastheading ) = $self->_slice_minus_discards;

    while ( my $line = <$input_fh> ) {

        $line =~ s/$RE_LINE_BREAK//xms;
        my @line_array = split /\t/, $line;

        my $row    = $line_array[ $self->get_index_columns()->[0] ];
        my $column = $line_array[ $self->get_index_columns()->[1] ];

        # We assume here that Agilent only prints their arrays in single
        # blocks
        my $metarow    = 1;
        my $metacolumn = 1;

        my @rowslice = ( @$slice, ( $lastheading + 1 ) .. $#line_array );
        my $new_line = [ @line_array[@rowslice] ];

        unshift( @$new_line, $metacolumn, $metarow, $column, $row );

        {
            no warnings qw(uninitialized);
            print $fixed_fh ( join( "\t", @$new_line ), $INPUT_RECORD_SEPARATOR );
        }

    }

    seek( $fixed_fh, 0, 0 ) or croak("Error seeking in data file: $!\n");

    $self->_genericize_fileinfo();

    return $fixed_fh;
}

sub _fix_nimblescanfeat : PRIVATE {

    my ( $self ) = @_;

    local $INPUT_RECORD_SEPARATOR = $self->get_linebreak_type();

    my $input_fh = $self->get_filehandle()
	or croak("Error: Unable to retrieve filehandle.");

    openhandle($input_fh) or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );
    my $fixed_fh = IO::File->new_tmpfile;

    # Set up an array slice base to use for the stripped array (faster
    # than strip_discards()).
    my ( $slice, $lastheading ) = $self->_slice_minus_discards;

    while ( my $line = <$input_fh> ) {

        $line =~ s/$RE_LINE_BREAK//xms;
        my @line_array = split /\t/, $line;

        my $column = $line_array[ $self->get_index_columns()->[0] ];
        my $row    = $line_array[ $self->get_index_columns()->[1] ];

        # Nimblegen, like Agilent, only prints their arrays in single
        # blocks
        my $metarow    = 1;
        my $metacolumn = 1;

        my @rowslice = ( @$slice, ( $lastheading + 1 ) .. $#line_array );
        my $new_line = [ @line_array[@rowslice] ];

        unshift( @$new_line, $metacolumn, $metarow, $column, $row );

        {
            no warnings qw(uninitialized);
            print $fixed_fh ( join( "\t", @$new_line ), $INPUT_RECORD_SEPARATOR );
        }

    }

    seek( $fixed_fh, 0, 0 ) or croak("Error seeking in data file: $!\n");

    $self->_genericize_fileinfo();

    return $fixed_fh;
}

sub _fix_nimblegennasa : PRIVATE {

    my ( $self ) = @_;

    local $INPUT_RECORD_SEPARATOR = $self->get_linebreak_type();

    my $input_fh = $self->get_filehandle()
	or croak("Error: Unable to retrieve filehandle.");

    openhandle($input_fh) or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );
    my $fixed_fh = IO::File->new_tmpfile;

    # Set up an array slice base to use for the stripped array (faster
    # than strip_discards()).
    my ( $slice, $lastheading ) = $self->_slice_minus_discards;

    while ( my $line = <$input_fh> ) {

        $line =~ s/$RE_LINE_BREAK//xms;
        my @line_array = split /\t/, $line;

        my $column = $line_array[ $self->get_index_columns()->[0] ];
        my $row    = $line_array[ $self->get_index_columns()->[1] ];

        # Nimblegen, like Agilent, only prints their arrays in single
        # blocks
        my $metarow    = 1;
        my $metacolumn = 1;

        my @rowslice = ( @$slice, ( $lastheading + 1 ) .. $#line_array );
        my $new_line = [ @line_array[@rowslice] ];

        unshift( @$new_line, $metacolumn, $metarow, $column, $row );

        {
            no warnings qw(uninitialized);
            print $fixed_fh ( join( "\t", @$new_line ), $INPUT_RECORD_SEPARATOR );
        }

    }

    seek( $fixed_fh, 0, 0 ) or croak("Error seeking in data file: $!\n");

    $self->_genericize_fileinfo();

    return $fixed_fh;
}

sub _fix_appliedbiosystems : PRIVATE {

    my ( $self ) = @_;

    local $INPUT_RECORD_SEPARATOR = $self->get_linebreak_type();

    my $input_fh = $self->get_filehandle()
	or croak("Error: Unable to retrieve filehandle.");

    openhandle($input_fh) or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );
    my $fixed_fh = IO::File->new_tmpfile;

    # Set up an array slice base to use for the stripped array (faster
    # than strip_discards()).
    my ( $slice, $lastheading ) = $self->_slice_minus_discards;

    while ( my $line = <$input_fh> ) {

        $line =~ s/$RE_LINE_BREAK//xms;
        my @line_array = split /\t/, $line;

        my $probe_id = $line_array[ $self->get_index_columns()->[0] ];

        my @rowslice = ( @$slice, ( $lastheading + 1 ) .. $#line_array );
        my $new_line = [ @line_array[@rowslice] ];

        unshift( @$new_line, $probe_id );

        {
            no warnings qw(uninitialized);
            print $fixed_fh ( join( "\t", @$new_line ), $INPUT_RECORD_SEPARATOR );
        }

    }

    seek( $fixed_fh, 0, 0 ) or croak("Error seeking in data file: $!\n");

    # FIXME this may actually be compseq, not reporter - depends on
    # array design TBA.
    $self->_reporter_genericize_fileinfo();

    $self->_strip_common_heading_suffixes();

    return $fixed_fh;
}

sub _fix_illumina_perhyb : PRIVATE {

    my ( $self ) = @_;

    # Generic Illumina fixes.
    my $fixed_fh = $self->_fix_illumina();

    # Per-hyb fixes. Don't strip suffixes if there's only one data column!
    my $num_datacols = scalar( @{ $self->get_column_headings() } )
	             - scalar( @{ $self->get_index_columns()   } );
    if ( $num_datacols > 1 ) {
	$self->_strip_common_heading_prefixes();
    }

    return $fixed_fh;
}

sub _fix_illumina : PRIVATE {

    my ( $self ) = @_;

    local $INPUT_RECORD_SEPARATOR = $self->get_linebreak_type();

    # Fix either per-hyb or FGEM Illumina data.
    my $input_fh = $self->get_filehandle()
	or croak("Error: Unable to retrieve filehandle.");

    openhandle($input_fh) or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );
    my $fixed_fh = IO::File->new_tmpfile;

    # Set up an array slice base to use for the stripped array (faster
    # than strip_discards()).
    my ( $slice, $lastheading ) = $self->_slice_minus_discards;

    while ( my $line = <$input_fh> ) {

        $line =~ s/$RE_LINE_BREAK//xms;
        my @line_array = split /\t/, $line;

        my $probe_id = $line_array[ $self->get_index_columns()->[0] ];

        my @rowslice = ( @$slice, ( $lastheading + 1 ) .. $#line_array );
        my $new_line = [ @line_array[@rowslice] ];

        unshift( @$new_line, $probe_id );

        {
            no warnings qw(uninitialized);
            print $fixed_fh ( join( "\t", @$new_line ), $INPUT_RECORD_SEPARATOR );
        }

    }

    seek( $fixed_fh, 0, 0 ) or croak("Error seeking in data file: $!\n");

    $self->_reporter_genericize_fileinfo();

    return $fixed_fh;
}

sub _strip_common_heading_prefixes : PRIVATE {

    my $self = shift;

    # Common suffixes contain metainfo; we don't want them in our
    # internal QT processing. Here we strip them out.
    my @headings = @{ $self->get_column_headings() };
    my $identifier_col = shift @headings;    # Drop the identifier column.
    my $prefix         = q{};

    # Adapted from similar code by Albannach on perlmonks.org node 274134
    CHAR:
    for my $length ( 1 .. length( $headings[0] ) ) {
        $prefix = substr( $headings[0], 0, $length - 1 );
        last CHAR unless ( scalar grep {/^\Q$prefix\E/} @headings ) == @headings;
    }

    # We've gone one CHAR too far - strip off the last character:
    chop $prefix;

    # Remove the suffix from all the headings.
    foreach my $heading (@headings) {
        $heading =~ s/^\Q$prefix\E//;
    }
    $self->set_column_headings( [ $identifier_col, @headings ] );

    return;
}

sub _strip_common_heading_suffixes : PRIVATE {

    my $self = shift;

    # Common suffixes contain metainfo; we don't want them in our
    # internal QT processing. Here we strip them out.
    my @headings = @{ $self->get_column_headings() };
    my $identifier_col = shift @headings;    # Drop the identifier column.
    my $suffix         = q{};

    # Adapted from similar code by Albannach on perlmonks.org node 274134
    CHAR:
    for my $length ( 1 .. length( $headings[0] ) ) {
        $suffix = substr( $headings[0], -($length), $length );
        last CHAR unless ( scalar grep {/\Q$suffix\E$/} @headings ) == @headings;
    }

    # We've gone one CHAR too far - strip off the first character:
    substr( $suffix, 0, 1, q{} );

    # Remove the suffix from all the headings.
    foreach my $heading (@headings) {
        $heading =~ s/\Q$suffix\E$//;
    }
    $self->set_column_headings( [ $identifier_col, @headings ] );

    return;
}

sub _scanarray_parse_image : PRIVATE {

    my ( $self ) = @_;

    local $INPUT_RECORD_SEPARATOR = $self->get_linebreak_type();

    my $input_fh = $self->get_filehandle()
	or croak("Error: Unable to retrieve filehandle.");

    openhandle($input_fh) or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );
    my $line = <$input_fh>;
    my @info_headings = split /\t/, $line;
    my %info;

    IMAGE_LINE:
    while ( $line = lc(<$input_fh>) ) {
        last IMAGE_LINE if ( $line =~ m/\A end [ ]/ixms );

        my @info_data = split /\t/, $line, -1;

        my ( $channel, $dye, $fallback );
        for ( my $i = 0; $i <= $#info_headings; $i++ ) {

	    # Skip blank values.
	    next unless $info_data[$i];

            $channel = $info_data[$i]
                if ( $info_headings[$i] =~ m/channel/ixms );
            $dye = $info_data[$i]
                if ( $info_headings[$i] =~ m/fluorophore?/ixms );

	    # Fall back to image file name (dubious FIXME).
            $fallback ||= $info_data[$i]
                if ( $info_headings[$i] =~ m/image/ixms );
        }

	# Attempt some smart matching on the results.
	my $cy3_regexp = qr/ cy (?:anine?)? [-_ ]* 3/ixms;
	my $cy5_regexp = qr/ cy (?:anine?)? [-_ ]* 5/ixms;
        if ($dye) {
            $dye = 'Cy3' if ( $dye =~ $cy3_regexp );
            $dye = 'Cy5' if ( $dye =~ $cy5_regexp );

            $info{$channel} = $dye;
        }
	elsif ( $fallback ) {

	    # This is a fairly desperate measure. We try to guess the
	    # label used from the image filename.
	    my $label;
            $label = 'Cy3' if ( $fallback =~ $cy3_regexp );
            $label = 'Cy5' if ( $fallback =~ $cy5_regexp );

            $info{$channel} = $label;
	}
    }
    return \%info;
}

sub _scanarray_parse_measurements : PRIVATE {

    my ( $self ) = @_;

    local $INPUT_RECORD_SEPARATOR = $self->get_linebreak_type();

    my $input_fh = $self->get_filehandle()
	or croak("Error: Unable to retrieve filehandle.");

    openhandle($input_fh) or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );
    # Read in any measurements, if present
    my %measurements;
    my @measurement_headings = @{ $self->get_column_headings() };

    MEASUREMENT_LINE:
    while ( my $line = <$input_fh> ) {

        last MEASUREMENT_LINE if ( $line =~ m/\A end [ ]/ixms );

        $line =~ s/$RE_LINE_BREAK//xms;
        my @line_array = split /\t/, $line;

        my $metacolumn = $line_array[ $self->get_index_columns()->[0] ];
        my $metarow    = $line_array[ $self->get_index_columns()->[1] ];
        my $column     = $line_array[ $self->get_index_columns()->[2] ];
        my $row        = $line_array[ $self->get_index_columns()->[3] ];

        for ( my $i = 0; $i <= $#{ $self->get_column_headings() }; $i++ ) {
            $measurements{"$metacolumn.$metarow.$column.$row"}
                { $self->get_column_headings()->[$i] } = $line_array[$i];
        }
    }
    return ( \%measurements, \@measurement_headings );
}

sub _parse_scanarray_header : PRIVATE {

    # Input filehandle should be set to the start of the DATA section
    # (immediately after the header line) upon exit from this sub.

    my ( $self, $content_start ) = @_;

    local $INPUT_RECORD_SEPARATOR = $self->get_linebreak_type();

    my $input_fh = $self->get_filehandle()
	or croak("Error: Unable to retrieve filehandle.");

    openhandle($input_fh) or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );

    my $info                 = {};
    my $measurements         = {};
    my $measurement_headings = [];
    seek( $input_fh, 0, 0 ) or croak("Error seeking in data file: $!\n");

    HEADER_LINE:
    while ( my $line = <$input_fh> ) {

        # Check we've not run past the first set of headers
        # (measurement or data). Sometimes DATA starts without a BEGIN
        # DATA tag.
        if ( tell($input_fh) > $content_start ) {
            seek( $input_fh, $content_start, 0 )
                or croak("Error seeking in data file: $!\n");
            last HEADER_LINE;
        }

        # Parse the various block types.
        if ( my ($data_block_type) = ( $line =~ m/\A begin [ ] (\w*)/ixms ) )
        {

            # Image info present in header, parse ready for
            # re-assigning QTs.
            ( $data_block_type =~ m/image/ixms ) && do {
                $info = $self->_scanarray_parse_image();
            };

            # Header contains measurements block as first parsable
            # header row; parse it into the measurement variables.
            ( $data_block_type =~ m/measurements/ixms ) && do {
                seek( $input_fh, $content_start, 0 )
                    or croak("Error seeking in data file: $!\n");
                ( $measurements, $measurement_headings )
                    = $self->_scanarray_parse_measurements();

                # The $file object currently thinks the measurement
                # section is the start of the data. Re-parse to find
                # the DATA section.
                $self->parse_header();
                last HEADER_LINE;
            };

            # Data block is the first parsable header row; seek to the
            # top of the content (DATA) section, drop out of the
            # header loop.
            ( $data_block_type =~ m/data/ixms ) && do {
                seek( $input_fh, $content_start, 0 )
                    or croak("Error seeking in data file: $!\n");
                last HEADER_LINE;
            };
        }
    }
    return ( $info, $measurements, $measurement_headings );
}

sub _fix_scanarray : PRIVATE {

    my ( $self ) = @_;

    local $INPUT_RECORD_SEPARATOR = $self->get_linebreak_type();

    my $input_fh = $self->get_filehandle()
	or croak("Error: Unable to retrieve filehandle.");

    openhandle($input_fh) or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );
    # Figure out which channel is which from the file header, detect
    # measurements if present
    my $content_start = tell($input_fh);

    # Check the header for image/channel/fluorophore info. Set the
    # input_fh to the top of the DATA section.
    my ( $info, $measurements, $measurement_headings )
        = $self->_parse_scanarray_header( $content_start );

    # Reformat the coordinates in the data section
    my $fixed_fh = IO::File->new_tmpfile;

    my %data_headings = map { $_ => 1 } @{ $self->get_column_headings() };

    # Set up an array slice base to use for the stripped array (faster
    # than strip_discards()).
    my ( $slice, $lastheading ) = $self->_slice_minus_discards;

    DATA_LINE:
    while ( my $line = <$input_fh> ) {

        last DATA_LINE if ( $line =~ m/\A end [ ]/ixms );

        $line =~ s/$RE_LINE_BREAK//xms;
        my @line_array = split /\t/, $line;

        my $metacolumn = $line_array[ $self->get_index_columns()->[0] ];
        my $metarow    = $line_array[ $self->get_index_columns()->[1] ];
        my $column     = $line_array[ $self->get_index_columns()->[2] ];
        my $row        = $line_array[ $self->get_index_columns()->[3] ];

        my @rowslice = ( @$slice, ( $lastheading + 1 ) .. $#line_array );
        my $new_line = [ @line_array[@rowslice] ];

        # Add measurement columns where they're missing from the data section
        if ( my $header_row
            = $measurements->{"$metacolumn.$metarow.$column.$row"} ) {
            foreach my $measurement ( sort keys %$header_row ) {
                push( @$new_line, $header_row->{$measurement} )
                    unless ( $data_headings{$measurement} );
            }
        }

        unshift( @$new_line, $metacolumn, $metarow, $column, $row );

        {
            no warnings qw(uninitialized);
            print $fixed_fh ( join( "\t", @$new_line ), $INPUT_RECORD_SEPARATOR );
        }

    }

    # Fix the measurement headings, if we have them
    foreach my $measurement ( sort @$measurement_headings ) {
        push( @{ $self->get_column_headings() }, $measurement )
            unless ( $data_headings{$measurement} );
    }

    $self->_map_channel_to_fluor($info);

    $self->_genericize_fileinfo();

    # Check that there's no data we're missing
    FOOTER_LINE:
    while ( my $line = <$input_fh> ) {
        if ( $line =~ m/\S/xms && $line !~ m/filter/ixms )
        {    # Any non-whitespace
            print {$self->get_error_fh()} (
                "WARNING: Possible data after END DATA marker is being discarded.\n"
            );
            last FOOTER_LINE;
        }
    }

    seek( $fixed_fh, 0, 0 ) or croak("Error seeking in data file: $!\n");

    return $fixed_fh;

}

sub _map_channel_to_fluor : PRIVATE {

    my ( $self, $info ) = @_;

    ref $info eq 'HASH' or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );

    my $warning_given;

    # Fix the column headings
    HEADING:
    foreach my $heading ( @{ $self->get_column_headings() } ) {

        my ($wanted) = ( $heading =~ m/\A (ch\d+) [ a-z]/ixms )
            or next HEADING;
        $wanted = lc($wanted);

        unless ( $info->{$wanted} ) {
            unless ( $warning_given->{$wanted} ) {
                print {$self->get_error_fh()} (
                    "Warning: unable to parse channel $wanted to fluorophore mapping from file header.\n"
                );
                $warning_given->{$wanted}++;
            }
            next HEADING;
        }

        $heading =~ s/\A $wanted/$info->{$wanted}/iexms;

    }

    return;
}

sub _fix_simple_mcmr : PRIVATE {

    # A generic method to fix files in which the index columns 0..3
    # are MetaColumn, MetaRow, Column, Row in that order (this is
    # controled by the T2M_INDICES option in Config.pm).

    my ( $self ) = @_;

    local $INPUT_RECORD_SEPARATOR = $self->get_linebreak_type();

    my $input_fh = $self->get_filehandle()
	or croak("Error: Unable to retrieve filehandle.");

    openhandle($input_fh) or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );
    my $fixed_fh = IO::File->new_tmpfile;

    # Set up an array slice base to use for the stripped array (faster
    # than strip_discards()).
    my ( $slice, $lastheading ) = $self->_slice_minus_discards;

    while ( my $line = <$input_fh> ) {

        $line =~ s/$RE_LINE_BREAK//xms;
        my @line_array = split /\t/, $line;

        my $metacolumn = $line_array[ $self->get_index_columns()->[0] ];
        my $metarow    = $line_array[ $self->get_index_columns()->[1] ];
        my $column     = $line_array[ $self->get_index_columns()->[2] ];
        my $row        = $line_array[ $self->get_index_columns()->[3] ];

        my @rowslice = ( @$slice, ( $lastheading + 1 ) .. $#line_array );
        my $new_line = [ @line_array[@rowslice] ];

        unshift( @$new_line, $metacolumn, $metarow, $column, $row );

        {
            no warnings qw(uninitialized);
            print $fixed_fh ( join( "\t", @$new_line ), $INPUT_RECORD_SEPARATOR );
        }

    }

    seek( $fixed_fh, 0, 0 ) or croak("Error seeking in data file: $!\n");

    $self->_genericize_fileinfo();

    return $fixed_fh;
}

sub _fix_spotfinder : PRIVATE {

    my ( $self ) = @_;

    my $fixed_fh = $self->_fix_simple_mcmr();
}

sub _fix_mev : PRIVATE {

    my ( $self ) = @_;

    my $fixed_fh = $self->_fix_simple_mcmr();
}

sub _fix_bluefuse : PRIVATE {

    # Note that ideally we would also fix the CH1/CH2 QTs to point to
    # fluors FIXME (the problem is that there's no standard tag for this
    # in the files).

    my ( $self ) = @_;

    my $fixed_fh = $self->_fix_simple_mcmr();

    return $fixed_fh;
}

sub _fix_ucsfspot : PRIVATE {

    my ( $self ) = @_;

    local $INPUT_RECORD_SEPARATOR = $self->get_linebreak_type();

    my $input_fh = $self->get_filehandle()
	or croak("Error: Unable to retrieve filehandle.");

    openhandle($input_fh) or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );
    my $fixed_fh = IO::File->new_tmpfile;

    # Set up an array slice base to use for the stripped array (faster
    # than strip_discards()).
    my ( $slice, $lastheading ) = $self->_slice_minus_discards;

    while ( my $line = <$input_fh> ) {

        $line =~ s/$RE_LINE_BREAK//xms;
        my @line_array = split /\t/, $line;

        my $metacolumn = $line_array[ $self->get_index_columns()->[0] ];
        my $metarow    = $line_array[ $self->get_index_columns()->[1] ];
        my $column     = $line_array[ $self->get_index_columns()->[2] ];
        my $row        = $line_array[ $self->get_index_columns()->[3] ];

        # Strip zero-padding
        $metacolumn =~ s/^0+// if defined($metacolumn);
        $metarow    =~ s/^0+// if defined($metarow);
        $column     =~ s/^0+// if defined($column);
        $row        =~ s/^0+// if defined($row);

        my @rowslice = ( @$slice, ( $lastheading + 1 ) .. $#line_array );
        my $new_line = [ @line_array[@rowslice] ];

        unshift( @$new_line, $metacolumn, $metarow, $column, $row );

        {
            no warnings qw(uninitialized);
            print $fixed_fh ( join( "\t", @$new_line ), $INPUT_RECORD_SEPARATOR );
        }

    }

    seek( $fixed_fh, 0, 0 ) or croak("Error seeking in data file: $!\n");

    $self->_genericize_fileinfo();

    return $fixed_fh;
}

sub _fix_csiro_spot : PRIVATE {

    my ( $self ) = @_;

    my $fixed_fh = $self->_fix_simple_mcmr();

    return $fixed_fh;
}

sub _fix_imagene : PRIVATE {

    my ( $self ) = @_;

    local $INPUT_RECORD_SEPARATOR = $self->get_linebreak_type();

    my $input_fh = $self->get_filehandle()
	or croak("Error: Unable to retrieve filehandle.");
    openhandle($input_fh) or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );

    # Try and determine which label was used from the file header.
    my $label;
    my $content_start = tell($input_fh);
    seek($input_fh, 0, 0) or croak("Error rewinding file for input: $!");
    HEADERLINE:
    while (my $line = <$input_fh>) {

	# Skip if at the end of the header.
	if (tell($input_fh) > $content_start) {
	    seek($input_fh, $content_start, 0)
		or croak("Error resetting filehandle to data section: $!");
	    last HEADERLINE;
	}

	# Dye info only in filename (if then!)
	if ( $line =~ m/\bImage File\b/ ) {
	    ($label) = ($line =~ m/(?:\b|_) (cy[35]|alexa\d{3}|green|red) (?:\b|_)/ixms);

	    # Fix casing issues.
	    if ($label) {
		$label =~ s/cy/Cy/i;
		$label =~ s/alexa/Alexa/i;
		$label =~ s/red/Cy5/i;
		$label =~ s/green/Cy3/i;
	    }
	}
    }
    if ($label) {
	my $columns = $self->get_column_headings();
	for (my $i = 0; $i <= $#{ $columns }; $i++) {

	    # Don't alter the index columns.
	    unless ( first { $i == $_ } @{ $self->get_index_columns() } ) {
		$columns->[$i] .= "_$label";
	    }
	}
	$self->set_column_headings($columns);
    }
    else {
	printf {$self->get_error_fh()} (
	    "Warning: Unable to determine channel assignment for file %s\n",
	    $self->get_name(),
	);
    }

    my $fixed_fh = $self->_fix_simple_mcmr();

    return $fixed_fh;
}

sub _imagene3_parse_measurements : PRIVATE {

    my ( $self ) = @_;

    local $INPUT_RECORD_SEPARATOR = $self->get_linebreak_type();

    my $input_fh = $self->get_filehandle()
	or croak("Error: Unable to retrieve filehandle.");

    openhandle($input_fh) or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );

    # Read in any measurements, if present
    my %measurements;
    my @measurement_headings = @{ $self->get_column_headings() };
    my $data_section_line;

    # No explicit "End" line, we have to spot the next "Begin" line
    # and backtrack.
    my $previous_line_loc = tell($input_fh);

    MEASUREMENT_LINE:
    while ( my $line = <$input_fh> ) {

         if ( $line =~ m/\A begin [ ]/ixms ) {
	     $data_section_line = $line;
	     last MEASUREMENT_LINE;
	 }
	$previous_line_loc = tell($input_fh);

        $line =~ s/$RE_LINE_BREAK//xms;
        my @line_array = split /\t/, $line;

        my $metacolumn = $line_array[ $self->get_index_columns()->[0] ];
        my $metarow    = $line_array[ $self->get_index_columns()->[1] ];
        my $column     = $line_array[ $self->get_index_columns()->[2] ];
        my $row        = $line_array[ $self->get_index_columns()->[3] ];

        for ( my $i = 0; $i <= $#{ $self->get_column_headings() }; $i++ ) {
            $measurements{"$metacolumn.$metarow.$column.$row"}
                { $self->get_column_headings()->[$i] } = $line_array[$i];
        }
    }

    # Rewind to the previous line.
    seek($input_fh, $previous_line_loc, 0);

    return ( \%measurements, \@measurement_headings, $data_section_line );
}

sub _parse_imagene3_header : PRIVATE {

    # Input filehandle should be set to the start of the DATA section
    # (immediately after the header line) upon exit from this sub.

    my ( $self, $content_start ) = @_;

    local $INPUT_RECORD_SEPARATOR = $self->get_linebreak_type();

    my $input_fh = $self->get_filehandle()
	or croak("Error: Unable to retrieve filehandle.");

    openhandle($input_fh) or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );

    my $measurements         = {};
    my $measurement_headings = [];
    my $data_section_line;
    seek( $input_fh, 0, 0 ) or croak("Error seeking in data file: $!\n");

    HEADER_LINE:
    while ( my $line = <$input_fh> ) {

        # Check we've not run past the first set of headers
        # (measurement or data). Sometimes DATA starts without a BEGIN
        # DATA tag.
        if ( tell($input_fh) > $content_start ) {
            seek( $input_fh, $content_start, 0 )
                or croak("Error seeking in data file: $!\n");
            last HEADER_LINE;
        }

        # Parse the various block types.
        if ( my ($data_block_type) = ( $line =~ m/\A begin [ ] (.*)/ixms ) )
        {

            # Header contains measurements block as first parsable
            # header row; parse it into the measurement variables.
            if ( $data_block_type =~ m/log [ ]+ ratio [ ]+ data/ixms ) {
                seek( $input_fh, $content_start, 0 )
                    or croak("Error seeking in data file: $!\n");
                ( $measurements, $measurement_headings, $data_section_line )
                    = $self->_imagene3_parse_measurements();

                # The $file object currently thinks the measurement
                # section is the start of the data. Re-parse to find
                # the DATA section.
                $self->parse_header();
                last HEADER_LINE;
            }

            # Data block is the first parsable header row; seek to the
            # top of the content (DATA) section, drop out of the
            # header loop.
            elsif ( $data_block_type =~ m/extracted [ ] data/ixms ) {
		$data_section_line = $line;
                seek( $input_fh, $content_start, 0 )
                    or croak("Error seeking in data file: $!\n");
                last HEADER_LINE;
            }
        }
    }
    return ( $measurements, $measurement_headings, $data_section_line );
}

sub _fix_imagene3 : PRIVATE {

    my ( $self ) = @_;

    local $INPUT_RECORD_SEPARATOR = $self->get_linebreak_type();

    my $input_fh = $self->get_filehandle()
	or croak("Error: Unable to retrieve filehandle.");
    openhandle($input_fh) or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );

    my $content_start = tell($input_fh);

    # Check the header for image/channel/fluorophore info. Set the
    # input_fh to the top of the DATA section.  Detect measurements if
    # present. If we ever get these files with meaningful channel
    # information we would incorporate it in this method call.
    my ( $measurements, $measurement_headings, $data_section_line )
        = $self->_parse_imagene3_header( $content_start );

    unless ( defined($data_section_line) && $data_section_line =~ /\A begin /ixms ) {
	die("Error: Unable to parse extracted data section headings.");
    }

    # Sort out the Control vs. Experimental columns here, modify the QT names.
    my (undef, @data_sections) = grep { $_ } split /\t/, $data_section_line;
    my %is_index = map { $_ => 1 } @{ $self->get_index_columns() };
    my %qt_processed;
    my $headings = $self->get_column_headings();
    DATA_HEADING:
    for ( my $i = 0; $i < @{ $headings }; $i++ ) {
	next DATA_HEADING if ($is_index{$i} || ! $headings->[$i]);
	my $section_num = $qt_processed{ $headings->[$i] } || 0;
	if ( my $section = $data_sections[$section_num] ) {
	    $qt_processed{ $headings->[$i] }++;
	    $headings->[$i] = "$section $headings->[$i]";
	}
	else {
	    die("Error: More duplicate column headings than there are data sections.");
	}
    }

    my $fixed_fh = IO::File->new_tmpfile;

    my %data_headings = map { $_ => 1 } @{ $self->get_column_headings() };

    # Set up an array slice base to use for the stripped array (faster
    # than strip_discards()).
    my ( $slice, $lastheading ) = $self->_slice_minus_discards;

    # Drop columns without headings.
    my @stripped_slice = grep { $headings->[$_] } @$slice;
    $slice = \@stripped_slice;

    # N.B. this won't work if the index columns are ever allowed to
    # contain q{}.
    my @stripped_headings = grep { $_ } @{ $headings };
    $self->set_column_headings( \@stripped_headings );

    DATA_LINE:
    while ( my $line = <$input_fh> ) {

        $line =~ s/$RE_LINE_BREAK//xms;

	# Skip over empty lines, end on any "end" or "begin" markers.
        next DATA_LINE if ( $line =~ m/\A \s* \z/ixms );
        last DATA_LINE if ( $line =~ m/\A (begin|end) [ ]/ixms );

        my @line_array = split /\t/, $line;

        my $metacolumn = $line_array[ $self->get_index_columns()->[0] ];
        my $metarow    = $line_array[ $self->get_index_columns()->[1] ];
        my $column     = $line_array[ $self->get_index_columns()->[2] ];
        my $row        = $line_array[ $self->get_index_columns()->[3] ];

        my @rowslice = ( @$slice, ( $lastheading + 1 ) .. $#line_array );
        my $new_line = [ @line_array[@rowslice] ];

        # Add measurement columns where they're missing from the data section
	# FIXME we want to use the $measurements value preferentially for ImaGene3.
        if ( my $header_row
            = $measurements->{"$metacolumn.$metarow.$column.$row"} ) {
            foreach my $measurement ( sort keys %$header_row ) {
                push( @$new_line, $header_row->{$measurement} )
                    unless ( $data_headings{$measurement} );
            }
        }

        unshift( @$new_line, $metacolumn, $metarow, $column, $row );

        {
            no warnings qw(uninitialized);
            print $fixed_fh ( join( "\t", @$new_line ), $INPUT_RECORD_SEPARATOR );
        }

    }

    seek( $fixed_fh, 0, 0 ) or croak("Error seeking in data file: $!\n");

    # Add the measurement headings, if we have them. FIXME sort out
    # the logic here to preferentially use $measurements headings.
    foreach my $measurement ( sort @$measurement_headings ) {
        push( @{ $self->get_column_headings() }, $measurement )
            unless ( $data_headings{$measurement} );
    }

    # Check that there's no data we're missing
    FOOTER_LINE:
    while ( my $line = <$input_fh> ) {
        if ( $line =~ m/\S/xms )
        {    # Any non-whitespace
            print {$self->get_error_fh()} (
                "WARNING: Possible data after END DATA marker is being discarded.\n"
            );
            last FOOTER_LINE;
        }
    }

    $self->_genericize_fileinfo();

    return $fixed_fh;
}

sub _fix_codelink : PRIVATE {

    my ( $self ) = @_;

    local $INPUT_RECORD_SEPARATOR = $self->get_linebreak_type();

    my $input_fh = $self->get_filehandle()
	or croak("Error: Unable to retrieve filehandle.");

    openhandle($input_fh) or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );
    my $fixed_fh = IO::File->new_tmpfile;

    # Set up an array slice base to use for the stripped array (faster
    # than strip_discards()).
    my ( $slice, $lastheading ) = $self->_slice_minus_discards;

    while ( my $line = <$input_fh> ) {

        $line =~ s/$RE_LINE_BREAK//xms;

	# Apparently CodeLink can have empty lines at the end.
	next if $line =~ m/$RE_EMPTY_STRING/xms;

        my @line_array = split /\t/, $line;

        my $row    = $line_array[ $self->get_index_columns()->[0] ];
        my $column = $line_array[ $self->get_index_columns()->[1] ];

        # We assume here that CodeLink only prints their arrays in single
        # blocks; I suspect this may have to change FIXME.
        my $metarow    = 1;
        my $metacolumn = 1;

        my @rowslice = ( @$slice, ( $lastheading + 1 ) .. $#line_array );
        my $new_line = [ @line_array[@rowslice] ];

        unshift( @$new_line, $metacolumn, $metarow, $column, $row );

        {
            no warnings qw(uninitialized);
            print $fixed_fh ( join( "\t", @$new_line ), $INPUT_RECORD_SEPARATOR );
        }

    }

    seek( $fixed_fh, 0, 0 ) or croak("Error seeking in data file: $!\n");

    $self->_genericize_fileinfo();

    return $fixed_fh;
}

sub _genericize_fileinfo : PRIVATE {

    my $self = shift;

    my $new_headings
        = strip_discards( $self->get_index_columns(), $self->get_column_headings() );

    unshift( @$new_headings, 'MetaColumn', 'MetaRow', 'Column', 'Row' );

    $self->set_index_columns( [ 0, 1, 2, 3 ] );
    $self->set_format_type('Generic');
    $self->set_column_headings( \@$new_headings );

    return;
}

sub _reporter_genericize_fileinfo : PRIVATE {

    my $self = shift;

    my $new_headings
        = strip_discards( $self->get_index_columns(), $self->get_column_headings() );

    unshift( @$new_headings, 'Reporter Identifier' );

    $self->set_index_columns( [0] );
    $self->set_format_type('FGEM');
    $self->set_column_headings( \@$new_headings );

    return;
}

sub _compseq_genericize_fileinfo : PRIVATE {

    my $self = shift;

    my $new_headings
        = strip_discards( $self->get_index_columns(), $self->get_column_headings() );

    unshift( @$new_headings, 'CompositeSequence Identifier' );

    $self->set_index_columns( [0] );

    # Not FGEM_CS as otherwise this crashes in DataFile::Parser.
    $self->set_format_type('FGEM');
    $self->set_column_headings( \@$new_headings );

    return;
}

sub get_expected_md5{
    my ($self) = @_;
    
    my $badata = $self->get_mage_badata();
    my $bioassay = $self->get_mage_ba();
    
    my @nvts;
    
    if ($badata){
    	push @nvts, @{ $badata->getPropertySets || [] };
    }
    if ($bioassay){
    	push @nvts, @{ $bioassay->getPropertySets || [] }
    }
    
    my ($md5_nvt) = grep { $_->getName eq "MD5" } @nvts;

    if ($md5_nvt){
    	return $md5_nvt->getValue;
    }
    else{
    	return undef;
    }
}


=head2 Accessor methods

=over 2

=item set_row_count

Setter method for the total row count.

=item get_row_count

Getter method for the total row count.

=item increment_row_count

Adds one (or the passed value) to the overall row count. Returns the
new row count.

=item get_parse_errors

Getter method for the total number of parse errors.

=item increment_parse_errors

Adds one (or the passed value) to the overall parsing error
count. Returns the new error count.

=item get_not_null

The number of data file cells which are not null relating to known
QTs.

=item increment_not_null

This is an incremental counter for the number of data file cells which
are not null relating to known QTs. Returns the new "not null" count.

=item set_hyb_identifier

Setter method for the Tab2MAGE or MIAMExpress hybridization identifier
associated with a raw or normalized data file. Does not apply to FGEM
files.

=item get_hyb_identifier

Getter method for the Tab2MAGE or MIAMExpress hybridization identifier
associated with a raw or normalized data file. Does not apply to FGEM
files.

=item set_hyb_sysuid

Setter method for the internal MIAMExpress SYSUID value associated
with a raw or normalized data file. Does not apply to FGEM files.

=item get_hyb_sysuid

Getter method for the internal MIAMExpress SYSUID value associated
with a raw or normalized data file. Does not apply to FGEM files.

=item set_array_design_id

Setter method for an identifier linking the data file to an array
design. For Tab2MAGE this identifier is the ArrayExpress array
accession number. For MIAMExpress this identifier is the internal
ArrayExpress Oracle database identifier for the array design.

=item get_array_design_id

Getter method for an identifier linking the data file to an array
design. For Tab2MAGE this identifier is the ArrayExpress array
accession number. For MIAMExpress this identifier is the internal
ArrayExpress Oracle database identifier for the array design.

=item set_ded_identifier

Setter method for the MAGE identifier string representing the
DesignElementDimension which has been associated with the file.

=item get_ded_identifier

Getter method for the MAGE identifier string representing the
DesignElementDimension which has been associated with the file.

=item set_array_design

Setter method for the ArrayDesign object associated with this data
file. See L<ArrayExpress::Datafile::ArrayDesign> for information on
this class.

=item get_array_design

Getter method for the Array Design object associated with this data
file.

=item set_data_metrics

The set_data_metrics method is a setter method for a hashref
which relates actual column heading to datatype, scale and
subclass. The keys are QT names as defined in
L<ArrayExpress::Datafile::QT_list>. Note that the returned hashref
should only have daughter hashrefs as values, and so if no
datatype,scale or subclass info is available for a column heading
(e.g. MetaRow, MetaColumn) then that coumn should not be
represented. In practice, this method should only return information
on the QTs for a single software type (see
$self->check_column_headings).

=item get_data_metrics

Getter method for data metrics hashref (see set_data_metrics).

=item set_intensity_vector

Setter method for a hashref linking a datafile row identifier
(e.g. "1.1.4.1") to a measured data value. Used in Pearson correlation
coefficient calculation.

=item get_intensity_vector

Getter method for a hashref linking a datafile row identifier
(e.g. "1.1.4.1") to a measured data value. Used in Pearson correlation
coefficient calculation.

=item set_index_columns

Setter method for an arrayref describing the array indices of the
coordinate columns (MetaColumn, MetaRow etc.) in
$self->get_column_headings.

=item get_index_columns

Getter method for an arrayref describing the array indices of the
coordinate columns (MetaColumn, MetaRow etc.) in
$self->get_column_headings.

=item set_column_headings

Setter method for the actual column headings found in the data file
(arrayref).

=item get_column_headings

Getter method for the actual column headings found in the data file
(arrayref).

=item set_heading_qts

Setter method for an arrayref containing a list of the actual
recognized QTs in the file. This is not a uniqued list - a repeated QT
will appear multiple times (as for example, in a FGEM data file).

=item get_heading_qts

Getter method for an arrayref containing a list of the actual
recognized QTs in the file. This is not a uniqued list - a repeated QT
will appear multiple times (as for example, in a FGEM data file).

=item set_heading_hybs

Setter method for an arrayref containing a list of (potential) hyb ids
derived from the column headings of a FGEM file. These are checked
elsewhere.

=item get_heading_hybs

Getter method for an arrayref containing a list of (potential) hyb ids
derived from the column headings of a FGEM file. These are checked
elsewhere.

=item add_fail_columns

Method which adds the passed argument to a list of column headings
which are unrecognized.

=item get_fail_columns

Returns an arrayref listing the unrecognized column headings (uniqued
and sorted).

=item add_fail_hybs

Method which adds the passed argument to a list of unrecognized
hybridization identifiers parsed from FGEM column headings which are
unrecognized. Hybridization identifiers are either the Tab2MAGE or
MIAMExpress user-supplied names for the hybridizations.

=item get_fail_hybs

Returns an arrayref listing the unrecognised hyb identifiers (uniqued
and sorted).

=item set_is_exp

Setter method for boolean flag indicating whether the file is an EXP file or not.

=item get_is_exp

Getter method for EXP file flag.

=item get_is_binary

Getter method for binary file flag.

=item set_is_miamexpress

Setter method for boolean flag indicating whether the file is part of
a MIAMExpress submission, for which slightly different validation
rules are used. More typically the is_miamexpress argument to new() is used.

=item get_is_miamexpress

Getter method for MIAMExpress file flag.

=item add_factor_value

Mutator method for the experimental factor values associated with the
file. Takes (category, value) as an argument, adds them to the list.

=item get_factor_value

Getter method for factor values associated with the file; returns a
hashref in the form:

 {category => [value1, value2, ...], ...}

=item set_ded_type

Setter method for the type of DesignElementDimension associated with
the file (Feature, Reporter or CompositeSequence).

=item get_ded_type

Getter method for the type of DesignElementDimension associated with
the file.

=item set_format_type

Setter method for the format type (e.g., Affymetrix, GenePix, BlueFuse
etc.). See L<EBI::FGPT::Config> for the enumerated types.

=item get_format_type

Getter method for the format type.

=item set_data_type

Setter method for the data type (e.g., raw, normalized,
transformed). See L<EBI::FGPT::Config> for the enumerated
types. Also allowed is the 'EXP' file type (Affymetrix).

=item get_data_type

Getter method for the data type.

=item set_qt_type

Setter method for the QT type associated with the file. This is
derived from the software names defined in
L<ArrayExpress::Datafile::QT_list>.

=item get_qt_type

Getter method for the QT type associated with the file.

=item set_path

Setter method for the full filesystem path of the data file.

=item get_path

Getter method for the full filesystem path of the data file.

=item set_name

Setter method for the name of the file. Also sets $self->set_path if
it has not been otherwise set. Note that this is not the same
behaviour as the "name" argument to the object constructor, which does
not change the path at all.

=item get_name

Getter method for the name of the file.

=item set_target_filename

Setter method for the name of the output stripped data file.

=item get_target_filename

Getter method for the name of the output stripped data file.

=item get_linebreak_type

Getter method for the line-ending character(s). Can be C<\n>, C<\r\n>,
C<\r> or C<Unknown>.

=item get_line_format

Getter method for the line-ending format (Mac, Unix, DOS or
Unknown). Used in reports.

=item set_exp_data

Setter method for storing the output of the $self->parse_exp_file
method.

=item get_exp_data

Getter method for retrieving the output of the
$self->parse_exp_file method.

=item set_mage_qtd

Setter method for the
Bio::MAGE::BioAssayData::QuantitationTypeDimension object associated
with the file.

=item get_mage_qtd

Getter method for the
Bio::MAGE::BioAssayData::QuantitationTypeDimension object associated
with the file.

=back

=head1 AUTHOR

Tim Rayner (rayner@ebi.ac.uk), ArrayExpress team, EBI, 2004.

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

1;

