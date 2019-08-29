#!/usr/bin/env perl
#
#  AE2Exporter.pm - methods to prepare submissions for
#  loading into AE2 (convert/split into MAGETAB idf and
#  sdrf and assign protocol accessions)
#
#  Anna Farne, ArrayExpress Production Team, EBI
#  2009
#
#  $Id: AE2Exporter.pm 2448 2012-07-16 12:58:42Z farne $

use strict;
use warnings;

package ArrayExpress::AutoSubmission::AE2Exporter;

use Class::Std;
use Carp;
use File::Spec;
use Text::CSV;
use Text::CSV::Encoded;
use Readonly;
use File::Path qw(mkpath);
use File::Copy;

use EBI::FGPT::Common qw(check_linebreaks 
                                     ae2_load_dir_for_acc 
                                     magetab_split_and_tidy
                                     );
                                                                         
use EBI::FGPT::Config qw($CONFIG);

Readonly my $COMMENT => qr/^\s*#/;
Readonly my $BLANK => qr/\A (->)? \z/xms;

my %accession   : ATTR( :name<accession> );
my %type        : ATTR( :name<type> );
my %spreadsheet : ATTR( :name<spreadsheet> );
my %data_dir    : ATTR( :name<data_dir>    :default<".">);
my %idf         : ATTR( :name<idf>,        :default<undef>);
my %sdrfs       : ATTR( :name<sdrfs>,      :default<[]>);
my %keep_prot_accns : ATTR( :name<keep_prot_accns>, :default<0>);
my %log_path    : ATTR( :name<log_path> );
my %log_fh      : ATTR( :name<log_fh>,     :default<undef>);
my %temp_dir    : ATTR( :name<temp_dir>    :default<undef>);
my %target_dir  : ATTR( :name<target_dir>, :default<undef>);

my %prot_accn_prefix : ATTR( :name<prot_accn_prefix>, :default<undef>);
my %prot_accn_service : ATTR( :name<prot_accn_service>, :default<undef>);

my %assign_samples : ATTR( :name<assign_samples>, :default<0>);
my %sample_accn_prefix : ATTR( :name<sample_accn_prefix>, :default<undef> );

sub START{
	my ($self, $ident, $args) = @_;
	
	# Check we recognize the submission type
	unless ($args->{type} =~ /^mage-?tab$/ig){
		confess("Error: AE2Exporter created with unrecognized type: ".$args->{type});
	}
	
	# Create an export log file
	my $log = $args->{log_path};
	open(my $log_fh, ">:encoding(UTF-8)", $log) or die "Could not open log $log for writing";
	$self->set_log_fh($log_fh);
	
	# Create the load directory
	my $load_dir = ($self->get_target_dir()
	                || ae2_load_dir_for_acc($self->get_accession) );
	unless (-e $load_dir){
		$self->log("Creating load directory $load_dir");
		mkpath($load_dir) or die "Could not create load directory $load_dir - $!";
	}
	$self->set_target_dir( $load_dir );
}

sub log{
    my ($self, $message) = @_;
    my $fh = $self->get_log_fh;
    print $fh "$message\n";
    return;
}

sub export{
	my ($self) = @_;
	
	my $rc = 0;
	my $type = $self->get_type;
	
	# Always convert mac files to unix before starting
	my $ss = $self->get_spreadsheet;
	$self->mac2unix($ss);
	$self->dos2unix($ss);
	
    if ($type =~/mage-?tab/i){
    	$rc = $self->export_magetab();
    }
    else{
    	confess("Error: cannot export unrecognized experiment type $type");
    }
    
    return $rc;
}

