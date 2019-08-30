#!/usr/bin/env perl
#
# EBI/FGPT/CheckSet.pm
#
# Anna Farne 2012 ArrayExpress team, EBI
#
# $Id: CheckSet.pm 26146 2014-11-21 15:19:36Z amytang $
#

=pod

=head1 NAME

EBI::FGPT::CheckSet

=head1 SYNOPSIS

Create your own CheckSet subclass:

 package EBI::FGPT::CheckSet::MyChecks;

 extends 'EBI::FGPT::CheckSet';

 augment 'run_idf_checks' => sub{

     my ($self) = @_;
	
	 $self->run_my_idf_checks();
  	
 };

 augment 'run_sdrf_checks' => sub{
     my ($self) = @_;
	
	 $self->run_my_sdrf_checks();	
 };


Then pass it to the EBI::FGPT::Reader::MAGETAB:
 
 use EBI::FGPT::Reader::MAGETAB;
 
 my $check_sets = {
	'EBI::FGPT::CheckSet::MyChecks'  => 'my_checks',
 };

 my $idf = $ARGV[0];
 my $checker = EBI::FGPT::Reader::MAGETAB->new( 
    'idf'                  => $idf, 
    'check_sets'           => $check_sets,
 );
 $checker->check();

=head1 DESCRIPTION

Base class which can be extended to specify sets of check to run on
a MAGE-TAB document. Pass the name of your CheckSet class to a
EBI::FGPT::Reader::MAGETAB and your checks will be run at the appropriate 
stage during parsing

=head1 ATTRIBUTES

=over 2

=item logger (required)

A Log::Log4perl::Logger to handle logging messages

=item data_dir (required)

Path of the directory where data files and SDRF file can be found

=item investigation (optional)

The Bio::MAGETAB::Investigation to check

=item simple_sdrfs (optional)

A list of EBI::FGPT::Reader::MAGETAB::SDRFSimple objects to check

=item magetab (optional)

The Bio::MAGETAB object to check

=item input_name (optional)

The name of the IDF or magetab doc being checked (for use in log file names only)

=item onto_terms (optional)

Config::YAML list of ontology terms that can be used in various contexts (loaded
on demand from *FIXME - add this file to config*)

=item skip_data_checks (default is 0)

Set to 1 or 0 to indicate if data file checks should be skipped

=back

=head1 METHODS

Each attribute has a get_* and set_* method.

=over 2

=item add_simple_sdrf

Adds an extra L<SDRFSimple|EBI::FGPT::Reader::MAGETAB::SDRFSimple> object for checking

=item run_idf_checks

Runs after successful IDFSimple parse. Requires that investigation has been set.

=item run_simple_sdrf_checks

Runs after SDRFSimple parse. Requires that simple_sdrfs has been set.

=item run_sdrf_checks

Runs after successful full SDRF parse. Requires that magetab has been set.

=head1 SHARED CHECKS

These checks are implemented here as they may be needed in more than one
child-class CheckSet:

=item check_ae_expt_type

This method fetches a list of AEExperimentType terms which are eligibile for
the ArrayExpress database from the controlled vocab, and then pass the list
to check_expt_type method for the actual check.

=item check_expt_type

IDF must provide at least one Comment[AEExperimentType] value.  This method takes
an arrayref of approved experiment types as argument, and compares the 
Comment[AEExperimentType] value(s) against the list of terms. All values must
be from the list of approved terms.

=item check_for_ae_accession

IDF must provide Comment[ArrayExpressAccession].

=item check_for_sdrf


=item check_release_date_format

This method checks that the Comment[ReleaseDateString] is in the format YYYY-MM-DD.
This comment is created by the EBI::FGPT::MAGETAB::IDFSimple parser. The method
does not check the investigation's publicReleaseDate attribute because this is 
coerced into the correct format during parsing so is not the same as the string 
in the input document.

=item check_unit_terms

Each unit for a measurement must come from a EFO unit subclass. 

=back

head1 SEE ALSO

L<EBI::FGPT::Reader::MAGETAB>

=cut

package EBI::FGPT::CheckSet;

use Data::Dumper;
use Moose;
use MooseX::FollowPBP;

use Config::YAML;
use EBI::FGPT::Config qw($CONFIG);
use EBI::FGPT::Resource::BioPortal;
use EBI::FGPT::Resource::OLS;
use Atlas::Common qw( get_aeatlas_controlled_vocabulary );
use File::Spec;


has 'input_name' => ( 
    is => 'rw', 
    isa => 'Str' 
);

has 'magetab'    => ( 
    is => 'rw', 
    isa => 'Bio::MAGETAB' 
);

