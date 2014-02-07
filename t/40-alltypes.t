#!/usr/bin/perl
#
#
#   This is a test for all data types handling.
#
# 2011-01-23 stefansbv
# New version based on testlib and Firebird.dbtest
# NOW and TOMORROW tests replaced with simple TIME and DATE tests
#   there is a separate test for them anyway


use strict;
use warnings;

use Test::More;
use lib 't','.';

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

# ------- TESTS ------------------------------------------------------------- #

my %expected = (
    VALUES	=> [
	30000,
	1000,
	'Edwin        ',
	'Edwin Pratomo       ',
	'A string',
	5000,
	1.125,
	1.25,
	'2011-01-23 17:14',
	'2011-01-23',
	'17:14',
	32.71,
	-32.71,
	123456.79,
	-123456.79,
	'86753090000.868',
    ],
    TYPE	=> [
	4,5,1,1,12,4,6,8,11,9,10,5,5,4,4,-9581,
    ],
    SCALE	=> [
	0,0,0,0,0,0,0,0,0,0,0,-3,-3,-3,-3,-3,
    ],
    PRECISION	=> [
	4,2,52,80,52,4,4,8,8,4,4,2,2,4,4,8,
    ]
);

my $def = <<"DEF";
    INTEGER_             INTEGER,
    SMALLINT_            SMALLINT,
    CHAR13_              CHAR(13),
    CHAR20_              CHAR(20),
    VARCHAR13_           VARCHAR(13),
    DECIMAL_             DECIMAL,
    FLOAT_               FLOAT,
    DOUBLE_              DOUBLE PRECISION,
    A_TIMESTAMP          TIMESTAMP,
    A_DATE               DATE,
    A_TIME               TIME,
    NUMERIC_AS_SMALLINT  NUMERIC(4,3),
    NUMERIC_AS_SMALLINT2 NUMERIC(4,3),
    NUMERIC_AS_INTEGER   NUMERIC(9,3),
    NUMERIC_AS_INTEGER2  NUMERIC(9,3),
    A_SIXTYFOUR          NUMERIC(18,3)
DEF
for (split m/[\r\n]+/ => $def) {
    my ($f, $d) = m/^\s*(\S+)\s+(\S[^,]+)/;
    push @{$expected{NAME}},    $f;
    push @{$expected{NAME_lc}}, lc $f;
    push @{$expected{NAME_uc}}, uc $f;
    push @{$expected{DEF}},     $d;
}

#
#   Find a possible new table name
#
my $table = find_new_table($dbh);
ok($table, qq{Table is '$table'});

#
#   Create a new table
#
ok($dbh->do("CREATE TABLE $table (\n$def)"), "CREATE TABLE $table");

# Prepare insert
#

my $NAMES  = join "," => @{$expected{NAME}};
my $cursor = $dbh->prepare(
    "INSERT INTO $table ($NAMES) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");

ok($cursor->execute(@{$expected{VALUES}}), "INSERT in $table");

ok(my $cursor2 = $dbh->prepare("SELECT * FROM $table", {
    ib_timestampformat => '%Y-%m-%d %H:%M',
    ib_dateformat => '%Y-%m-%d',
    ib_timeformat => '%H:%M',
}), "PREPARE");

ok($cursor2->execute, "EXECUTE");

ok(my $res = $cursor2->fetchall_arrayref, 'FETCHALL arrayref');

is($cursor2->{NUM_OF_FIELDS}, 16, "Field count");
is_deeply($res->[0],$expected{VALUES}, "Content");
is_deeply($cursor2->{$_}, $expected{$_}, "attribute $_") for qw( NAME NAME_lc NAME_uc TYPE PRECISION SCALE );

#
#  Drop the test table
#
ok($dbh->do("DROP TABLE $table"), "DROP TABLE '$table'");

#
#   Finally disconnect.
#
ok($dbh->disconnect(), "Disconnect");
