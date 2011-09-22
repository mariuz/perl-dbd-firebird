#!/usr/bin/perl -w
#
#
#   This is a test for ib_set_tx_param() private method.
#
# 2011-01-29 stefan(s. bv)
# New version based on t/testlib.pl and Firebird.dbtest
# Note: set_tx_param() is obsoleted by ib_set_tx_param().
#
# Transaction behavior default parameter values:
#   Access mode:        read_write
#   Isolation level:    snapshot
#   Lock resolution:    wait

use strict;
use warnings;

use Test::More;
use DBI;

use lib 't','.';

require 'tests-setup.pl';

my ( $dbh1, $error_str1 ) =
  connect_to_database( { ChopBlanks => 1 } );

if ($error_str1) {
    BAIL_OUT("Unknown: $error_str1!");
}
else {
    plan tests => 22;
}

unless ( $dbh1->isa('DBI::db') ) {
    plan skip_all => 'Connection to database failed, cannot continue testing';
}

ok($dbh1, 'Connected to the database (1)');

my ( $dbh2, $error_str2 ) =
  connect_to_database( { ChopBlanks => 1 } );

ok($dbh2, 'Connected to the database (2)');

# DBI->trace(4, "trace.txt");

# ------- TESTS ------------------------------------------------------------- #

#
#   Find a possible new table name
#
my $table = find_new_table($dbh1);
ok($table, "TABLE is '$table'");

#
#   Create a new table
#

my $def =<<"DEF";
CREATE TABLE $table (
    id     INTEGER PRIMARY KEY,
    name   VARCHAR(20)
)
DEF
ok( $dbh1->do($def), qq{CREATE TABLE '$table'} );

#
#   Changes transaction params
#
ok(
    $dbh1->func(
        -access_mode     => 'read_write',
        -isolation_level => 'read_committed',
        -lock_resolution => 'wait',
        'ib_set_tx_param'
    ),
    'SET tx param for dbh 1'
);

ok(
    $dbh2->func(
        -access_mode     => 'read_only',
        -lock_resolution => 'no_wait',
        'ib_set_tx_param'
    ),
    'SET tx param for dbh 2'
);

SCOPE: {

    local $dbh1->{AutoCommit} = 0;
    local $dbh2->{PrintError} = 0;

    my $insert_stmt = qq{ INSERT INTO $table VALUES(?, 'Yustina') };
    my $select_stmt = qq{ SELECT * FROM $table WHERE 1 = 0 };

    ok(my $sth2 = $dbh2->prepare($select_stmt), 'PREPARE SELECT');

    ok($dbh1->do($insert_stmt, undef, 1), 'DO INSERT (1)');

    #- Expected failure ( -access_mode => 'read_only' )

    eval {
        $dbh2->do($insert_stmt, undef, 2);
    };
    ok($@, "DO INSERT (2) Expected failure ('read_only' )");

    #- Reading should be ok here

    ok($sth2->execute, 'EXECUTE sth 2');

    ok($sth2->finish, 'FINISH sth 2');

    #- Committing the first trans

    ok($dbh1->commit, 'COMMIT dbh 1');

    ok(
        $dbh1->func(
            -access_mode     => 'read_write',
            -isolation_level => 'read_committed',
            -lock_resolution => 'wait',
            -reserving       => {
                $table => {
                    lock   => 'write',
                    access => 'protected',
                },
            },
            'ib_set_tx_param'
        ),
        'CHANGE tx param for dbh 1'
    );

    ok(
        $dbh2->func(
            -lock_resolution => 'no_wait',
            'ib_set_tx_param'
        ),
        'CHANGE tx param for dbh 2'
    );

    ok($dbh1->do($insert_stmt, undef, 3), 'DO INSERT (2)');

    #- Expected failure ( -lock_resolution => 'no_wait' )

    eval {
        $dbh2->do($insert_stmt, undef, 4);
    };
    ok($@, "DO INSERT (3) Expected failure ('no_wait')");

    # Committing the first trans
    ok($dbh1->commit, 'COMMIT dbh 1');
}

#
#  Drop the test table
#

isa_ok( $dbh1, 'DBI::db' );
isa_ok( $dbh2, 'DBI::db' );

#
#   Disconnect 2
ok($dbh2->disconnect, 'DISCONNECT 2');

# AutoCommit is on
ok( $dbh1->do("DROP TABLE $table"), "DROP TABLE '$table'" );

#
#   Finally disconnect 1
#
ok($dbh1->disconnect, 'DISCONNECT 1');
