#!/usr/bin/env perl
#
=pod

=head1 NAME

Atlas::Common - functions shared by multiple programs in Atlas.

=head1 SYNOPSIS

	use Atlas::Common qw(
		create_atlas_site_config
	);

	# ...

	my $atlasSiteConfig = create_atlas_site_config;

=head1 DESCRIPTION

This module exports functions that are used by multiple different scripts and
classes in Atlas Perl code.

=cut

package Atlas::Common;

use 5.10.0;

use Moose;
use MooseX::FollowPBP;

use LWP::Simple;
use Log::Log4perl;
use DateTime;
use LWP::UserAgent;
use HTTP::Request;
use Config::YAML;
use File::Basename;
use File::Spec;
use URI::Escape;
use URL::Encode qw( url_encode_utf8 );
use XML::Simple qw( :strict );
use IPC::Cmd qw( can_run );

use EBI::FGPT::Config qw( $CONFIG );
use EBI::FGPT::Resource::Database::GXA;
# TODO: rpetry - a hack to prevent using Postgres module on anything other than RH7 (plantain VM runs RH6 and doesn't seem to have Postgres installed)
my $rhVersion = `cat /etc/redhat-release | awk '{print \$7}' | awk -F'.' '{print \$1}'`;
if ( "$rhVersion" == "7" ) {
  eval "use EBI::FGPT::Resource::Database::pgGXA;"; die $@ if $@;
}
use Atlas::AtlasContrastDetails;
use Atlas::Magetab4Atlas;

use base 'Exporter';
our @EXPORT_OK = qw(
    connect_pg_atlas
	download_atlas_details_file
	get_atlas_contrast_details
    get_supporting_file
	create_atlas_site_config
	get_log_file_header
	get_log_file_name
    make_http_request
    make_ae_idf_path
    make_idf_path
    create_non_strict_magetab4atlas
    get_aeatlas_controlled_vocabulary
    fetch_array_data_files
    fetch_ncbi_taxid
    http_request_successful
    get_array_design_name_from_arrayexpress
    check_privacy_in_ae
    fetch_isl_study_status
    get_load_base
    get_idfFile_path
    get_ena_study_id
    get_singlecell_idfFile_path
);


# Get the logger (if any).
my $logger = Log::Log4perl::get_logger;

=head1 METHODS

=over 2

=item _build_supporting_files_path

Find where the supporting_files folder is

=cut
sub _build_supporting_files_path {
    # Deduce the path to the config file from the path to this module.
    # This module's location on the filesystem.
    my $thisModulePath = __FILE__;

    # The directory this module occupies.
    my $thisModuleDir = dirname( $thisModulePath );

    # First split the directories we have.
    my @directories = File::Spec->splitdir( $thisModuleDir );

    # Get up to the atlasprod directory.
    while( $directories[ -1 ] ne "atlasprod" ) {
        pop @directories;

        unless( @directories ) {
            die "ERROR - Cannot find atlasprod directory in path to Atlas::Common. Please ensure this module is installed under atlasprod.\n";
        }
    }
    push @directories, "supporting_files";

    # Stick the remaining directories back together, now pointing to atlasprod directory.
    # Check that the supporting_files dir is in the dir now in $atlasprodDir.
    my $result = File::Spec->catdir( @directories );
    unless( -d $result ) {
        die "ERROR - Cannot find $result -- cannot locate site config.\n";
    }

    return $result;
}

=item get_supporting_file

Returns a path to a file in supporting_files directory

=cut

sub get_supporting_file {
	my ($file_name) =  @_;
    my $supporting_files_dir = _build_supporting_files_path();
    my $result = File::Spec->catfile(
		$supporting_files_dir,
		$file_name
	);
    unless( -r $result ) {
        die "ERROR - Cannot read supporting file: $result -- please check it exists and is readable by your user ID.\n";
    }
    return $result;
}

=item create_atlas_site_config

This function creates a new Config::YAML object representing the Atlas site
config YAML file, and returns it.

=cut
sub create_atlas_site_config {
    return Config::YAML->new(
        config => get_supporting_file("AtlasSiteConfig.yml"),
    );
}


=item get_log_file_name

This function creates a path to a log file in the user's ~/tmp directory and returns it.

=cut

sub get_log_file_name {

	my ( $nameBase ) = @_;

	unless( $nameBase ) {
		die "ERROR - No name provided for log file.";
	}

	my $home = $ENV{ "HOME" };

	my $filename = $nameBase . "_" . $$ . ".log";

	my $logFileName = File::Spec->catfile( $home, "tmp", $filename );

	return $logFileName;
}


=item get_log_file_header

