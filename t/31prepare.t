#!/usr/bin/perl -w
# $Id: 31prepare.t 396 2008-01-08 05:43:26Z edpratomo $
# test for prepare_cached()

use strict;
use DBI;

use Test::More tests => 36;
#DBI->trace(4, "trace.txt");

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

my $dbh = DBI->connect($::test_dsn, $::test_user, $::test_password,
                      {AutoCommit => 1, PrintError => 0});
ok($dbh);

my $table = find_new_table($dbh);
ok($table);

{
    my $def = "CREATE TABLE $table(id INTEGER NOT NULL, PRIMARY KEY(id))";
    ok($dbh->do($def));

    my $stmt = "INSERT INTO $table(id) VALUES(?)";
    ok($dbh->do($stmt, undef, 1));
}

my $prepare_sub = sub { $dbh->prepare(shift), "prepare" };

SKIP: {
    skip("prepare() tests", 10) if $ENV{SKIP_PREPARE};

    simpleQuery($dbh, $prepare_sub);
    faultyQuery($dbh, $prepare_sub);
    simpleQuery($dbh, $prepare_sub);
}

TEST_CACHED: {
    $prepare_sub = sub { $dbh->prepare_cached(shift), "prepare_cached" };
    my ($query, $n_cached);

    $query = simpleQuery($dbh, $prepare_sub);
	for (values %{$dbh->{CachedKids}}) {
		$n_cached++ if $_->{Statement} eq $query;
	}
    is($n_cached, 1, qq{cached "$query"});

    $dbh->commit() unless $dbh->{AutoCommit};

#    print Dumper $dbh->{CachedKids} unless $dbh->{AutoCommit};
#    $k = faultyQuery($dbh, $mode);
#    ok($dbh->{CachedKids}{$k}, qq{cached "$k"});
#    $dbh->rollback() unless $dbh->{AutoCommit};

    $query = simpleQuery($dbh, $prepare_sub);
    is(scalar keys(%{$dbh->{CachedKids}}), 1);

    # clear cached sth
    %{$dbh->{CachedKids}} = ();
    # wrong:
    # $dbh->{CachedKids} = undef;

    # repeat with AutoCommit off
    if ($dbh->{AutoCommit}) {
        $dbh->{AutoCommit} = 0;
        diag("AutoCommit is now turned Off");
        goto TEST_CACHED;
    } else {
        $dbh->{AutoCommit} = 1;
        last TEST_CACHED;
    }
}

ok($dbh->do("DROP TABLE $table"), "DROP TABLE $table");
ok($dbh->disconnect);

# 4 tests
sub simpleQuery {
    my ($dbh, $prepare_sub) = @_;
    my $sql = "SELECT id FROM $table";
    my ($sth, $mode) = $prepare_sub->($sql);

    ok($sth, "$mode() for SELECT");
    ok(defined($sth->execute()), "execute()");

#    print "Active? ", $sth->{Active}, "\n";

    my $r = $sth->fetchall_arrayref;
    is($r->[0][0], 1, "check fetch result");
    is($sth->err, undef, "fetch all result set");

    return $sql;
}

# 2 tests
sub faultyQuery {
    my ($dbh, $prepare_sub) = @_;
    my $sql = "INSERT INTO $table VALUES(?)";
    my ($sth, $mode) = $prepare_sub->($sql);

    ok($sth, "$mode() for INSERT");
    is($sth->execute(1), undef, "expected INSERT failure");

    return $sql;
}

