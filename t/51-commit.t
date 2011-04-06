#!/usr/local/bin/perl
#
#   $Id: 50commit.t 112 2001-04-19 14:56:06Z edpratomo $
#
#   This is testing the transaction support.
#
# 2011-01-23 stefan(s.bv.)
# New version based on t/testlib.pl and Firebird.dbtest

use strict;
use warnings;

use Test::More;
use DBI;

use lib 't','.';

require 'tests-setup.pl';

my ( $dbh, $error_str ) =
  connect_to_database( { ChopBlanks => 1, AutoCommit => 1 } );

if ($error_str) {
    BAIL_OUT("Unknown: $error_str!");
}
else {
    plan tests => 30;
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

use vars qw($gotWarning);
sub CatchWarning ($) {
    $gotWarning = 1;
}

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

ok($dbh->{AutoCommit}, 'AutoCommit is on');

#- Turn AutoCommit off
$dbh->{AutoCommit} = 0;

ok(! $dbh->{AutoCommit}, 'AutoCommit is off');

#-- Check rollback

ok($dbh->do("INSERT INTO $table VALUES (1, 'Jochen')"), 'INSERT 1');

is(NumRows($dbh, $table), 1, 'CHECK rows');

ok($dbh->rollback, 'ROLLBACK');

is(NumRows($dbh, $table), 0, 'CHECK rows');

#-- Check commit

ok($dbh->do("DELETE FROM $table WHERE id = 1"), 'DELETE id=1');

is(NumRows($dbh, $table), 0, 'CHECK rows');

ok($dbh->commit, 'COMMIT');

is(NumRows($dbh, $table), 0, 'CHECK rows');

#-- Check auto rollback after disconnect

ok($dbh->do("INSERT INTO $table VALUES (1, 'Jochen')"), 'INSERT 1');

is(NumRows($dbh, $table), 1, 'CHECK rows');

ok($dbh->disconnect, 'DISCONNECT for auto rollback');

#--- Reconnect

( $dbh, $error_str ) = connect_to_database( { ChopBlanks => 1 } );

ok($dbh, 'reConnected to the database');

is(NumRows($dbh, $table), 0, 'CHECK rows');

#--- Check whether AutoCommit is on again

ok($dbh->{AutoCommit}, 'AutoCommit is on');

#-- Check whether AutoCommit mode works.

ok($dbh->do("INSERT INTO $table VALUES (1, 'Jochen')"), 'INSERT 1');

is(NumRows($dbh, $table), 1, 'CHECK rows');

ok($dbh->disconnect, 'DISCONNECT for auto commit');

#--- Reconnect

( $dbh, $error_str ) = connect_to_database( { ChopBlanks => 1 } );

ok($dbh, 'reConnected to the database');

is(NumRows($dbh, $table), 1, 'CHECK rows');

#-- Check whether commit issues a warning in AutoCommit mode

ok($dbh->do("INSERT INTO $table VALUES (2, 'Tim')"), 'INSERT 2');

my $result;
$@ = '';
$SIG{__WARN__} = \&CatchWarning;
$gotWarning = 0;
eval { $result = $dbh->commit; };
$SIG{__WARN__} = 'DEFAULT';

ok($gotWarning, 'GOT WARNING');

#   Check whether rollback issues a warning in AutoCommit mode
#   We accept error messages as being legal, because the DBI
#   requirement of just issueing a warning seems scary.

ok($dbh->do("INSERT INTO $table VALUES (3, 'Alligator')"), 'INSERT 3');

$@ = '';
$SIG{__WARN__} = \&CatchWarning;
$gotWarning = 0;
eval { $result = $dbh->rollback; };
$SIG{__WARN__} = 'DEFAULT';

ok($gotWarning, 'GOT WARNING');

#
#  Drop the test table
#
$dbh->{AutoCommit} = 1;

ok( $dbh->do("DROP TABLE $table"), "DROP TABLE '$table'" );

#
#   Finally disconnect.
#
ok($dbh->disconnect, 'DISCONNECT');

sub NumRows {
    my($dbh, $table) = @_;

    my $sth = $dbh->prepare( qq{SELECT * FROM $table} );

    $sth->execute;

    my $got = 0;
    while ($sth->fetchrow_arrayref) {
        $got++;
    }

    return $got;
}
