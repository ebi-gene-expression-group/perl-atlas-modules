#!/usr/bin/env perl
#
# EBI/FGPT/Reader/MAGETAB/IDFSimple.pm
# 
# Anna Farne 2012 ArrayExpress team, EBI
#
# $Id: IDFSimple.pm 20483 2012-07-30 13:11:40Z farne $
#

=pod

=head1 NAME

EBI::FGPT::Reader::MAGETAB::IDFSimple

=head1 DESCRIPTION

A custom Bio::MAGETAB::Util::Reader::IDF which allows us to collect errors
generated when attempting to parse the IDF

=cut

package EBI::FGPT::Reader::MAGETAB::IDFSimple;

use Moose;
use MooseX::FollowPBP;

use 5.008008;

use Carp;
use English qw( -no_match_vars );
use List::Util qw(first);
use Data::Dumper;
use Bio::MAGETAB::Comment;
use Bio::MAGETAB::Types qw( Date );

extends 'Bio::MAGETAB::Util::Reader::IDF';

has 'logger'        => (is => 'rw', isa => 'Log::Log4perl::Logger', required => 1);

# Temporarily redefine croak in IDF reader to get as much info as we can from it
# and store any errors about unrecognized tags    
my @errors;
sub log_croak{ 
	my ($error) = @_;
	push @errors, $error;
};

{
	no warnings 'redefine';
	
    *Bio::MAGETAB::Util::Reader::TagValueFile::croak = \&log_croak;
    *croak = \&log_croak;
}
# This will be called after the parent BUILD method
# so we can use it to modify the tag recognition regex
# to conform to a more strict specification
sub BUILD{

    my ($self) = @_;
    my $dispatch = $self->get_dispatch_table;
    my $strict_dispatch;
    
    
    foreach my $regex (keys %$dispatch){
    	my $value = $dispatch->{$regex};
    	
    	if ($regex =~ /(Initial|Role|Parameter)s\?/i){
    		my $singular_form = $1;
    		my $plural = $singular_form."s";
    		
    		# Make everything singular
    		$regex =~ s/ ( s | \(es\) ) \? //gixms;
    		
            # Then make the exceptional term plural again
    		$regex =~ s/$singular_form/$plural/g;
    		
    		# We do it like this because some regex contain
    	    # both singular and plural
    	    # e.g. Person Roles Term Accession Number
    	}
    	else{
    		# Must be singular
    		$regex =~ s/ ( s | \(es\) ) \? //gixms;
    	}
    	
    	# Use US spelling
    	$regex =~ s/\[  [sz]{2}  \]/z/ixms;
    	
    	# Don't allow, e.g. Protocol <Type> Term Source REF
    	$regex =~ s/\( \? \: Type \) \? \s \*//gixms;
    	
    	$strict_dispatch->{$regex} = $value;
    }
   
    $self->set_dispatch_table($strict_dispatch);
}

# After parse we add the collected errors to the logger
after 'parse' => sub{
	my ($self) = @_;
	foreach my $error (@errors){
		$self->get_logger->error($error);
	}
	
	# And store the original date string for later checking
	my $text_store = $self->get_text_store;
	if (my $release_date = $text_store->{'investigation'}{'publicReleaseDate'}){
		my $comment = Bio::MAGETAB::Comment->new({
			name  => "ReleaseDateString",
			value => $release_date
		});
		my $investigation = $self->get_magetab_object;
		my @comments = $investigation->get_comments;
		push @comments, $comment;
		$investigation->set_comments(\@comments);
	}
	
};

# Method redefined to report error where too many values provided for tag
sub _add_singleton_datum {

    # Record a 1:1 group:arg relationship.
    my ( $self, $group, $tag, @args ) = @_;

    my $arg = $args[0];
    
    if (@args > 1){
    	croak("More than one value found for $tag");
    }
    
    # These really aren't allowed to be duplicated so we throw an
    # error here rather than try and cope.
    if ( defined $self->get_text_store()->{ $group }{ $tag } ) {
        croak("Error: Duplicate $group $tag field encountered");
    }

    # We catch invalid dates here because if date type
    # coercion fails during _create_investigation it
    # causes parsing to crash
    if ($tag eq "publicReleaseDate"){
    	eval{
    		to_Date($arg);
    	};
    	if($@){
    		croak("This is not a valid date: $arg");
    		return;
    	}
    }
    
    $self->get_text_store()->{ $group }{ $tag } = $arg;

    return;
}

# Additional check for attributes provided without a name
sub validate_grouped_data{
	
    my ($self) = @_;
    
    my $text_store = $self->get_text_store;
    
    my %required_for = (
    	factor     => 'name',
    	protocol   => 'name',
    	termsource => 'name',
    );
    
    while (my ($group, $required_att) = each %required_for){
    	$self->get_logger->debug("Checking that $required_att is specified for all $group attributes");
    	
    	ENTRY: foreach my $entry (@{ $text_store->{$group} || [] }){
            # If no atts at all are specified we skip this entry
            next ENTRY unless grep { $_ } values %{ $entry || {} };
            
            unless ($entry->{$required_att}){
            	my @atts = map { $_." = ".$entry->{$_} } keys %{ $entry || {} };
            	my $atts_string = join ", ", @atts;
    			$self->get_logger->error("Found a $group without a $required_att (attributes provided: $atts_string)");
            }
    	}
    }
}

1;
