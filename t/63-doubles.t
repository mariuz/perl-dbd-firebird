#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Deep;
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

ok($dbh, 'Connected to the database');

# DBI->trace(4, "trace.txt");

# ------- TESTS ------------------------------------------------------------- #

#
#   Find a possible new table name
#
my $table = find_new_table($dbh);
ok($table, "TABLE is '$table'");

my @doubles = ( 0.4, 0.6, 0.8, 0.95, 1.0, 1.1, 1.2, 1.15, 3.14159 );

my $def =<<"DEF";
CREATE TABLE $table (
    id integer,
    flt float,
    dbl double precision
)
DEF
ok( $dbh->do($def), qq{CREATE TABLE '$table'} );

#
#   Insert some values
#

my $stmt =<<"END_OF_QUERY";
INSERT INTO $table (
    id, flt, dbl
) VALUES (?, ?, ?)
END_OF_QUERY

ok(my $insert = $dbh->prepare($stmt), 'PREPARE INSERT');

# Insert positive numbers
my $id = 1;
ok($insert->execute( $id++, $_, $_ ), "Inserting $_" ) for @doubles;

# Insert positive numbers
ok($insert->execute( $id++, -$_, -$_ ), "Inserting -$_" ) for @doubles;


#
#   Select the values
#
ok( my $cursor = $dbh->prepare( qq{SELECT id, flt, dbl FROM $table WHERE id=?} ),
    'PREPARE SELECT' );

$id = 0;
for my $n (@doubles) {
    $id++;
    ok($cursor->execute($id), "EXECUTE SELECT $id ($n)");
    ok((my $res = $cursor->fetchrow_arrayref), "FETCHALL arrayref $id ($n)");
    cmp_deeply($res, [ $id, num($n, 1e-6), num($n, 1e-6) ], "row $id ($n)");
}

for my $n (@doubles) {
    $id++;
    ok($cursor->execute($id), "EXECUTE SELECT $id (-$n)");
    ok((my $res = $cursor->fetchrow_arrayref), "FETCHALL arrayref $id (-$n)");
    cmp_deeply($res, [ $id, num(-$n, 1e-6), num(-$n, 1e-6) ], "row $id (-$n)");
}


#
#  Drop the test table
#
$dbh->{AutoCommit} = 1;

ok( $dbh->do("DROP TABLE $table"), "DROP TABLE '$table'" );

#
#   Finally disconnect.
#
ok($dbh->disconnect, 'DISCONNECT');

done_testing;
