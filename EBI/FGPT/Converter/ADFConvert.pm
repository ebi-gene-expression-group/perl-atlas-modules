#!/usr/bin/perl
#
#  ADFConvert.pm - methods and mappings for converting between
#  different flavours of ADF
#
#  Anna Farne, ArrayExpress Production Team, EBI
#  2008
#
#  $Id: ADFConvert.pm 2389 2011-11-29 12:52:06Z farne $

package ArrayExpress::ADFParser::ADFConvert;
use strict;
use Exporter;
use Carp;
use strict;
use warnings;
use Getopt::Long;
use ArrayExpress::Curator::Database qw(get_ae_dbh);
use ArrayExpress::Curator::Common qw(db_tag_name_version);
use FileHandle;

my $svn_revision = '$Revision: 2389 $';
our ($VERSION) = ( $svn_revision =~ /^\$Revision: ([\d\.]*)/ );

my $MGED = "MGED Ontology";
my $MGED_URI = "http://mged.sourceforge.net/ontologies/MGEDontology.php";

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
                    add_dbs_to_header
                    get_identifier_prefix
                    get_magetab_to_mx_mapping
                    get_ae_to_magetab_mapping
                    get_mx_to_magetab_mapping
                    get_magetab_adf_header
                    make_magetab_adf_header_from_design_info
                    process_header
                    process_lines
                    print_adf
                    print_adf_header
                    $VERSION
                    );

sub get_magetab_to_mx_mapping{
    my %adf_tags = (
               "blockcolumn"                     => "MetaColumn",
               "blockrow"                        => "MetaRow",
               "column"                          => "Column",
               "row"                             => "Row",
               "reportername"                    => "Reporter Identifier;Reporter Name",
               "reporterdatabaseentry"           => "Reporter BioSequence Database Entry",
               "reportersequence"                => "Reporter BioSequence [Actual Sequence]",
               "reportergroup"                   => "Reporter Group",
               "reportergrouptermsourceref"      => "DROP",
               "reportercomment"                 => "Reporter Comment",
               "controltype"                     => "Reporter Control Type",
               "controltypetermsourceref"        => "DROP",
               "compositeelementname"            => "CompositeSequence Identifier;CompositeSequence Name",
               "compositeelementdatabaseentry"   => "CompositeSequence Database Entry",
               "compositeelementcomment"         => "CompositeSequence Comment",
               );
    return %adf_tags;
}

# FIX: will need sub to combine 2 part magetab ADFs


sub get_magetab_header_tags{
    my @all_tags = (
                   "Array Design Name",
                   "Version",
                   "Provider",
                   "Comment[ArrayExpressAccession]",
                   "Comment[Description]",
                   "Comment[SubmittedName]",
                   "Comment[Organism]",
		   "Comment[ArrayExpressReleaseDate]",
 		   "Comment[ArrayExpressSubmissionDate]",
                   "Printing Protocol",
                   "Technology Type",
                   "Technology Type Term Accession Number",
                   "Technology Type Term Source REF",
                   "Surface Type",
                   "Surface Type Term Accession Number",
                   "Surface Type Term Source REF",
                   "Substrate Type",
                   "Substrate Type Term Accession Number",
                   "Substrate Type Term Source REF",
                   "Sequence Polymer Type",
                   "Sequence Polymer Type Term Accession Number",
                   "Sequence Polymer Type Term Source REF",
                   "Term Source Name",
                   "Term Source File",
                   "Term Source Version",
                   );
    return @all_tags;
}

# ARGS: accession
sub get_magetab_adf_header {
    my %values;
    my $header_value_ref = \%values;
    my ($accession) = @_;

    my $dbh = get_ae_dbh or die "Could not connect to ArrayExpress database";
    $dbh->{LongReadLen} = 100000;

    get_array_details($accession, $header_value_ref, $dbh);
    get_array_descr($header_value_ref, $dbh);
    get_array_protocol($header_value_ref, $dbh);
    get_array_tech($header_value_ref, $dbh);
    get_array_surface_type($header_value_ref, $dbh);
    get_array_substrate_type($header_value_ref, $dbh);
    get_array_provider($header_value_ref, $dbh);
    get_array_organism($header_value_ref, $dbh);

    $header_value_ref->{"Comment[ArrayExpressAccession]"} = $accession;

    return $header_value_ref;
}