This function creates a header to be used at the top of a log file.

=cut

sub get_log_file_header {

	my ( $description ) = @_;

	# Add the current time.
	my $headerText = $description . " log created at " . DateTime->now;

	# Add a dashed line and some newlines.
	$headerText .= "\n" . ( "-" x 80 ) . "\n\n";

	return $headerText;
}

=item download_atlas_details

This function takes a URL and downloads it, and returns the content in a
scalar. We use it e.g. for downloading the content of the contrastdetails.tsv
and assaygroupsdetails.tsv files.

=cut
sub download_atlas_details_file {

	my ( $url ) = @_;

	# Log what we're downloading.
	$logger->info( "Downloading $url..." );

	# Download the content.
	my $details = get $url;

	# Check that we got something, die if not.
	unless( defined( $details ) ) {
		$logger->logdie( "Unable to download content from $url" );
	}

	# If we're still here, log that the download was successful.
	$logger->info( "Download successful." );

	return $details;
}


sub get_atlas_contrast_details {

	my $atlasSiteConfig = create_atlas_site_config;

	my $url = $atlasSiteConfig->get_contrast_details_url;

	# Download the content from the URL.
	my $contrastDetailsContent = download_atlas_details_file( $url );

	# Split on newlines.
	my @contrastDetailsLines = split "\n", $contrastDetailsContent;

	# Empty hash to sort file lines into.
	my $sortedContrastDetails = {};

	# Go through the file
	foreach my $line ( @contrastDetailsLines ) {

		# Split on tabs
		my @splitLine = split "\t", $line;

		# Get the experiment accession and contrast ID.
		my ( $expAcc, $contrastID ) = @splitLine[ 0..1 ];

		# Add the line to the hash under this experiment accession and contrast ID.
		if( exists( $sortedContrastDetails->{ $expAcc }->{ $contrastID } ) ) {

			push @{ $sortedContrastDetails->{ $expAcc }->{ $contrastID } }, $line;
		}
		else {
			$sortedContrastDetails->{ $expAcc }->{ $contrastID } = [ $line ];
		}
	}

	# Empty array for Atlas::AtlasContrastDetails objects.
	my $allContrastDetails = [];

	# Go through the sorted file hash.
	foreach my $expAcc ( keys %{ $sortedContrastDetails } ) {

		foreach my $contrastID ( keys %{ $sortedContrastDetails->{ $expAcc } } ) {

			# Get the array of lines for this contrast.
			my $contrastFileLines = $sortedContrastDetails->{ $expAcc }->{ $contrastID };

			# Make a new Atlas::AtlasContrastDetails object.
			my $contrastDetails = Atlas::AtlasContrastDetails->new( file_lines => $contrastFileLines );

			# Add it to the array.
			push @{ $allContrastDetails }, $contrastDetails;
		}
	}

	return $allContrastDetails;
}


=item get_array_design_name_from_arrayexpress

Query ArrayExpress REST API for array design name using arraydesign accession.

=cut

sub get_array_design_name_from_arrayexpress {

	my ( $adfAcc ) = @_;

    my $atlasSiteConfig = create_atlas_site_config;

    my $adfQueryUrlBase = $atlasSiteConfig->get_arrayexpress_adf_info_url;

    my $adfQueryUrl = $adfQueryUrlBase . $adfAcc;

    my $content = make_http_request( $adfQueryUrl, "text" );

    # Parse out the array design name.
    my @splitLine = split /\t/, $content;

    # The name is the third element.
    my $adfName = $splitLine[ 2 ];

    unless( $adfName ) {

        $logger->debug( "Could not get name for ADF accession $adfAcc" );

        next;
    }

    chomp $adfName;

	return $adfName;
}

=item connect_pg_atlas

Create a connection to the postgres Atlas database.

=cut

sub connect_pg_atlas {

    $logger->info( "Connecting to pg Atlas database..." );

    # Connect to Atlas database.
    my $atlasDB = EBI::FGPT::Resource::Database::pgGXA->new
        or $logger->logdie( "Could not connect to pg Atlas database: $DBI::errstr" );

    $logger->info( "Connected OK." );

    return $atlasDB;
}


=item make_http_request

This function accepts a URL and a format ("xml", "json", or "text"), and runs
an HTTP request to retrieve content from the URL in the requested format.

=cut

