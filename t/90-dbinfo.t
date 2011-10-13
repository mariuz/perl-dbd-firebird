#!/usr/bin/perl -w
# test for ib_database_info()

use strict;
use warnings;

use Test::More;
use lib 't','.';

use TestFirebird;
my $T = TestFirebird->new;

my ($dbh1, $error_str) = $T->connect_to_database();

my ( $test_dsn, $test_user, $test_password ) =
  ( $T->{tdsn}, $T->{user}, $T->{pass} );

if ($error_str) {
    BAIL_OUT("Unknown: $error_str!");
}

unless ( $dbh1->isa('DBI::db') ) {
    plan skip_all => 'Connection to database failed, cannot continue testing';
}
else {
    plan tests => 13;
}

ok($dbh1, 'Connected to the database');

my @items = qw/
        allocation
        base_level
        db_id
        implementation
        no_reserve
        db_read_only
        ods_minor_version
        ods_version
        page_size
        version
        db_sql_dialect
        current_memory
        forced_writes
        max_memory
        num_buffers
        sweep_interval
        user_names
        fetches
        marks
        reads
        writes
        active_tran_count
        creation_date
/;

my $info = $dbh1->func(@items, 'ib_database_info');
ok($info);

SKIP: {
    my $k = 'active_tran_count';

    skip "$k is not available", 10 unless exists $info->{$k};

    my ($dbh2, $error_str2) = $T->connect_to_database({AutoCommit => 0 });
    ok($dbh2);

    is($dbh2->func($k, 'ib_database_info')->{$k}, 0, "tx count should be 0, no tx started yet");

    ok( $dbh2->selectall_arrayref(q{SELECT COUNT(1) FROM RDB$DATABASE}) );

    is($dbh2->func($k, 'ib_database_info')->{$k}, 1, "tx count should be 1");

    ok($dbh2->commit);

    is($dbh2->func($k, 'ib_database_info')->{$k}, 0, "tx count should be 0 after commit");

    ok($dbh2->disconnect);

    ok($dbh1->disconnect);

    $dbh1 = DBI->connect($test_dsn . ';ib_dbkey_scope=1', $test_user, $test_password);
    ok($dbh1);

    is($dbh1->func($k, 'ib_database_info')->{$k}, 1, "tx count should be 1, with dbkey_scope = 1");
}

ok($dbh1->disconnect);
