#!/usr/local/bin/perl
#
#   $Id: 40numrows.t 112 2001-04-19 14:56:06Z edpratomo $
#
#   This tests, whether the number of rows can be retrieved.
#

# 2011-01-30 stefansbv
# New version based on t/testlib.pl and InterBase.dbtest

# Quote from the DBI POD:
#
# For "SELECT" statements, it is generally not possible to know
# how many rows will be returned except by fetching them all. Some
# drivers will return the number of rows the application has
# fetched so far, but others may return -1 until all rows have
# been fetched. So use of the "rows" method or $DBI::rows with
# "SELECT" statements is not recommended.
#
# Of course, I read the docs after converting the test :)
# It's possible that I did't understand the purpose of the test,
# so I leave it here for now.

use strict;

BEGIN {
        $|  = 1;
        $^W = 1;
}

use DBI;
use Test::More;
#use Test::NoWarnings;

plan skip_all => q{"rows" method with "SELECT" not recommended};

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

#   Connect to the database
my $dbh =
  DBI->connect( $::test_dsn, $::test_user, $::test_password,
    { ChopBlanks => 1 } );

# DBI->trace(4, "trace.txt");

# ------- TESTS ------------------------------------------------------------- #

ok($dbh, 'dbh OK');

#
#   Find a possible new table name
#
my $table = find_new_table($dbh);
ok($table, "TABLE is '$table'");

#
#   Create a new table
#

my $def =<<"DEF";
CREATE TABLE $table (
    id     INTEGER PRIMARY KEY,
    name   CHAR(64)
)
DEF
ok( $dbh->do($def), qq{CREATE TABLE '$table'} );

#
#   This section should exercise the sth->rows
#   method by preparing a statement, then finding the
#   number of rows within it.
#   Prior to execution, that should fail. After execution, the
#   number of rows affected by the statement will be returned.
#

my $insert = qq{ INSERT INTO $table (id, name) VALUES (?, ?) };
ok(my $sth1 = $dbh->prepare($insert), 'PREPARE INSERT');
ok($sth1->execute(1, 'Alligator Descartes'), "EXECUTE INSERT (1)");

my $sele = qq{SELECT id, name FROM $table WHERE id = ?};
ok(my $sth2 = $dbh->prepare($sele), 'PREPARE SELECT');

ok($sth2->execute(1), "EXECUTE SELECT 1 (1)");

is($sth2->rows, 1);

# Test($state or ($numrows = TrueRows($cursor)) == 1)
# or ErrMsgF("Expected to fetch 1 rows, got %s.\n", $numrows);

ok($sth2->finish);

ok($sth1->execute(2, 'Jochen Wiedmann'), "EXECUTE INSERT (2)");

#-

my $sele2 = qq{SELECT id, name FROM $table WHERE id >= ?};
ok(my $sth3 = $dbh->prepare($sele2), 'PREPARE SELECT2');

ok($sth3->execute(1), "EXECUTE SELECT 1 (>=1)");

is($sth3->rows, 2);

# Test($state or ($numrows = TrueRows($cursor)) == 2)
# or ErrMsgF("Expected to fetch 2 rows, got %s.\n", $numrows);

ok($sth3->finish);

ok($sth1->execute(3, 'Tim Bunce'), "EXECUTE INSERT (3)");

ok($sth3->execute(2), "EXECUTE SELECT 1 (>=2)");

is($sth3->rows, 2);

# Test($state or ($numrows = TrueRows($cursor)) == 2)
# or ErrMsgF("Expected to fetch 2 rows, got %s.\n", $numrows);

ok($sth3->finish);

#
#  Drop the test table
#
$dbh->{AutoCommit} = 1;

ok( $dbh->do("DROP TABLE $table"), "DROP TABLE '$table'" );

#
#   Finally disconnect.
#
ok($dbh->disconnect, 'DISCONNECT');

sub TrueRows($) {
    my ($sth) = @_;
    my $count = 0;
    while ($sth->fetchrow_arrayref) {
    ++$count;
    }
    $count;
}
