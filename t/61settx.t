#!/usr/bin/perl -w
#
#   $Id: 61settx.t 229 2002-04-05 03:12:51Z edpratomo $
#
#   This is a test for ib_set_tx_param() private method.
#
# 2011-01-29 stefan(s. bv)
# New version based on t/testlib.pl and InterBase.dbtest
# Note: set_tx_param() is obsoleted by ib_set_tx_param().

use strict;

BEGIN {
    $|  = 1;
    $^W = 1;
}

use DBI;
use Test::More tests => 23;

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

#   Connect to the database 1
my $dbh1 =
  DBI->connect( $::test_dsn, $::test_user, $::test_password,
    { ChopBlanks => 1 } );

ok($dbh1, 'dbh1 OK');

#   Connect to the database 2
my $dbh2 =
  DBI->connect( $::test_dsn, $::test_user, $::test_password,
    { ChopBlanks => 1 } );

ok($dbh2, 'dbh2 OK');

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
        # -isolation_level => 'snapshot_table_stability',
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

    #- Expected failure

    ok(! $dbh2->do($insert_stmt, undef, 2), 'DO INSERT (2)');

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

            # -isolation_level => 'snapshot_table_stability',
            -lock_resolution => 'no_wait',
            'ib_set_tx_param'
        ),
        'CHANGE tx param for dbh 2'
    );

    # stefan: This should fail?
    ok($dbh1->do($insert_stmt, undef, 2), 'DO INSERT (2)');

    ok($dbh2->do($insert_stmt, undef, 3), 'DO INSERT (3)');

    # Committing the first trans
    ok($dbh1->commit, 'COMMIT dbh 1');
}

#
#  Drop the test table
#

isa_ok( $dbh1, 'DBI::db' );
isa_ok( $dbh2, 'DBI::db' );

$dbh1->{AutoCommit} = 1;
ok($dbh1->{AutoCommit}, 'AutoCommit is on');

# stefan: Why does that fail?
ok( $dbh1->do("DROP TABLE $table"), "DROP TABLE '$table'" );

#
#   Finally disconnect.
#
ok($dbh1->disconnect, 'DISCONNECT 1');
ok($dbh2->disconnect, 'DISCONNECT 2');