sub make_http_request {

    my ( $url, $format, $externalLogger ) = @_;

    $logger = $externalLogger if $externalLogger;

    my $allowedFormats = {
        "xml"   => "application/xml",
        "json"  => "application/json",
        "text"  => "text/plain"
    };

    unless( $allowedFormats->{ lc( $format ) } ) {

        my $allowed = join ", ", ( keys %{ $allowedFormats } );

        $logger->error(
            "Format \"",
            $format,
            "\" is not one of the allowed formats: ",
            $allowed,
            ". Cannot complete HTTP request."
        );

        return;
    }

    # User agent to execute the query.
    my $userAgent = LWP::UserAgent->new;

    # Use the proxy from the current user's environment, if any.
    $userAgent->env_proxy;

    # Initialise an HTTP get request with the query URL.
    my $request = HTTP::Request->new(
        GET => $url
    );

    # We expect content matching the format requested. Don't allow anything
    # else.
    $request->header( 'Accept' => $allowedFormats->{ $format } );

    $logger->debug( "Querying for $format content from: $url ..." );

    my $response = $userAgent->request( $request );

    # If we got a 400 Bad Request, something's wrong with the query URL we're
    # sending, not the service we're querying. Warn and return.
    if( $response->code == 400 ) {

        $logger->warn(
            "Query unsuccessful: ",
            $response->status_line,
            ". Something is wrong with query URL: ",
            $url
        );

        # Return the response object so we know in calling code that
        # something's not right.
        return $response;
    }

    # Check if the request was successful.
    my $numRetries = 0;
    while( $numRetries < 10 && ! $response->is_success ) {

        $logger->warn( "Query unsuccessful: ", $response->status_line , ", retrying..." );

        $response = $userAgent->request( $request );

        $numRetries++;
    }

    unless( $response->is_success ) {
        $logger->error(
            "Maximum number of retries reached. Service appears to be unresponsive (",
            $response->status_line,
            ")."
        );

        # Return the response object so we know in calling code that
        # something's not right.
        return $response;
    }
    else {
        $logger->debug( "Query successful." );
    }

    # Warn if content is empty.
    if( ! $response->decoded_content ) {
        $logger->warn( "No content found for URL $url" );
    }

    # Return the decoded content (XML string, JSON string, ...).
    return $response->decoded_content;
}


sub check_privacy_in_ae {

    my ( $expAcc ) = @_;

    my $atlasSiteConfig = create_atlas_site_config;

    my $aePrivacyURL = $atlasSiteConfig->get_arrayexpress_privacy_info_url;

    my $privacyString = make_http_request( $aePrivacyURL . $expAcc, "text" );

    if( ref( $privacyString ) eq "HTTP::Response" ) {
        die "Didn't get a privacy status from $aePrivacyURL" . $expAcc . " : " . $privacyString->status_line . "\n";
    }

    chomp $privacyString;

    ( my $privacy = $privacyString ) =~ s/.*privacy:(\w+)\t.*/$1/;

    return $privacy;
}


sub fetch_isl_study_status {

    my ( $expAcc ) = @_;

    my $irapSingleLib = $ENV{ "IRAP_SINGLE_LIB" };

    unless( $irapSingleLib ) {
        die "IRAP_SINGLE_LIB environment variable is not set. Cannot continue.\n";
    }

    my $atlasSiteConfig = create_atlas_site_config;

    my $islStudyInfoScript = File::Spec->catfile(
        $irapSingleLib,
        $atlasSiteConfig->get_isl_study_info_script
    );

    unless( can_run( $islStudyInfoScript ) ) {
        die "Cannot run $islStudyInfoScript to check ISL status of experiment $expAcc.\n";
    }

    ( my $pipeline = $expAcc ) =~ s/E-(\w{4})-\d+/$1/;

    my $studyInfo;
    my $status;
    
    ## all direct import ENA experiemnts are processed by ISL.
    if ( $pipeline eq "ENAD" ) {
        $status = "Complete";
        return $status;
    }

    else {
        $studyInfo = `$islStudyInfoScript $expAcc 2>&1`;

        if( $? ) {
        die "Error running $islStudyInfoScript to check ISL status of experiment $expAcc:\n$studyInfo";
        }

        my @studyInfoLines = split /\n/, $studyInfo;

        my $record = $studyInfoLines[ 1 ];

        # If there's no record for this study, log an error and return undef.
        unless( $record ) {
        say STDERR "ERROR - No iRAP single-lib record found for $expAcc";
        return;
        }

        my @splitRecord = split /\t/, $record;

        $status = $splitRecord[ 5 ];
    }

    return $status;
}

