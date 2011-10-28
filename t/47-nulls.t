#!/usr/local/bin/perl
#
#
#   This is a test for correctly handling NULL values.
#

# 2011-01-29 stefansbv
# New version based on t/testlib.pl and Firebird.dbtest

use strict;
use warnings;

use Test::More;
use Test::Exception;
use DBI;

use lib 't','.';

use TestFirebird;
my $T = TestFirebird->new;

my ( $dbh, $error_str ) = $T->connect_to_database( { ChopBlanks => 1 } );

if ($error_str) {
    BAIL_OUT("Unknown: $error_str!");
}

unless ( $dbh->isa('DBI::db') ) {
    plan skip_all => 'Connection to database failed, cannot continue testing';
}
else {
    plan tests => 14;
}

ok($dbh, 'Connected to the database');

# DBI->trace(4, "trace.txt");

# ------- TESTS ------------------------------------------------------------- #

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
    id    INTEGER,
    name  CHAR(64)
)
DEF

ok( $dbh->do($def), qq{CREATE TABLE '$table'} );

#
#   Test whether or not a field containing a NULL is returned correctly
#   as undef, or something much more bizarre
#
my $sql_insert = qq{INSERT INTO $table VALUES ( NULL, 'NULL-valued id' )};
ok( $dbh->do($sql_insert), 'DO INSERT' );

my $sql_sele = qq{SELECT * FROM $table WHERE id IS NULL};
ok( my $cursor = $dbh->prepare($sql_sele), 'PREPARE SELECT' );
ok($cursor->execute, 'EXECUTE SELECT');

ok(my $rv = $cursor->fetchrow_arrayref, 'FETCHROW');

is($$rv[0], undef, 'UNDEFINED id');
is($$rv[1], 'NULL-valued id', 'DEFINED name');

ok($cursor->finish, 'FINISH');

#
# Test whether inserting NULL in a non-null field fails
#

my $table2 = find_new_table($dbh);
$dbh->do("CREATE table $table2(id integer not null)");
my $sth = $dbh->prepare("INSERT INTO $table2 VALUES(?)");

throws_ok { $sth->execute(undef) }
qr/^DBD::Firebird::st execute failed: You have not provided a value for non-nullable parameter #0\./;

#
#  Drop the test table
#
$dbh->{AutoCommit} = 1;

ok( $dbh->do("DROP TABLE $table"), "DROP TABLE '$table'" );
ok( $dbh->do("DROP TABLE $table2"), "DROP TABLE '$table2'" );

#
#   Finally disconnect.
#
ok($dbh->disconnect(), 'DISCONNECT');
