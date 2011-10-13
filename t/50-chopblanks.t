#!/usr/local/bin/perl
#
#
#   This driver should check whether 'ChopBlanks' works.
#

# 2011-01-29 stefansbv
# New version based on t/testlib.pl and Firebird.dbtest

use strict;
use warnings;

use Test::More;
use DBI;

use lib 't','.';

use TestFirebird;
my $T = TestFirebird->new;

my ( $dbh, $error_str ) = $T->connect_to_database( { ChopBlanks => 1 } );

if ($error_str) {
    BAIL_OUT("Unknown: $error_str!");
}
else {
    plan tests => 38;
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

#
#   Create a new table
#

my $fld_len = 20;               # length of the name field

my $def =<<"DEF";
CREATE TABLE $table (
    id     INTEGER PRIMARY KEY,
    name   CHAR($fld_len)
)
DEF
ok( $dbh->do($def), qq{CREATE TABLE '$table'} );

my @rows = ( [ 1, '' ], [ 2, ' ' ], [ 3, ' a b c ' ] );

foreach my $ref (@rows) {
    my ($id, $name) = @{$ref};

    #- Insert

    my $insert = qq{ INSERT INTO $table (id, name) VALUES (?, ?) };

    ok(my $sth1 = $dbh->prepare($insert), 'PREPARE INSERT');

    ok($sth1->execute($id, $name), "EXECUTE INSERT ($id)");

    #- Select

    my $sele = qq{SELECT id, name FROM $table WHERE id = ?};

    ok(my $sth2 = $dbh->prepare($sele), 'PREPARE SELECT');

    #-- First try to retrieve without chopping blanks.

    $sth2->{ChopBlanks} = 0;

    ok($sth2->execute($id), "EXECUTE SELECT 1 ($id)");

    ok(my $nochop = $sth2->fetchrow_arrayref, 'FETCHrow ARRAYref 1');

    # Right padding name to the length of the field
    my $n_ncb = sprintf("%-*s", $fld_len, $name);

    is($n_ncb, $nochop->[1], 'COMPARE 1');

    ok($sth2->finish, 'FINISH 1');

    #-- Now try to retrieve with chopping blanks.

    $sth2->{ChopBlanks} = 1;

    ok($sth2->execute($id), "EXECUTE SELECT 2 ($id)");

    ( my $n_cb = $name ) =~ s{\s+$}{}g;

    ok(my $chopping = $sth2->fetchrow_arrayref, 'FETCHrow ARRAYref 2');

    is($n_cb, $chopping->[1], 'COMPARE 2');

    ok($sth2->finish, 'FINISH 2');
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
