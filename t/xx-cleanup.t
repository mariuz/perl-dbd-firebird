#!/usr/bin/perl
#
# Test for the connection first ...
#

use strict;
use warnings;

use Test::More;
use lib 't','.';

require 'tests-setup.pl';

plan tests => 2;

ok( drop_test_database() );

ok( cleanup() );

# end