sub get_ena_study_id {

    my ( $expAcc ) = @_;
    
    my $ena_id;
    my $idfFile;

    my $atlasSiteConfig = create_atlas_site_config;

    my $atlasProdDir = $ENV{ "ATLAS_PROD" };

    ( my $pipeline = $expAcc ) =~ s/E-(\w{4})-\d+/$1/;

    $idfFile = File::Spec->catfile(
        $atlasProdDir,
        $atlasSiteConfig->get_ena_experiment_load_dir,
        $pipeline,
        $expAcc,
        $expAcc . ".idf.txt"
    );

    open (my $in_idf, '<', $idfFile) or
    die("Could not open idf file - $idfFile. $!\n");

    my @record;
    while ( my $line = <$in_idf> ) {

    if ($line =~ /Comment\[SecondaryAccession\]/){
        push (@record, $line);
        last;
        }
    }

    unless( @record ) {
        say STDERR "ERROR - No ENA study id record found for $expAcc";
         return;
    }

    my @splitRecord = split /\t/, $record[ 0 ];

    $ena_id = $splitRecord[ 1 ];

    return $ena_id;
}

# Get the full path of the IDF file in the ArrayExpress load directory.
sub make_ae_idf_path {

    my ( $expAcc ) = @_;

    my $atlasSiteConfig = create_atlas_site_config;

    my $atlasProdDir = $ENV{ "ATLAS_PROD" };

    ( my $pipeline = $expAcc ) =~ s/E-(\w{4})-\d+/$1/;

    my $idfFile = File::Spec->catfile(
        $atlasSiteConfig->get_arrayexpress_experiment_load_dir,
        $pipeline,
        $expAcc,
        $expAcc . ".idf.txt"
    );

    return $idfFile;
}

# Get the full path of importRoute - geo/ena from the config file to
# import IDF file from the AtlasProd load directory.
## geo = $ATLAS_PROD/GEO_import/GEOD
## ena = $ATLAS_PROD/ENA_import/ERAD
sub make_idf_path {

    my ( $expAcc, $importPath ) = @_;

    my $atlasSiteConfig = create_atlas_site_config;

    my $atlasProdDir = $ENV{ "ATLAS_PROD" };

    ( my $pipeline = $expAcc ) =~ s/E-(\w{4})-\d+/$1/;

    my $import = "get" . "_" . "$importPath" . "_" . "experiment_load_dir";

    my $idfFile = File::Spec->catfile(
        $atlasProdDir,
        $atlasSiteConfig->${import},
        $pipeline,
        $expAcc,
        $expAcc . ".idf.txt"
    );

    return $idfFile;
}

sub get_load_base {
    my ( $expAcc ) = @_;
    my $loadBase;

    ( my $pipeline = $expAcc ) =~ s/E-(\w{4})-\d+/$1/;

    if ( $pipeline eq "MTAB" || $pipeline eq "ERAD" ) {
        $loadBase = "get_AUTOSUBMISSIONS_TARGET";
    }

    elsif ( $pipeline eq "GEOD") {
        $loadBase = "get_GEO_SUBMISSIONS_TARGET";
    }

    elsif ( $pipeline eq "ENAD" ) {
        $loadBase = "get_ENA_SUBMISSIONS_TARGET";
    }

    return $loadBase;
}

sub get_idfFile_path {

    my ( $expAcc ) = @_;
    my $idfFile;

    ( my $pipeline = $expAcc ) =~ s/E-(\w{4})-\d+/$1/;

    my $atlasSiteConfig = create_atlas_site_config;

    my $atlasProdDir = $ENV{ "ATLAS_PROD" };

    if ( $pipeline eq "GEOD" ) {
        $idfFile = File::Spec->catfile(
        $atlasProdDir,
        $atlasSiteConfig->get_geo_experiment_load_dir,
        $pipeline,
        $expAcc,
        $expAcc . ".idf.txt"
    );
        if ( ! -e $idfFile ) {
        $idfFile = make_ae_idf_path( $expAcc );
        }
    }

    elsif ( $pipeline eq "ENAD" ) {
        $idfFile = File::Spec->catfile(
        $atlasProdDir,
        $atlasSiteConfig->get_ena_experiment_load_dir,
        $pipeline,
        $expAcc,
        $expAcc . ".idf.txt"
    );
    }

    else  {
        $idfFile = make_ae_idf_path( $expAcc );
    }

    return $idfFile;
}


sub create_non_strict_magetab4atlas {

    my ( $expAcc, $importPath ) = @_;
    my $idfFile; 

    if ( $importPath eq "annotare" ) {
        $idfFile = make_ae_idf_path( $expAcc );
    }
    elsif ( $importPath eq "geo" || $importPath eq "ena" ) {
        $idfFile = make_idf_path( $expAcc, $importPath );
    }

    unless( -e $idfFile ) {

        $logger->logdie( "IDF does not exist: $idfFile" );
    }

    $logger->info( "Reading MAGE-TAB from $idfFile ..." );

    my $magetab4atlas = Atlas::Magetab4Atlas->new(
        "idf_filename" => $idfFile,
        "strict" => 0
    );

    $logger->info( "Finished reading MAGE-TAB." );

    return $magetab4atlas;
}