sub make_magetab_adf_header_from_design_info{
	my ($info) = @_;
	unless ($info->isa("ArrayExpress::ADFParser::ArrayDesignInfo")){
		die "Error: argument passed to make_magetab_adf_header_from_design_info must"
		    ." be an ArrayExpress::ADFParser::ArrayDesignInfo object";
	}
	
	my $header = {};
    $header->{"Array Design Name"} = $info->get_name;
    $header->{"Version"} = $info->get_version;
    $header->{"Provider"} = $info->get_provider_name." (".$info->get_provider_email.")";
    $header->{"Comment[ArrayExpressAccession]"} = $info->get_accession;
    $header->{"Comment[Description]"} = $info->get_description;
    $header->{"Comment[SubmittedName]"} = $info->get_name;
    $header->{"Comment[Organism]"} = $info->get_species;
    $header->{"Comment[ArrayExpressReleaseDate]"} = $info->get_comments->{'ArrayExpressReleaseDate'};
    $header->{"Comment[ArrayExpressSubmissionDate]"} = $info->get_comments->{'ArrayExpressSubmissionDate'};	
    $header->{"Printing Protocol"} = $info->get_protocol_name.": ".$info->get_protocol_text;
    $header->{"Technology Type"} = $info->get_tech_type_value;
    $header->{"Surface Type"} = $info->get_surface_type_value;
    $header->{"Substrate Type"} = $info->get_substrate_type_value;
    $header->{"Sequence Polymer Type"} = $info->get_pol_type_value;

	return $header;
}

sub add_dbs_to_header{
    my ($header_info_ref, $dbs_ref) = @_;

    my $dbh = get_ae_dbh or warn "Could not connect to ArrayExpress database to get Database URIs\n";
    my $sql=<<END;
select d.URI from tt_database d, tt_identifiable i
where d.id=i.id
and i.name = ?
END
    my (@names, @uris);
    foreach my $db (@$dbs_ref){

        my ($name, $version) = db_tag_name_version($db);

        # get URI from AE if poss. if not found just push "" to array
        my $uri;
        if ( $dbh ){
            my $results_array_ref = run_query($dbh, $sql, $name);

            if (scalar @$results_array_ref == 1){
                $uri = $results_array_ref->[0]->{URI};
            }
        }
        
        # Add info to header
        add_term_source($header_info_ref, $name, $version, $uri);
    }
}

#ARGS: dbh, sql, query term, max number of expected results
sub run_query{
    my ($dbh, $sql, $term, $max) = @_;

    my $sth = $dbh->prepare($sql);
    $sth->execute($term)
        or croak "Could not execute statement: $sth->errstr";

    my $all_results_ref = $sth->fetchall_arrayref({});

    my $count = scalar @{ $all_results_ref };

    if (defined $max and $count > $max){
        croak "Unexpected number of results returned by query";
    }

    return $all_results_ref;
}

#get basic array info for header. write to hash.
sub get_array_details{
    my ($accession, $value_ref, $dbh) = @_;

    my $sql= <<END;
select i.*, a.version from
tt_identifiable i,
tt_arraydesign a
where
i.identifier=?
and a.id = i.id
END
    my $results_array_ref = run_query($dbh, $sql, $accession, 1);
    if (!@{ $results_array_ref }){
        croak "no results returned for $accession in query $sql";
    }
    $value_ref->{"Comment[SubmittedName]"} = $results_array_ref->[0]->{NAME};
    $value_ref->{"Version"} = $results_array_ref->[0]->{VERSION};
    $value_ref->{"Comment[Accession]"} = $results_array_ref->[0]->{IDENTIFIER};
    $value_ref->{"ID"} = $results_array_ref->[0]->{ID};

    # Set design name as submitted name as default
    # then attempt to replace this with the display name NVT
    $value_ref->{"Array Design Name"} = $results_array_ref->[0]->{NAME};
    get_array_display_name($accession, $value_ref, $dbh);
    
    return $value_ref;
}

sub get_array_display_name{
	my ($accession, $value_ref, $dbh) = @_;
	
	my $sql =<<END;
select n.value from 
tt_identifiable i, 
tt_namevaluetype n
where identifier=?
and i.id = n.t_extendable_id
and n.name = 'AEArrayDisplayName'
END

   my $results_array_ref = run_query($dbh, $sql, $accession, 1);
   my $name = $results_array_ref->[0]->{VALUE};
   if (!$name){
        print "Warning: no display name NVT identified for $accession\n";
   }
   else{
       $value_ref->{"Array Design Name"} = $name;	   
   }
   
   return $value_ref;
}

