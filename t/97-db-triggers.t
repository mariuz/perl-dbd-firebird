#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Exception;
use DBI;

use lib 't','.';

use TestFirebird;
my $T = TestFirebird->new;

my ($dbh, $error_str) = $T->connect_to_database();

if ($error_str) {
    BAIL_OUT("Unknown: $error_str!");
}

unless ($dbh->isa('DBI::db')) {
    plan skip_all => 'Connection to database failed, cannot continue testing';
}
else {
    my $orig_ver = $dbh->func(version => 'ib_database_info')->{version};
    (my $ver = $orig_ver) =~ s/.*\bFirebird\s*//;

    if ($ver =~ /^(\d+)\.(\d+)$/) {
        if ($1 > 2 or $1 == 2 and $2 >= 1) {
            plan tests => 15;
        }
        else {
            plan skip_all =>
"Firebird version $1.$2 doesn't support database-level triggers";
        }
    }
    else {
        plan skip_all =>
"Unable to determine Firebird version from '$orig_ver'. Assuming no database-level triggers";
    }
}

ok($dbh, 'Connected to the database');

# DBI->trace(4, "trace.txt");

eval { $dbh->do("drop table conn_log") };
lives_ok(sub { $dbh->do("create table conn_log(tm timestamp not null)") },
    "create conn_log table");

eval { $dbh->do("drop trigger conn_log") };
lives_ok(
    sub {
        $dbh->do(<<SQL);
create trigger conn_log
on connect
as
begin
  insert into conn_log(tm) values(current_timestamp);
end
SQL
    },
    "create on connect trigger"
);

# ------- TESTS ------------------------------------------------------------- #

ok($dbh->disconnect, 'DISCONNECT');

($dbh, $error_str) = $T->connect_to_database();

ok($dbh, 'reconnected');

my ($cnt) = $dbh->selectrow_array("SELECT COUNT(*) FROM conn_log");
is($cnt, 1, "Single connection logged (trigger works)");

ok($dbh->disconnect, 'DISCONNECT');

($dbh, $error_str) =
  $T->connect_to_database({ ib_db_triggers => 0 });

ok($dbh, 'reconnected wuth ib_db_triggers=0');

($cnt) = $dbh->selectrow_array("SELECT COUNT(*) FROM conn_log");
is($cnt, 1, "Still single connection logged (ib_db_triggers=0 works)");

ok($dbh->disconnect, 'DISCONNECT');

($dbh, $error_str) =
  $T->connect_to_database({ ib_db_triggers => 1 });

ok($dbh, 'reconnected with ib_db_triggers=1');

($cnt) = $dbh->selectrow_array("SELECT COUNT(*) FROM conn_log");
is($cnt, 2, "Two connections logged (ib_db_triggers=1 works)");

#
#  Drop the test table/trigger
#
$dbh->{AutoCommit} = 1;

ok($dbh->do("DROP TRIGGER conn_log"), "DROP TRIGGER conn_log");

ok($dbh->do("DROP TABLE conn_log"), "DROP TABLE conn_log");

#
#   Finally disconnect.
#
ok($dbh->disconnect, 'DISCONNECT');
