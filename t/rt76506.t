#!/usr/bin/perl

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
    plan tests => 12;
}

ok($dbh, 'Connected to the database');

# ------- TESTS ------------------------------------------------------------- #

#
#   Find new table name
#
my $table = find_new_table($dbh);
ok($table, qq{Table is '$table'});

#
#   Create a new table
#
my $def =<<"DEF";
CREATE TABLE $table (
    CHAR_TEST   CHAR(10) CHARACTER SET UTF8
)
DEF
ok( $dbh->do($def), qq{CREATE TABLE '$table'} );

#
# Prepare insert
#

my $stmt =<<"END_OF_QUERY";
INSERT INTO $table (CHAR_TEST) VALUES (?)
END_OF_QUERY

ok(my $cursor = $dbh->prepare($stmt), 'PREPARE INSERT');
ok($cursor->execute('TEST'), "INSERT in $table");

ok( my $cursor2 = $dbh->prepare(
        "SELECT CHAR_TEST FROM $table",
        { ib_enable_utf8 => 1 }
    ),
    'PREPARE SELECT'
);
ok($cursor2->execute, 'SELECT');
ok(my $hash_ref = $cursor2->fetchrow_hashref, 'FETCHALL hashref');
is(length $hash_ref->{CHAR_TEST}, 10, 'Match length');
ok($cursor2->finish, 'FINISH');

#
#  Drop the test table
#
ok($dbh->do("DROP TABLE $table"), "DROP TABLE '$table'");

#
#   Finally disconnect.
#
ok($dbh->disconnect(), 'DISCONNECT');
