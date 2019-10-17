#!/usr/bin/env perl
#
# Module to provide constant values for a local installation of the
# ArrayExpress::Curator modules.
#
# Tim Rayner 2004, ArrayExpress team, European Bioinformatics Institute
#
# $Id: Config.pm 2448 2012-07-16 12:58:42Z farne $
#

package EBI::FGPT::Config;

use strict;
use warnings;

use Config::YAML;
use Tie::IxHash;
use Readonly;
use File::Spec;
use File::Basename;
use Carp;

use base 'Exporter';
our @EXPORT_OK = qw($CONFIG);

my $module_path      = File::Spec->rel2abs(__FILE__);
my @module_dir_array = File::Spec->splitpath($module_path);

my $moduleconf = File::Spec->catpath( @module_dir_array[ 0, 1 ], 'Config.yml' );

if ( $ENV{PAR_TEMP} ) {
	require PAR;
	my $content = PAR::read_file('Config.yml');
	my $tmp_conf = File::Spec->catpath( $ENV{PAR_TEMP}, 'Config.yml' );
	open( my $fh, ">", $tmp_conf )
	  or die "Could not open file $tmp_conf for writing - $!";
	print $fh $content;
	close $fh;
	$moduleconf = $tmp_conf;
}

# Add your site config path in the next line.
# Alternatively, create a config file ~/.tab2mage.conf in your home directory.

# TODO my $siteconf = q{/path/to/SiteConfig.yml};

my $siteconf = _build_yaml_file_path();

my $userconf = File::Spec->catpath( undef, $ENV{HOME}, '.tab2mage.conf' );

our $CONFIG = Config::YAML->new(
	config => $moduleconf,
	output => $userconf,
);

if ($siteconf) {
	$CONFIG->read($siteconf)
	  or croak("Error: Site config file $siteconf not found: $!\n");
}

# NOTE that order is critical in the arrays referenced below:
# Acceptable columns for raw and normalized data. These can also
# be specified as qr// quoted strings, e.g. if case-insensitive
# matching is desirable.
tie my %datafile_indices, 'Tie::IxHash', (

	# Preferential treatment given to Generic file format; this is
	# because if we miss these and fixate on e.g. GenePix headers in
	# the same file, we will then create duplicate MetaRow/MetaColumn
	# headings, which is messy.
	Generic => [ qr/MetaColumn/i, qr/MetaRow/i, qr/Column/i, qr/Row/i ],

	GenePix     => [qw(Block Column Row X Y)],
	ArrayVision => [qw(Primary Secondary)],
	Agilent     => [qw(Row Col PositionX PositionY)],
	Scanalyze   => [qw(GRID COL ROW LEFT TOP RIGHT BOT)],
	ScanArray   => [
		'Array Column',
		'Array Row',
		'Spot Column',
		'Spot Row',
		'X',
		'Y'
	],
	QuantArray => [ 'Array Column', 'Array Row', 'Column', 'Row' ],
	Spotfinder => [qw(MC MR SC SR C R)],
	MEV        => [qw(MC MR C R UID)],
	CodeLink          => [qw(Logical_row Logical_col Center_X Center_Y)],
	BlueFuse          => [qw(COL ROW SUBGRIDCOL SUBGRIDROW)],
	UCSFSpot          => [qw(Arr-colx Arr-rowy Spot-colx Spot-rowy)],
	NimbleScanFeature => [qw(X Y PROBE_ID X_PIXEL Y_PIXEL)],
	NimblegenNASA     => [qw(X_BC Y_BC Feature_ID ProbID_BC)],
	ImaGene  => [ 'Meta Column', 'Meta Row', 'Column', 'Row', 'Field', 'Gene ID', q{} ],
	ImaGene3 => [qw(Meta_col Meta_row Sub_col Sub_row Name Selected)],
	ImaGene7 =>
	  [ qw(Block Column Row), 'Ch1 XCoord', 'Ch1 YCoord', 'Ch2 XCoord', 'Ch2 YCoord' ],
	ImaGeneFields => [qw(Field Column Row XCoord YCoord)],
	CSIRO_Spot    => [qw(grid_c grid_r spot_c spot_r indexs)],

	# N.B. the FGEM and FGEM_CS indices are assumed to reside here
	# by other classes. Also AffyNorm and GEO.
	FGEM     => [qr/Reporter ?Identifier/i],
	FGEM_CS  => [qr/Composite ?Sequence ?Identifier/i],
	GEO      => [qw(ID_REF)],
	AffyNorm => ['Probe ?Set ?(Name|ID)'],

	# Lower specificity column headings.
	NimbleScanNorm    => [qw(X Y PROBE_ID)],
	AppliedBiosystems => [qw(Probe_ID Gene_ID)],
	ArrayVision_lg2   => ['Spot labels'],

	# Very non-specific column headings are left till the end:
	Illumina => [qw(PROBE_ID)],
);

