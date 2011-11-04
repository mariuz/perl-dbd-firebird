#!/usr/local/bin/perl -w
#
#

use strict;
use warnings;

use DBI;
use Config;
use POSIX qw(:signal_h);
use Test::More;
use lib 't','.';

plan skip_all => 'DBD_FIREBIRD_TEST_SKIP_EVENTS found in the environment'
    if $ENV{DBD_FIREBIRD_TEST_SKIP_EVENTS};

use TestFirebird;
my $T = TestFirebird->new;

my ($dbh, $error_str) = $T->connect_to_database();

if ($error_str) {
    BAIL_OUT("Unknown: $error_str!");
}

unless ( $dbh->isa('DBI::db') ) {
    plan skip_all => 'Connection to database failed, cannot continue testing';
}
else {
    plan tests => 17;
}

ok($dbh, 'Connected to the database');

my $table = find_new_table($dbh);
ok($table, qq{Table is '$table'});

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

# detect SIGNAL availability
my $sig_ok = grep { /HUP$/ } split(/ /, $Config{sig_name});

$dbh->disconnect if $dbh->{ib_embedded};

# try fork
{
    my $how_many = 8;
SKIP: {
    skip "known problems under MSWin32 ActivePerl's emulated fork()", $how_many if $Config{osname} eq 'MSWin32';
    skip "SIGHUP is not avalailable", $how_many unless $sig_ok;
    my $pid = fork;
    skip "failed to fork", $how_many unless defined $pid;

    if ($pid) {
        %::CNT = ();

        my ($dbh, $error_str) = $T->connect_to_database();
        ok($dbh, "Connected: $pid");

        my $evh = $dbh->func('foo_inserted', 'foo_deleted', 'ib_init_event');
        ok($evh);

        ok($dbh->func($evh,
            sub {
                my $posted_events = shift;
                while (my ($k, $v) = each %$posted_events) {
                    #diag "Got event $k";
                    $::CNT{$k} += $v;
                }
                1;
            },
            'ib_register_callback'
        ), "Event callback registered");

        kill SIGHUP => $pid;
        is(wait, $pid, "Kid finished");
        BAIL_OUT("Kid exit status: $?") unless $? == 0;
        # then wait until foo_deleted gets posted
        while (not exists $::CNT{'foo_deleted'}) {}
        ok($dbh->func($evh, 'ib_cancel_callback'));
        ok($dbh->disconnect);
        is($::CNT{'foo_inserted'}, 5, "compare number of inserts");
        is($::CNT{'foo_deleted'}, 5, "compare number of deleted rows");
    } else {
        $dbh->{InactiveDestroy} = 1;
        $|++;
        $SIG{HUP} = sub {
            #diag("kid $$ gets sighup\n");
            $::SLEEP = 0;
        };
        $::SLEEP = 1;
        while ($::SLEEP) {}

        #diag "Kid about to connect";
        my ($dbh, $error_str) = $T->connect_to_database({AutoCommit => 1 });
        if ($error_str) {
            #diag "Kid connection error: $error_str";
            die;
        }
        #diag "Kid connected";
        for (1..5) {
            #diag "Kid about to insert";
            $dbh->do(qq{INSERT INTO $table VALUES($_, 'bar')});
            #diag "Inserted a row";
        }
        $dbh->do(qq{DELETE FROM $table});
        #diag "Deleted all rows";
        $dbh->disconnect;
        #diag "Kid exiting";
        exit;
    }
}}

($dbh, $error_str) = $T->connect_to_database() if $dbh->{ib_embedded};

ok($dbh->do(qq(DROP TRIGGER ins_${table}_trig)));
ok($dbh->do(qq(DROP TRIGGER del_${table}_trig)));
ok($dbh->do(qq(DROP TABLE $table)), "DROP TABLE $table");
ok($dbh->disconnect);

