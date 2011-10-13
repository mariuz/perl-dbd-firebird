#!/usr/bin/perl
#
#
#   This is a simple insert/fetch test.
#
# 2011-04-05 stefan(s.bv.)
# Adapted to the new test library
#
# 2011-01-23 stefan(s.bv.)
# New version based on testlib and Firebird.dbtest

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
    plan tests => 13;
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
