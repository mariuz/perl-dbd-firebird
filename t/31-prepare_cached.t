#!/usr/bin/perl
# $Id: 31prepare.t 396 2008-01-08 05:43:26Z edpratomo $
# test for prepare_cached()

use strict;
use warnings;

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
    plan tests => 37;
}

ok($dbh, 'Connected to the database');

# ------- TESTS ------------------------------------------------------------- #

#
#   Find a possible new table name
#
my $table = find_new_table($dbh);
ok($table, qq{Table is '$table'});

{
    my $def = "CREATE TABLE $table (id INTEGER NOT NULL, PRIMARY KEY(id))";
    ok($dbh->do($def));

    my $stmt = "INSERT INTO $table (id) VALUES(?)";
    ok($dbh->do($stmt, undef, 1));
}

my $prepare_sub = sub { $dbh->prepare(shift), "prepare" };

SKIP: {
    skip("prepare() tests", 10) if $ENV{SKIP_PREPARE};

    simple_query($dbh, $prepare_sub);
    faulty_query($dbh, $prepare_sub);
    simple_query($dbh, $prepare_sub);
}

TEST_CACHED: {
    $prepare_sub = sub { $dbh->prepare_cached(shift), "prepare_cached" };
    my ($query, $n_cached);

    $query = simple_query($dbh, $prepare_sub);
    for (values %{$dbh->{CachedKids}}) {
        $n_cached++ if $_->{Statement} eq $query;
    }
    is($n_cached, 1, qq{cached "$query"});

    $dbh->commit() unless $dbh->{AutoCommit};

#    print Dumper $dbh->{CachedKids} unless $dbh->{AutoCommit};
#    $k = faulty_query($dbh, $mode);
#    ok($dbh->{CachedKids}{$k}, qq{cached "$k"});
#    $dbh->rollback() unless $dbh->{AutoCommit};

    $query = simple_query($dbh, $prepare_sub);
    is(scalar keys(%{$dbh->{CachedKids}}), 1);

    # clear cached sth
    %{$dbh->{CachedKids}} = ();
    # wrong:
    # $dbh->{CachedKids} = undef;

    # repeat with AutoCommit off
    if ($dbh->{AutoCommit}) {
        $dbh->{AutoCommit} = 0;
        pass("AutoCommit is now turned Off");
        goto TEST_CACHED;
    } else {
        $dbh->{AutoCommit} = 1;
        last TEST_CACHED;
    }
}

ok($dbh->do("DROP TABLE $table"), "DROP TABLE $table");
ok($dbh->disconnect);

# 4 tests
sub simple_query {
    my ($dbh, $prepare_sub) = @_;

    my $sql = "SELECT id FROM $table";
    my ($sth, $mode) = $prepare_sub->($sql);

    ok($sth, "$mode() for SELECT");
    ok(defined($sth->execute()), "execute()");

    # print "Active? ", $sth->{Active}, "\n";

    my $r = $sth->fetchall_arrayref;
    is($r->[0][0], 1, "check fetch result");
    is($sth->err, undef, "fetch all result set");

    return $sql;
}

# 2 tests
sub faulty_query {
    my ($dbh, $prepare_sub) = @_;

    my $sql = "INSERT INTO $table VALUES(?)";
    my ($sth, $mode) = $prepare_sub->($sql);

    ok($sth, "$mode() for INSERT");
    eval { $sth->execute(1) };
    ok ($@, 'expected INSERT failure');

    return $sql;
}
