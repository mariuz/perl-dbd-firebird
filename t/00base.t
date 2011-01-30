# Test that everything compiles, so the rest of the test suite can
# load modules without having to check if it worked.
#
# 2011-01-29 stefan(s.bv.)
# Stolen from DBD::SQLite ;)
#

use strict;
BEGIN {
    $|  = 1;
    $^W = 1;
}

use Test::More tests => 2;

use_ok('DBI');

use_ok('DBD::InterBase');

diag("\$DBI::VERSION=$DBI::VERSION");