# Some content is not appropriate for the config file, we handle it
# internally here. This overwrites any siteconf changes, but can still
# be overridden by userconf settings.
my %default = (
	MX_DBPARAMS       => { PrintError => 0, RaiseError => 1 },
	AE_DBPARAMS       => { PrintError => 0, RaiseError => 1 },
	AUTOSUBS_DBPARAMS => { PrintError => 0, RaiseError => 1 },

	# Acceptable columns form tab2mage data. See above - this is a
	# tied hash to retain order.
	#TODO retaining TAB2MAGE naming for legacy reasons
	T2M_INDICES => \%datafile_indices,

	# Ignored QTs for general QT checks on non-data matrix files.
	IGNORED_QTS => [
		qr/MetaColumn/i,                  qr/MetaRow/i,
		qr/Column/i,                      qr/Row/i,
		qr/Reporter ?(Name|Identifier)/i, qr/Composite ?Sequence ?(Name|Identifier)/i,
		qr/ID_REF/,                       qr/X/,
		qr/Y/,                            qr/CellHeader=X/,
		qr/Block/,                        qr/Name/,
		qr/ID/,
	],

	# Order here is important - see Tab2MAGE.pm
	T2M_FILE_TYPES   => [qw(raw normalized)],
	FGEM_FILE_TYPE   => 'transformed',
	RAW_DM_FILE_TYPE => 'measured_data_matrix',

	# N.B. at least one value (1,2,4,8...) should be kept back so that
	# we can always determine if the process has simply died (error
	# code 255).  Note also that the use of these codes will probably
	# need to be modulated depending on the submission type.

	# Innocent errors which may be ignored.
	ERROR_INNOCENT => 2,

	# Missing MIAME information.
	ERROR_MIAME => 8,

	# Parsing will work but experiment may not be displayed
	# correctly in ArrayExpress
	ERROR_ARRAYEXPRESS => 16,

	# Parsing may fail or give erroneous results.
	ERROR_PARSEBAD => 32,

	# Parsing _will_ fail.
	ERROR_PARSEFAIL => 128,

	# Checking crashed (in a recoverable way).
	ERROR_CHECKERCRASH => 512,

	# Values used in tracking MIAME checklist compliance. This list
	# will probably grow.
	MIAME_RAWDATA      => 1,
	MIAME_NORMDATA     => 2,
	MIAME_FACTORVALUES => 4,
	MIAME_NORMPROTOCOL => 8,
	MIAME_ARRAYSEQ     => 16,

	ERROR_MESSAGE_ARGS    => 'Bad parameters passed to method',
	ERROR_MESSAGE_PRIVATE => 'Attempt to access a private method',

	STATUS_PENDING          => 'Waiting',
	STATUS_GDS_TO_CURATE    => 'GDS to curate',
	STATUS_DB_RETRIEVAL     => 'Retrieving info from MX',
	STATUS_CHECKING         => 'Checking in progress',
	STATUS_CRASHED          => '** CHECKER CRASH **',
	STATUS_PASSED           => 'Checking passed',
	STATUS_FAILED           => 'Checking failed',
	STATUS_EXPORT_ERROR     => 'Export failed',
	STATUS_COMPLETE         => 'Complete',

	STATUS_AE2_EXPORT       => 'MAGE-TAB export',
	STATUS_AE2_COMPLETE     => 'AE2 Export Complete',
	STATUS_AE2_EXPORT_ERROR => 'MAGE-TAB export failed',

	EXPTCHECK_PROGNAME => 'expt_check.pl',
	EXPTCHECK_VERSION  => '3.2.2',

	TAB2MAGE_PROGNAME => 'Tab2MAGE',
	TAB2MAGE_VERSION  => '2.2.2',

	# This is now set in QT_list.pm
	DEFAULT_QT_FILENAME     => q{},
	DEFAULT_ENTREZ_FILENAME =>  File::Spec->catpath( @module_dir_array[ 0, 1 ], 'Entrez_list.txt' ),

	# N.B. these are processed using oct()
	FILE_PERMISSIONS => '0666',
	DIR_PERMISSIONS  => '0777',

	# regex for identifying different ADF formats
	MX_ADF_REGEX =>
qr{(\t|^)(Meta\s*Column|Reporter\s*Identifier|Composite\s*Sequence\s*Identifier)\s*(\t|\n)}ixms,
	MAGETAB_ADF_REGEX =>
qr{(\t|^)(Block\s*Column|Block\s*Row|Reporter\s*Name|Composite\s*Element\s*Name)\s*(\t|\n)}ixms,

	# List of characters which cannot be used in data file names
	FILENAME_FORBIDDEN_CHARS => qr{ [ \: \\ \" ]+ }ixms,
);

$CONFIG->fold( \%default );

# Incorporate user config, if present.
if ( $ENV{HOME} ) {
	if ( -f $userconf ) {
		warn("Reading user config file $userconf\n");
		$CONFIG->read($userconf);
	}
}



# Returns full path to YAML file containing site config.
sub _build_yaml_file_path {

    # Deduce the path to the config file from the path to this module.
    # This module's location on the filesystem.
    my $thisModulePath = __FILE__;

    # The directory this module occupies.
    my $thisModuleDir = dirname( $thisModulePath );
    
    # Split the directory names.
    my @directories = File::Spec->splitdir( $thisModuleDir );
    
    # Get up to the atlasprod directory.
    while( $directories[ -1 ] ne "atlasprod" ) {
        pop @directories;

        unless( @directories ) {
            die "ERROR - Cannot find atlasprod directory in path to EBI::FGPT::Config. Please ensure this module is installed under atlasprod.\n";
        }
    }
    
    # Stick the remaining directories back together, now pointing to atlasprod dir.
    my $atlasprodDir = File::Spec->catdir( @directories );

    # Check that the supporting_files dir is in the dir now in $atlasprodDir.
    unless( -d File::Spec->catdir( $atlasprodDir, "supporting_files" ) ) {
        die "ERROR - Cannot find supporting_files directory in $atlasprodDir -- cannot locate ArrayExpress site config.\n";
    }

    # Otherwise, create path to site config.
    my $siteConfigPath = File::Spec->catfile( $atlasprodDir, "supporting_files", "ArrayExpressSiteConfig.yml" );

    # Check that the file exists and is readable.
    unless( -r $siteConfigPath ) {
        
        my $mode = ( stat( $siteConfigPath ) )[ 2 ];

        print STDERR "ERROR - Problem reading $siteConfigPath\n";
        printf STDERR "ERROR - File permissions are %04o\n", $mode & 07777;
        
        my $user = ( getpwuid( $< ) )[ 0 ];
        print STDERR "ERROR - Your user name is $user\n";
        print STDERR "ERROR - Your groups are: $(\n";

        print STDERR "ERROR - Effective UID: $>\n";
        print STDERR "ERROR - Effective GID: $)\n";

        print STDERR "ERROR - Running system call \"id fg_atlas\"...\n";
        my $ID = `id fg_atlas`;
        print STDERR "ERROR - Result: $ID\n";
        print STDERR "ERROR - Running system call \"id -g fg_atlas\"...\n";
        my $IDG = `id -g fg_atlas`;
        print STDERR "ERROR - Result: $IDG\n";

        die "ERROR - Cannot read $siteConfigPath -- please check it exists and is readable by your user ID.\n";
    }

    # If so, return the path to the config file.
    return $siteConfigPath;
}


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
	    <td class="pagetitle">Module detail: ExperimentChecker.pm</td>
	  </tr>
      </table>
    </div>

=end html

=head1 NAME

ArrayExpress::Curator::Config.pm - a module defining general config options.

=head1 SYNOPSIS

 use ArrayExpress::Curator::Config qw($CONFIG);

=head1 DESCRIPTION

This module provides definition of some configuration options used
throughout the code. These options may be changed by editing the
ArrayExpress/Curator/Config.yml file. If you wish to point your
installation to an alternate site config YAML file, please
edit the $siteconf variable in the ArrayExpress/Curator/Config.pm
file. For user-specific configuration, this module will also read any
.tab2mage.conf file located in your home directory (i.e.,
$HOME/.tab2mage.conf).

See L<ArrayExpress::Curator::MAGE::Definitions> for other
MAGE-specific constants.

=head2 Configuration options

=over 2

=item MX_DSN

MIAMExpress data source name or DSN, e.g., "DBI:mysql:db_name:host:port".

=item MX_USERNAME

The username used to connect to the MIAMExpress database.

=item MX_PASSWORD

The password used to connect to the MIAMExpress database.

=item AE_DSN

For local ArrayExpress installations only. This is the ArrayExpress
data source name or DSN, e.g., "DBI:Oracle:db_name:host:port" used in
direct connection to the database. Note that the appropriate
DBD::Oracle module must be installed for this to work.

=item AE_USERNAME

The username used to connect to the ArrayExpress database.

=item AE_PASSWORD

The password used to connect to the ArrayExpress database.

=item AEDW_DSN

For checking the data warehouse readiness of an experiment
submission. This database connection is used in checking that any
required array designs have been loaded into the data warehouse. This
config value should be the ArrayExpress DW data source name or DSN,
e.g., "DBI:Oracle:db_name:host:port" used in direct connection to the
data warehouse. Note that the appropriate DBD::Oracle module must be
installed for this to work.

=item AEDW_USERNAME

The username used to connect to the AEDW database.

=item AEDW_PASSWORD

The password used to connect to the AEDW database.

=item AE2_INSTANCE_NAME

There may be several instances of the AE2 database. Use this config to give the
name of the instance used in your set up. This value is used in the target_db
column of the events table to keep track of what has been loaded into each 
instance.

=item AE2_DSN

This config value should be the ArrayExpress 2 data source name or DSN,
e.g., "DBI:Oracle:db_name:host:port" used in direct connection to the
database. Note that the appropriate DBD::Oracle module must be
installed for this to work.

=item AE2_USERNAME

The username used to connect to the AE2 database.

=item AE2_PASSWORD

The password used to connect to the AE2 database.

=item HTTP_PROXY

The http proxy to use when getting URLs.

=item AE_ARRAYDESIGN_LIST

Remote ArrayExpress array design list web page. Used by Tab2MAGE,
MIAMExpress and the experiment checker. This is currently accessible
from outside EBI, and so the setting can be left as it is.

=item T2M_PROTOCOL_PREFIX

The prefix used to autogenerate reassigned protocol
accessions. Default value is "P-TABM-". Please note that you should
change this to prevent conflicts if you intend to use protocol
accession reassignment and submit the resulting MAGE-ML to
ArrayExpress.

=item T2M_EXPERIMENT_PREFIX

The prefix used in creating experiment accessions. This is used to
check that a valid experiment accession number has been used in
conjunction with the protocol reassignment mechanism.

=item MAX_LWP_DOWNLOAD

The maximum size of LWP::UserAgent downloads. This applies to
ArrayExpress ADF and feature list downloads. Currently set to 40MB.

=item VISUALIZE_FONT

The name of the default font to use in visualization graph
creation. This gets passed to the "dot" program. Currently set to
"Courier".

=item AUTOSUBS_ADMIN

Email address of the administrator responsible for managing the
checker and exporter daemon processes. Emails will be sent to this
address on abnormal termination of the process (e.g. on crashes).

=item AUTOSUBS_ADMIN_USERNAME

Login for the administrator responsible for managing the checker and
exporter daemon processes. Other users are restricted from launching
these daemons to aid in process management.

=item AUTOSUBS_DOMAIN

The default domain used in creating MAGE-ML identifiers when exporting
experiments using the autosubmissions system. This is set by default
to 'ebi.ac.uk'. Note that this does not affect submissions exported
from a MIAMExpress database.

=item AUTOSUBS_DSN

The DSN to use when connecting to the autosubmissions database
system. Typically this will be of the form
"DBI:mysql:dbname:host:port".

=item AUTOSUBS_USERNAME

The username to use when connecting to the autosubmissions database.

=item AUTOSUBS_PASSWORD

The password to use when connecting to the autosubmissions database.

=item AUTOSUBMISSIONS_FILEBASE

The filesystem path to the top-level directory where the
autosubmissions system should store uploaded spreadsheets and data
files.

=item AUTOSUBMISSIONS_TARGET

The filesystem directory into which new submissions are exported as
MAGE-ML. A new directory, named using the automatically assigned
experiment accession, will be created and populated.

=item AEDW_DESIGN_TYPES

A list of MO ExperimentDesignTypes that indicate an experiment is
suitable for the ArrayExpress Data Warehouse.

=item AEDW_UNWANTED_DESIGN_TYPES

A list of MO ExperimentDesignTypes that indicate an experiment is not
suitable for the ArrayExpress Data Warehouse. This is used to
differentiate between experiments known to be of the wrong type from
those which are merely under-annotated.

=item AEDW_MINIMUM_HYBS

The minimum number of hybridizations required in an experiment for it
to be considered for the AE Data Warehouse.

=item MIAME_COMPLIANT_ARRAY_PIPELINES

A list of array design accession prefixes (e.g. "A-AFFY-") where every
design can be assumed to be MIAME compliant, for the purposes of
experiment MIAME checking.

=back

=head1 Private options

These are options we recommend you don't change, unless you know what
you're doing.

=over 2

=item T2M_INDICES

A hashref, with keys representing data file format type and values as
arrayrefs listing the coordinate index columns to be used for parsing
those formats. See also L<ArrayExpress::Datafile>. Current format
types are: Generic, GenePix, Affymetrix, ArrayVision, Agilent,
Scanalyze, ScanArray, QuantArray, Spotfinder, BlueFuse, UCSF Spot,
Illumina, CodeLink, Applied Biosystems, NimbleScan.

=item T2M_FILE_TYPES

Supported data file types for per-hyb parsing and MAGE-ML
creation. These tags can appear in the Tab2MAGE spreadsheet as part of
a File[] column heading. Currently supported: "raw" and "normalized".

=item FGEM_FILE_TYPE

Supported data file type for FGEM parsing and MAGE-ML creation. These
tags can appear in the Tab2MAGE spreadsheet as part of a File[] column
heading. Currently supported: "transformed".

=item IGNORED_QTS

A list of regular expression which match QTs which are omitted
from analyses or MAGE-ML output from non-data matrix files.

=item ERROR_INNOCENT, ERROR_MIAME, ERROR_PARSEBAD, ERROR_PARSEFAIL

Errors returned to the shell by each of the scripts are represented by
8-bit integers; here we map them to the constants used.

=item ERROR_CHECKERCRASH

Similar to the errors above, this error indicates that the checking
process crashed for some reason.

=item ERROR_MESSAGE_ARGS, ERROR_MESSAGE_PRIVATE

A selection of internal error message texts.

=item MX_EXTENDED_REPORT

Controls whether extended reporting of sample annotation and factor
values is available (only supported for generic MIAMExpress
installations).

=item DEFAULT_QT_FILENAME

Name of the file to use as the default source of QT information. This
is used to point to a file installed alongside the perl modules, and
should not be changed unless you know what you're doing.

=item DEFAULT_ENTREZ_FILENAME

Name of the file containing a list of Entrez-approved publication
abbreviations. Again, this value should not be changed unless strictly
necessary.

=item FILE_PERMISSIONS

Octal number indicating the default permissions to use when creating
files using the autosubmission system. This is useful if, for example,
your webserver process is in a different group from that of your
users. The default is 0555.

=item DIR_PERMISSIONS

Octal number indicating the default directory permissions for the
autosubmission system. The default is 0777.

=item MX_ADF_REGEX

Regular expression to match the heading line of a MIAMExpress format ADF.

=item MAGETAB_ADF_REGEX

Regular expression to match the heading line of a MAGETAB format ADF.

=item MX_DBPARAMS

A hashref of parameters used in the MIAMExpress database connection.

=item AE_DBPARAMS

A hashref of parameters used in the ArrayExpress database connection.

=item AEDW_DBPARAMS

A hashref of parameters used in the AEDW database connection.

=item AUTOSUBS_DBPARAMS

A hashref of parameters used in the autosubmissions database connection.

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
