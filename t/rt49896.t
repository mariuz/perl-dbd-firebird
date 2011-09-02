#!/usr/local/bin/perl -w
#
#   Test cases for DBD-Firebird rt.cpan.org #49896
#   "Varchar fields accept data one char over field length (but memory
#   is corrupted)"
#

use strict;
use warnings;

use Test::More;
use lib 't','.';

require 'tests-setup.pl';

my ($dbh, $error_str) = connect_to_database();

if ($error_str) {
    BAIL_OUT("Unknown: $error_str!");
}

unless ( $dbh->isa('DBI::db') ) {
    plan skip_all => 'Connection to database failed, cannot continue testing';
}
else {
    plan tests => 9;
}

ok($dbh, 'Connected to the database');

# ------- TESTS ------------------------------------------------------------- #

my $table = find_new_table($dbh);
ok($table, qq{Table is '$table'});

my $def =<<"DEF";
CREATE TABLE $table (
    c1 VARCHAR(3)
)
DEF
ok( $dbh->do($def), qq{CREATE TABLE '$table'} );

ok($dbh->do("INSERT INTO $table (c1) VALUES (?)", undef, 'aa'),
   "INSERT string (length < column size) succeeds");

ok($dbh->do("INSERT INTO $table (c1) VALUES (?)", undef, 'aaa'),
   "INSERT string (length == column size) succeeds");

$dbh->{RaiseError} = 0;

ok(! defined $dbh->do("INSERT INTO $table (c1) VALUES (?)", undef, 'aaa!'),
   "INSERT string (length == column size + 1) fails");

ok(! defined $dbh->do("INSERT INTO $table (c1) VALUES (?)", undef, 'aaa!!'),
   "INSERT string (length == column size + 2) fails");

ok($dbh->do("DROP TABLE $table"), "DROP TABLE $table");

ok( $dbh->disconnect );
