#!/usr/bin/env perl
#
# EBI/FGPT/Writer/Report.pm
# 
# Anna Farne 2012 ArrayExpress team, EBI
#
# $Id$
#

=pod

=head1 NAME

EBI::FGPT::Writer::Report

=head1 DESCRIPTION

A Log4perl appender to report certain errors and warnings produced
during MAGETAB checking in a human readable format

=cut

package EBI::FGPT::Writer::Report;

use 5.008008;
use strict;
use warnings;

use Moose;
use MooseX::FollowPBP;

use Log::Log4perl::Level;
use Data::Dumper;

use EBI::FGPT::Common qw(open_log_fh);

has 'error_fh' => ( is => 'rw', builder => '_open_error_log', lazy => 1 );
has 'report_fh' => (is => 'rw', builder => '_open_report_log', lazy => 1 );
has 'width'     => (is => 'rw', default => 80);
has 'input_name' => (is => 'rw', isa => 'Str');

sub _open_error_log{
	my ($self) = @_;
	return open_log_fh("expt",$self->get_input_name,"error", $self->get_width);
}

sub _open_report_log{
	my ($self) = @_;
	return open_log_fh("expt",$self->get_input_name,"report", $self->get_width);
}

sub log {
  
    my ($self,%args) = @_;
    
    # Filter out INFO messages for now
    return if $args{log4p_level} eq "INFO";
    
    if ($args{log4p_level} eq "REPORT"){
    	my $fh = $self->get_report_fh;
    	my $message = $args{message};
    	$message =~ s/REPORT - //;
    	print $fh $message;
    }
    else{
    	my $fh = $self->get_error_fh;
        print $fh $args{message};
    } 
}

sub error_section{
	
	my ($self, $name) = @_;
	my $fh = $self->get_error_fh;
	
	$self->section($name, $fh);
}

sub report_section{
	
	my ($self, $name) = @_;
	my $fh = $self->get_report_fh;
	
	print $fh "\n";
	$self->section($name, $fh);
	print $fh "\n";
}

sub section{
    
    my ($self, $name, $fh) = @_;
    
    # Default to writing to error log
    $fh ||= $self->get_error_fh;
    
    my $REPORT_WIDTH = $self->get_width;
    
    my $line = $name
	? q{---} . " $name "
	    . (q{-} x ($REPORT_WIDTH - (length($name) + 5)))
	: q{-} x $REPORT_WIDTH;
	
    print $fh "$line\n";
}

1;