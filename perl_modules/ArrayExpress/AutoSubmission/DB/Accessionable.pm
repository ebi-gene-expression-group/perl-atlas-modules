#!/usr/bin/env perl
#
# $Id: Accessionable.pm 2276 2010-01-21 17:04:46Z farne $

use strict;
use warnings;

####################################################################
# Superclass for experiment, array, protocol which have accessions #
####################################################################
package ArrayExpress::AutoSubmission::DB::Accessionable;

# Abstract package without corresponding DB table
use base 'Class::Data::Inheritable';
use List::Util qw(max);
use Carp;

use EBI::FGPT::Common qw(date_now);

__PACKAGE__->mk_classdata('accession_prefix');

sub next_accession {    # Class method.
    my $proto = shift;
    my $class = ref $proto || $proto;

    my $prefix = $class->accession_prefix()
	or croak("Error: $class->accession_prefix() not set.");

    # Only use the accessions matching the prefix pattern.
    my @accessions;
    my $iterator = $class->retrieve_all();
    while (my $object = $iterator->next() ) {
	my $acc = $object->accession();
	push(@accessions, $acc) if ($acc && $acc =~ s/^$prefix//);
    }

    return ( $prefix . ( ( max(@accessions) || 0 ) + 1 ) );
}

sub get_accession {    # Instance method.
    my ($self, $values) = @_;

    # Set any additional accessors passed.
    if ($values) {
	ref $values eq 'HASH'
	    or croak("Error: get_accession() needs a hash ref.");
	$self->set( %{ $values } );
    }

    # Grab the accession, or generate a new one.
    unless ( $self->accession() ) {
        $self->set( accession => $self->next_accession() );
        if ($self->find_column("date_assigned")){
        	$self->set( date_assigned => date_now() );
        }
    }
    $self->update();
    return ( $self->accession() );
}

1;