has 'simple_sdrfs' => (
    is      => 'rw',
	isa     => 'ArrayRef[EBI::FGPT::Reader::MAGETAB::SDRFSimple]',
	default => sub { [] }
);

has 'investigation' => ( 
    is => 'rw', 
    isa => 'Bio::MAGETAB::Investigation' 
);

has 'logger' => (
    is       => 'rw',
	isa      => 'Log::Log4perl::Logger',
	required => 1,
	handles  => [qw(logdie fatal error warn info debug report)],
);

has 'report_writer' => (
	is       => 'rw',
	isa      => 'Log::Log4perl::Appender',
	required => 0,
);

has 'data_dir' => ( 
    is => 'rw', 
    required => 1 
);

has 'onto_terms' => ( 
    is => 'rw', 
    isa => 'Config::YAML', 
    builder => '_load_onto_terms', 
    lazy => 1 
);

has 'skip_data_checks' => ( 
    is => 'rw', 
    isa => 'Bool', 
    default => 0 
);

has 'aeatlas_controlled_vocab' => (
    is  => 'rw',
    isa => 'Config::YAML',
    builder => '_build_aeatlas_controlled_vocab'
);

# Methods to handle some custom log appender functions
sub error_section {
	my ( $self, $name ) = @_;
	my $report = $self->get_report_writer or return;
	$report->error_section($name);
}

sub report_section {
	my ( $self, $name ) = @_;
	my $report = $self->get_report_writer or return;
	$report->report_section($name);
}

sub _load_onto_terms {

	my ($self) = @_;

	my $list_path = $CONFIG->get_ONTO_TERMS_LIST;

	my $cache = Config::YAML->new( config => $list_path );

	return $cache;
}

sub add_simple_sdrf {

	my ( $self, $sdrf ) = @_;

	my @existing = @{ $self->get_simple_sdrfs || [] };
	push @existing, $sdrf;
	$self->set_simple_sdrfs( \@existing );

}

# Some stub methods to check we have the required objects before proceeding
# to the actual checks implemented by the subclasses
sub run_idf_checks {

	my ($self) = @_;

	unless ( $self->get_investigation )
	{
		$self->logdie("Cannot perform checks on IDF - no Investigation object available");
	}

	$self->info("Running IDF checks");
	inner();

}

sub run_simple_sdrf_checks {

	my ($self) = @_;

	unless ( @{ $self->get_simple_sdrfs || [] } )
	{
		$self->logdie(
				 "Cannot perform simple checks on SDRF - no SDRFSimple reader available");
	}

	$self->info("Running simple SDRF checks");
    inner();
}

sub run_sdrf_checks {

	my ($self) = @_;

	unless ( $self->get_magetab )
	{
		$self->logdie("Cannot perform checks on SDRF - no MAGETAB object available");
	}

	$self->info("Running SDRF checks");
	inner();
}

###
### Checks which may be called by more than one check set can be included here
###

# check_ae_expt_type is shared by CheckSet/Curation.pm and CheckSet/AEArchive.pm
sub check_ae_expt_type {

	my ($self) = @_;
    
    my $controlledVocab = $self->get_aeatlas_controlled_vocab;

	my $approved_expt_types = $controlledVocab->get_arrayexpress_experiment_types;

	# Some experiments are imported from GEO with no valid AEExperimentType
	# If in the GEO SOFT file it says "other", then the type maps to EFO "other".
	# Anything which can't be mapped was given "unknown experiment type".
	# Comment[AEExperimentType] is no longer added to new imports, but
	# the extra terms need to be included here for backward compatibility

   # FIXME: Maybe the we should set this in the config, or approved term generation script
	push @$approved_expt_types, "other", "unknown experiment type";
	$self->check_expt_type($approved_expt_types);

}

# check_expt_type is used by check_ae_expt_type and is shared by CheckSet/AEAtlas.pm
# This subroutine is split into two parts - checks for AE Archive and checks for the Atlas.
# For ArrayExpress, we just check that all experiment types are in the controlled vocab.
# For the Atlas, we check whether there is 1, 2 or more experiment types. If 1, then check is in Atlas list,
# if 2 then check as some combinations of experiment types ok, others not, if > 2 then the Atlas processing can't
# handle this as don't know which assays are of which type.