#get description text if available
sub get_array_descr{
    my ($value_ref, $dbh) = @_;
    my $id = $value_ref->{"ID"};

    my $sql = <<END;
select * from
tt_description
where t_describable_id = ?
and text not like '(Generated description)%'
END

    my $results_array_ref = run_query($dbh, $sql, $id);
    my @descr_text;
    foreach my $descr_ref (@{ $results_array_ref }){
        if ($descr_ref->{TEXT}){
            push @descr_text, $descr_ref->{TEXT};
        }
    }
    $value_ref->{"Comment[Description]"} = join "<br>", @descr_text;

    return $value_ref;
}

#get protocol text
sub get_array_protocol{
    my ($value_ref, $dbh) = @_;
    my $id = $value_ref->{"ID"};

    my $sql = <<END;
select * from
tt_protocol p,
tt_protocolapplication pa
where
pa.t_arraydesign_id = ?
and pa.protocol_id = p.id
END

    my $results_array_ref = run_query($dbh, $sql, $id);
    my @protocols;
    foreach my $prot_ref (@{ $results_array_ref }){
        if ($prot_ref->{TEXT}){
            push @protocols, $prot_ref->{TEXT};
        }
    }
    $value_ref->{"Printing Protocol"} = join "<br>", @protocols;

    return $value_ref;
}

#get tech type
sub get_array_tech{
    my ($value_ref, $dbh) = @_;
    my $id = $value_ref->{"ID"};

    my $sql = <<END;
select * from
tt_featuregroup f,
tt_ontologyentry o
where
f.t_arraydesign_id= ?
and f.technologytype_id = o.id
END

    my $results_array_ref = run_query($dbh, $sql, $id);
    my $tech;
    my $ontology_reference;
    foreach my $oe_ref (@{ $results_array_ref}){
        my $value = $oe_ref->{VALUE};
        next unless $value;
        
        $ontology_reference = $oe_ref->{ONTOLOGYREFERENCE_ID}; 
        
        if ($value){
            if ($tech and $tech ne $value){
                $tech.=";$value";
            }
            else {
                $tech = $value;
            }
        }
    }
    $value_ref->{"Technology Type"} = $tech;

    if (defined $ontology_reference){
    	
    	my ($acc, $db_name, $db_version, $db_uri) =
    	    get_ontology_reference($ontology_reference, $dbh);
    	
    	$value_ref->{"Technology Type Term Accession Number"} = $acc if $acc;
    	$value_ref->{"Technology Type Term Source REF"} = $db_name if $db_name;
    	
    	add_term_source($value_ref, $db_name, $db_version, $db_uri) if $db_name;
    }
    return $value_ref;
}

sub get_array_surface_type{
    my ($value_ref, $dbh) = @_;
    
    my $design_id = $value_ref->{"ID"};
    my $sql = <<END;
select oe.* from tt_physicalarraydesign a,
tt_ontologyentry oe 
where a.id=?
and surfacetype_id=oe.id
END

    my $results_ref = run_query($dbh, $sql, $design_id, 1);   
    if (defined (my $result = $results_ref->[0]) ){
    	my $oe_term = $result->{VALUE};
    	$value_ref->{"Surface Type"} = $oe_term;
    	
    	my $oe_ref = $result->{ONTOLOGYREFERENCE_ID};
    	if ($oe_ref){
    		
    		my ($acc, $db_name, $db_version, $db_uri) = 
    		    get_ontology_reference($oe_ref, $dbh);
    		
    		$value_ref->{"Surface Type Term Accession Number"} = $acc if $acc;
    		$value_ref->{"Surface Type Term Source REF"} = $db_name if $db_name;
    		
    		add_term_source($value_ref, $db_name, $db_version, $db_uri) if $db_name;   
    	}
    }
    return $value_ref;	
}

