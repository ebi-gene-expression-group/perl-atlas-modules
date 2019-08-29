# $Id: Config.pm 4743 2008-06-04 15:53:58Z rayner $

package EBI::FGPT::Converter::GEO::Config;

use strict;
use warnings;

use Carp;
use File::Spec;
use Config::Tiny;

use base qw(Exporter);
our @EXPORT_OK = qw(get_config init_config);

my $CONFIG_BASE;
my $CONFIG;

sub get_config {

    my ( $option ) = @_;

    unless (defined $option) {
	croak("Error: get_config() needs an option name to return its value.")
    }

    parse_config() unless $CONFIG;

    unless ( defined $CONFIG->{ $option } ) {
	croak("Error: Config option $option not recognised.");
    }

    return $CONFIG->{ $option };
}

sub init_config {

    my ( $caller_filename ) = @_;

    my $caller_path = File::Spec->rel2abs( $caller_filename );
    my @dir_array   = File::Spec->splitpath( $caller_path );
    $CONFIG_BASE    = File::Spec->catpath( @dir_array[ 0, 1 ] );

    parse_config();

    return;
}

sub parse_config {

    my $sectionname = 'GEOImport';

    unless ( defined $CONFIG_BASE ) {
	confess("Error: CONFIG_BASE not set. You must call "
	      . __PACKAGE__
	      . "::init_config with the name of your script (e.g. init_config(__FILE__))");
    }
    my $file = File::Spec->catfile( $CONFIG_BASE, 'geo_import_config.txt' );
    unless ( -r $file ) {
	die("Error: Configuration file $file is absent or unreadable. "
	  . "Please make sure you have edited the config file (included "
	  . "in the downloaded package) appropriately, and copied it to this location.\n");
    }

    my $parsed = Config::Tiny->read( $file );

    # Quote spaces and any other odd characters.
    foreach my $key ( keys %{ $parsed->{$sectionname} } ) {
	my $value = $parsed->{$sectionname}{$key};
	$value =~ s/([ ])/\\$1/g;
	$parsed->{$sectionname}{$key} = $value;
    }

    # We just use the "GEOImport" section of the INI file.
    $CONFIG = $parsed->{$sectionname};

    return;

}

1;
