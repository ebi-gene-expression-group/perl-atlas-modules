#!/usr/bin/env perl
#
# $Id: Parameter.pm 1973 2008-02-27 18:10:51Z tfrayner $

use strict;
use warnings;

package ArrayExpress::Datafile::Affymetrix::Calvin::Parameter;

# Simple class to store NVT-style parameter values.

use Class::Std;
use Carp;

my %name  : ATTR( :name<name>,  :default<undef> );
my %value : ATTR( :name<value>, :default<undef> );
my %type  : ATTR( :name<type>,  :default<undef> );

1;
