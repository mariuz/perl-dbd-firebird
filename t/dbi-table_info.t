#! /usr/bin/env perl

#
# Verify that $dbh->tables() returns a list of (quoted) tables.
#
# Changes 2011-01-21   stefansbv:
# - localized variables per test block
#

use strict;
use warnings;

use DBI 1.19; # FetchHashKeyName support (2001-07-20)
use Test::More;
use lib 't','.';

use constant TI_DBI_FIELDS =>
             [qw/ TABLE_CAT TABLE_SCHEM TABLE_NAME TABLE_TYPE REMARKS / ];

use TestFirebird;
my $T = TestFirebird->new;

my ( $dbh, $error_str )
    = $T->connect_to_database(
    { RaiseError => 1, FetchHashKeyName => 'NAME_uc' } );

if ($error_str) {
    BAIL_OUT("Unknown: $error_str!");
}

unless ( $dbh->isa('DBI::db') ) {
    plan skip_all => 'Connection to database failed, cannot continue testing';
}
else {
    plan tests => 41;
}

ok($dbh, 'Connected to the database');

# IB/FB derivatives can add at least 'ib_owner_name'
# (rdb$relations.rdb$owner_name) to the ordinary DBI table_info() fields.
use constant TI_IB_FIELDS =>
             [ @{TI_DBI_FIELDS()}, 'IB_OWNER_NAME' ];

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
    return 1;
}

# ------- TESTS ------------------------------------------------------------- #

#
#   Find a possible new table name
#
my $table = find_new_table($dbh);
ok($table, qq{Table is '$table'});

# -- List all catalogs (none)
{
    my $sth = $dbh->table_info('%', '', '');
    my $r = $sth->fetch;
    ok(!defined($r), "No DBI catalog support");
    ok(contains($sth->{NAME_uc}, TI_DBI_FIELDS),
       "Result set contains expected table_info() fields");
}

# -- List all schema (none)
{
    my $sth = $dbh->table_info('', '%', '');
    ok(!defined($sth->fetch), "No DBI schema support");
    ok(contains($sth->{NAME_uc}, TI_DBI_FIELDS),
       "Result set contains expected table_info() fields");
}

# -- List all supported types
{
    my $sth = $dbh->table_info('', '', '', '%');
    my @types;
    while (my $r = $sth->fetchrow_hashref) {
        push @types, $r->{TABLE_TYPE};
    }
    ok(contains(\@types, ['VIEW', 'TABLE', 'SYSTEM TABLE']),
       "Minimal types supported");
}

# -- Literal table specification
{
    for my $tbl_spec ('RDB$DATABASE') {
        my $sth1 = $dbh->table_info('', '', $tbl_spec);
        my $r1 = $sth1->fetchrow_hashref;
        is($r1->{TABLE_NAME}, $tbl_spec, "TABLE_NAME is $tbl_spec");
        is($r1->{TABLE_TYPE}, 'SYSTEM TABLE', 'TABLE_TYPE is SYSTEM TABLE');
        ok(contains($sth1->{NAME_uc}, TI_IB_FIELDS),
           "Result set contains expected table_info() fields");
        ok(!defined($sth1->fetch), "One and only one row returned for $tbl_spec");

        my $sth2 = $dbh->table_info('', '', $tbl_spec, 'VIEW');
        ok(!defined($sth2->fetch), "No VIEW named $tbl_spec");
        ok(contains($sth2->{NAME_uc}, TI_IB_FIELDS),
           "Result set contains expected table_info() fields");

        my $sth3 = $dbh->table_info('', '', $tbl_spec, 'VIEW,SYSTEM TABLE');
        my $r3 = $sth3->fetchrow_hashref;
        is($r3->{TABLE_NAME}, $tbl_spec, "$tbl_spec found (multiple TYPEs given)");
        is($r3->{TABLE_TYPE}, 'SYSTEM TABLE', 'TABLE_TYPE is SYSTEM TABLE (multiple TYPEs given)');
        ok(!defined($sth3->fetch), "Only one row returned (multiple TYPEs given)");
        ok(contains($sth3->{NAME_uc}, TI_IB_FIELDS),
           "Result set contains expected table_info() fields");
    }
}

# -- Pattern tests
#    Similar to the literal table spec, but may return more than one
#    matching entry (remember: '_' and '%' are search pattern characters)

for my $tbl_spec ('RDB$D_T_B_S_', 'RDB$%', '%', '') {

    #
    {
        my $sth = $dbh->table_info('', '', $tbl_spec);
        ok(contains($sth->{NAME_uc}, TI_IB_FIELDS),
           "Result set contains expected table_info() fields");
        my ($table_name, $table_type);
        while (my $r = $sth->fetchrow_hashref) {
            if ( $r->{TABLE_NAME} eq 'RDB$DATABASE' ) {
                $table_name = $r->{TABLE_NAME};
                $table_type = $r->{TABLE_TYPE};
                last;
            }
        }
        is( $table_name, 'RDB$DATABASE',
            "RDB\$DATABASE found against '$tbl_spec'" );
        is( $table_type, 'SYSTEM TABLE', 'is SYSTEM TABLE' );
    }

    #
    {
        my $sth = $dbh->table_info('', '', $tbl_spec, 'VIEW,SYSTEM TABLE');
        ok(contains($sth->{NAME_uc}, TI_IB_FIELDS),
           "Result set contains expected table_info() fields");

        my ($table_name, $table_type);
        while (my $r = $sth->fetchrow_hashref) {
            if ( $r->{TABLE_NAME} eq 'RDB$DATABASE' ) {
                $table_name = $r->{TABLE_NAME};
                $table_type = $r->{TABLE_TYPE};
                last;
            }
        }

        is( $table_name, 'RDB$DATABASE',
            "RDB\$DATABASE found against '$tbl_spec' (multiple TYPEs)" );
        is( $table_type, 'SYSTEM TABLE', 'is SYSTEM TABLE (multiple TYPEs)' );
    }
}

done_testing;

__END__
# vim: set et ts=4:
