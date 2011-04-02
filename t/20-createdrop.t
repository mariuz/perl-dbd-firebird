#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use lib 't','.';

require 'tests-setup.pl';

my $dbh = connect_to_database();

if (! defined $dbh) {
    plan skip_all => 'Connection to database failed, cannot continue testing';
}
else {
    plan tests => 5;
}

pass('Connected to the test database');

# ------- TESTS ------------------------------------------------------------- #

#
#   Find a possible new table name
#
my $table = find_new_table($dbh);
diag $table;
ok($table);

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