sub export_magetab{
	my ($self) = @_;
	
	$self->log("Exporting MAGE-TAB file");
	# If we do not already have idf and sdrf paths we
	# create them from submitted mtab file (may be a combined
	# mtab doc)
	unless ($self->get_idf and $self->get_sdrfs){
	    $self->log("Splitting MAGE-TAB file");
    
        my ($idf,@sdrfs) = magetab_split_and_tidy($self->get_spreadsheet,
                                                  $self->get_data_dir,
                                                  $self->get_export_temp_dir,
                                                  $self->get_accession);		
		
        $self->set_idf($idf);
        $self->set_sdrfs(\@sdrfs)
	}
    
	# Parse idf, assign prot accs and write to target dir with
	# prot and experiment accessions
	my ($prot_accs, $additional_files) = $self->export_idf();
	
	# Parse sdrfs and write to target dir with new prot accs
	my @data_files;
	foreach my $sdrf(@{ $self->get_sdrfs }){
		my $new_name;
		if ($sdrf =~ /\.(assay|seq)\./){
			$new_name = $self->get_accession.".seq.sdrf.txt";
		}
		elsif ($sdrf =~ /\.hyb\./){
			$new_name = $self->get_accession.".hyb.sdrf.txt";
		}
		else{
			$new_name = $self->get_accession.".sdrf.txt";
		}
		my $output = File::Spec->catfile($self->get_target_dir, $new_name);
		my @data = $self->export_sdrf($sdrf, $output, $prot_accs);
		push @data_files, @data;
	}
	
	# Copy the data files to the target dir
	foreach my $file (@data_files, @$additional_files){
		my $old_path = File::Spec->catfile($self->get_data_dir, $file);
		my $new_path = File::Spec->catfile($self->get_target_dir, $file);
		$self->log("Copying $old_path to $new_path");
		copy($old_path, $new_path) or die "Could not copy $old_path to load directory - $!";
	}
	
	return 1;
}

