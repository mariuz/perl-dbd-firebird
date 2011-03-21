#!/usr/local/bin/perl
#
#   $Id: 40nulls.t 112 2001-04-19 14:56:06Z edpratomo $
#
#   This is a test for correctly handling NULL values.
#

# 2011-01-29 stefansbv
# New version based on t/testlib.pl and Firebird.dbtest

use strict;

BEGIN {
        $|  = 1;
        $^W = 1;
}

use DBI;
use Test::More tests => 12;
#use Test::NoWarnings;

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

ok($dbh, 'DBH ok');

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
#  Drop the test table
#
$dbh->{AutoCommit} = 1;

ok( $dbh->do("DROP TABLE $table"), "DROP TABLE '$table'" );

#
#   Finally disconnect.
#
ok($dbh->disconnect(), 'DISCONNECT');
