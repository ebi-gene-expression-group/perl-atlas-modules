#!/usr/bin/env perl
#
# EBI/FGPT/Reader/Status.pm
# 
# Anna Farne 2012 ArrayExpress team, EBI
#
# $Id: Status.pm 19518 2012-03-29 13:50:43Z farne $
#

=pod

=head1 NAME

EBI::FGPT::Reader::Status

=head1 DESCRIPTION

A Log4perl appender to count the number of errors and warnings reported 
by the associated logger.

Code based on stackoverflow solution from Greg Bacon here:
http://stackoverflow.com/questions/2585546/how-can-i-tell-if-log4perl-emitted-any-warnings-during-a-run

=cut

package EBI::FGPT::Reader::Status;

use 5.008008;
use strict;
use warnings;

use Log::Log4perl::Level;

sub new {
  my($class,%arg) = @_;
  bless {} => $class;
}

sub log {
  my($self,%arg) = @_;
  ++$self->{ $arg{log4p_level} };
}

sub has_warnings{
	my ($self) = @_;
	return $self->{"WARN"} ? 1 : 0;
}

sub has_errors{
	my ($self) = @_;
	return $self->{"ERROR"} ? 1 : 0;	
}

sub howmany {
  my($self,@which) = @_;
  my $total = 0;
  $total += ($self->{$_} || 0) for @which;
  $total;
}

sub reset {
	my ($self) = @_;
	$self->{"WARN"} = 0;
	$self->{"ERROR"} = 0;
}
1;