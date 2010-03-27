#! /usr/bin/env perl

#
# Verify that $dbh->tables() returns a list of (quoted) tables.
#

use DBI 1.19; # FetchHashKeyName support (2001-07-20)
use Test::More tests => 19;
use strict;

use constant TI_DBI_FIELDS =>
             [qw/ TABLE_CAT TABLE_SCHEM TABLE_NAME TABLE_TYPE REMARKS / ];

# IB/FB derivatives can add at least 'ib_owner_name'
# (rdb$relations.rdb$owner_name) to the ordinary DBI table_info() fields.
use constant TI_IB_FIELDS =>
             [ @{TI_DBI_FIELDS()}, 'IB_OWNER_NAME' ];

# FIXME - consolidate this duplicated code

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

sub contains {
    my ($superset, $subset) = @_;

    # for our purposes, sets must not be empty
    if (0 == @$superset or 0 == @$subset) {
        die "Empty set given to contains()";
    }

    my %super = map {$_=>undef} @$superset;
    for my $element (@$subset) {
        return undef unless exists $super{$element};
    }
    1;
}

sub find_new_table {
    my $dbh = shift;
    my $try_name = 'TESTAA';
    my $try_name_quoted = $dbh->quote_identifier($try_name);
    my %tables = map { uc($_) => 1 } $dbh->tables;
    while (exists $tables{$try_name} or exists $tables{$try_name_quoted}) {
        ++$try_name;
    }
    $try_name;
}

# === BEGIN TESTS ===

my ($dbh, $sth, $r);

$dbh = DBI->connect($::test_dsn, $::test_user, $::test_password,
                       { RaiseError => 1, FetchHashKeyName => 'NAME_uc' });
ok($dbh);

# -- List all catalogs (none)
$sth = $dbh->table_info('%', '', '');
$r = $sth->fetch;
ok(!defined($r), "No DBI catalog support");
ok(contains($sth->{NAME_uc}, TI_DBI_FIELDS),
   "Result set contains expected table_info() fields");

# -- List all schema (none)
$sth = $dbh->table_info('', '%', '');
ok(!defined($sth->fetch), "No DBI schema support");
ok(contains($sth->{NAME_uc}, TI_DBI_FIELDS),
   "Result set contains expected table_info() fields");

# -- List all supported types
$sth = $dbh->table_info('', '', '', '%');
my @types;
while (my $r = $sth->fetchrow_hashref) {
    push @types, $r->{TABLE_TYPE};
}
ok(contains(\@types, ['VIEW', 'TABLE', 'SYSTEM TABLE']),
   "Minimal types supported");

# -- Literal table specification

for my $tbl_spec ('RDB$DATABASE') {
    $sth = $dbh->table_info('', '', $tbl_spec);
    $r = $sth->fetchrow_hashref;
    is($r->{TABLE_NAME}, $tbl_spec, "TABLE_NAME is $tbl_spec");
    is($r->{TABLE_TYPE}, 'SYSTEM TABLE', 'TABLE_TYPE is SYSTEM TABLE');
    ok(contains($sth->{NAME_uc}, TI_IB_FIELDS),
        "Result set contains expected table_info() fields");
    ok(!defined($sth->fetch), "One and only one row returned for $tbl_spec");

    $sth = $dbh->table_info('', '', $tbl_spec, 'VIEW');
    ok(!defined($sth->fetch), "No VIEW named $tbl_spec");
    ok(contains($sth->{NAME_uc}, TI_IB_FIELDS),
        "Result set contains expected table_info() fields");

    $sth = $dbh->table_info('', '', $tbl_spec, 'VIEW,SYSTEM TABLE');
    $r = $sth->fetchrow_hashref;
    is($r->{TABLE_NAME}, $tbl_spec, "$tbl_spec found (multiple TYPEs given)");
    is($r->{TABLE_TYPE}, 'SYSTEM TABLE', 'TABLE_TYPE is SYSTEM TABLE (multiple TYPEs given)');
    ok(!defined($sth->fetch), "Only one row returned (multiple TYPEs given)");
    ok(contains($sth->{NAME_uc}, TI_IB_FIELDS),
        "Result set contains expected table_info() fields");
}

# -- Pattern tests
#    Similar to the literal table spec, but may return more than one
#    matching entry

for my $tbl_spec ('RDB$D_T_B_S_', 'RDB$%', '%', '') {
    $sth = $dbh->table_info('', '', $tbl_spec);
    while ($r = $sth->fetchrow_hashref) {
        last if $r->{TABLE_NAME} eq 'RDB$DATABASE';
    }
    is($r->{TABLE_NAME}, 'RDB$DATABASE', "RDB\$DATABASE found against '$tbl_spec'");
    is($r->{TABLE_TYPE}, 'SYSTEM TABLE', 'is SYSTEM TABLE');
    ok(contains($sth->{NAME_uc}, TI_IB_FIELDS),
        "Result set contains expected table_info() fields");

    $sth = $dbh->table_info('', '', $tbl_spec, 'VIEW,SYSTEM TABLE');
    while ($r = $sth->fetchrow_hashref) {
        last if $r->{TABLE_NAME} eq 'RDB$DATABASE';
    }
    is($r->{TABLE_NAME}, 'RDB$DATABASE', "RDB\$DATABASE found against '$tbl_spec' (multiple TYPEs)");
    is($r->{TABLE_TYPE}, 'SYSTEM TABLE', 'is SYSTEM TABLE (multiple TYPEs)');
    ok(contains($sth->{NAME_uc}, TI_IB_FIELDS),
        "Result set contains expected table_info() fields");
}

__END__
# vim: set et ts=4:
