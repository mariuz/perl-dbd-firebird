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

use Test::More tests => 7;

use_ok('DBI');

use_ok('DBD::Firebird');
use_ok('DBD::Firebird::GetInfo');
use_ok('DBD::Firebird::TableInfo');
use_ok('DBD::Firebird::TableInfo::Basic');
use_ok('DBD::Firebird::TableInfo::Firebird21');
use_ok('DBD::Firebird::TypeInfo');

# diag("\$DBI::VERSION=$DBI::VERSION");