## single cell
sub get_singlecell_idfFile_path {

    my ( $expAcc ) = @_;
    my $idfFile;

    ( my $pipeline = $expAcc ) =~ s/E-(\w{4})-\d+/$1/;

    my $atlasProdDir = $ENV{ "ATLAS_PROD" };

    my $singleCellPath = "/singlecell/experiment";

        $idfFile = File::Spec->catfile(
        $atlasProdDir,
        $singleCellPath,
        $expAcc . ".idf.txt"
    );

    return $idfFile;

}

sub get_aeatlas_controlled_vocabulary {

    my $atlasSiteConfig = create_atlas_site_config;

    my $atlasProdDir = $ENV{ "ATLAS_PROD" };

    my $controlledVocabFile = $atlasSiteConfig->get_aeatlas_controlled_vocab_file;

    unless( -r $controlledVocabFile ) {
        die "Cannot read AE/Atlas controlled vocab file: $controlledVocabFile.\n";
    }

    my $aeatlasControlledVocabulary = Config::YAML->new(
        config => $controlledVocabFile
    );

    return $aeatlasControlledVocabulary;
}


=item fetch_array_data_files

Given an ArrayRef of Bio::MAGETAB::SDRFRow objects, this function returns an ArrayRef of raw
data filenames.

=cut

sub fetch_array_data_files {

    my ( $sdrfRows ) = @_;

    my $arrayDataFiles = {};

    foreach my $sdrfRow ( @{ $sdrfRows } ) {

        my @nodes = $sdrfRow->get_nodes;

        foreach my $node ( @nodes ) {

            # Find the raw data file. There could be normalized data files as
            # well.
            if( ref( $node ) eq "Bio::MAGETAB::DataFile" ) {

                my $dataType = $node->get_dataType->get_value;

                unless( $dataType eq "raw" ) { next; }
                else {

                    my $arrayDataFile = $node->get_uri;

                    $arrayDataFile =~ s/^file\://;

                    $arrayDataFile = uri_unescape( $arrayDataFile );

                    $arrayDataFiles->{ $arrayDataFile } = 1;
                }
            }
        }
    }

    my @arrayDataFiles = keys %{ $arrayDataFiles };

    return \@arrayDataFiles;
}


sub fetch_ncbi_taxid {

    my ( $queryOrganism, $externalLogger ) = @_;

    # If we were passed a logger to use, use that one.
    $logger = $externalLogger if $externalLogger;

    my $esearchBase = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=taxonomy&term=";

    my $esearchURL = $esearchBase . url_encode_utf8( $queryOrganism );

    my $esearchXML = make_http_request( $esearchURL, "xml" );

    unless( http_request_successful( $esearchXML ) ) {

        $logger->error(
            "Error querying NCBI taxonomy for taxid of $queryOrganism, with URL $esearchURL"
        );

        return;
    }

    my $esearchResult = XMLin(
        $esearchXML,
        ForceArray  => [
            "Id",
            "eSearchResult"
        ],
        KeyAttr => {
            "eSearchResult" => "QueryTranslation"
        }
    );

    my $idArray = $esearchResult->{ "IdList" }->{ "Id" };

    # Check that there's exactly one ID, error and return if not.
    if( !$idArray ) {
        $logger->error(
            "No NCBI taxonomy ID found for species \"",
            $queryOrganism,
            "\"."
        );

        return;
    }
    elsif( @{ $idArray } > 1 ) {
        $logger->error(
            "More than one NCBI taxonomy ID found for species \"",
            $queryOrganism,
            "\"."
        );

        return;
    }
    else {
        my ( $id ) = @{ $idArray };

        return $id;
    }
}


sub http_request_successful {

    my ( $result, $externalLogger ) = @_;

    # If we were passed a logger to use, use that one.
    $logger = $externalLogger if $externalLogger;

    # If the result is undefined, return 0 (unsuccessful).
    if( ! $result ) {

        return 0;
    }

    # If we got an HTTP::Response object back then something went
    # wrong with the query. Return 0 (unsuccessful).
    elsif( $result->isa( "HTTP::Response" ) ) {

        my $status = $result->status_line;

        $logger->error(
            "HTTP response was: $status. "
        );

        return 0;
    }
    # Otherwise, the query was successful, so return 1 (success).
    else {
        return 1;
    }
}

1;
