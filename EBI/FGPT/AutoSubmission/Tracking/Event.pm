#!/usr/bin/env perl

package EBI::FGPT::AutoSubmission::Tracking::Event;

=head1 NAME

EBI::FGPT::AutoSubmission::Tracking::Event
 
=head1 DESCRIPTION

Class used as a bridge between the AE database query objects and the tracking database.

=cut

use Moose;
use MooseX::FollowPBP;

has 'event_type' => ( is => 'rw', isa => 'Str' );
has 'success' => ( is => 'rw' );
has 'source_db' => ( is => 'rw', isa => 'Str' );
has 'target_db' => ( is => 'rw', isa => 'Str' );
has 'starttime'        => ( is => 'rw' );
has 'endtime'          => ( is => 'rw' );
has 'machine'          => ( is => 'rw' );
has 'operator'         => ( is => 'rw' );
has 'log_file'         => ( is => 'rw' );
has 'jobregister_dbid' => ( is => 'rw' );
has 'comment'          => ( is => 'rw' );

1;
