#!/usr/bin/perl
#
# Test for the connection first ...
#

use strict;
use warnings;

use Test::More;
use lib 't','.';

use TestFirebird;

plan tests => 2;

pass('clean1');
my $msg1 = drop_test_database();
diag($msg1) if $msg1;

#ok(1);
pass('clean2');
my $msg2 = cleanup();
diag($msg2) if $msg2;

# end
