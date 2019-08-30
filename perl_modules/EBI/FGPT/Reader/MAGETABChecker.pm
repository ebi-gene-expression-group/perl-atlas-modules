#!/usr/bin/env perl
#
# EBI/FGPT/Reader/MAGETABChecker.pm
# 
# Anna Farne 2012 ArrayExpress team, EBI
#
# $Id: MAGETABChecker.pm 23516 2013-04-19 14:23:05Z amytang $
#

=pod

=head1 NAME

EBI::FGPT::Reader::MAGETABChecker


=head1 DESCRIPTION

An extension of EBI::FGPT::Reader::MAGETAB which provides some additional
and wrapper methods so that the module can be used in exactly the same
way as the ArrayExpress::MAGETAB::Checker

=head1 METHODS

=item validate

Runs a basic parse plus the checks in the AEArchive CheckSet

=item check

Runs a basic parse plus the checks in the AEArchive and Curation CheckSets

=item get_validation_fail

Returns 1 if validate produced errors, 0 if it did not.

=item get_error

Returns an error code indicating the severity of problems found.
Error codes defined in EBI::FGPT::Config

=item get_miamexpress_software_type

Returns the name of the software types of the raw data files

=item get_aedw_score

Returns undef for now but this wrapper module could be extended to run
Atlas checks if necessary

=item get_miame

Returns undef for now but a MIAME CheckSet could be created if we need
this score

=item set_clobber

Does nothing. We always clobber logs and reports now.

=cut

package EBI::FGPT::Reader::MAGETABChecker;

use Moose;
use MooseX::FollowPBP;

extends 'EBI::FGPT::Reader::MAGETAB';

use Data::Dumper;
use EBI::FGPT::Config qw($CONFIG);

use EBI::FGPT::Writer::Report;
use Bio::MAGETAB::Util::Writer::GraphViz;

use Log::Log4perl::Level;


around BUILDARGS => sub{
	
	my $orig_buildargs = shift;
	my $self = shift;
	
	my $args = shift;
	
	my %arg_mapping = (
	    magetab_doc        => 'mtab_doc',
	    idf                => 'idf',
	    source_directory   => 'data_dir',
	    skip_data_checks   => 'skip_data_checks',
	);
	
	my %new_args;
	
	foreach my $type (keys %$args){
		my $new_type = $arg_mapping{$type};
		if($new_type and defined $args->{$type}){
			$new_args{$new_type} = $args->{$type};
		}
	}
	
	return $self->$orig_buildargs(\%new_args);
};

sub validate{
	
	my ($self) = @_;

    # To avoid errors about lack of accession in submitted file
    $self->set_accession("DUMMY");
    	
	my $check_sets = { 'EBI::FGPT::CheckSet::AEArchive' => 'ae_validation' };
	$self->set_check_sets($check_sets);
	
	$self->parse;
    return;
}

sub check{
	
	my ($self) = @_;
	
	# To avoid errors about lack of accession in submitted file
	$self->set_accession("DUMMY");


	# Set up two report writers (Log::Log4perl::Appender objects),
	# one for Atlas checkset, one for non-Atlas checksets (that's AEArchive
	# and Curation). This has to be done before the check sets are added
	# to the MAGETAB Reader object:
	
	my $atlas_reporter = Log::Log4perl::Appender->new(
                                            "EBI::FGPT::Writer::Report", 
                                            name=> "atlas_report_writer", 
                                            additivity => 1,
                                            );

    $atlas_reporter->threshold($INFO);
    $self->set_atlas_report_writer($atlas_reporter);
	
	my $reporter = Log::Log4perl::Appender->new(
                                            "EBI::FGPT::Writer::Report", 
                                            name=> "report_writer", 
                                            additivity => 1,
                                            );

    $reporter->threshold($INFO);
    $self->set_report_writer($reporter);
    
	# No file names because we don't want to create log files
	# Curation CheckSet will create reports instead
	my $check_sets = {
		'EBI::FGPT::CheckSet::AEArchive' => '',
		'EBI::FGPT::CheckSet::Curation'  => '',
		'EBI::FGPT::CheckSet::AEAtlas'  => '',
	};
	
	$self->set_check_sets($check_sets);
	
	$self->parse;
	$self->draw_graph;
	return;
}