sub get_array_substrate_type{
    my ($value_ref, $dbh) = @_;
    
    my $design_id = $value_ref->{"ID"};
    my $sql = <<END;
select o.* from tt_description d, tt_annotations_t_descriptio a, tt_ontologyentry o
where d.t_describable_id = ?
and a.T_DESCRIPTION_ID = d.id
and annotations_id=o.id
and o.category='SubstrateType'
END

    my $results_ref = run_query($dbh, $sql, $design_id, 1);   
    if (defined (my $result = $results_ref->[0]) ){
    	my $oe_term = $result->{VALUE};
    	$value_ref->{"Substrate Type"} = $oe_term;
    	
    	my $oe_ref = $result->{ONTOLOGYREFERENCE_ID};
    	if ($oe_ref){
    		
    		my ($acc, $db_name, $db_version, $db_uri) = 
    		    get_ontology_reference($oe_ref, $dbh);
    		
    		$value_ref->{"Substrate Type Term Accession Number"} = $acc if $acc;
    		$value_ref->{"Substrate Type Term Source REF"} = $db_name if $db_name;
    		
    		add_term_source($value_ref, $db_name, $db_version, $db_uri) if $db_name;   
    	}
    }
    return $value_ref;		
}

sub add_pol_types_to_header{

    # Unfortunately the PolymerType OEs are not included in the AE ADFs
    # so for now this info will not be added to the MAGETAB ADF header
}

sub get_array_organism{
	my ($value_ref, $dbh) = @_;
	
	my $design_id = $value_ref->{"ID"};
	my @de_groups;
	
	# Find all design element groups for array
	# and get species associations
	
	# Features (shouldn't have species assn but we'll check just in case)
	my $feature_sql = "select * from tt_featuregroup where t_arraydesign_id=?";
	my $feature_results = run_query($dbh, $feature_sql, $design_id);
    push @de_groups, map { $_->{ID} } @$feature_results;
    
    # Reporter Groups
    my $reporter_sql = "select * from TT_REPORTERGRO_T_ARRAYDESI where t_arraydesign_id=?";
    my $reporter_results = run_query($dbh, $reporter_sql, $design_id);
    push @de_groups, map {$_->{REPORTERGROUPS_ID}} @$reporter_results;
    
    # Composite Groups
    my $composite_sql = "select * from TT_COMPOSITEGR_T_ARRAYDESI where t_arraydesign_id=?";
    my $comp_results = run_query($dbh, $composite_sql, $design_id);
    push @de_groups, map {$_->{COMPOSITEGROUPS_ID}} @$comp_results;
    
    # Get any species assns for these groups
    my %found_species;
    my $species_sql = <<END;
select oe.value from tt_designelementgroup g, tt_ontologyentry oe
where g.id = ?
and oe.id = g.species_id
END

    foreach my $group (@de_groups){
    	my $results_ref = run_query($dbh, $species_sql, $group, 1);
    	if (defined (my $result = $results_ref->[0]) ){  		
    		my $species = $result->{VALUE};
    		$found_species{$species} = 1; 
    	}
    }
    
    my $species_string = join ";", sort keys %found_species;
    $value_ref->{"Comment[Organism]"} = $species_string;       
}

#get provider
sub get_array_provider{
    my ($value_ref, $dbh) = @_;
    my $id = $value_ref->{"ID"};

    my $sql = <<END;
select
c.id as cid,
c.email,
p.id as pid,
p.lastname,
p.firstname,
i.name
from
tt_contact c left join tt_person p on p.id=c.id,
TT_DESIGNPROVI_T_ARRAYDESI dp,
tt_identifiable i
where
c.id=DESIGNPROVIDERS_ID
and T_ARRAYDESIGN_ID= ?
and i.id=c.id
END

    my $results_array_ref = run_query($dbh, $sql, $id);
    my @providers;
    foreach my $prov_ref (@{ $results_array_ref }){
        if ($prov_ref->{"PID"}){
            #use person firstname lastname
            my $name = "$prov_ref->{FIRSTNAME} $prov_ref->{LASTNAME}";
            if (defined $prov_ref->{EMAIL}){
                $name.=" ($prov_ref->{EMAIL})";
            }
            push @providers, $name;
        }
        else{
            #is organization - use name from tt_identifiable
            my $name = $prov_ref->{NAME};
            if (defined $prov_ref->{EMAIL}){
                $name.=" ($prov_ref->{EMAIL})";
            }
            push @providers, $name;
        }
    }
    $value_ref->{"Provider"} = join ";", @providers;

    return $value_ref;
}

