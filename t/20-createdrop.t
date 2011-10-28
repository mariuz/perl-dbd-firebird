#!/usr/bin/perl
#
#
# 2011-04-05 stefan(s.bv.)
# Adapted to the new test library
#
# 2011-01-21 stefan(s.bv.)
# New version based on t/testlib.pl and Firebird.dbtest

use strict;
use warnings;

use Test::More;
use lib 't','.';

use TestFirebird;
my $T = TestFirebird->new;

my ($dbh, $error_str) = $T->connect_to_database;

if ($error_str) {
    BAIL_OUT("Unknown: $error_str!");
}

unless ( $dbh->isa('DBI::db') ) {
    plan skip_all => 'Connection to database failed, cannot continue testing';
}
else {
    plan tests => 5;
}

ok($dbh, 'Connected to the database');

# ------- TESTS ------------------------------------------------------------- #

#
#   Find a possible new table name
#
my $table = find_new_table($dbh);
ok($table, qq{Table is '$table'});

#
#   Create a new table
#
my $def =<<"DEF";
CREATE TABLE $table (
    id     INTEGER NOT NULL PRIMARY KEY,
    name CHAR(64) CHARACTER SET ISO8859_1
)
DEF
ok( $dbh->do($def), qq{CREATE TABLE '$table'} );

#
#   ... and drop it.
#
ok( $dbh->do(qq{DROP TABLE $table}), qq{DROP TABLE '$table'} );

#
#   Finally disconnect.
#
ok( $dbh->disconnect );
