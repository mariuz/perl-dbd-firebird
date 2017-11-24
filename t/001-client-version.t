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

use Test::More tests => 4;

use DBD::Firebird;

can_ok( 'DBD::Firebird' => 'fb_api_ver' );
can_ok( 'DBD::Firebird' => 'client_major_version' );
can_ok( 'DBD::Firebird' => 'client_minor_version' );
can_ok( 'DBD::Firebird' => 'client_version' );

note( "Firebird API version is " . DBD::Firebird->fb_api_ver );
note( "Firebird client major version is " . DBD::Firebird->client_major_version );
note( "Firebird client minor version is " . DBD::Firebird->client_minor_version );
note( "Firebird client version is " . DBD::Firebird->client_version );

# diag("\$DBI::VERSION=$DBI::VERSION");
