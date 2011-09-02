#!/usr/local/bin/perl -w
#
#   $Id: 81event-fork.t 397 2008-01-08 05:58:49Z edpratomo $
#

use strict;
use warnings;

use DBI;
use Config;
use POSIX qw(:signal_h);
use Test::More;
use lib 't','.';

require 'tests-setup.pl';

my ($dbh, $error_str) = connect_to_database();

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

$dbh->{InactiveDestroy} = 1;

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

        my ($dbh, $error_str) = connect_to_database();
        ok($dbh, "Connected: $pid");

        my $evh = $dbh->func('foo_inserted', 'foo_deleted', 'ib_init_event');
        ok($evh);

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

        kill SIGHUP => $pid;
        is(wait, $pid);
        # then wait until foo_deleted gets posted
        while (not exists $::CNT{'foo_deleted'}) {}
        ok($dbh->func($evh, 'ib_cancel_callback'));
        ok($dbh->disconnect);
        is($::CNT{'foo_inserted'}, 5, "compare number of inserts");
        is($::CNT{'foo_deleted'}, 5, "compare number of deleted rows");
    } else {
        $|++;
        $SIG{HUP} = sub { diag("kid gets sighup\n"); $::SLEEP = 0 };
        $::SLEEP = 1;
        while ($::SLEEP) {}

        my ($dbh, $error_str) = connect_to_database({AutoCommit => 1 });
        for (1..5) {
            $dbh->do(qq{INSERT INTO $table VALUES($_, 'bar')});
            sleep 1;
        }
        $dbh->do(qq{DELETE FROM $table});
        #sleep 1;    # give some time for db to post event
        $dbh->disconnect;
        exit;
    }
}}

$dbh->{InactiveDestroy} = 0;
ok($dbh->do(qq(DROP TRIGGER ins_${table}_trig)));
ok($dbh->do(qq(DROP TRIGGER del_${table}_trig)));
ok($dbh->do(qq(DROP TABLE $table)), "DROP TABLE $table");
ok($dbh->disconnect);