sub get_ontology_reference{
	
	my ($oeref_id, $dbh) = @_;
	
	my $sql = <<END;
select de.accession, i.name, d.version, d.uri 
from tt_databaseentry de,
tt_database d,
tt_identifiable i 
where de.id = ?
and database_id = d.id
and i.id = d.id	
END

   my $results_array_ref = run_query($dbh, $sql, $oeref_id, 1); 
   my $result = $results_array_ref->[0];
   
   return undef unless $result;
   
   return ($result->{ACCESSION}, $result->{NAME}, $result->{VERSION}, $result->{URI});
}

# returns hash of AE to MAGETAB headings
sub get_ae_to_magetab_mapping {
    my %adf_tag = (
    metacolumn                             => "Block Column",
    metarow                                => "Block Row",
    column                                 => "Column",
    row                                    => "Row",
    "reporteridentifier"                   => "Reporter Name",
    "reportername"                         => "Comment[AEReporterName]",
    "reporterbiosequencedatabaseentry"     => "Reporter Database Entry",
    "reporterbiosequencetype"              => "DROP",
    "reporterbiosequencepolymertype"       => "DROP",
    # AE ADFs are inconsistent
    # older ones have sequence as Reporter Actual Sequence
    # newer ones Reporter BioSequence [Actual Sequence]
    "reporteractualsequence"               => "Reporter Sequence",
    "reporterbiosequence"                  => "Reporter Sequence",
    "reportercomment"                      => "Reporter Comment",
    "reportergroup"                        => "Reporter Group[role]",
    # and in older AE ADFS:
    "reportergrouprole"                    => "Reporter Group[role]",
    "reportercontroltype"                  => "Control Type",
    "compositesequenceidentifier"          => "Composite Element Name",
    "compositesequencename"                => "Comment[AECompositeName]",
    "compositesequencedatabaseentry"       => "Composite Element Database Entry",
    "compositesequencecomment"             => "Composite Element Comment",
    "compositebiosequencecomment"          => "Composite Element Comment",
    );
    return %adf_tag;
}

# returns hash of AE to MAGETAB headings
sub get_mx_to_magetab_mapping {
    my %adf_tag = (
    metacolumn                             => "Block Column",
    metarow                                => "Block Row",
    column                                 => "Column",
    row                                    => "Row",
    "reporteridentifier"                   => "Reporter Name",
    "reportername"                         => "Comment[AEReporterName]",
    "reporterbiosequencedatabaseentry"     => "Reporter Database Entry",
    "reporterbiosequencetype"              => "DROP",
    "reporterbiosequencepolymertype"       => "DROP",
    "reporterbiosequence"                  => "Reporter Sequence",
    "reportercomment"                      => "Reporter Comment",
    "reportergroup"                        => "Reporter Group[role]",
    "reportercontroltype"                  => "Control Type",
    "compositesequenceidentifier"          => "Composite Element Name",
    "compositesequencename"                => "Comment[AECompositeName]",
    "compositesequencedatabaseentry"       => "Composite Element Database Entry",
    "compositesequencecomment"             => "Composite Element Comment",
    "compositebiosequencecomment"          => "Composite Element Comment",
    "compositesequencebiosequencetype"     => "DROP",
    "compositesequencebiosequencepolymertype" => "DROP",
    );
    return %adf_tag;
}

# ARGS: file handle, reference to array of headers, file handle to ADF lines,
# reference to array of indexes of columns to keep, delimiter
sub print_adf{
    my %args = @_;
    my @required = qw(fh headers_ref lines_fh keepers_ref delim); #header_info_ref and extra are optional
    my @missing = grep { not exists $args{$_} } @required;
    if (@missing) {
        croak "The following required parameters were not provided to print_adf: @missing";
    }

    my $fh = $args{fh};

    print STDERR "writing new adf...";
    print_adf_header($args{header_info_ref}, $fh, $args{delim});

    # add any extra headers and print header
    my @extra_headers;
    if ( $args{extra} ){
        @extra_headers = sort keys %{ $args{extra} };
        push @{ $args{headers_ref} }, @extra_headers;
    }
    print $fh join $args{delim}, @{ $args{headers_ref} };
    print $fh "\n";	
    
    my $lines_fh = $args{lines_fh};
    seek ($lines_fh,0,0);
    foreach my $line ( <$lines_fh> ) {
        chomp $line;
        my @cells = split "\t", $line;

        # print everything out
        # add extra values (unless line is control_empty or control_buffer)
        my @cells_to_print = @cells[@{ $args{keepers_ref} }];

        if ( !grep(/(control_empty|control_buffer)/, @cells) ){
	    foreach my $extra_col (@extra_headers){
                my $extra_value = $args{extra}->{$extra_col};
                push @cells_to_print, $extra_value;
	    }
	}

        no warnings;
        print $fh join $args{delim}, @cells_to_print;
        print $fh "\n";
    }
    print STDERR "done\n";
}

