#! /usr/bin/env perl

#
# Verify that $dbh->tables() returns a list of (quoted) tables.
#

use DBI;
use Test::More tests => 5;
use strict;

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

# === BEGIN TESTS ===

my ($dbh, $tbl, %tables);

$dbh = DBI->connect($::test_dsn, $::test_user, $::test_password,
                    { RaiseError => 1 });
ok($dbh);

$tbl = find_new_table($dbh);
ok($dbh->do(<<__eocreate), "CREATE TABLE $tbl");
CREATE TABLE $tbl(
    i INTEGER NOT NULL,
    vc VARCHAR(64) NOT NULL
)
__eocreate

%tables = map { uc($_) => 1 } $dbh->tables;

ok(exists $tables{ $dbh->quote_identifier(uc($tbl)) },
   "tables() returned uppercased, quoted $tbl");
#diag join(' ', sort keys %tables);

ok($dbh->do("DROP TABLE $tbl"), "DROP TABLE $tbl");

%tables = map { uc($_) => 1 } $dbh->tables;
#diag join(' ', sort keys %tables);

ok(!exists($tables{ $dbh->quote_identifier(uc($tbl)) }),
   "$tbl no longer in tables()");

__END__
# vim: set et ts=4:
