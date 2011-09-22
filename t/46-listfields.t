#!/usr/local/bin/perl
#
#
#   This is a test for statement attributes being present appropriately.
#

# 2011-01-29 stefansbv
# New version based on t/testlib.pl and Firebird.dbtest

use strict;
use warnings;

use Test::More;
use DBI qw(:sql_types);

use lib 't','.';

require 'tests-setup.pl';

my ( $dbh, $error_str ) = connect_to_database( { ChopBlanks => 1 } );

if ($error_str) {
    BAIL_OUT("Unknown: $error_str!");
}

unless ( $dbh->isa('DBI::db') ) {
    plan skip_all => 'Connection to database failed, cannot continue testing';
}
else {
    plan tests => 15;
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
    id   INTEGER PRIMARY KEY,
    name VARCHAR(64)
)
DEF
ok($dbh->do($def), "CREATE TABLE $table");

my $sql_sele = qq{SELECT * FROM $table};
ok( my $cursor = $dbh->prepare($sql_sele), 'PREPARE SELECT' );
ok($cursor->execute, 'EXECUTE SELECT');

my ($types, $names, $fields, $nullable) = @{$cursor}{qw(TYPE NAME NUM_OF_FIELDS NULLABLE)};

is( $fields,     2,      'CHECK FIELDS NUMBER' );       # 2 fields
is( $names->[0], 'ID',   'CHECK NAME for field 1' );    # id
is( $names->[1], 'NAME', 'CHECK NAME for field 1' );    # name

is( $nullable->[0], q{}, 'CHECK NULLABLE for field 1' );    # id
is( $nullable->[1], 1,   'CHECK NULLABLE for field 2' );    # name

is( $types->[0], SQL_INTEGER, 'CHECK TYPE for field 1' );    # id
is( $types->[1], SQL_VARCHAR, 'CHECK TYPE for field 2' );    # name

ok($cursor->finish, 'FINISH');

#
#  Drop the test table
#
ok($dbh->do("DROP TABLE $table"), "DROP TABLE '$table'");

#
#   Finally disconnect.
#
ok($dbh->disconnect, 'DISCONNECT');