sub check_expt_type {

	my ( $self, $approved_list ) = @_;
	my @approved_types = @{ $approved_list || [] };

	if ( scalar(@approved_types) == 0 )
	{
		$self->error(
"No list of approved experiment types have been provided. Can't check if experiment type is OK."
		);
	}

	my $atlas_fail_flag = 0;

	# IDF must provide Comment[AEExperimentType]
	my @type_comments =
	    grep { $_->get_name eq "AEExperimentType" }
	    @{ $self->get_investigation->get_comments || [] };
	
	# Don't bother checking further if no AEExperimentType value was provided
	
	unless (@type_comments)
	{
		$self->error("No Comment[AEExperimentType] value provided");
		$atlas_fail_flag = 1;
		return $atlas_fail_flag;
	}

	# Find out the CheckSet type

	my @strings = split( /::/, ref($self) );
	my $checkset_name = $strings[3];
	$self->debug("CheckSet type is $checkset_name");

	# If AE experiment type checks do this

	if ( $checkset_name eq "AEArchive" )
	{

		foreach my $comment (@type_comments)
		{
			my $type = $comment->get_value;
			unless ( grep { $type eq $_ } @approved_types )
			{
				my @strings = split( /::/, ref($self) );
				my $checkset_name = $strings[3];
				$atlas_fail_flag = 1;
				$self->error(   "\"$type\" is not an approved AEExperimentType for $checkset_name check."
				);
			}
		}

	}
	else
	{

		# else Atlas experiment type checks

	 # If there is only 1 experiment type see if it is in the Atlas eligible list in controlled vocab.
		if ( scalar @type_comments == 1 )
		{    #FIXME: improve code to look at just one value
			$self->debug("1 experiment type - checking it");

			foreach my $comment (@type_comments)
			{
				my $type = $comment->get_value;
				unless ( grep { $type eq $_ } @approved_types )
				{
					my @strings = split( /::/, ref($self) );
					my $checkset_name = $strings[3];
					$atlas_fail_flag = 1;
				}
			}

		}
		elsif ( scalar @type_comments == 2 )
		{

			$self->debug("2 experiment types - checking them");

# check if the 2 experiment types are either of these 2 combinations, if not, then Atlas fail
#$self->debug(Dumper(@type_comments));
			my @experiment_types;
			foreach my $comment (@type_comments)
			{
				my $type = $comment->get_value;
				push( @experiment_types, $type );
			}

			if (
				 (
				      ( $experiment_types[0] eq 'transcription profiling by array' )
				   && ( $experiment_types[1] eq 'microRNA profiling by array' )
				 )
				 || (    ( $experiment_types[1] eq 'transcription profiling by array' )
					  && ( $experiment_types[0] eq 'microRNA profiling by array' ) )
			  )
			{
				$atlas_fail_flag = 0;    # these combinations ok
				$self->debug("2 OK array experiment types");
			}
			elsif (
					(
					     ( $experiment_types[0] eq 'RNA-seq of coding RNA' )
					  && ( $experiment_types[1] eq 'RNA-seq of non coding RNA' )
					)
					|| (    ( $experiment_types[1] eq 'RNA-seq of coding RNA' )
						 && ( $experiment_types[0] eq 'RNA-seq of non coding RNA' ) )
			  )
			{
				$atlas_fail_flag = 0;    # these combinations ok
				$self->debug("2 OK sequencing experiment types");
			}
			else
			{
				$atlas_fail_flag = 1;
				$self->debug("This combination of 2 experiment types is not ok");

			}

		}
		elsif ( scalar @type_comments > 2 )
		{
			$atlas_fail_flag = 1
			  ; # there is not a combination of > 2 expt types that the Atlas processing can handle
			$self->debug("More than 2 experiment types - Atlas can't handle this");
		}

	}

	return $atlas_fail_flag;

}

