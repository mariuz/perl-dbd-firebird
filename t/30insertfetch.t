#!/usr/bin/perl
#
#   $Id: 30insertfetch.t 326 2005-01-13 23:32:29Z danielritz $
#
#   This is a simple insert/fetch test.
#

# 2011-01-23 stefan(s.bv.)
# New version based on testlib and InterBase.dbtest

use strict;
use warnings;
use DBI;
use Test::More tests => 13;

#
#   Make -w happy
#
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
ok($table);

#
#   Create a new table
#
my $def =<<"DEF";
CREATE TABLE $table (
    id     INTEGER PRIMARY KEY,
    name   VARCHAR(20)
)
DEF
ok( $dbh->do($def), qq{CREATE TABLE '$table'} );

#
#   Insert a row into the test table.......
#
ok( $dbh->do(qq{INSERT INTO $table VALUES (1, 'Alligator Descartes')}) );

#
# ... and delete it ...
#
ok($dbh->do("DELETE FROM $table WHERE id = 1"), "DELETE FROM $table");

#
#   Now, try SELECT'ing the row out. This should fail.
#
ok(my $cursor = $dbh->prepare("SELECT * FROM $table WHERE id = 1"), 'SELECT');
ok($cursor->execute);

my $row = $cursor->fetchrow_arrayref;
$cursor->finish;

#
#   Insert two new rows
#
ok( $dbh->do("INSERT INTO $table VALUES (1, 'Edwin Pratomo')") );
ok( $dbh->do("INSERT INTO $table VALUES (2, 'Daniel Ritz')") );

#
#   Try selectrow_array
#
my @array = $dbh->selectrow_array(qq{SELECT * FROM $table WHERE id = 1});
is( scalar @array, 2, q{TEST selectrow_array} );

#
#   Try fetchall_hashref
#
my $hash = $dbh->selectall_hashref( qq{SELECT * FROM $table}, 'ID' );
is( scalar keys %{$hash}, 2, q{TEST selectall_hashref} );

#
#   ... and drop it.
#
ok($dbh->do("DROP TABLE $table"), "DROP TABLE '$table'");

#
#   Finally disconnect.
#
ok($dbh->disconnect());
