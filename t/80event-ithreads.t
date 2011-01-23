#!/usr/local/bin/perl -w
#
#   $Id: 80event-ithreads.t 372 2006-10-25 18:17:44Z edpratomo $
#

use strict;
use Test::More tests => 22;
use DBI;
use Config;

#DBI->trace(4, "/dev/shm/trace.log");

# test cases:
# event creation, register callback, cancel callback
# event creation, fork / thread (except win32), destruction
# event creation, fork / thread (except win32), wait event, destruction
# event creation, fork / thread (except win32), register callback, destruction

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

my $dbh = DBI->connect($::test_dsn, $::test_user, $::test_password);
ok($dbh);

my $table = find_new_table($dbh);
ok($table);

# create required test table and triggers
{
    my @ddl = (<<"DDL", <<"DDL", <<"DDL");
CREATE TABLE $table (
    id    INTEGER NOT NULL,
    title VARCHAR(255) NOT NULL
);
DDL

CREATE TRIGGER ins_${table}_trig FOR $table
    AFTER INSERT POSITION 0
    AS BEGIN
        POST_EVENT 'foo_inserted';
    END
DDL

CREATE TRIGGER del_${table}_trig FOR $table
    AFTER DELETE POSITION 0
    AS BEGIN
        POST_EVENT 'foo_deleted';
    END
DDL

    ok($dbh->do($_)) foreach @ddl; # 3 times
}

my $evh = $dbh->func('foo_inserted', 'foo_deleted', 'ib_init_event');
ok($evh);

ok($dbh->func($evh, sub { print "about to cancel"; 1 }, 'ib_register_callback'));
ok($dbh->func($evh, 'ib_cancel_callback'));

my $worker = sub {
    my $table = shift;
    my $dbh = DBI->connect(@_, {AutoCommit => 1 }) or return 0;
    for (1..5) {
        $dbh->do(qq{INSERT INTO $table VALUES($_, 'bar')});
        sleep 1;
    }
    $dbh->do(qq{DELETE FROM $table});
    $dbh->disconnect;
};

# try ithreads
{
    my $how_many = 10;
SKIP: {
    skip "this $^O perl $] is not configured to support iThreads", $how_many if (!$Config{useithreads} || $] < 5.008);
    skip "known problems under MSWin32 ActivePerl's iThreads", $how_many if $Config{osname} eq 'MSWin32';
    skip "Perl version is older than 5.8.8", $how_many if $^V and $^V lt v5.8.8;
    eval { require threads };
    skip "unable to use threads;", $how_many if $@;

    %::CNT = ();

    ok($dbh->func($evh, 
        sub { 
            my $posted_events = shift;
            while (my ($k, $v) = each %$posted_events) {
                $::CNT{$k} += $v;
            }
            1;
        }, 
        'ib_register_callback'
    ));

    my $t = threads->create($worker, $table, $::test_dsn, $::test_user, $::test_password);
    ok($t);
    ok($t->join);
    
    while (not exists $::CNT{'foo_deleted'}) {}
    ok($dbh->func($evh, 'ib_cancel_callback'));
    is($::CNT{'foo_inserted'}, 5);
    is($::CNT{'foo_deleted'}, 5);

    # test ib_wait_event
    %::CNT = ();
    $t = threads->create($worker, $table, $::test_dsn, $::test_user, $::test_password);
    ok($t, "create thread");
    for (1..6) {
        my $posted_events = $dbh->func($evh, 'ib_wait_event');
        while (my ($k, $v) = each %$posted_events) {
            $::CNT{$k} += $v;
        }
    }
    ok($t->join);
    is($::CNT{'foo_inserted'}, 5);
    is($::CNT{'foo_deleted'}, 5);
}}

ok($dbh->do(qq(DROP TRIGGER ins_${table}_trig)));
ok($dbh->do(qq(DROP TRIGGER del_${table}_trig)));
ok($dbh->do(qq(DROP TABLE $table)));
ok($dbh->disconnect);

