#!/usr/bin/env perl
#
# EBI/FGPT/Resource/ArrayExpressREST
# 
# Anna Farne 2012 ArrayExpress team, EBI
#
# $Id: ArrayExpressREST.pm 21742 2012-11-19 12:55:13Z amytang $
#

package EBI::FGPT::Resource::ArrayExpressREST;

use Moose;
use MooseX::FollowPBP;

extends 'EBI::FGPT::Resource';

use 5.008008;

use Carp;
use English qw( -no_match_vars );
use LWP::UserAgent;
use HTTP::Cookies;
use EBI::FGPT::Config qw($CONFIG);

has 'array_list' => (is => 'rw', isa => 'HashRef', builder => '_load_array_list' , lazy => 1);

sub _load_array_list{
	
	my ($self) = @_;
	
	# Set the array list to empty hash so the builder is
	# not called again if array list fails to load
	$self->set_array_list({});
	
	# FIXME: do we have external version of this uri for public arrays only?
	my $uri = $CONFIG->get_AE_ARRAYDESIGN_LIST
	or croak("AE_ARRAYDESIGN_LIST URI not set in Config file - cannot load array design list");

	my $ua = $self->get_user_agent;
	
	my $response = $ua->get($uri);
    if ($response->is_success) {
        my @lines = split /\n/, $response->content;
        my %arrays;
        foreach my $line (@lines){
        	my @cells = split "\t", $line;
        	next unless $cells[1]; # Skip if accession is missing
        	$arrays{$cells[1]} = $cells[2];
        }
        $self->set_array_list(\%arrays);
    }
    else {
        croak("Could not get array design list from $uri - ".$response->status_line);
    }	
}

sub get_affy_design_id{
	
	my ($self, $acc) = @_;
	
	unless(scalar %{ $self->get_array_list }){
	    croak("Array list not loaded");	
	}
	
	my $name = $self->get_array_list->{$acc};
	
	if ($name){
		my $design_id;
		
		if ($name =~ m/\[ ([^\]]+) \]/xms){
		    $design_id = $1;
		}
		
		return $design_id;
	}
	else{
	    croak("Array accession $acc not found in ArrayExpress");
	}
}

sub get_adf{

	my $uri_base = $CONFIG->get_PRIVATE_ADF_URI_BASE;  
	# e.g. "http://www.ebi.ac.uk/arrayexpress/files/", to be appended by "A-AFFY-1/A-AFFY-1.adf.txt" later
	
	my ($self,$acc) = @_;
	
	my $cookie_jar = HTTP::Cookies->new();


        # 12 Jul 2016: We used to get the user agent using an internal method of EBI::FGPT::Resource,
        # but that agent's identity somehow changes between the first HTTP call (for authentication)
        # and second HTTP call (to fetch ADF), and that's no longer compatible with the AE back-end
        # server configuration (some machines in London Data Centres, some in Hinxton).
        # Creating the user agent directl using LWP::UserAgent has solved the problem, hence this change.

	#my $ua = $self->get_user_agent();
        my $ua = LWP::UserAgent->new(); 

	$ua->cookie_jar($cookie_jar);   #empty jar, no cookies yet.  User agent also not associated with any proxy.
	
	# We are logging in with username and password to retrieve ADF. This is not
	# really required for public ADFs but at this point we don't really
	# know whether the ADF is public or private, so it's better to treat
	# all ADFs are private.
	
	# Fire the first HTTP request to get the login token cookie:
	
	my $username = $CONFIG->get_PRIVATE_ADF_USERNAME;
	my $password = $CONFIG->get_PRIVATE_ADF_PASSWORD;
	
	my $verify_site = 'http://www.ebi.ac.uk/arrayexpress/verify-login.txt?u='.$username.'&p='.$password;
	my $verify_response = $ua->get($verify_site);
    
	my $uri = $uri_base."$acc/$acc.adf.txt";
	
	# Assign the two required cookies to the user agent object

	$cookie_jar->set_cookie(0,'AeLoginToken', $verify_response->content, '/','www.ebi.ac.uk');
	$cookie_jar->set_cookie(0,'AeLoggedUser', 'curator','/','www.ebi.ac.uk');
	
	# print "Set Cookie Jar?\n", $ua->cookie_jar->as_string, "\n";   # DEBUG
	
	# Fire the second HTTP request from the same user agent to get the ADF
	
	my $response = $ua->get($uri);
	
	my $adf;
    if ($response->is_success) {
        $adf = $response->content;
    }
    else {
        croak("Could not get ADF from $uri - ".$response->status_line);
    }
	
	return $adf;
}
1;
