#!/usr/local/bin/perl -w
#
#   $Id: 62timeout.t 370 2006-10-25 16:13:18Z edpratomo $
#
#   This is a test for Firebird 2.0's wait timeout for ib_set_tx_param().
#

use strict;
use DBI;
use Test::More tests => 14;

# Make -w happy
$::test_dsn = '';
$::test_user = '';
$::test_password = '';

my $file;
do {
    if (-f ($file = "t/InterBase.dbtest") ||
        -f ($file = "InterBase.dbtest")) 
    {
        eval { require $file };
        if ($@) {
            diag("Cannot execute $file: $@\n");
            exit 0;
        }
    }
};

sub find_new_table {
    my $dbh = shift;
    my $try_name = 'TESTAA';
    my %tables = map { uc($_) => 1 } $dbh->tables;
    while (exists $tables{$try_name}) {
        ++$try_name;
    }
    $try_name;  
}

my $dbh2 = DBI->connect($::test_dsn, $::test_user, $::test_password);
ok($dbh2);

SKIP: {
    my $r = $dbh2->func(
        -lock_resolution => { 'wait' => 2 },
        'ib_set_tx_param');
        
    defined $r or skip "wait timeout is not available", 12;

    my $dbh1 = DBI->connect($::test_dsn, $::test_user, $::test_password);
    ok($dbh1);

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

        diag("2nd tx issues update (${\scalar localtime()})");

        # expected failure after 2 seconds:
        my $r = $dbh2->do($update_stmt, undef, 1);
        isnt($r, defined($r), "timeout (${\scalar localtime()})");

        ok($dbh1->commit, "1st tx committed");
    }

    ok($dbh1->do("DROP TABLE $table"), "DROP TABLE $table");
    ok($dbh1->disconnect);    
}

ok($dbh2->disconnect);

