#!/usr/bin/env perl
#
# EBI/FGPT/ADFParser.pm
# 
# Amy Tang 2014 ArrayExpress team, EBI
#
# $Id: ADFParser.pm 26118 2014-11-17 11:13:21 amytang $


=pod

=head1 NAME

EBI::FGPT::Reader::ADFParser

=head1 SYNOPSIS

# Create a new ADF parser:

 use EBI::FGPT::Reader::ADFParser;
 
 my $parser = EBI::FGPT::Reader::ADFParser->new({
           'adf_path'  => $file_path,
     'custom_log_path' => $log_file_path,
 });

 $parser->check;

=head1 DESCRIPTION

MAGE-TAB format array design file (ADF) parser and checker. The checks run are:

=head2 Preparation before CPAN parsing

- Is it a Nimblegen NDF (if it is then no further check performed)

- ERROR if [main] divider line cannot be identified

- ERROR if duplicate column headings are found

- ERROR if any coordinate feature is repeated in the file

- ERROR if any Reporter Name value is missing

- ERROR if any Composite Element Name value is missing

- WARNING if mandatory headings ("Reporter Group [role]" and "Control Type") are missing (not an error, as GEO imported ADFs don't have such headings)

- ERROR if data is found in a column which has no heading ("stray data")

- ERROR if completely empty column found (has column heading)


=head2 Errors picked up by the CPAN parser during parsing

- ERROR if unrecognized MAGE-TAB ADF column names found

- ERROR if there are coordinate features but one of the coordinate columns (Block Column, Block Row, Column, Row) is missing

- ERROR if there are coordinate column headings, but either some values are missing from some rows, or coordinate column contains no values at all

- ERROR if some coordinate values are not whole numbers (\d+)

- ERROR if database entry is present in the ADF table but "Term Source Name" does not mention that database


=head2 Checks run post CPAN parsing

=head3 Meta-data checks

- ERROR if "Provider" field doesn't contain submitter's name followed by email address in brackets

- ERROR if no Comment[Description] provided.

- ERROR if no Comment[Organism] provided.

- ERROR if files mentioned in Comment[AdditionalFile:xxx] are not in the same directory as the ADF.

- ERROR if files mentioned in Comment[AdditionalFile:xxx] are blank (zero byte).

- WARNING if no "Technology Type" info provided.

- WARNING if no "Surface Type" info provided.

- WARNING if no printing protocol provided

- WARNING if no "Substrate Type" info provided.

=head3 Feature checks (only performed for ADFs that contain features):

- WARNING if array has too many (1500+) blocks (Zones)

- WARNING if blocks have too many features (1000+) to check for missing features

- WARNING if block does not contain expected number of features

=head3 Reporter checks (only performed if ADF contains reporters):
 
- ERROR if reporter has different annotation (e.g. DB entry, Composite Element Name) on different lines

- WARNING if reporter in group 'Experimental' has no annotation (sequence or database entry)

- WARNING if no reporters found in group 'Experimental'

=head3 Reporter database entry annotation check

- ERROR if the file containing database accession regex (adf_db_patterns.txt) can't be opened

- ERROR if the database name is not recognized (does not appear in the adf_db_patterns.txt regex file)

- ERROR if a database entry's accession does not match its regex

- WARNING if we do not have a regex for one of the databases used (it is set to 'UNKNOWN' in adf_db_patterns.txt regex file)

=head3 Reporter sequence and group/role checks

- ERROR if a sequence contains non-sequence letters or characters

- ERROR if Reporter Group [role] is not 'Control' or 'Experimental' (or is missing, case-insensitive)

- ERROR if a reporter has more than one role

- ERROR if an experimental reporter has a 'Control Type' value

- ERROR if a control reporter does not have a 'Control Type' value

- ERROR if a control reporter has a 'Control Type' value not an EFO term

- WARNING if a control reporter of type "array control biosequence" has no Reporter Sequence annotation

- ERROR if a control reporter of type "array control empty", "array control buffer" or "array control label" has Reporter Sequence annotation

=head3 Composite Element checks (if ADF contains composites):

- ERROR if Composite has different annotation on different lines

=head1 ATTRIBUTES

=over 2

=item logger (required)

A Log::Log4perl::Logger to handle logging messages

=item adf_path (required)

Path of the directory where the ADF file is

=item composites

Path to the composite mapping file, no checks developed for this yet

=item eol_char

The end-of-line character for the ADF file (because ADFs can come with different
styles of line-endings)

=item csv_parser

A Text::CSV_XS object which allows us to read and parse the ADF as a tab-delimited
text file

=item main_row_num

The row number at which the "[main]" section divider is found, separating the
meta-data section and the ADF table

=item col_headings

A reference to an array which stores normalised headings of the ADF table.
(Normalised = no underscores, no spaces, all lowercase). Set inside
"check_adf_col_headings" method.

=item adf_heading_value_hash_per_row

A reference to an array which holds one hash per ADF table row. In the hash,
key is the ADF table column heading, value is the data under that particular
heading. Set inside "check_empty_columns_stray_data" method.

=item arraydesign

A Bio::MAGETAB::ArrayDesign object created after the ADF file is parsed

=item nimblegen_status

A boolean variable indicating whether an ADF is a NimbleGen NDF (which we do
not check but just export for loading)

=item custom_log_path

Path to the custom log file location.  (Default location is the directory where
the ADF file is.)

=back

#############################################

=cut

package EBI::FGPT::Reader::ADFParser;

use Moose;
use MooseX::FollowPBP;

use Data::Dumper;

use Config::YAML;
use EBI::FGPT::Config qw($CONFIG);

use EBI::FGPT::Common qw(
    check_linebreaks
    );

use Bio::MAGETAB::Util::Reader;
use Bio::MAGETAB::Util::Reader::ADF;
use Bio::MAGETAB::ArrayDesign;

use Log::Log4perl;

use Log::Log4perl::Level;  # this allows global level variables such as "$DEBUG" be understood

use File::Spec;  # for copying files
use File::Copy;

use EBI::FGPT::Resource::BioPortal;   # for fetching ontology terms

has 'adf_path' => (is => 'rw', isa => 'Str', required => 1);

# path to the composite mapping file, no checks developed for this yet
has 'composites' => (is => 'rw', isa => 'Str');  

has 'eol_char'  => (is => 'rw',
                    isa=> 'Str',
                    builder => '_calculate_eol_char',
                    lazy => 1
                   );

has 'csv_parser' => (is => 'rw',
                     isa => 'Text::CSV_XS',
                     builder=> '_create_csv_parser',
                     lazy => 1
                    );
                   

has 'main_row_num' => (is => 'rw', isa => 'Str');

has 'col_headings' => (is => 'rw', isa => 'ArrayRef');

has 'adf_heading_value_hash_per_row' => (is => 'rw', isa => 'ArrayRef');

has 'arraydesign'   => (is => 'rw', isa => 'Bio::MAGETAB::ArrayDesign');

has 'nimblegen_status' => (is => 'rw', isa => 'Bool');

has 'logger'       => (is => 'rw', 
                       isa => 'Log::Log4perl::Logger', 
                       required => 1,
                       handles => [ qw(logdie fatal error warn info debug report) ],
                       builder => '_create_logger',
                       lazy => 1
                       );

has 'custom_log_path' => (is => 'rw', isa => 'Str');

has 'verbose_logging' => (
    is  => 'rw',
    isa => 'Bool',
    default => 0
);


#### The BUILDARGS method is called as a class method *before* an object is created.
#### It will receive all of the arguments that were passed to new() as-is, 
#### and is expected to return a hash reference. This hash reference will be used to construct the object,

sub BUILDARGS {
	my ( $class, $args ) = @_;
    my $adf_file_path = $args->{adf_file_path};
    $args->{adf_file_path} = $adf_file_path;
	return $args;
}


#### The BUILD method is called *after* an object is created.
#### One of the most common use of the BUILD method is to check that the object state is valid.
#### While we can validate individual attributes through the use of types (e.g. to check whether a certain
#### attribute is a "string" or "boolean"), we can't validate the state of a whole object that way, e.g.
#### we've got a string, but is the string's content what we expected?

# Check the ADFParser object was properly built before we start using it

sub BUILD {
	my ($self) = @_;
	$self->debug("Inside BUILD method.");
	#  Here I'm not checking whether the adf_path attribute is a string or not
	#  I'm checking whether the path is valid and the file is readable
	unless ( -r $self->get_adf_path ) {  
		$self->logdie(                   
        "ADF file location not found or the file is not readable, exiting."
		);
	}
}




###########                                    #############
########### MAIN CODE BLOCK RUNNING THE CHECK  #############
###########                                    #############


sub check{
  
    my ($self)  = @_;
    
    # Stage 1: Initiate logger, filter out NimbleGen NDF
    
    # initiate the "lazy" construction of the logger object as an attribute of this class
    my $logger = $self->get_logger;  
    
    # Don't check it if it's a Nimblgen NDF.
    # Will create and set the csv_parser attribute of the ADFParser class
    # while checking for nimblegen status, so we can get the csv_parser
    # object later for sanity checks prior to parsing with Bio::MAGETAB CPAN code.   
    
    $self->set_nimblegen_status($self->_is_nimblegen);

    if ( $self->get_nimblegen_status ){
        $self->warn("Nimblgen NDF heading found. No further checks will be done.");
        return 0;
    } else {
        $self->debug("Not Nimblegen NDF, continue with parsing.");
    }    
    
    # Stage 2: check the column headings of the ADF table as 
    # they aren't rigorously checked by the CPAN parser.
    # Will logdie if no [main] delimiter. Other problems will throw error.
    # Don't change the order of these two checks as some attributes of
    # ADFParser object are set in "check_adf_col_headings" method for
    # "check_empty_columns_stray_data" to use.
    
    $self->info("---------- CHECK ADF COLUMN HEADINGS ----------");  
    $self->check_adf_col_headings;
    
    $self->info("---------- CHECK FOR EMPTY COLUMNS AND STRAY DATA ---------");
    $self->check_empty_columns_stray_data;

    # Stage 3: check for presence of reporter or composite element names.
    # Reporter Names are only mandatory for features (with Block Column etc coordinates).
    # Any ADF rows with blank reporter or composite elements will simply be skipped
    # by the CPAN parser with no reporter/composite element object created!
       
    $self->info("---------- CHECK REPORTER OR COMPOSITE ELEMENT NAMES ----------");
    $self->check_reporter_or_comp_element_names;  
    
    # Stage 4: Proceed with MAGE-TAB ADF file parsing after checks in stages 2 and 3,
    # because the Bio::MAGETAB CPAN parser doesn't do those checks.
    # Get my parsed Bio::MAGETAB::DatabaseEntry::ArrayDesign object
    # The object has attributes like: "has_name", "has_provider", "has_designElements".
    # Each design element has "chromosome", has "feature", has "reporter", has "composite element"   
   
    $self->info("---------- ADF PARSING STARTS ----------");
   
    my $adf_reader = Bio::MAGETAB::Util::Reader::ADF->new({
        uri => $self->get_adf_path,
    });
 
    my $array_design;
 
    eval { $array_design = $adf_reader->parse() };

    if ($@ ) {
	    $self->logdie( "ADF parsing failed, can't proceed with checking ADF content:\n",
	    $@ );

    }
    else {
	    $self->info("---------- ADF PARSING ENDS SUCCESSFUL ----------");
        $self->set_arraydesign($array_design);
    }


    # Stage 5: After parsing, check the meta-data header (e.g. ADF name,
    # submitter details, ADF description etc)      
    
    $self->info("---------- CHECK HEADER META-DATA ----------");
    $self->check_header_metadata;

    # Stage 6: Get the key objects from the parsed ADF "table", before doing any checks:
    
    my $array_design_elements = $array_design->get_designElements;
    
    $self->debug (scalar(@{$array_design_elements})." array design elements were returned.");
    
    # The above returns a reference to an array of "design elements".
    # A microarray "feature" is a type of "design elements", so is
    # a microarray "reporter" or a "composite element".
     
    # $self->debug ( "The first array design element object is ${$array_design_elements}[0], 
                    # with the following structure:\n".
                    # Dumper(${$array_design_elements}[0]) ."\n" );

    my (@features, @reporters, @composites);
    
    foreach my $element(@{$array_design_elements}) {
        if ( $element->isa("Bio::MAGETAB::Feature") ) {
            push (@features, $element);
        } elsif ( $element->isa("Bio::MAGETAB::Reporter") ) {
            push (@reporters, $element);
        } elsif ( $element->isa("Bio::MAGETAB::CompositeElement") ) {
            push (@composites, $element);    
        }
    }    

    $self->info ("We have ".scalar@features." features, ".
                             scalar@reporters." reporters and ".
                             scalar@composites." composite elements.");
                             
    if ( scalar(@features) == 0 && scalar(@reporters) == 0 && scalar(@composites) == 0 ) {
        $self->error("There are no features or reporters at all. Will not proceed with any checks. Exiting.");
        return;
    }    
      
    # Stage 7: Feature-related checks
    
    if ( scalar(@features) ) {
        $self->info("---------- CHECK FEATURES ----------");
        $self->check_feature_count_per_block(\@features);
        $self->check_duplicate_features(\@features);        
    }
    
    # Stage 8a: Reporter checks

    if ( scalar(@reporters) ) {
        $self->info("---------- CHECK REPORTERS ----------");
        # Same reporter for different spots/features end up in 
        # the same reporter object. Reporter annotation on multiple
        # rows will end up in the same reporter object. 
        $self->check_reporter_consistency (\@reporters);
        $self->check_expt_reporters_have_annot(\@reporters);
    }   

    # Stage 8b: Annotation sanity and quality checks for reporters
    
    if ( scalar(@reporters) ) {
        $self->info("---------- CHECK ANNOTATION QUALITY ----------");
        $self->check_reporter_seq_sanity (\@reporters);
        $self->check_reporter_group_sanity (\@reporters);    
        $self->check_db_acc_sanity(\@reporters);   
    }    
    
    # Stage 9: Composite elemn
    if ( scalar(@composites) ) {
        $self->info("---------- CHECK COMPOSITES ----------");
        $self->check_composite_consistency (\@composites);
        $self->check_db_acc_sanity(\@composites);
    }    
    
}


###########                                    #############
###########  METHODS CALLED BY "CHECK" METHOD  #############
###########                                    #############


sub check_header_metadata {

    # No need to check ADF name as parsing would have failed if the name was missing.
    
    my ($self) = @_;
    my $arraydesign = $self->get_arraydesign;
    
    # Check the essential
    # While it's not crucial to have provider info in exactly this format: Joe Bloggs (job.bloggs@abc.com),
    # we still need to catch cases where potentially there isn't an email address.
    # ADF loader doesn't mind whether there is a space between the provider's name and the open brackets
    # for the email address.
    
    if (!$arraydesign->get_provider) {
        $self->error("No array design provider in the header.");
    } else {
        my $provider = $arraydesign->get_provider;
            unless ($provider =~ /.*\(+[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,4}\)/i) {  
            $self->error("Provider \'$provider\' should be written in this format: Joe Bloggs (job.bloggs\@abc.com).");
        }
    }                  
        
    my @organism_comments = grep {$_->get_name =~/organism/i} @{ $arraydesign->get_comments || []};
    
    if ( (!@organism_comments) || (scalar @organism_comments == 0) ) {
        $self->error("Organism info missing. 'Comment[organism]' must be included in the header and must be filled.");
    } else {
        $self->debug("ADF organism is: ".$organism_comments[0]->get_value);
    }    

    my @desc_comments = grep {$_->get_name =~ /description/i} @{ $arraydesign->get_comments || []};
    
    if ( (!@desc_comments) || (scalar @desc_comments == 0) ) {
        $self->error("ADF description missing. 'Comment[description]' must be included in the header and must be filled.");
    } else {
        $self->debug("ADF description is: ".$desc_comments[0]->get_value);
    }
    
    my @release_date_comments = grep {$_->get_name =~ /arrayexpressreleasedate/i} @{ $arraydesign->get_comments || []};
    
    if ( (!@release_date_comments) || (scalar @release_date_comments == 0) ) {
        $self->error("ArrayExpress release date missing. 'Comment[ArrayExpressReleaseDate]' must be included in the header (value = YYYY-MM-DD).");
    } elsif ($release_date_comments[0]->get_value !~ /\d{4}-\d{2}-\d{2}/)  {
        $self->error("ArrayExpress release date ". $release_date_comments[0]->get_value . " is not in a recognised format. Must use YYYY-MM-DD.");       
    } else {
        $self->debug("AE release date is: ".$release_date_comments[0]->get_value);
    }  
        
   
    # Check that additional files mentioned in meta-data header exist. 
    # Expects additional files to be in the same directory as the ADF.
    
    my @file_comments = grep {$_->get_name =~/additional/i} @{ $arraydesign->get_comments || []};
    
    if (scalar @file_comments > 0) {
        my $input_filename = $self->get_adf_path();
        my ( $vol, $dir, $name ) = File::Spec->splitpath($input_filename);
        # for cases where the adf file is in the same dir as the working dir. without this fix, catfile will insert a "/" before filename:
        $dir = "./" if ($dir eq '');  
        FILE_COMMENT: foreach my $file_comment (@file_comments) {
            my $path = File::Spec->catfile( $dir, $file_comment->get_value );
		    unless ( -r $path ) {
			    $self->error("Additional file $path not found or unreadable.\n");
			    next FILE_COMMENT;
		    }

		    if ( -s $path == 0 ) {
			    $self->error("Additional file $path is empty (zero bytes).\n");
		    }
	    }
    }  

    # Check optional, nice-to-have information.
    # Decided to keep them separate so we can easily remove
    
    if (!$arraydesign->get_technologyType) {
        $self->warn("No Technology Type info provided.");
    }
       
    if (!$arraydesign->get_surfaceType) {
        $self->warn("No Surface Type info provided.");
    }      
    
    if (!$arraydesign->get_printingProtocol) {
        $self->warn("No array printing protocol provided.");
    }       
     
    if (!$arraydesign->get_substrateType) {
        $self->warn("No Substrate Type info provided.");
    }    
}    


sub check_adf_col_headings {
    
    # The headings aren't parsed as mandatory objects in the Bio::MAGETAB
    # model so we can't access them via the CPAN ArrayDesign object.
    # We have to resort to old-fashioned line-by-line parsing of tab-delimited
    # text file. csv_parser attribute has previously been set in _is_nimblegen
    # method.
    
    my ($self) = @_;
    my $file = $self->get_adf_path;
    open (my $adf_fh, "<", $file);
    
    local $/ = $self->get_eol_char;
 
    # First, identify the row number where the "[main]" line starts 
    
    my $start_line_row_num = 1;

    my $csv_parser = $self->get_csv_parser;
    $self->debug( "csv_parser returned is $csv_parser, of class ".ref($csv_parser) );

    LINE: while (my $line = $csv_parser->getline($adf_fh) ) {
        my $line_string = join( q{}, @$line );
        if ($line_string =~/^\[main\]$/) {  # next line will be the header
           $self->set_main_row_num($start_line_row_num);                     
           last LINE;
        } else {   
           $start_line_row_num ++;
        }
    } 

    close $adf_fh;
    
    # The next line after "[main]" is the header line. 
    
    my %col_heading_hash; # key = normalised heading string, value = how many times the string is seen
    my %raw_new_heading_hash; # key = new normalised heading, value = old heading
    
    if (!$self->get_main_row_num) { # can't find the [main] line in the entire file
        $self->logdie("Can't find the delimiter '\[main\]' between header and ADF table. Parsing will fail.");
    } 
    
    else {
        my $header_row_num = ($self->get_main_row_num) + 1;
        $self->debug ("Header starts at row $header_row_num.");
        # we have to open the file again to get to the header line!
        open (FILE, "<", $file) or die $!;
        
        my @adf_table_col_headings; # for storing normalised headings
        
        while (<FILE>) {
            if ( ($. == $header_row_num) && ($csv_parser->parse($_)) ) {
            # i.e. if row number matches and the parsing of the row returns "true"
                my @raw_col_headings = $csv_parser->fields();
                foreach my $raw_heading (@raw_col_headings) {
                    my $new_heading = $self->_normalize($raw_heading);
                    $raw_new_heading_hash{$new_heading} = $raw_heading;
                    push (@adf_table_col_headings, $new_heading);
                }    
                
                $self->set_col_headings(\@adf_table_col_headings);
                
                foreach my $heading(@adf_table_col_headings) {
                    if ($heading ne '') {
                        $col_heading_hash{$heading}++;    # Don't want to count empty headings
                     }    
                }
                last;
            }
        }
        close FILE;
    }     
    
    # First check: No column heading should appear twice.
    # In some cases, information from both columns will be assigned to a design element, e.g.
    # two values for "Reporter Group [role]". In other cases, e.g. "control type", information
    # in the second column will over-write the first's.
    
    foreach my $heading(keys %col_heading_hash) {
        if ( $col_heading_hash{$heading} > 1 ) {
             my $orig_head_name = $raw_new_heading_hash{$heading};
             $self->logdie("Column heading '$orig_head_name' appears ".$col_heading_hash{$heading}." times. Parsing will fail");
        }     
    }    
    
    # Second check: make sure all non-feature related mandatory headings are present,
    # and composite-related headings are not present.
    
    # This only applies to ADFs with reporters.
    # Not checking Block Column, Block Row, Reporter Name etc as such
    # problems would be picked up by the CPAN parser as parser-fail.
    
    if  ( ( grep 'reportername' eq $_,  keys%col_heading_hash ) &&
          ( !grep 'compositeelementname' eq $_,  keys%col_heading_hash ) ) {

        my @mandatory_headings = ('Reporter Group[role]', 'Control Type');
        my @banned_strings = 'composite';
    
        foreach my $man_heading (@mandatory_headings) {           
            my $clean_man_heading = $self->_normalize($man_heading);

            # Other forms of grep somehow don't work...
            if  ( !grep $clean_man_heading eq $_,  keys%col_heading_hash ) {
                $self->warn("Mandatory column '$man_heading' is missing."); 
            }
        }
        
        foreach my $banned_string (@banned_strings) {
            foreach my $col_heading ( keys%col_heading_hash ) {
                if ($col_heading =~ /$banned_string/) {
                    my $orig_col_heading = $raw_new_heading_hash{$col_heading};
                    $self->logdie("There are no composite elements in this ADF so column '$orig_col_heading' is not allowed. Parsing will fail.");
                }
            }
        }        
            
    } 

    # Third check: for ADFs with composite elements only (no features, no reporters),
    # there are columns which we don't expect to see, e.g. "Reporter Group[role]"
    # Banning any headings that start with "Reporter", and "Control Type"
    
    if  ( ( grep 'compositeelementname' eq $_,  keys%col_heading_hash ) &&
          ( !grep 'reportername' eq $_,  keys%col_heading_hash ) ) {
        
        my @banned_strings = ('reporter', 'controltype');
    
        foreach my $banned_string (@banned_strings) {
            foreach my $col_heading ( keys%col_heading_hash ) {
                if ($col_heading =~ /$banned_string/) {
                    my $orig_col_heading = $raw_new_heading_hash{$col_heading};
                    $self->logdie("There are no reporters in this ADF so column '$orig_col_heading' is not allowed. Parsing will fail.");
                    
                }
            }
        } 
    }
}


sub check_empty_columns_stray_data { 

    # Caveat: This check will raise false alarm when the Term Source Name / Term Source File
    # section in the header is exceedingly long and cover more columns than the
    # ADF table.  We had a similar problem with IDF/SDRF parsing when (very rarely) 
    # the IDF has more columns than the SDRF
    
    my ($self) = @_;
    my $file = $self->get_adf_path;
    my $csv_parser = $self->get_csv_parser;
    my $headings = $self->get_col_headings; # set in "check_adf_col_headings" method, already normalised
    
    local $/ = $self->get_eol_char;
    
    my @adf_values; # This will hold many hashrefs

    open (my $adf_fh, "<", $file) or die $!;
    
    # We build an anonymous hash for each row of data.
    # key = col heading, value = data under that heading.
    # The anonymous hash will be pushed into @adf_values.
    # Once all rows have been processed, we can work out
    # which column has a heading but no data at all.
    
    # While building the hash, we take the opportunity
    # to check for the reverse, i.e. stray data with no column headings
    
    # The array of hashes will be used in some checks after the CPAN
    # code parsing (see check_reporter_consistency method) 

    my %stray_col_num;

    while ( my $line = $csv_parser->getline($adf_fh) ) {
        # skip the ADF meta-data, "[main]" row AND ADF table headings
        if ($. >  ( $self->get_main_row_num + 1 ) ) {
            
            my @rowlist = @$line;
            my $heading_data_hash_per_row;  # one hashref per row,                   
                        
            for ( my $col_index = 0; $col_index < scalar(@$headings); $col_index++ ) {
                
                # no heading but have stuff in the ADF table's row 
                if ( ( $headings->[$col_index] eq '' ) && ( $rowlist[$col_index] ne '' ) ) {  
                    $stray_col_num{$col_index+1}++;   # The counter starts from "0", but human counting starts from "1"!
                }

                $heading_data_hash_per_row->{ $headings->[$col_index] } = $rowlist[$col_index];   # store $rowlist[$col_index] even if it's ''       
            }
            push @adf_values, $heading_data_hash_per_row;           
        }    
    }    
   
    close $adf_fh;
    
    $self->set_adf_heading_value_hash_per_row(\@adf_values);
    
    if (keys %stray_col_num) {
        my $stray_cols = join ",", sort (keys %stray_col_num) ;
        $self->error("Column(s) $stray_cols has/have no heading but contain stray data.");
    }    
        
    $self->debug("There are ".scalar(@adf_values)." in adf_values hash.");
 
    # Catch columns with heading but no data at all
       
    HEADING: foreach my $heading (@{$headings}){
        next HEADING if ($heading eq '');
        my $blank_rows_count_per_heading = 0 ;
        foreach my $line ( @adf_values ){
            $blank_rows_count_per_heading++ if ( $line->{$heading} eq '' );    
        }
        if ( $blank_rows_count_per_heading == scalar(@adf_values) ) {
            $self->error("Column \'$heading\' is empty.");
        }    
    }
}


sub check_reporter_or_comp_element_names {

    my ($self) = @_;
    
    my $main_row_num = $self->get_main_row_num;
    my @adf_values = @{$self->get_adf_heading_value_hash_per_row()};
    my @col_headings = @{$self->get_col_headings()};

    my @missed_reporter_rows;
    my @missed_composite_rows;
    
    my $adf_table_row = 0;
    
    foreach my $per_row_hash (@adf_values) {
        $adf_table_row ++;
        if ( ( grep 'reportername' eq $_, @col_headings ) && 
             ( !$per_row_hash->{'reportername'} ) ){
            my $missed_row = $main_row_num+1+$adf_table_row;
            push (@missed_reporter_rows, $missed_row);
        }
        
        elsif ( ( grep 'compositeelementname' eq $_, @col_headings) && 
             (!$per_row_hash->{'compositeelementname'} ) ){
            my $missed_row = $main_row_num+1+$adf_table_row;
            push (@missed_composite_rows, $missed_row);
        }
    }
    
    if ( scalar@missed_reporter_rows < 20 ) {
        foreach my $missed (@missed_reporter_rows) {
            $self->error("Reporter Name is missing from row $missed.");
        }
    } else {
        my $count = scalar@missed_reporter_rows;
        $self->error("$count rows don't have reporter names (too many to list).")
    }
    
    if ( scalar@missed_composite_rows < 20 ) {
        foreach my $missed (@missed_composite_rows) {
            $self->error("Composite Element Name is missing from row $missed.");
        }
    } else {
        my $count = scalar@missed_composite_rows;
        $self->error("$count rows don't have composite element names (too many to list).")
    }  
        
}


sub check_duplicate_features{

    my ($self, $features) = @_;
        
    $self->info("---------- Checking for duplicate features...");
    
    my %combo_coord_hash;
    
    foreach my $feature (@$features) {

        my ($block_col, $block_row, $col, $row);     
           
        $block_col = $feature->get_blockCol(); 
        $block_row = $feature->get_blockRow();
        $col = $feature->get_col;
        $row = $feature->get_row;
        # No need to check whether the coordinate string contains any
        # whitespaces as the CPAN ADF Reader strips off all whitespaces
        # before creating the parsed array_design object
        
        my $combo_string = "$block_col\t$block_row\t$col\t$row";
        $combo_coord_hash{$combo_string}++;   
    }
    
    # Check if any concatenated coordinate strings appear more
    # than once
    
    foreach my $string(keys %combo_coord_hash) {
        if ( $combo_coord_hash{$string} > 1 ) { 
            my $frequency = $combo_coord_hash{$string};        
            $string=~s/\t/-/g;   # replaced the tab characters with a dash for easy reading
            $self->error("Feature with coordinates $string (block_col, block_row, col, row) appears $frequency times.");
        }    
    }
}


sub check_feature_count_per_block {

    my ($self, $features) = @_;    
    
    # build feature arrays and find maximums
    $self->info("---------- Counting no. of blocks and no. of features per block...");

    my %maximums;
    my @coord_types = ("blockCol", "blockRow", "col", "row");
    
    # Initialise the %maximums hash values
    
    foreach my $coord_type (@coord_types) {
       $maximums{$coord_type} = 0;
    }   
       
    foreach my $feature (@$features) {
        foreach my $coord_type(@coord_types) {
            my $coord_access_method = "get_$coord_type";
            my $coord_value = $feature->$coord_access_method;
            if ( $coord_value > $maximums{$coord_type} ) {
                $maximums{$coord_type} = $coord_value;
            }
        }        
    }        
    
    $self->info("Maximum block column, block row, column, row values are ".
                  $maximums{blockCol}.", ".
                  $maximums{blockRow}.", ".
                  $maximums{col}.", ".
                  $maximums{row}."\n");
                 
    
    # Check how many blocks and features per block we've got.
    # Skip feature count per block if the numbers are overwhelming
    
    if ( $maximums{"blockCol"}*$maximums{"blockRow"} > 1500 ) {
        $self->warn("Array has more than 1500 blocks. Skipping feature count per block.");
    }
    elsif ( $maximums{"col"}*$maximums{"row"} > 1000 ) {
        $self->warn("Each block has more than 1000 features. Skipping feature count per block.");
    }
    else {
        my $blocks_with_missing_features_count = 0;
        my $expected=$maximums{"col"}*$maximums{"row"};

        foreach my $i (1..$maximums{"blockCol"}){
            foreach my $j (1..$maximums{"blockRow"}){
                my $count = 0 ;
                foreach my $feature (@$features) {
                    if ( ( $feature->get_blockCol == $i ) && ( $feature->get_blockRow == $j ) ) {
                        $count++;
                    }
                }    

	            # If the count is not as expected...

	            if ($count != $expected) {
	                $self->warn("Incorrect number of features in block_column $i - block_row $j ".
	                            "($expected features expected, but only found $count features).");
	                $blocks_with_missing_features_count++;

	                if ($expected-$count>100){
	                	$self->error("More than 100 features missing from block $i-$j (too many to list here).");
	                }

                    # Identify missing features if there aren't too many
	                else {
	                    # Get all features which lie within one block
	                    my @block = grep{ ($_->get_blockCol==$i) && ($_->get_blockRow==$j)} @$features;
	                    # Loop through the columns and rows of each feature inside that block
	                    foreach my $k (1..$maximums{col}){
	                        foreach my  $l (1..$maximums{row}){
		                        if(!grep{$_->get_col==$k && $_->get_row==$l}@block){
		                        	$self->error("Missing feature: $i-$j-$k-$l (block_col, block_row, col, row).");
		                        }
	                        }
	                    }
	                }

	            }
             }
         }
         $self->info("All blocks contain $expected features as expected.") if ( $blocks_with_missing_features_count==0 );
    }    
}



sub check_reporter_consistency {
    
    my ($self, $reporters) = @_;
    
    $self->info("---------- Checking DB entries and reporter role consistency...");
    
    # First, use the CPAN parsed reporters to do DB entry and reporter role checks:
    
    foreach my $reporter (@$reporters) {
        
        my $reporter_name = $reporter->get_name;

        my %mini_db_entry_hash;
        if ($reporter->get_databaseEntries) {
            foreach my $db_entry ( @{ $reporter->get_databaseEntries } ) {
                # term source is always defined for a db entry,
                # or else CPAN parser would have thrown fatal error
                my $db_acc = $db_entry->get_accession;
                my $db_source = $db_entry->get_termSource->get_name;
                push (@{$mini_db_entry_hash{$db_source}}, $db_acc);
            }
        }
        
        foreach my $db_name (keys %mini_db_entry_hash) {
            my @acc = @{ $mini_db_entry_hash{$db_name} };
            if ( scalar @acc > 1 ) {
                my $multi_db_entry_per_reporter = join (", ", @acc);
                $self->error("Reporter $reporter_name has inconsistent entries for database \'$db_name\': $multi_db_entry_per_reporter.");
            }
        }

        # Each reporter should only have one "Repoter Role" column (it's checked by
        # check_adf_col_headings already). Multiple "Reporter Role" values are still
        # possible if one reporter has different roles on different rows.
           
        my @roles = ( grep {$_->get_category eq "role"} @{ $reporter->get_groups } );
        if (scalar @roles > 1) {
            my @role_names = map { $_->get_value } @ roles;
            my $multi_roles_per_reporter = join (", ", @role_names);
            $self->error("Reporter $reporter_name has multiple roles: $multi_roles_per_reporter.");
        }
    }
    
    # For checking of reporter sequence and control type, 
    # CPAN parser doesn't keep more than one value per reporter.
    # If a reporter has two sequences, for example, the second one
    # will overwrite the first one. Therefore, we cannot use the
    # parsed reporter objects to do these two checks
       
    my @adf_values = @{$self->get_adf_heading_value_hash_per_row};  # set in "check_empty_columns_stray_data" method
    
    my %reporter_name_seq_hash;
    my %reporter_name_control_type_hash;
    my %reporter_name_composite_name_hash;
    
    foreach my $adf_row(@adf_values) {
        my $name = $adf_row->{'reportername'};
        my $sequence = $adf_row->{'reportersequence'};
        my $control_type = $adf_row->{'controltype'};
        my $composite_name = $adf_row->{'compositeelementname'};        
        
        push(@{$reporter_name_seq_hash{$name}}, $sequence) if ($sequence);
        push(@{$reporter_name_control_type_hash{$name}}, $control_type) if ($control_type);
        push(@{$reporter_name_composite_name_hash{$name}}, $composite_name) if ($composite_name);
    }


    $self->info("---------- Checking reporter sequence consistency...");
    foreach my $reporter_name (keys %reporter_name_seq_hash) {        
        my @seqs = @{$reporter_name_seq_hash{$reporter_name}};
        my %mini_seq_count_hash;
        if (scalar @seqs > 0) {
            foreach my $seq (@seqs) {
                $mini_seq_count_hash{$seq} ++;
            }    
            if (keys %mini_seq_count_hash > 1 ){
                my $multi_seqs_per_reporter = join (", ", keys %mini_seq_count_hash);
                $self->error("Reporter $reporter_name has more than one sequence: $multi_seqs_per_reporter.");
            }
        }    
    }
  
    
    $self->info("---------- Checking reporter control type consistency...");
    foreach my $reporter_name (keys %reporter_name_control_type_hash) {  
        my @types = @{$reporter_name_control_type_hash{$reporter_name}};
        my %mini_types_count_hash;
        if (scalar @types > 0) {
            foreach my $type (@types) {
                $mini_types_count_hash{$type} ++;
            }    
            if (keys %mini_types_count_hash > 1 ){
                my $multi_types_per_reporter = join (", ", keys %mini_types_count_hash);
                $self->error("Reporter $reporter_name has more than one control type: $multi_types_per_reporter.");
            }
        }    
    }
    
    $self->info("---------- Checking reporter -- composite element association consistency...");
    foreach my $reporter_name (keys %reporter_name_composite_name_hash) {
        my @comp_names = @{$reporter_name_composite_name_hash{$reporter_name}};
        my %mini_comp_names_count_hash;
        if (scalar @comp_names > 0) {
            foreach my $comp_name (@comp_names) {
                $mini_comp_names_count_hash{$comp_name} ++;
            }    
            if (keys %mini_comp_names_count_hash > 1 ){
                my $multi_comp_per_reporter = join (", ", keys %mini_comp_names_count_hash);
                $self->error("Reporter $reporter_name is associated with more than one composite element: $multi_comp_per_reporter.");
            }
        }    
    }
}

sub check_expt_reporters_have_annot {

    my ( $self, $reporters ) = @_;

    my $expt_reporter_count = 0 ;
    my @expt_reporters;
    
    foreach my $reporter (@$reporters) {
        my @roles = grep {$_->get_category eq "role"} @{ $reporter->get_groups };
        if (scalar @roles == 1) {  # one role per reporter
            my @role_names = map { $self->_normalize($_->get_value) } @roles;
            if ( grep 'experimental' eq $_, @role_names ) {
                push (@expt_reporters, $reporter);
                $expt_reporter_count++;
            }    
        }
    }    
    
    if ( $expt_reporter_count == 0 ) {
        $self->warn("There are no reporters with role 'experimental'.");
        return;     # No point doing annotation check if we have no experimental reporters
    }
    
    $self->info("---------- Checking experimental reporters for annotation...");
    
    # We allow experimental reporters to have either sequence or DB entry to
    # pass this check.
    # Not worried about multiple sequences or DB entries over-writing each other
    # per reporter, as those problems would have been caught by check_reporter_consistency
    # and check_adf_col_headings
    
    my $annotated_count = 0;
   
    foreach my $expt_reporter (@expt_reporters) {
        if ( ( $expt_reporter->get_sequence ) || ( $expt_reporter->get_databaseEntries ) ){
            $annotated_count ++;
        }
    }    

    
    if ($annotated_count > 0) {
        my $percent = sprintf("%.2f", $annotated_count/$expt_reporter_count * 100); # only want 2 decimal places
        $self->info("$percent% of experimental reporters have sequence, DB entry, or both as annotation");
        if ($percent < 10 ){
            my $missing_annot_count = $expt_reporter_count - $annotated_count;
            my $missing_percent = 100-$percent;
            $self->warn("$missing_annot_count of $expt_reporter_count [$missing_percent%] reporters have no sequence annotation or database cross references.");
        }
    } else {
        $self->warn("None of the reporters have sequence annotation or database cross references.");        
    }        
    
}


sub check_reporter_seq_sanity {

    my ( $self, $reporters ) = @_;
    $self->info("---------- Checking reporter sequence sanity...");

    REPORTER: foreach my $reporter (@$reporters) {

        my $reporter_name = $reporter->get_name;
        
        # Work out the role of the reporter first
        my @roles = grep {$_->get_category eq "role"} @{ $reporter->get_groups };
        my @role_names = map { $self->_normalize($_->get_value) } @roles;
                
        if ($reporter->get_sequence) {  # has sequence
        
           # Make sure "control type" is not undef for control probes
           if ( ( grep 'control' eq $_, @role_names ) &&  ($reporter->get_controlType) ) {
               if ( ($reporter->get_controlType->get_value)=~/empty|buffer|label/ ) {  # not expecting sequence
                $self->error("Control probe \'$reporter_name\' is of type \'".$reporter->get_controlType->get_value."\'. It should not have any sequence annotation.");
              }
           }    
           
           unless (length($reporter->get_sequence) > 4) { # too short
               $self->error ("Sequence for reporter ".$reporter->get_name." is too short (< 5 bases).");
               next REPORTER;
           }    

           if ( ($reporter->get_sequence) =~/[OJ]/i ) {  # only O, J and U aren't assigned to amino acids, U is for uracil
               $self->error("Reporter ".$reporter->get_name." has sequence containing unrecognised character(s): ".$reporter->get_sequence.
                        ". Letter O or J are not valid symbols for nucleotides or amino acids.");
           }
        }       
        
        else {  # no sequence
            # Make sure "control type" is not undef for control probes
            if ( ( grep 'control' eq $_, @role_names ) &&  ($reporter->get_controlType) ) {
                if ( $reporter->get_controlType->get_value eq "array control biosequence" ) {
                $self->warn("Control biosequence probe \'$reporter_name\' does not have sequence annotation.");
                }
            }
        }            
    } 
}

sub check_reporter_group_sanity {

    my ( $self, $reporters ) = @_;
    $self->info("---------- Checking reporter group (Experimental or Control) sanity...");
    
    my %uniq_ctrl_types_to_check;
    my @disallowed_control_types;
        
    my $bioportal = EBI::FGPT::Resource::BioPortal->new(
					subtree_root => "http%3A%2F%2Fwww.ebi.ac.uk%2Fefo%2FEFO_0005440",
					ontology     => "EFO",
					exact_match  => "true"
	);
	
    REPORTER: foreach my $reporter (@$reporters) {
        
        my $reporter_name = $reporter->get_name;
        my @roles = grep {$_->get_category eq "role"} @{ $reporter->get_groups };
              
        if (scalar @roles == 1) {  # one role per reporter
            my @role_names = map { $self->_normalize($_->get_value) } @roles;
            
            # check role term
            unless ( ( grep 'experimental' eq $_, @role_names ) || ( grep 'control' eq $_, @role_names ) ) {
                $self->error("Reporter $reporter_name has an unrecognised role: \'$role_names[0]\'. Allowed roles are 'experimental' and 'control'.");
                next REPORTER;
            }
            # check expt reporters
            if ( ( grep 'experimental' eq $_, @role_names ) && ($reporter->get_controlType) ) {
                $self->error("Experimental reproter $reporter_name should not have a 'control type'.");
                next REPORTER;
            }

            # check control reporters

            # Note: CPAN parser only stores one control type per control reporter, whichever it comes across last during parsing.
            # If one control reporter has several control types, we catch that in method "check_feature_consistency".
            # If several of the control types are disallowed, this check may not pick them up, since it depends on which type
            # got stored in the parsed object.
            
            if ( grep 'control' eq $_, @role_names ) {
                if (!$reporter->get_controlType) {
                    $self->error("Control reproter $reporter_name has no 'control type'.")
                }             
                else {
                    my $control_type_value = $reporter->get_controlType->get_value;
                    $uniq_ctrl_types_to_check{$control_type_value} = 1;
                }
            }        
        }
        elsif (scalar @roles > 1) {
            $self->error("Reporter $reporter_name has more than one role.");
        }   
    }
    
    foreach my $ctrl_type_to_check (keys %uniq_ctrl_types_to_check) {
        my $matches = $bioportal->query_adf_term($ctrl_type_to_check);
        if ( !$matches ) {  # no match at all
            $self->debug("No match for ".$ctrl_type_to_check);
               push (@disallowed_control_types, $ctrl_type_to_check);
        } else {  # only similar matches but not exact.
            # What bioportal considers as "similar" match is quite conservative. The term may be OK after all, so check further
            $self->debug('Only partial match for "'.$ctrl_type_to_check.'". The matches are '.join(", ", @$matches));
            unless ( grep $ctrl_type_to_check eq $_, @$matches ) {                           
                push (@disallowed_control_types, $ctrl_type_to_check)
            }    
        }           
    }   
    
    if (scalar @disallowed_control_types) {
        my $bad_types_string = join (", ", @disallowed_control_types);
        $self->error("Reporter control type(s) '$bad_types_string' is/are not allowed. The allowed terms are ".
                     "'array control biosequence', 'array control buffer', 'array control empty', ".
                     "'array control genomic DNA', 'array control label', 'array control reporter size', ".
                     "'array control spike calibration' and 'array control design'.");
    }
}

sub check_db_acc_sanity {
    
    # This method should work for both reporters and composite elements.
    # "get_databaseEntries" call should work on both types of objects
    
    my ( $self, $design_elements ) = @_;
    
    $self->info("---------- Checking external database accession reference sanity...");
    
    unless ( $CONFIG->get_ADF_DB_PATTERN_FILE ) {
       $self->error("Cannot find ADF DB pattern file via config file, cannot check database accession sanity.");
       return;
    }   
       
    my $adf_db_pattern_file_path = $CONFIG->get_ADF_DB_PATTERN_FILE;
    
    my %adf_db_pattern = % { $self->_load_db_patterns($adf_db_pattern_file_path) } ;           
    
    # We need the next three hashes so we don't print out "xxx db unrecognised" or similar error for every single reporter
    
    my ( %unrecognised_db_source ,  %unrecognised_regex ,  %unimplemented, %aggregate) ;
    my $has_chromosome_coord = 0;
                                                        
    foreach my $design_element (@$design_elements) {
        
        my $design_element_name = $design_element->get_name;

        if ($design_element->get_databaseEntries) {
            foreach my $db_entry ( @{ $design_element->get_databaseEntries } ) {
                
                # term source name is always defined for a db entry,
                # or else CPAN parser would have thrown fatal error
                
                # Database entries for composite elements can be separated by semi-colons
                # and CPAN parser stores each accession in one databaseEntries object.
                #  For reporters, the parser doesn't parse semi-colon separated values
                # so we have to do it here before checking accessions against regex
                
                my $db_acc_string = $db_entry->get_accession;
                my @db_acc;
                
                if ( $design_element->isa("Bio::MAGETAB::Reporter") ) {
                    @db_acc = split (/;/, $db_acc_string);
                } else {
                    push (@db_acc, $db_acc_string);    
                }    
                                   
                my $db_source = $db_entry->get_termSource->get_name;

                # Take care of chromosome coordinaet as a special case because
                # the DB source name will change depending on the genome assembly
                # used, except for the "chromosome_coordinate" prefix.
                
                if ($db_source =~/^chromosome_coordinate/) {
                    $has_chromosome_coord = 1;
                    $db_source = "chromosome_coordinate";
                }    
                
                if ( !$adf_db_pattern{$db_source} ) {
                    $unrecognised_db_source{$db_source} = 1;
                } else {
                    my $regex = $adf_db_pattern{$db_source};
                    if ( $regex eq "UNKNOWN" ) {
                        $unimplemented{$db_source} = 1;
                    } elsif ( $regex eq "AGGREGATE" ) {
                        $aggregate{$db_source} = 1;
                    } else {
                        foreach my $indv_acc (@db_acc) {
                            if ( $indv_acc !~ $regex ) {
                                $unrecognised_regex{"$db_source\t$indv_acc"} = "$design_element_name\t$regex";
                            }    
                        }    
                    }
                }    
            }
        }
    }
    
    if ($has_chromosome_coord) {
        $self->warn("Check 'Term Source File' in the header for the source of chromosome coordinate.");
    }
          
    if ( scalar keys %unrecognised_db_source > 0 ) {
        my $dbs = join (", ", keys %unrecognised_db_source);
        $self->error("Database(s) \'$dbs\' not recognised. Consider adding to the adf_db_patterns.txt file.");
    }
    
    if (scalar keys %unrecognised_regex < 20) {
         foreach my $db_source_acc (keys%unrecognised_regex) {
             my ($db_source, $db_acc) = split ("\t", $db_source_acc);
             my ($element_name, $regex) = split ("\t", $unrecognised_regex{$db_source_acc});
             $self->error("Accession \'$db_acc\' for database \'$db_source\' (design element \'$element_name\') doesn't match expected pattern: $regex.");
         }    
    }
    
    if (keys%unimplemented) {
        foreach my $db_no_regex(keys%unimplemented) {
            $self->warn("No check for \'$db_no_regex\' DB entries has been implemented yet. Consider adding regex to the adf_db_patterns.txt file.");
        }
    } 

    if (keys%aggregate) {
        foreach my $agg_db(keys%aggregate) {
            $self->warn("No check for \'$agg_db\' as identifiers do not follow a certain pattern.");
        }
    }   
           
}


sub check_composite_consistency {
    
    my ($self, $composites) = @_;
    
    $self->info("---------- Checking composite DB entries...");
    
    foreach my $composite (@$composites) {
        
        my $composite_name = $composite->get_name;

        my %mini_db_entry_hash;
        if ($composite->get_databaseEntries) {
            foreach my $db_entry ( @{ $composite->get_databaseEntries } ) {
                # term source is always defined for a db entry,
                # or else CPAN parser would have thrown fatal error
                my $db_acc = $db_entry->get_accession;
                my $db_source = $db_entry->get_termSource->get_name;
                push (@{$mini_db_entry_hash{$db_source}}, $db_acc);
            }
        }
        
        foreach my $db_name (keys %mini_db_entry_hash) {
            my @acc = @{ $mini_db_entry_hash{$db_name} };
            if ( scalar @acc > 1 ) {
                my $multi_db_entry_per_composite = join (", ", @acc);
                $self->error("composite \'$composite_name\' has inconsistent entries for database \'$db_name\': $multi_db_entry_per_composite.");
            }
        }

    }
}

    
sub has_errors {

	my ( $self ) = @_;

	return $self->has_status( "has_errors" );
}

sub has_warnings {

	my ( $self ) = @_;

	return $self->has_status( "has_warnings" );
}

sub has_status {
	
	my ( $self, $has_method ) = @_;
	
    my $checker_status = Log::Log4perl->appender_by_name("adf_checker_status")
		  or die("Could not find log appender named adf_checker_status");		  
    
    my $total_errors += $checker_status->$has_method;

    return $total_errors;
}



###########                    #############
###########  INTERNAL METHODS  #############
###########                    #############

### _create_logger is the main method which creates the logger objects
### and controls where log files are written.
### This method is called when the logger attribute is first
### accessed, mainly via calls like "$self->error". Log4perl
### is scarily smart that there's no need to do
### $self->get_logger->error() !

sub _create_logger {

	my ($self) = @_;
	    
	# Create layout. This controls how the message looks like when printed on screen
	# or in the log file. E.g.
	
	# %c{1} %p - %m%n means:
	# category - log message \n
	# e.g. "ADF ERROR - ADF has no features" (followed by a new line character)
	# "category" is either taken as an argument of when "Log::Log4perl->get_logger" is called,
	# or taken from the perl module's name ("ADFParser" in this case)
	
	my $layout = Log::Log4perl::Layout::PatternLayout->new("%p - %m%n");

	# Create new logger

	my $logger = Log::Log4perl->get_logger();
	$logger->additivity(0);
	$logger->level($DEBUG);
	
	# APPENDER (1)
	# Create screen appender
	my $screen_appender = Log::Log4perl::Appender->new(
		"Log::Log4perl::Appender::Screen",
		name   => "adf_checker_screen",
		stderr => 0,
	);
	$screen_appender->layout($layout);
	$screen_appender->threshold($INFO);

    # Switch on verbose logging, if requested.
    if( $self->get_verbose_logging ) {
        $screen_appender->threshold($DEBUG);
    }
	
	$logger->add_appender($screen_appender);
	
	# APPENDER (2)
	# Create appenders to count errors and warnings
	
	my $checker_status =
	  Log::Log4perl::Appender->new( "EBI::FGPT::Reader::Status",
		name => "adf_checker_status", );

    $checker_status->layout($layout);		
	$logger->add_appender($checker_status);

	# APPENDER (3)
	# Create file appender. 
	# Write to custom log location if indicated.
	# Otherwise, write log to the same directory as the input file
	
	my $log_file_path;
	
    if ($self->get_custom_log_path) {
       $log_file_path = $self->get_custom_log_path;    
    } else {
        my $input_filename = $self->get_adf_path();

        my ( $vol, $dir, $name ) = File::Spec->splitpath($input_filename);


        if ($dir) {
        $log_file_path = File::Spec->catfile( $dir, $name."_report.log" );
        }
        else {
        $log_file_path = $name."_report.log";
        }
    }

    my $file_appender = Log::Log4perl::Appender->new(
        "Log::Dispatch::File",
        filename => $log_file_path,
        mode     => "write",
    );

    $file_appender->threshold($INFO);
    $file_appender->layout($layout);
    $logger->add_appender($file_appender);
   
    return $logger;                   
}


### KEEP THIS FOR NimbleGen parsing, setting the "csv_parser" attribute
### and setting the "eol_char" attribute of ADFParser object

sub _is_nimblegen{

    #returns true if specified file is recognised a NimbleGen format ndf
    
    my ( $self ) = @_;
          
    my $file = $self->get_adf_path;
    open (my $adf_fh, "<", $file);
    
    # Both "csv_parser" and "eol_char" attributes are populated
    # when they're first called in the code (which is here!).
    # Setting eol_char attribute requires the help of csv_parser,
    # so csv_parser has to be called first. Don't swap the order!
    
    my $line = $self->get_csv_parser->getline($adf_fh);
    local $/ = $self->get_eol_char;
    
    until ( grep /^PROBE_DESIGN_ID$/, @$line ){
        defined( $line = $self->get_csv_parser->getline($adf_fh) ) or return 0;
    }
    
    close $adf_fh;
    return 1;
}

# KEEP _create_csv_parser for nimblegen stuff and for
# parsing column headings that the CPAN code doesn't check.
#  _calculate_eol_char is needed for a similar reason.
# Named them as _create* or _calculate*, not _get* because
# get/set are controlled vocabulary in Moose

sub _create_csv_parser {

    my ( $self ) = @_;

    my $csv_parser = Text::CSV_XS->new(
        {   sep_char    => qq{\t},
            quote_char  => qq{"},                   # default
            escape_char => qq{"},                   # default
            binary      => 1,
            eol         => ($self->get_eol_char() || "\n" ),
	    allow_loose_quotes => 1,
        }
    );

    $self->debug("Returning csv parser.");
    return $csv_parser;
}

sub _calculate_eol_char  {

    my ( $self ) = @_;
    
    $self->debug("In _calculate_eol_char method.");
    $self->debug("ADF file path is ".$self->get_adf_path()."");

	my ($eols, $eol_char) = check_linebreaks( $self->get_adf_path() );
	if ($eol_char) {
	    if (    ( $eol_char eq "\015" )
             && ( $Text::CSV_XS::VERSION < 0.27 ) ) {

        # Mac linebreaks not supported by older versions of Text::CSV_XS.
        $self->logdie("Mac linebreaks not supported by this version of Text::CSV_XS. Please upgrade to version 0.27 or higher");
        } else {
            return $eol_char;  # this will set the eol_char attribute for ADFParser object
        }
    } else {    
	    $self->logdie(
		sprintf(
		    "Cannot correctly parse linebreaks in file %s"
			. " (%s unix, %s dos, %s mac)\n",
		    $self->get_adf_path(),
		    $eols->{unix},
		    $eols->{dos},
		    $eols->{mac},
		)
	    );
	}	
}


sub _normalize {

    my ( $self, $string ) = @_;

    $string =~s/\s//g;
   
    $string = lc($string);

    return $string;

}


sub _load_db_patterns{

    my ($self, $filepath) = @_;

    open (my $db_file, "<", $filepath)
        or $self->error ("Could not find db patterns file at $filepath.");

    my %db_patterns;
    
    while (<$db_file>){
    	chomp;
        my ( $acc, $pattern, $uri ) = split("\t", $_);
        $db_patterns{ $acc }=$pattern;
    }
    
    close $db_file;

    return \%db_patterns;
}

1;
