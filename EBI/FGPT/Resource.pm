#!/usr/bin/env perl
#
# EBI/FGPT/Resource
# 
# Anna Farne 2012 ArrayExpress team, EBI
#
# Abstract class which contains some methods useful
# to the individual Resource classes
#
# $Id: Resource.pm 21741 2012-11-19 12:53:29Z amytang $
#

package EBI::FGPT::Resource;

use Moose;
use MooseX::FollowPBP;

use 5.008008;

use Carp;
use English qw( -no_match_vars );
use LWP::UserAgent;

use EBI::FGPT::Config qw($CONFIG);

has 'user_agent' => (is => 'rw', isa => 'LWP::UserAgent', builder => '_create_agent', lazy => 1);

sub _create_agent{
    my ($self) = @_;
    
    my $ua = LWP::UserAgent->new();
	$ua->max_size( $CONFIG->get_MAX_LWP_DOWNLOAD() );

    $ua->env_proxy;
	
	$self->set_user_agent($ua);	
}

1;
