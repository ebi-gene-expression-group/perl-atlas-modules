
=head1 NAME

Atlas::AtlasAdmin -- run queries against the Atlas admin REST API.

=head1 DESCRIPTION

Module for running queries against the Expression Atlas admin API, to do things
like getting information about an experiment, load an experiment, delete an
experiment, etc.

- reads curator password from a file
- makes query to the correct webapp
- checks the response came back
- checks the response reports success
- extracts bits of the response

The client code should assume the calls will succeed: the module will validate this and Carp::confess any errors


=head1 SYNOPSIS

use Atlas::AtlasAdmin;

my $api = Atlas::AtlasAdmin->new;

# do an operation for an experiment (or: all)
# works quietly, at the end says nothing and goes to rest until it's time to work again
$api -> perform_operation( $accession, $operation);

# fetch a property of a single experiment, like "last update" or privacy status
$v = $api -> fetch_experiment_property( $accession, $property);

# equivalent of above for many experiments (or all experiments: $refToExperimentsArray is optional)
# returns dictionary : accession => property value
%d = $api -> fetch_property_for_list($property, $refToExperimentsArray);

# lower level, intended to be internal
# returns dictionary: accession => result type
# consider adding a new subroutine to this module if none of above suit your use case
%d = $api -> query_experiment_api($accession, $property);

=head1 AUTHOR

Expression Atlas Team <arrayexpress-atlas@ebi.ac.uk>

=cut

package Atlas::AtlasAdmin;

use strict;
use warnings;
use 5.10.0;

use Moose;
use MooseX::FollowPBP;
use File::Spec;
use JSON::Parse qw( parse_json );
use LWP::UserAgent;
use HTTP::Request::Common;
use Encode 'decode';
use Path::Tiny qw( path );
use Carp;

=head1 ATTRIBUTES

=over 2

=item atlas_host

Hostname of Atlas instance.

=cut

has 'atlas_host' => (
    is  => 'rw',
    isa => 'Str',
    default => 'ves-hx-76'
);

=item atlas_port

Port for Atlas instance on host.

=cut

has 'atlas_port' => (
    is  => 'rw',
    isa => 'Int',
    default => 8080
);

=item username

User name to log in to admin API.

=cut

has 'user_name' => (
    is  => 'rw',
    isa => 'Str',
    default => 'curator'
);

=item user_password

Password to log in to admin API. Loaded from the right place on disk if unset.

=cut

has 'user_password' => (
    is  => 'rw',
    isa => 'Str',
    lazy_build => 1
);

=item user_agent

LWP::UserAgent object for connecting.

=cut

has 'user_agent' => (
    is  => 'ro',
    isa => 'LWP::UserAgent',
    lazy_build => 1
);

=item timeout_seconds

Number of seconds after which a query should time out.

=cut

has 'timeout_seconds' => (
    is  => 'rw',
    isa => 'Int',
    default => 3600
);

=item atlas_api_base

URL to form the base of API queries.

=cut

has 'atlas_api_base' => (
    is  => 'rw',
    isa => 'Str',
    lazy_build  => 1
);


=back

=head1 METHODS

=over 2

=item _build_user_password

Read password from filesystem. It assumes you are fg_atlas.

=cut

sub _build_user_password {
    my ( $self ) = @_;
    return path(
        File::Spec->catfile(
            $ENV{ "ATLAS_PROD" },
            "sw",
            $self->get_user_name
        )
    )->slurp_utf8;
}

sub construct_url {
    my ( $self, $accession, $operation ) = @_;
    my $atlasHost = $self->get_atlas_host;
    my $atlasPort = $self->get_atlas_port;
    return "http://$atlasHost:$atlasPort/gxa/admin/experiments/$accession/$operation";
}

sub query_experiment_api {
    my ( $self, $accession, $operation ) = @_;

    my $url = $self->construct_url($accession, $operation);
    my $request = GET $url;

    $request->header( 'Accept' => 'application/json' );
    $request->authorization_basic(
        $self->get_user_name,
        $self->get_user_password
    );

    my $ua = LWP::UserAgent->new;
    # Large experiments take a long time to load.
    $ua->timeout( $self->get_timeout_seconds );
    my $response = $ua->request($request);

    Carp::confess(
        "Error ".
        $response->status_line.
        ": $url"
    ) unless $response->is_success;

    my %result_per_experiment ;
    for my $o (@{parse_json( decode ('UTF-8', $response->content) )}){
        my $accession = $o->{"accession"};
        my $error = $o->{"error"};
        my $result = $o->{"result"};

        Carp::confess(
            "Error from the API: $error"
        ) if $error;

        $result_per_experiment{$accession}=$result;
    }

    return %result_per_experiment;
}

sub perform_operation {
    my ($self, $accession, $op) = @_;

    my %results = $self->query_experiment_api($accession, $op);

    return keys %results;
}

# fetch experiment property for one
sub fetch_experiment_property {
    my ($self, $accession, $property) = @_;

    Carp::confess(
        "Error: $accession is not an ArrayExpress accession"
    ) unless $accession =~ /^E-\w{4}-\d+$/;

    my %result = $self->query_experiment_api($accession, "list");
    Carp::confess(
        "Property $property missing from " . Data::Dumper::Dumper($result{$accession})
    ) unless exists $result{$accession}{$property};

    return $result{$accession}{$property};
}

# Fetch a hash of accession => property, for a given list of accessions or for all accessions
# The API supports passing in a list of accessions separated by comma
# It works well enough to query for "all" and then filter out.
sub fetch_property_for_list {
    my ( $self, $property, $expAccs ) = @_;

    my %mappedAccs;
    %mappedAccs = map { $_ => 1 } @$expAccs if $expAccs;

    my %allProperties = $self->query_experiment_api("all","list");

    my %result = ();
    while ( my ($accession, $properties) = each %allProperties ) {
        my %ps = %$properties;
        next if %mappedAccs and not $mappedAccs{ $accession };
        $result{$accession} = $ps{ $property };
    }
    return %result;
}

1;
