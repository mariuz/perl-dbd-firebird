#!/usr/local/bin/perl -w
#
#   $Id: 62timeout.t 370 2006-10-25 16:13:18Z edpratomo $
#
#   This is a test for Firebird 2.0's wait timeout for ib_set_tx_param().
#

use strict;
use warnings;

use Test::More;
use lib 't','.';

require 'tests-setup.pl';

my ($dbh2, $error_str2) = connect_to_database();

if ($error_str2) {
    BAIL_OUT("Unknown: $error_str2!");
}

unless ( $dbh2->isa('DBI::db') ) {
    plan skip_all => 'Connection to database failed, cannot continue testing';
}
else {
    plan tests => 15;
}

ok($dbh2, 'Connected to the database (2)');

# ------- TESTS ------------------------------------------------------------- #

SKIP: {
    my $r = $dbh2->func(
        -lock_resolution => { 'wait' => 2 },
        'ib_set_tx_param');

    defined $r or skip "wait timeout is not available", 12;


    my ($dbh1, $error_str1) = connect_to_database();
    ok($dbh1, 'Connected to the database (1)');

    my $table = find_new_table($dbh1);
    ok($table);

    {
        my $def = "CREATE TABLE $table(id INTEGER NOT NULL, cnt INTEGER DEFAULT 0 NOT NULL)";
        ok($dbh1->do($def));
    }

    ok(
        !defined(
            $dbh2->func(
                -lock_resolution => { 'no_wait' => 2 },
                'ib_set_tx_param'
            )
        ),
        "try invalid lock resolution. " . $dbh2->errstr
    );

    is($dbh1->{AutoCommit}, 1, "1st tx AutoCommit == 1");

    {
        local $dbh2->{PrintError} = 0;

        my $stmt = "INSERT INTO $table(id) VALUES(?)";
        my $update_stmt = "UPDATE $table SET cnt = cnt+1 WHERE id = ?";

        ok($dbh1->do($stmt, undef, 1));

        # from now, commit manually
        local $dbh1->{AutoCommit} = 0;
        isnt($dbh1->{AutoCommit}, 1, "1st tx AutoCommit == 0");

        ok($dbh1->do($update_stmt, undef, 1), "1st tx issues update");

        pass("2nd tx issues update (${\scalar localtime()})");

        # expected failure after 2 seconds:
        eval {
        my $r = $dbh2->do($update_stmt, undef, 1);
        };
        ok($@, "Timeout (${\scalar localtime()})");

        ok($dbh1->commit, "1st tx committed");
    }

    ok($dbh2->disconnect);

    ok($dbh1->do("DROP TABLE $table"), "DROP TABLE $table");
    ok($dbh1->disconnect);
} # - SKIP {}
