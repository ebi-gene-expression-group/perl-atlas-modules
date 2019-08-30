#!/usr/bin/env perl
#
# EBI/FGPT/Common.pm
#
# Amy Tang 2012 ArrayExpress team, EBI
#
# $Id$
#

=pod

=head1 NAME

EBI::FGPT::Common - some common methods used by EBI::FGPT tools

=head1 SYNOPSIS

use EBI:FGPT:Common qw(date_now $RE_EMPTY_STRING);
 
 if ( $test =~ $RE_EMPTY_STRING ) {
    print date_now();
 }

=head1 POPULAR SUBROUTINES

=over 2

=item C<open_log_fh( $prefix, $input, $type, $width )>

Prefix is the filename's prefix, separated from the core (input) of
the filename by an underscore. Type is the type of log (error? data?
report?). Width is set at 80 characters by default but can be changed.
The filename always ends with ".log".

=item C<date_now()>

Return current date and time in a MAGE best practice date-time string.
This string will always be from the UTC/GMT time zone, in the format
of yyyy-mm-ddThh:mm:ssZ. E.g. 2012-10-04T07:33:28Z. "T" is the delimiter
separating date and time, and "Z" implies UTC (i.e. GMT)

=item C<ae2_load_dir_for_acc>

Given an experiment or array accession number returns the corresponding
AE2 load directory path

=item C<get_acc_type_and_prefix>

Given an accession number returns the type of submission (A or E)
and the 4 letter pipeline prefix

=item C<db_tag_name_version>

Given a database tag name, e.g. "chromosome_coordinate:ucsc_hg17" in
"Reporter Database Entry[chromosome_coordinate:ucsc_hg17] from an 
array design file, the name "chromosome_coordinate" and version 
"ucsc_hg17" will be returned. The string after the last colon in the
tag is always treated as the version. If there is no version, 
then the version string returned is undef.

=item C<check_linebreaks( $path )>

Takes a filename as an argument, checks for Mac, Unix or DOS line
endings by reading the whole file in chunks, and regexp matching the
various linebreak types. Line breaks must be unanimous, i.e. a
mixture of different line endings is not allowed.

If this subroutine is called in the scalar context, i.e.
$line_break = check_linebreaks($path), the subroutine returns
the type of linebreak (if unanimous), or returns undef.

If this subroutine is called in the list context, i.e.
@line_breaks = check_linebreaks($path), the subroutine
returns a list, where the first element is a hashref (gives
line_ending_type--count key-value pairs when dereferenced),
and the second element is the unanimous line ending type
(again undef if a mixture of line endings is used in the file)

=item C<decamelize( $string )>

Function to convert CamelCase strings to underscore_delimited.

=item C<magetab_split_and_tidy>

Given an IDF path, data directory path, target directory path and
accession number rewrites the files to the target directory and renames
them acc.idf.txt, acc.sdrf.txt (or acc.hyb.sdrf.txt and acc.seq.sdrf.txt
for mixed technology submissions)

=item C<rewrite_sdrf ( $old_path , $new_path )>

Often called from within magetab_split_and_tidy subroutine. Given an old
directory path and a new one, write the SDRF to the new path. During the
rewriting process, commented lines, blank lines and white spaces inside
square brackets (e.g. Characteristics[ Age]) will be removed.

=item C<get_range_from_list>

Turns a list of numbers with a common prefix into a string representing
the range of numbers covered. First arg is the prefix string, all other
args are the array of values, e.g. ("ERR", "ERR1", "ERR2", "ERR7", "ERR8")
returns ERR1-ERR2,ERR7-ERR8. These ranges can be used in links to ENA.

=item C<get_ena_fastq_uri>

Given a fastq file named with an ENA run accession returns the location
of the file on the ENA ftp site (uses ENA_FTP_URI from Config file as uri base)

=head1 OTHER SUBROUTINES

=over 2

=item C<mprint( @filehandles, $text )>

Given a list of filehandles followed by a string, prints the string
to each filehandle.