sub export_sdrf{
    my ($self, $input, $output, $prot_accs) = @_;
    
    $self->log("Rewriting SDRF to load directory");
    
    my ($counts,$eol) = check_linebreaks($input);
    unless($eol){ die "Error: cannot determine line ending type for file $input"};
    
    open (my $in_fh, "<:encoding(UTF-8)", $input) or die "Could not open SDRF $input for reading";   # new 13 Jul
    open (my $out_fh, ">:encoding(UTF-8)", $output) or die "Could not open new SDRF $output for writing";
    
    my %data_files = ();
    
    my $parser = Text::CSV::Encoded->new({   
     	sep_char    => qq{\t},
        quote_char  => qq{"},                   # default
        escape_char => qq{"},                   # default
        encoding_in => "UTF-8",                 # new 13 Jul
        encoding_out=> "UTF-8",
        # binary      => 1,                     # new 13 Jul
        eol         => $eol,
        allow_loose_quotes => 1,
    });
    
    my @prot_columns;
    my @data_columns;
    my @sample_columns;
    my @headings;
    
    while (my $row = $parser->getline($in_fh)){
    	next if (join "\t", @$row) =~ $BLANK;
    	next if (join "\t", @$row) =~ $COMMENT;
        
        unless(@headings){
        	@headings = @$row;
        	@prot_columns = grep { @$row[$_]=~/Protocol\s*REF/i } 0..$#headings;
        	@data_columns = grep { @$row[$_]=~/.*Array\s*Data.*File$/i } 0..$#headings;
        	@sample_columns = grep { @$row[$_]=~/Source\s*Name/i } 0..$#headings;
        	
        	if ($self->get_assign_samples){
        		if (my $prefix = $self->get_sample_accn_prefix){
        		    require ArrayExpress::AutoSubmission::DB::Sample;
        		    ArrayExpress::AutoSubmission::DB::Sample->accession_prefix(
        		        $prefix,
        		    );
        		}
        		else{
        			die "Error: cannot assign sample accessions as no prefix has been set";
        		}
        		
        		# Add extra columns to contain sample accessions
        		my $number_of_inserts = 0;
        		foreach my $index (@sample_columns){
        			splice (@$row, 
        			        $index+$number_of_inserts+1,
        			        0, 
        			        "Comment[SampleAccession]");
        			$number_of_inserts++;
        		}
        	}
        	
        	print $out_fh join "\t", @$row;
        	print $out_fh "\n";
        	
        	next;
        }

        # Store data file names
        foreach my $data_col (@data_columns){
        	my $name = $row->[$data_col];
        	$data_files{$name}=1 if $name;
        }
               
        unless ($self->get_keep_prot_accns){
	        # Replace protocol names with accessions
	        foreach my $col (@prot_columns){
	         	my $prot_name = $row->[$col];
	         	my $acc = $prot_accs->{$prot_name};
	         	$row->[$col] = $acc || $prot_name; #changed by Natalja from $row->[$col] = $acc;
	        }
        }
        
        # We do this last because it adds columns and
        # thus changes indices of other columns
        if ($self->get_assign_samples){
        	# Insert sample accessions
        	my $number_of_inserts = 0;
        	foreach my $index (@sample_columns){
        		my $sample_name = $row->[$index+$number_of_inserts];
        	    my $accession = "";
        	    $accession = ArrayExpress::AutoSubmission::DB::Sample->reassign_sample(
        	        $sample_name,
        	        $self->get_accession,
        	    );
        	    	
        		splice (@$row, 
        			    $index+$number_of_inserts+1,
        			    0, 
        			    $accession);
        		$number_of_inserts++;
        	}        	
        }
        
        print $out_fh join "\t", @$row;
        print $out_fh "\n";   
    }
    
   	return keys %data_files;
}

sub export_idf{
    my ($self) = @_;
    
    $self->log("Rewriting IDF to load directory");
    
    # Set up the protocol accession service
    unless ($self->get_prot_accn_service){
    	$self->set_prot_accn_service( $self->generate_prot_accn_service);
    }
    
    open (my $in_fh, "<", $self->get_idf) or die "Could not open idf ".$self->get_idf." for reading";
    
    my $output = File::Spec->catfile($self->get_target_dir,$self->get_accession.".idf.txt");
    open (my $out_fh, ">:encoding(UTF-8)", $output) or die "Could not open new idf $output for writing";
    
    my %prot_accs;
    my @additional_files;
    
    # List of things not to export from original file
    my @do_not_export;
    
    # Add experiment accession
    print $out_fh "Comment[ArrayExpressAccession]\t".$self->get_accession."\n";
    push @do_not_export, "Comment[ArrayExpressAccession]";

    my @term_sources;
    
    foreach my $line (<$in_fh>){   
        
        # Remove double quotes
        $line=~s/\"//g;
        
        # Remove dos line endings
        $line=~s/\r\n//g;
        
        # Fix some IDF tags which are now validated more strictly
        $line =~ s/Quality\s*Control\s*Types/Quality Control Type/i;
        $line =~ s/Person\s*Mid\s*Initial\t/Person Mid Initials\t/i;
        
        chomp $line;
        next if $line=~/^SDRF\s*File/i;
        next if $line=~$COMMENT;
        next if $line=~$BLANK;
        my @cells = split "\t", $line;
        next if grep { $self->tags_are_same($cells[0],$_) } @do_not_export;
        
        # Store list of additional files as these need copying to load dir
        if ($cells[0] =~/Comment\[AdditionalFile.*\]/i){
        	push @additional_files, @cells[1..$#cells];
        }
        
        # Replace protocol names with accessions
        if ($line =~ /^\"?Protocol\s*Name/i){
        	my @names = split "\t", $line;
        	if ( my $service = $self->get_prot_accn_service() and not $self->get_keep_prot_accns ) {
        		my @acc_list;
        		foreach my $name (@names[1..$#names]){
	                if ($name){
	                    my $accession = $service->(
	                        $name,
	                        $self->get_accession,
	                    );
	                    # Store new accessions
	                    push @acc_list, $accession;
	                    $prot_accs{$name} = $accession;
	                }
	                else{
	                	push @acc_list, "";
	                }
        		}
        		# Print new accessions
                print $out_fh join "\t", "Protocol Name", @acc_list;
                print $out_fh "\n";	
        	}
        	else { print $out_fh $line."\n";}
        }
        elsif($line =~ /^\"?Term Source Name/i){
            my @names = split "\t", $line;
            foreach my $new_source (@term_sources){
            	unless (grep {$_ eq $new_source} @names){
            		push @names, $new_source;
            	}
            }
            $line = join "\t", @names;
            print $out_fh $line."\n";
        }
        elsif ($line =~ /^\"?Investigation\s*Title/i){
            # Add Comment[Submitted Name] so we do not lose orig name
            print $out_fh $line."\n";
            my $name = $cells[1];
            print $out_fh "Comment[Submitted Name]\t$name\n";
        }
        else{
        	print $out_fh $line."\n";
        }
    }
    
    # Add new SDRF file names
    my @new_names = map { (File::Spec->splitpath($_))[2] } @{ $self->get_sdrfs };
    print $out_fh "SDRF File\t".(join "\t", @new_names)."\n";
    
    return (\%prot_accs, \@additional_files);	
}

sub tags_are_same{
	my ($self, $tag1, $tag2) = @_;
	
	$tag1 =~ s/\s//g;
	$tag2 =~ s/\s//g;
	
	if (lc($tag1) eq lc($tag2)){
		return 1;
	}
	else{
		return 0;
	}
	
}

sub get_export_temp_dir{
	my ($self) = @_;

	my $tmp_dir = $self->get_temp_dir;
	
	unless (-e $tmp_dir){
		mkdir $tmp_dir or die "Could not create AE2 export directory $tmp_dir";
	}
	
	return $tmp_dir;
}

sub generate_prot_accn_service{
	my ($self) = @_;
	
	my $prefix = $self->get_prot_accn_prefix;
	unless ($prefix){
		warn ("Error: cannot set up protocol accession service as not prefix was provided");
	}
	
    # Skip this if we want to keep our original accessions.
    return undef if $self->get_keep_prot_accns();

    if ( $CONFIG->get_AUTOSUBS_DSN() ) {
	
		require ArrayExpress::AutoSubmission::DB::Protocol;
	
		ArrayExpress::AutoSubmission::DB::Protocol->accession_prefix(
		    $prefix
		);
	
		return sub {
	
		    my ($user_accession, $expt_accession) = @_;
		    warn(
			sprintf(
			"Assigning accession for protocol %s using autosubmission system...\n",
			$user_accession,
			)
		    );
	
		    # Arguments are user_accession, expt_accession, protocol name.
		    my $new_accession
			= ArrayExpress::AutoSubmission::DB::Protocol->reassign_protocol(
			$user_accession,
			$expt_accession,
			$user_accession,
		    );
	
		    return $new_accession;
		}
    }
    else{
    	return undef
    }	
}

sub mac2unix{
	my ($self, $file) = @_;
	
	my ($counts, $le) = check_linebreaks($file);
	
	if ($counts->{mac}){
		print "Converting mac line endings to unix for file $file\n";
		my $command = "/usr/bin/env perl -i -pe 's/\r/\n/g' $file";
        
        system $command;
        
        # Example from http://perldoc.perl.org/functions/system.html
        unless( $? == 0 ) {
            
            if( $? == -1 ) {
                die "Failed to execute \"system $command\" : $!\n";
            }
            elsif( $? & 127 ) {
                my $withWithout = ( $? & 128 ) ? "with" : "without";
                my $message = 
                    "In mac2unix, child died with signal "
                    . ( $? & 127 )
                    . " $withWithout coredump\n";
                die $message;
            }
            else {
                my $exitval = $? >> 8;
                die "In mac2unix, child died with value $exitval\n";
            }
        }
	}
	return;
}
sub dos2unix {

	my ( $self, $file ) = @_;
	my ( $counts, $le ) = check_linebreaks($file);

	if ( $counts->{dos} ) {
		print "Converting dos line endings to unix for file $file\n";
		my $command =  "/usr/bin/env perl -i -pe 's/\r\n/\n/g' $file";

        system $command;
        
        # Example from http://perldoc.perl.org/functions/system.html
        unless( $? == 0 ) {
            
            if( $? == -1 ) {
                die "Failed to execute \"system $command\" : $!\n";
            }
            elsif( $? & 127 ) {
                my $withWithout = ( $? & 128 ) ? "with" : "without";
                my $message = 
                    "In dos2unix, child died with signal "
                    . ( $? & 127 )
                    . " $withWithout coredump\n";
                die $message;
            }
            else {
                my $exitval = $? >> 8;
                die "In dos2unix, child died with value $exitval\n";
            }
        }
	}
	return;
}

1;