sub print_adf_header{
	my ($header_info, $fh, $delim) = @_;
	
    # print header info if supplied
    if ($header_info){
        my %header_value = %{ $header_info };
        my @tag_order = get_magetab_header_tags;
        foreach my $tag (@tag_order){
	        if (my $value = $header_value{$tag}){
                print $fh join $delim, $tag, $value;
                print $fh "\n";
	        }
	    }
        print $fh "\n";
    }
}

# ARGS: file handle of file containing ADF lines
# splits each line into array of cells and does any processing of values
# also counts number of values in each column and returns as hash
# (this can be used to filter out empty columns later on)
sub process_lines{
    my ($all_lines_fh, $header_regex) = @_;
    my $lines_tmp_fh = IO::File->new_tmpfile or die "Error trying to create tmp file $!";
    my $header;
    my %value_count;

    print STDERR "reading ADF...";
    foreach my $line (<$all_lines_fh>) {
        chomp $line;
        if ($line =~ /$header_regex/){
            $header = $line;
            next;
	}

        next unless $header;

        my @cells = split "\t", $line;
        #AE ADFs sometimes have dashes where there are no values - remove em
        foreach (my $i=0; $i <= $#cells; $i++) {
            if ($cells[$i] eq "-") {
                $cells[$i] = "";
            }
            if ($cells[$i] ne ""){
                $value_count{$i}++;
	    }
        }
        print $lines_tmp_fh join "\t", @cells;
        print $lines_tmp_fh "\n";
    }
    print STDERR "done\n";
    return $header, $lines_tmp_fh, \%value_count;
}


# ARGS: header line, reference to mapping hash
# returns: reference to array of columns to keep, reference to array of new headers
sub process_header{
    my ($header, $mapping_ref, $value_count_ref) = @_;
    my (@keep, @new_headers, %dbs);

    # identify identifier columns and column to keep
    chomp $header;
    my @headers = split "\t", $header;
    my $index = 0;
    foreach my $col_header ( @headers ) {
        # ignore columns that have no values in them except control type column which is required
        if (!$value_count_ref->{$index} and $col_header !~/^Reporter ?Control ?Type$/i){
        	print "WARNING: dropping empty column: $col_header\n";
            $index++;
            next;
        }

        my $suffix;
        my $col = $col_header;
        if ( $col_header =~ /^(.*)\s*\[(.*)\]$/g ) {
            $col = $1;
            $suffix = $2;
        }
        $col = lc $col;
        $col =~ s/\s//g;

        if ( $mapping_ref->{$col} ) {
            # special case: drop column
            if ( $mapping_ref->{$col} eq "DROP" ) {
                # don't keep it
                print "WARNING: dropping unwanted column: $col_header\n";
            }

            # general case (semi-colon separated list in mapping indicates that
            # column should be repeated for each header in list)
            else {
                my @header_list = split ";", $mapping_ref->{$col};
                foreach my $header (@header_list){
                    push @keep, $index;
                    my $new;
                    # need to put suffix on unless new header already has one
                    # or new header is "Reporter Sequence"
                    if ($suffix and $header!~/.*\[.*\]/ and $header ne "Reporter Sequence") {
                        $new = $header."[$suffix]";
	            }
	            else {
	                $new = $header;
                    }
                    push @new_headers, $new;
		        }
            }

            # Store list of databases used for inclusion as sources in file header
            if ($col =~ /databaseentry/){
                $dbs{$suffix} = 1;
            }
        }

        # keep unrecognized columns in case something is missing from mapping
        else {
            print "WARNING: keeping unrecognized column: $col_header\n";
            push @keep, $index;
            push @new_headers, $col_header;
        }
        $index++;
    }

    my @db_array = sort keys %dbs;
    return \@keep, \@new_headers, \@db_array;
}