=item C<replace_forbidden_chars( $string )>

Replaces forbidden characters (specified in Config.pm) with underscores
in the given string. Returns new string.

=item C<get_indexcol( $list, $name )>

Function to return the first index within @$list matching the string
or regexp passed as $name. Returns -1 on failure.

=item C<clean_hash( $hashref )>

Strip out undef or empty string values from $hashref.

=item C<strip_discards( $indexcols, $line_array )>

Sub to strip values out of an arrayref ($line_array) based on an
arrayref of unwanted array indices ($indexcols). Does not modify the
input lists, but instead returns a suitably stripped arrayref.

=item C<round( $number, $precision )>

A simple rounding function that returns $number rounded to $precision
decimal places.


=item C<epoch_from_mage_date( $mage_date )>

When passed a MAGE best practice formetted date string returns the
epoch time for it (or undef if it cannot be parsed).

=item C<untaint( $string )>

A convenient data untainting function which replaces any run of
non-whitelisted characters with a single underscore.

=item C<get_filepath_from_uri( $string, $dir )>

Given a string and an optional directory argument, this function
determines which URI scheme is in use (default is "file://"), and
downloads "http://" and "ftp://" URIs to either the indicated
filesystem directory or the current working directory. Returns the
filesystem path to the file.


=head1 REGEXPS

=over 2

=item C<$RE_EMPTY_STRING>

Matches an empty string (whitespace ignored).

=item C<$RE_COMMENTED_STRING>

Matches a string beginning with #.

=item C<$RE_SURROUNDED_BY_WHITESPACE>

Matches a string with whitespace on either side; $1 contains the
string minus the whitespace.

=item C<$RE_WITHIN_PARENTHESES>

Matches a string with parentheses on either side; $1 contains the
string minus the parentheses.

=item C<$RE_WITHIN_BRACKETS>

Matches a string with brackets on either side; $1 contains the
string minus the brackets.

=item C<$RE_SQUARE_BRACKETS>

Matches either [ or ]; $1 contains the matched character.

=item C<$RE_LINE_BREAK>

Matches a linebreak (DOS, Unix or MacOS).


=head1 AUTHOR

Amy Tang (amytang@ebi.ac.uk), ArrayExpress team, EBI, 2012.

Most of subroutines were implemented by Tim Rayner.

Acknowledgements go to the ArrayExpress curation team for feature
requests, bug reports and other valuable comments.

=cut

package EBI::FGPT::Common;

use strict;
use warnings;

use Carp;
use charnames qw( :full );

use Scalar::Util qw( openhandle );
use File::Spec;
use IO::File;
use IO::Handle;
use Readonly;
use English qw( -no_match_vars );
use Date::Parse;
use File::Path qw(mkpath);
use IPC::Cmd qw( can_run );

use EBI::FGPT::Config qw($CONFIG);

use base 'Exporter';
our @EXPORT_OK = qw(
  open_log_fh
  date_now
  ae2_load_dir_for_acc
  get_acc_type_and_prefix
  db_tag_name_version
  check_linebreaks
  decamelize
  magetab_split_and_tidy
  rewrite_sdrf
  get_range_from_list
  get_ena_fastq_uri
  mprint
  round
  get_indexcol
  strip_discards
  clean_hash
  epoch_from_mage_date
  untaint
  replace_forbidden_chars
  get_filepath_from_uri
  check_network_file
  $RE_EMPTY_STRING
  $RE_COMMENTED_STRING
  $RE_SURROUNDED_BY_WHITESPACE
  $RE_WITHIN_PARENTHESES
  $RE_WITHIN_BRACKETS
  $RE_SQUARE_BRACKETS
  $RE_LINE_BREAK
);

# Define some standard regexps, as if they are global variables:

Readonly our $RE_EMPTY_STRING             => qr{\A \s* \z}xms;
Readonly our $RE_COMMENTED_STRING         => qr{\A [\"\s]* \#}xms;
Readonly our $RE_SURROUNDED_BY_WHITESPACE => qr{\A [\"\s]* (.*?) [\"\s]* \z}xms;
Readonly our $RE_WITHIN_PARENTHESES       => qr{\( \s* (.*?) \s* \)}xms;
Readonly our $RE_WITHIN_BRACKETS          => qr{\[ \s* (.*?) \s* \]}xms;
Readonly our $RE_SQUARE_BRACKETS          => qr{( [\[\]] )}xms;
Readonly our $RE_LINE_BREAK               => qr{[\r\n]* \z}xms;

sub open_log_fh {

	my ( $prefix, $input, $type, $width ) = @_;

	$width ||= 80;

	my $input_orig = $input;

	# We don't want to include the directory path in the log file name
	my ( $vol, $dir, $file ) = File::Spec->splitpath($input);
	$input = $file;

	# Remove e.g. .txt suffix if input is a filename
	$input =~ s/\.[^\.]*$//;
	my $log_name = join "_", ( $prefix, $input, $type );
	$log_name .= ".log";

	# Create the log in the same dir as the input file
	my $path;
	if ($dir) {
		$path = File::Spec->catfile( $dir, $log_name );
	}
	else {
		$path = $log_name;
	}

	open( my $fh, ">:encoding(UTF-8)", $path ) or die "Could not open log file $path for writing - $!";

	print $fh "Log generated " . date_now() . " from $input_orig\n";

	my $line = q{-} x $width;
	print $fh "$line\n\n";

	return $fh;
}

sub date_now {

	my $datenum = time;
	my ( $sec, $min, $hour, $mday, $mon, $year, $wday ) = gmtime($datenum);
	$mon++;    # localtime starts months from 0
	$year += 1900;    # localtime starts years from 100

	return
	  sprintf( "%04d-%02d-%02dT%02d:%02d:%02d", $year, $mon, $mday, $hour, $min, $sec );
}

sub ae2_load_dir_for_acc {

	my ($acc) = @_;

	my ( $acc_type, $acc_prefix ) = get_acc_type_and_prefix($acc);
	unless ( $acc_type and $acc_prefix ) {
		die "Error: could not create AE2 load directory path for accession $acc";
	}

	my $subdir;
	if ( $acc =~ /^A-/i ) {
		$subdir = "ARRAY";
	}
	else {
		$subdir = "EXPERIMENT";
	}

	my $dir =
	  File::Spec->catdir( $CONFIG->get_AE2_LOAD_DIR, $subdir, $acc_prefix, $acc, );

	# Create target dir if it does not exist
	unless ( -e $dir && -d $dir ) {
		mkpath( $dir, 0, 0777 ) or die "Error: Could not create directory $dir. $!";
	}
	return $dir;
}

sub get_acc_type_and_prefix {
	my ($acc) = @_;

	$acc =~ /([EA])-([A-Z]{4})-\d*/g;
	my $acc_type   = $1;
	my $acc_prefix = $2;

	return ( $acc_type, $acc_prefix );
}

sub db_tag_name_version {
	my ($full_tag) = @_;

	my @bits = split /:/, $full_tag;

	# if split produces only one thing it is the name
	my $name = shift @bits;

	# if there is anything else the last thing is the version
	my $version = pop @bits;

	# anything leftover is included in the name
	$name = join ":", $name, @bits;

	return $name, $version;
}

sub check_linebreaks {

	my $path = shift;
	my $fh = IO::File->new( $path, '<' )
	  or croak("Error: Failed to open file $path for linebreak checking: $!\n");

	my $bytelength = -s $path;

	# Count all the line endings. This can get memory intensive
	# (implicit list generation, can be over 1,000,000 entries for
	# Affy CEL). We read the file in defined chunks to address this.
	my ( $unix_count, $mac_count, $dos_count );
	my $chunk_size          = 3_000_000;    # ~10 chunks to a big CEL file.
	my $previous_final_char = q{};
	for ( my $offset = 0 ; $offset < $bytelength ; $offset += $chunk_size ) {

		my $chunk;

		my $bytes_read = read( $fh, $chunk, $chunk_size );

		unless ( defined($bytes_read) ) {
			croak("Error reading file chunk at offset $offset ($path): $!\n");
		}

		# Lists generated implicitly here.
		# "\N{xxx}" came from the charnames CPAN module.
		# the string inside the curly braces is first looked up in the
		# list of standard Unicode character names

		$unix_count += () = ( $chunk =~ m{\N{LINE FEED}}g );
		$mac_count  += () = ( $chunk =~ m{\N{CARRIAGE RETURN}}g );
		$dos_count  += () = ( $chunk =~ m{\N{CARRIAGE RETURN}\N{LINE FEED}}g );

		# DOS line endings could conceivably be split between chunks.
		if ($bytes_read) {    # Skip if at end of file.
			if (   ( substr( $chunk, 0, 1 ) eq "\N{LINE FEED}" )
				&& ( $previous_final_char eq "\N{CARRIAGE RETURN}" ) )
			{
				$dos_count++;
			}
			$previous_final_char = substr( $chunk, -1, 1 );
		}
	}

	close($fh)
	  or croak("Error closing file $path in sub check_linebreaks: $!\n");

	my $dos  = $dos_count;
	my $mac  = $mac_count - $dos_count;
	my $unix = $unix_count - $dos_count;

	# Set to undef on failure.
	my $line_ending = undef;

	# Determine the file line endings format, return the "standard" line
	# ending to use
	if ( $unix && !$mac && !$dos ) {    # Unix
		$line_ending = "\N{LINE FEED}";
	}
	elsif ( $mac && !$unix && !$dos ) {    # Mac
		$line_ending = "\N{CARRIAGE RETURN}";
	}
	elsif ( $dos && !$mac && !$unix ) {    # DOS
		$line_ending = "\N{CARRIAGE RETURN}\N{LINE FEED}";
	}

	# Calling in scalar context just gives $line_ending.
	my $counts = {
		unix => $unix,
		dos  => $dos,
		mac  => $mac,
	};
	return wantarray ? ( $counts, $line_ending ) : $line_ending;

}

sub decamelize {

	# Function to convert CamelCase strings to underscore_delimited.
	my ($camel) = @_;

	# Underscore separates internal capitals
	$camel =~ s/([a-z])([A-Z])/$1\_$2/g;

	# substitute spaces
	$camel =~ s/\s+/\_/g;

	# and then lowercase
	$camel = lc($camel);

	return $camel;
}

sub magetab_split_and_tidy {
	my ( $mtab_file, $data_dir, $target_dir, $acc ) = @_;

    # If possible, run dos2unix in case of any non-UNIX line endings.
    if( can_run( "dos2unix" ) ) {
        `dos2unix $mtab_file`;
    }

	print "\nSplitting and tidying MAGE-TAB file $mtab_file to $target_dir...\n";

	my ( $idf_file, $sdrf_file ) =
	  map { File::Spec->catfile( $target_dir, "$acc.$_.txt" ) } ( "idf", "sdrf" );

	open my $in_fh,   "<", $mtab_file or die $!;
	open my $idf_fh,  ">", $idf_file  or die $!;
	open my $sdrf_fh, ">", $sdrf_file or die $!;

	my $out_fh = $idf_fh;
	my @orig_sdrf_files;
	my @new_sdrf_files;
  LINE: foreach my $line (<$in_fh>) {

		$line =~ s/\"//g;

		# Skip blank lines and comments
		next LINE if $line =~ $RE_EMPTY_STRING;
		next LINE if $line =~ $RE_COMMENTED_STRING;

		# Remove extra/trailing whitespaces in square brackets,
		# e.g. "FactorValue[ Age]", "FactorValue[ Sex ]"

		$line =~ s/\[\s+/\[/g;
		$line =~ s/\s+\]/\]/g;

		# Don't print section delimiters or original SDRF file name
		print $out_fh $line unless $line =~ /^( \[ ( IDF|SDRF ) \] | SDRF \s? File )/ixms;

		# If we see the start of the SDRF section switch to writing to SDRF file
		if ( $line =~ /\[SDRF\]/ ) {
			$out_fh = $sdrf_fh;
			push @new_sdrf_files, $sdrf_file;
		}

		# If we see name of submitted SDRF store it and continue to write to IDF file
		if ( $line =~ /"?SDRF File"?\t/i ) {
			chomp $line;
			my @cells = split "\t", $line;

			# Store sdrf names from non-blank cells
			push @orig_sdrf_files, grep { $_ } @cells[ 1 .. $#cells ];
		}
	}
	close $sdrf_fh;

	# If a separate SDRF was named in the IDF write this out to new SDRF file
	# Now handles separate assay and hyb SDRFs

	if (@orig_sdrf_files) {
		if ( @orig_sdrf_files == 1 ) {

			# Remove "file:" prefix that Bio::MAGETAB puts on
			my $old = $orig_sdrf_files[0];
			$old =~ s/^file://g;
			my $old_path = File::Spec->catfile( $data_dir,   $old );
			my $new_path = File::Spec->catfile( $target_dir, $acc . ".sdrf.txt" );
			rewrite_sdrf( $old_path, $new_path );
			push @new_sdrf_files, $new_path;
		}
		elsif ( @orig_sdrf_files == 2 ) {
			foreach my $sdrf (@orig_sdrf_files) {
				my $new_name;
				if ( $sdrf =~ /\.(assay|seq)\./ ) {
					$new_name = $acc . ".seq.sdrf.txt";
				}
				elsif ( $sdrf =~ /\.hyb\./ ) {
					$new_name = $acc . ".hyb.sdrf.txt";
				}
				else {
					die "Error: SDRF type not recognized $sdrf "
					  . "- please rename with .assay.sdrf, .seq.sdrf or .hyb.sdrf suffix. If you only have one SDRF this error could be due to line endings. Please verify there are no non-UNIX line endings in $mtab_file";
				}

				# Remove "file:" prefix that Bio::MAGETAB puts on

				$sdrf =~ s/^file://g;
				my $old_path = File::Spec->catfile( $data_dir,   $sdrf );
				my $new_path = File::Spec->catfile( $target_dir, $new_name );
				my $path     = rewrite_sdrf( $old_path,          $new_path );
				push @new_sdrf_files, $new_path;
			}
		}
		else {
			die "Error: more than 2 original SDRF files found for $acc "
			  . "- I don't know how to handle this!";
		}
	}

	# Write new SDRF file names to IDF
	my @add_to_idf;
	foreach my $sdrf (@new_sdrf_files) {
		my ( $vol, $path, $file ) = File::Spec->splitpath($sdrf);
		push @add_to_idf, $file;
	}
	print $idf_fh join "\t", "SDRF File", @add_to_idf;
	close $idf_fh;
	return $idf_file, @new_sdrf_files;
}

sub rewrite_sdrf {

	# Usually called by magetab_split_and_tidy subroutine
	# in this module.

	my ( $old_path, $new_path ) = @_;

	print "\nRewriting orig SDRF file $old_path to $new_path...\n";

	open( my $sdrf_in_fh, "<", $old_path ) or die $!;
	open( my $sdrf_fh,    ">:encoding(UTF-8)", $new_path ) or die $!;

  LINE: foreach my $s_line (<$sdrf_in_fh>) {

		# Skip blank lines and comments
		next LINE if $s_line =~ $RE_EMPTY_STRING;
		next LINE if $s_line =~ $RE_COMMENTED_STRING;

		# Remove extra/trailing whitespaces in square brackets,
		# e.g. "FactorValue[ Age]", "FactorValue[ Sex ]"

		$s_line =~ s/\[\s+/\[/g;
		$s_line =~ s/\s+\]/\]/g;

		print $sdrf_fh $s_line;
	}

	return $new_path;
}

sub get_range_from_list {
	my ( $prefix, @list ) = @_;
	my ( $min, $max );
	my $string;

	if ( scalar @list == 1 ) {
		return $list[0];
	}

	my $previous;
	foreach my $value ( sort @list ) {
		$value =~ s/$prefix//;
		$min = $value unless $min;
		$max = $value;
		if ( $previous and $value > $previous + 1 ) {

			# we have reached the end of the current range
			my $range = $prefix . $min . "-" . $prefix . $previous;
			if ($string) { $string .= ",$range" }
			else { $string = $range }
			$min = $value;
		}
		$previous = $value;
	}

	# create the final range string
	my $range = $prefix . $min . "-" . $prefix . $max;
	if ($string) { $string .= ",$range" }
	else { $string = $range }

	return $string;
}

sub get_ena_fastq_uri {
	my ($fastq) = @_;

	my $uri_base = $CONFIG->get_ENA_FTP_URI;
	$uri_base .= "/" unless $uri_base =~ /\/$/;

	my ( $subdir, $dir, $vol );

	if ( $fastq =~ /^([A-Z0-9]{6}).*/ ) { $subdir = $1; }

	# If acc is only 9 chars long
	if ( $fastq =~ /^([A-Z0-9]{9,9}).*/ )
	{
		$dir = $1;
	}

# ENA rule : If the number part is greater than 1,000,000 then create an extra subdirectory
# with numbers extracted from the 7th number onwards and zero padded on the left
# Note code takes account of SRR part at beginning of fastq variable i.e acc is greater than 10 chars long
	if ( $fastq =~ /^([A-Z0-9]{10,}).*/ )
	{
		$dir = $1;
		$vol = substr( $dir, 9 );

		# Single digit
		if ( $vol =~ m/^\d$/ ) { $vol = "0" . "0" . $vol; }

		# 2 digits
		if ( $vol =~ m/^\d{2}$/ ) { $vol = "0" . $vol; }

	}

	if ($vol)
	{
		return $uri_base . $subdir . "/" . $vol . "/" . $dir . "/" . $fastq;
	}

	else
	{
		return $uri_base . $subdir . "/" . $dir . "/" . $fastq;
	}
}


sub mprint {
	my @fh_list = @_;
	my $string  = pop @fh_list;

	foreach my $fh (@fh_list) {
		print $fh $string
		  or warn "Could not print to filehandle $fh";
	}
}

sub replace_forbidden_chars {
	my ($string) = @_;

	$_ = $string;

	my $re = $CONFIG->get_FILENAME_FORBIDDEN_CHARS();
	s/$re/_/g;

	return $_;
}

sub get_indexcol {

	# Given a list and a value in that list, returns the value index

	my ( $columnlist, $columnname ) = @_;

	ref $columnlist eq 'ARRAY'
	  or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );
	defined($columnname) or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );

	# For efficiency; N.B. $columnname may contain whitepace, so no /x
	# modifier here. Similarly we rely on the caller to specify /i or not.
	my $re;

	# Empty string is a special case (won't match \b)
	if ( $columnname eq q{} ) {
		$re = qr/\A\s*$columnname\s*\z/ms;
	}
	else {
		$re = qr/\A\s*\b$columnname\b\s*\z/ms;
	}
	my $num_cols = scalar @{$columnlist};

	for ( my $i = 0 ; $i < $num_cols ; $i++ ) {
		return $i if $columnlist->[$i] =~ $re;
	}
	return -1;
}

sub strip_discards {

	# Sub to strip values out of an array (@line_array) based on a list
	# of unwanted array indices (@indexcols). Does not modify the input
	# lists.

	my ( $indexcols, $line_array ) = @_;

	ref $indexcols eq 'ARRAY'
	  or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );
	ref $line_array eq 'ARRAY'
	  or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );

	my %to_be_discarded = map { $_ => 1 } @$indexcols;

	my @new_line;
	my $last_index = $#$line_array;    # Calculate this just once
	foreach my $i ( 0 .. $last_index ) {
		push( @new_line, $line_array->[$i] )
		  unless ( $to_be_discarded{$i} );
	}

	return \@new_line;

}

sub round {

	# Orignially taken from www.perlmonks.org
	my ( $number, $precision ) = @_;
	my $sign = ( $number > 0 ) ? 1 : -1;    # store the sign for later

	$precision ||= 0;                       # $precision should not be undefined

	$number *= 10**$precision;              # move the decimal place
	                                        # $precision places to the
	                                        # right

	$number = int( $number + .5 * $sign );  # add 0.5, correct the sign and
	                                        # truncate the number after the
	                                        # decimal point, thereby
	                                        # rounding it

	return ( $number / 10**$precision );    # move the decimal place back again
}

sub clean_hash {

	# Strip out undef or empty string values

	my ($hashref) = @_;

	ref $hashref eq 'HASH'
	  or confess( $CONFIG->get_ERROR_MESSAGE_ARGS() );

	my %cleaned;
	while ( my ( $key, $value ) = each %$hashref ) {
		$cleaned{$key} = $value if ( defined($value) && $value ne q{} );
	}

	return \%cleaned;

}

sub epoch_from_mage_date {
	my ($mage_date) = @_;
	my $epoch = str2time($mage_date);
	return $epoch;
}

sub untaint {

	# Untaint the input (runs with perl -T switch)

	my $string = shift;
	my @nameparts = $string =~ m/[-a-zA-Z0-9\.@\-\+\_]+/g;
	$string = join( '_', @nameparts );
	return $string;
}

sub get_filepath_from_uri {

	my ( $uri_string, $dir ) = @_;

	require URI;

	# N.B. URI module doesn't seem to like the file://my_filename.txt
	# URI form, and confuses the path with the authority. URI module
	# behaviour is probably correct, but the MAGE-TAB spec asks for
	# this (invalid?) URI form. We fix that here:
	$uri_string =~ s/\A file:\/\/ //ixms;

	my $uri = URI->new($uri_string);

	# Assume file as default URI scheme.
	my $path;
	if ( !$uri->scheme() || $uri->scheme() eq 'file' ) {

		$uri->scheme('file');

		# URI::File specific, this avoids quoting e.g. spaces in filenames.
		my $uri_path = $uri->file();

		if ($dir) {
			$path =
			  File::Spec->file_name_is_absolute($uri_path)
			  ? $uri_path
			  : File::Spec->catfile( $dir, $uri_path );
		}
		else {
			$path = File::Spec->rel2abs($uri_path);
		}
	}

	# Add the common network URI schemes.
	elsif ( $uri->scheme() eq 'http' || $uri->scheme() eq 'ftp' ) {
		$path = cache_network_file( $uri, $dir );
	}
	else {
		croak( sprintf( "ERROR: Unsupported URI scheme: %s\n", $uri->scheme(), ) );
	}

	return $path;
}

sub cache_network_file {

	my ( $uri, $dir ) = @_;

	require LWP::UserAgent;

	# N.B. we don't handle URI fragments, just the path.
	my ($basename) = ( $uri->path() =~ m!/([^/]+) \z!xms );

	my $target;
	if ($dir) {
		$target = File::Spec->catfile( $dir, $basename );
	}
	else {
		$target = $basename;
	}

	# Only download the file once.
	unless ( -f $target ) {

		printf STDOUT ( qq{Downloading network file "%s"...\n}, $uri->as_string(), );

		# Download the $uri->as_string()
		my $ua = LWP::UserAgent->new();

		my $response = $ua->get( $uri->as_string(), ':content_file' => $target, );

		unless ( $response->is_success() ) {
			croak(
				sprintf(
					qq{Error downloading network file "%s" : %s\n},
					$uri->as_string(), $response->status_line(),
				)
			);
		}
	}

	return $target;
}

1;