sub get_validation_fail{
	
	my ($self) = @_;
	
	my $validation_errors = $self->has_errors('EBI::FGPT::Reader::MAGETAB')
	                      || $self->has_errors('EBI::FGPT::CheckSet::AEArchive');
	
	return $validation_errors;
}

sub get_error{
	
    my ($self) = @_;
    
    my $error_code = 0;
    
    # Create an error code based on the status of the various
    # CheckSets we have run
    
    if($self->has_errors('EBI::FGPT::Reader::MAGETAB')){
    	$error_code |= $CONFIG->get_ERROR_PARSEFAIL;
    }
    
    if($self->has_errors('EBI::FGPT::CheckSet::AEArchive')){
    	$error_code |= $CONFIG->get_ERROR_PARSEFAIL;
    }
    
    if($self->has_warnings('EBI::FGPT::CheckSet::AEArchive')){
    	$error_code |= $CONFIG->get_ERROR_INNOCENT;
    }
    
    if($self->has_errors('EBI::FGPT::CheckSet::Curation')){
    	$error_code |= $CONFIG->get_ERROR_PARSEBAD;
    }
    
    if($self->has_warnings('EBI::FGPT::CheckSet::Curation')){
    	$error_code |= $CONFIG->get_ERROR_INNOCENT;
    }
    
    return $error_code;
}

sub get_miamexpress_software_type{
	
	my ($self) = @_;
	
	my $curation_check_set = $self->get_check_set_objects->{'EBI::FGPT::CheckSet::Curation'};
	
	if ($curation_check_set){
		return join ", ", keys %{ $curation_check_set->get_raw_file_type };
	}
	else{
		return undef;
	}
}

sub draw_graph{
	
	my ($self) = @_;
	
	my $file_name = $self->get_input_name;
	
	my ($vol,$dir,$file) = File::Spec->splitpath($file_name);
	$file_name = $file;
	
	# Replace the input file suffix with .png
	$file_name =~ s/\.[^\.]*$//;
	$file_name.=".png";
	
	$dir ||= ".";
	my $file_path = File::Spec->catfile($dir,$file_name);
	open (my $graph_fh, ">", $file_path) or die "Could not open $file_path for writing - $!";
	if (my $mtab = $self->get_magetab){
		my $graphviz = Bio::MAGETAB::Util::Writer::GraphViz->new({
			sdrfs => [$mtab->get_sdrfs],
			font  => 'luxisr', 
		});
		my $image = $graphviz->draw();
		print $graph_fh $image->as_png();
	}
	else{
		$self->error("Could not create experiment graph as MAGE-TAB objects are not available");
	}
}

sub get_atlas_fail_codes{
	
	my ($self) = @_;
	
	my $eligibility_check_set = $self->get_check_set_objects->{'EBI::FGPT::CheckSet::AEAtlas'};
	
	if ($eligibility_check_set) {
		my $code_string = join ", ", sort {$a <=> $b} @{$eligibility_check_set->get_atlas_fail_codes};
		return $code_string;
	}
	else{
		return undef;
	}

}	

# We are using get_aedw_score to get the Atlas fail code because
# a method of this name exists for the MIAMExpress and Tab2MAGE checkers
# too, and they are all run by the same Daemon code
sub get_aedw_score{
	
	my ($self) = @_;
	
	my $code = $self->get_atlas_fail_codes;
	
	if (defined $code and $code eq ""){
		return "PASS";
	}
	else{
		return $code;
	}
}

sub get_miame{
	
	return undef;

}

sub set_clobber{
	
	return;

}

1;