# Cleanly add a new term source to an ADF header tag in the hash
sub add_term_source{
	my ($value_ref, $name, $version, $uri) = @_;
	
	my %atts = (
		"Term Source Version" => $version,
		"Term Source File"    => $uri,
	);
	
	my $position;
	my $existing_value = $value_ref->{"Term Source Name"};
	
	if ($existing_value){
		# check it is not already in list then add it
		my @name_list = split /\t/, $existing_value;
		my %seen = map { $_ => 1 } @name_list;
		if (!$seen{$name}){
			push @name_list, $name;
			$position = $#name_list;
			$value_ref->{"Term Source Name"} = join "\t", @name_list;
		}
	}
	else {
		$value_ref->{"Term Source Name"} = $name;
		$position = 0;
	}
	
	# If we have a new position add attributes at this position
	return unless defined $position;
	
	foreach my $att ("Term Source Version", "Term Source File"){
		my $existing_value = $value_ref->{$att};
		my @list = split /\t/, ( $existing_value || "");
		$list[$position] = ( $atts{$att} || "");
		my @new_list;
		foreach my $element (@list){
			$element = "" unless defined $element;
			push @new_list, $element;
		}
		$value_ref->{$att} = join "\t", @new_list; 
	}
	return;
}

# identifies common prefix of a list of strings
# returns prefix
#my @test = qw(qwe.rty qwe.rhjk qwe.rtyuip qwe.riiiiiiii);
#my $prefix = get_identifier_prefix( \@test );
#print STDERR "prefix: $prefix\n";
sub get_identifier_prefix {
    my $array_ref = $_[0];
    my $sep = chr(0);
    my $common = $$array_ref[0];

    foreach my $id ( @$array_ref ){
        if ($id) {
            if ( "$common$sep$id" =~ /^(.*).*$sep\1.*$/ ) {
                $common = $1;
            }
        }
    }

    # if prefix ends in characters that are not usually used
    # as delimiters then only use the bit up to and including the delimiter
    if ( $common =~ /^(.*[.:])[^.:]*$/ ) {
        $common = $1;
    }
    return $common;
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
	    <td class="pagetitle">Module detail: ADFConvert.pm</td>
	  </tr>
      </table>
    </div>

=end html

=head1 NAME

ArrayExpress::ADFParser::ADFConvert - A collection of methods and mappings
used to convert between different ADF formats.

=head1 DESCRIPTION

A collection of methods and mappings used to convert between different ADF formats.

=head1 METHODS

=over 2

=item C<add_dbs_to_header>

Requires direct connection to ArrayExpress. Takes reference to a hash of MAGETAB
header tags and values, ref to list of databases reference in the ADF. Retrieves
URIs for these databases and adds this info to MAGETAB header hash.

tags.

=item C<get_magetab_to_mx_mapping>

Returns a hash mapping MAGETAB ADF headings (lower case with spaces removed) to
MIAMExpress ADF headings. If a column is to be dropped it is mapped to a value
of "DROP". If a column is to be repeated it is mapped to a semi-colon seprated list of
new column names.

=item C<get_ae_to_magetab_mapping>

Returns a hash mapping ArrayExpress ADF headings (lower case with spaces removed)
to MAGETAB ADF headings. Rules for dropping or repeating columns as above.

=item C<get_magetab_adf_header>

Requires direct access to the ArrayExpress database. Takes an ArrayExpress array
design accession. Fetches information about the array design from the database
and returns it as a hash reference where keys are header tags and values are
array refs to the list of values to include in the header.

=item C<process_header>

Takes args: ADF heading line, reference to mapping hash. Returns: reference to
array of columns to keep, reference to array of new headers for these columns.

=item C<process_lines>

Takes args: file handle of file containing ADF lines and regex to identify ADF
heading line. Removes any useless values (like "-") and counts how many real
values there are in each column so that empty columns can be discarded. Returns:
the heading line as a string, a temp filehandle where the processed values are
stored and a hashref containing the count of values in each column.

=item C<print_adf>

Takes args: fh (the output file handle), headers_ref (the list of new ADF headings),
lines_fh (the temp filehandle containing the values), keepers_ref (the indeces
of columns to keep) delim (the delimiter used)

Optional args: header_info_ref (ref to hash of magetab header section tags and
values, extra (and extra new column headings which may need to be added)

Writes new format ADF to ouput file.

=back

=head1 AUTHOR

Anna Farne (farne@ebi.ac.uk), ArrayExpress team, EBI, 2008.

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