# check_unit_terms is also used by Checkset/AEAtlas.pm
sub check_unit_terms {

	my ($self) = @_;
	my $atlas_units_fail_flag = 0;

    # Create OLS client object. Will try to use this instead of old way, but
    # fall back on the old way if OLS is unsuccessful.
    my $ols = EBI::FGPT::Resource::OLS->new;
    
    # Subtree is the bioportal url for Units subtree
	my $bp = EBI::FGPT::Resource::BioPortal->new(
					subtree_root => "http%3A%2F%2Fpurl.obolibrary.org%2Fobo%2FUO_0000000",
					ontology     => "EFO",
					exact_match  => "true"
	);

    # Collect the unique unit values so as not to print the same one to the
    # logs over and over.
    my $uniqueUnits = {};
  MEASUREMENT:
	foreach my $measurement ( $self->get_magetab->get_measurements ) {
		my $unit    = $measurement->get_unit or next MEASUREMENT;
		my $value   = $unit->get_value;

        # If the value is empty or just spaces, skip it.
        if( not defined $value or $value =~ /^ *$/ ) { next; }

        $uniqueUnits->{ $value } = 1;
    }

    if( keys %{ $uniqueUnits } ) {

        foreach my $value ( keys %{ $uniqueUnits } ) {
		
            $self->debug("Checking $value is an approved unit");

            # FIXME: First try OLS beta. If this is unsuccessful, try old way (YAML
            # file) as a fall-back.
            # OLS.pm gives a hash as its result, e.g. as follows:
            # {
            #  'label' => 'milligram per kilogram',
            #  'possible_match' => 0,
            #  'matched_label' => 1
            # };
            #   - If matched_label is set, then the term matches the EFO label an all
            #   is fine.
            #   - If possible_match is set, the term matched one of the synonyms in EFO
            #   or the EFO label but with different casing. In that case we can
            #   suggest the label to the curator to make the change.
            #   - If nothing is set and label is undef, there was no match and we can't
            #   make any suggestions.
            my $OLSResults = $ols->query_unit_term( $value );
            
            my $OLSFail = 0;

            unless( $OLSResults ) { $OLSFail = 1; }
            else {
                # Take a look at the OLS results.
                if( $OLSResults->{ "label" } ) {
                    
                    # If we've got a label, see if it's for a "possible match" -- this
                    # means the value didn't match the preferred EFO label.
                    if( $OLSResults->{ "possible_match" } ) {

                        $self->error( 
                            "\"$value\" is not a preferred EFO label. Did you mean \"" .
                            $OLSResults->{ "label" } .
                            "\"?"
                        );

                        $atlas_units_fail_flag = 1;
                    }
                }
                # Otherwise, if label is undef, we didn't get any matches for this unit
                # value from OLS.
                # FIXME: While trying out OLS, if it fails to find a match, fall back
                # on the old way which is to search inside a YAML config file.
                else {
                    $self->error(
                        "\"$value\" was not found in EFO via OLS. Searching YAML file instead..."
                    );

                    $OLSFail = 1;
                }
            }

            # If OLS failed, either because there was no match or because of some
            # problem with our code or the OLS service, try the YAML file instead.
            if( $OLSFail ) {

                my $matches = $bp->query_unit_term($value);

                # If we cannot find a match then throw an error
                if ( !$matches ) {

                    $self->error("\"$value\" is not an approved unit");
                    $atlas_units_fail_flag = 1;
                }
                # Otherwise if the match returned isn't an exact match suggest these matches to curator
                else {

                    my @matches = @$matches;
                    foreach my $match (@matches) {

                        if ( $match ne $value ) {

                            my $all_matches = join( '" or "', @matches );
                            
                            $self->warn(
                                "\"$value\" is not a prefered label in EFO, suggest changing to \"$all_matches\""
                            );
                        }
                    }
                }
            }
        }
    }
    return $atlas_units_fail_flag;
}

sub check_release_date_format {

	my ($self) = @_;

	# IDFSimple stores the original date string as "ReleaseDateString" comment
	# so we can see how it looked before being coerced into a DateTime object
	my ($date_comment) =
	  grep { $_->get_name eq "ReleaseDateString" }
	  @{ $self->get_investigation->get_comments || [] };
	my $date = $date_comment->get_value;
	unless ( $date =~ /^\d\d\d\d-\d\d-\d\d(T\d\d:\d\d:\d\dZ)?$/ )
	{
		$self->error("Release date \"$date\" is not in the correct format (YYYY-MM-DD)");
	}
}

sub check_for_ae_accession {

	my ($self) = @_;

	# IDF must provide Comment[ArrayExpressAccession]
	my ($acc_comment) =
	  grep { $_->get_name eq "ArrayExpressAccession" }
	  @{ $self->get_investigation->get_comments || [] };
	$self->error("No Comment[ArrayExpressAccession] provided") unless $acc_comment;

}

sub check_for_sdrf {

	my ($self) = @_;

	my @sdrfs = $self->get_investigation->get_sdrfs;

	# IDF must reference an SDRF
	$self->error("No SDRFs found in IDF") unless @sdrfs;
}

sub _normalize_category {

	my ( $self, $string ) = @_;

	$string = lc($string);
	$string =~ s/ //g;
	$string =~ s/_//g;

	return $string;
}

sub _dont_normalize_category {

   # quick fix to stop normalization of categories without changing all code in AEAtlas.pm

	my ( $self, $string ) = @_;

	return $string;
}


# Create the Config::YAML representation of the controlled vocabulary, for
# checking eligible experiment types, property types, etc.
sub _build_aeatlas_controlled_vocab {

    my $aeatlasControlledVocab = get_aeatlas_controlled_vocabulary;

    return $aeatlasControlledVocab;
}

1;
