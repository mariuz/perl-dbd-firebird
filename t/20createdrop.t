#!/usr/bin/perl
#
#   $Id: 20createdrop.t 112 2001-04-19 14:56:06Z edpratomo $
#

# 2011-01-21 stefan(s.bv.)
# New version based on t/testlib.pl and InterBase.dbtest

use strict;
use warnings;

use DBI;
use Test::More tests => 5;

# Make -w happy
$::test_dsn = '';
$::test_user = '';
$::test_password = '';

for my $file ('t/testlib.pl', 'testlib.pl') {
    next unless -f $file;
    eval { require $file };
    BAIL_OUT("Cannot load testlib.pl\n") if $@;
    last;
}

# ------- TESTS ------------------------------------------------------------- #

#   Connect to the database
my $dbh = DBI->connect($::test_dsn, $::test_user, $::test_password);
ok($dbh);

#
#   Find a possible new table name
#
my $table = find_new_table($dbh);
#diag $table;
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
