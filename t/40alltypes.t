#!/usr/local/bin/perl
#
#   $Id: 40alltypes.t 349 2005-09-10 16:55:31Z edpratomo $
#
#   This is a test for all data types handling.
#

# 2011-01-23 stefansbv
# New version based on testlib and Firebird.dbtest
# NOW and TOMORROW tests replaced with simple TIME and DATE tests
#   there is a separate test for them anyway

use strict;
use warnings;

use DBI;
use Test::More tests => 24;

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

my %expected = (
    0  => 30000,
    1  => 1000,
    2  => 'Edwin        ',
    3  => 'Edwin Pratomo       ',
    4  => 'A string',
    5  => 5000,
    6  => '1.20000004768372',
    7  => 1.44,
    8  => '2011-01-23 17:14',
    9  => '2011-01-23',
    10 => '17:14',
    11 => 32.71,
    12 => -32.71,
    13 => 123456.79,
    14 => -123456.79,
    15 => '86753090000.868',
);

#
#   Connect to the database
my $dbh = DBI->connect($::test_dsn, $::test_user, $::test_password,
                       {AutoCommit => 1, PrintError => 0});
ok($dbh);

#
#   Find a possible new table name
#
my $table = find_new_table($dbh);
ok($table);

#
#   Create a new table
#
my $def =<<"DEF";
CREATE TABLE $table (
    INTEGER_    INTEGER,
    SMALLINT_   SMALLINT,
    CHAR13_     CHAR(13),
    CHAR20_     CHAR(20),
    VARCHAR13_  VARCHAR(13),
    DECIMAL_    DECIMAL,
    FLOAT_      FLOAT,
    DOUBLE_     DOUBLE PRECISION,
    A_TIMESTAMP  TIMESTAMP,
    A_DATE       DATE,
    A_TIME       TIME,
    NUMERIC_AS_SMALLINT  NUMERIC(4,3),
    NUMERIC_AS_SMALLINT2 NUMERIC(4,3),
    NUMERIC_AS_INTEGER   NUMERIC(9,3),
    NUMERIC_AS_INTEGER2  NUMERIC(9,3),
    A_SIXTYFOUR  NUMERIC(18,3)
)
DEF

ok($dbh->do($def));

#
# Prepare insert
#

my $stmt =<<"END_OF_QUERY";
INSERT INTO $table (
    INTEGER_,
    SMALLINT_,
    CHAR13_,
    CHAR20_,
    VARCHAR13_,
    DECIMAL_,
    FLOAT_,
    DOUBLE_,
    A_TIMESTAMP,
    A_DATE,
    A_TIME,
    NUMERIC_AS_SMALLINT,
    NUMERIC_AS_SMALLINT2,
    NUMERIC_AS_INTEGER,
    NUMERIC_AS_INTEGER2,
    A_SIXTYFOUR
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
END_OF_QUERY

my $cursor = $dbh->prepare($stmt);

ok($cursor->execute(
    30000,
    1000,
    'Edwin',
    'Edwin Pratomo',
    'A string',
    5000,
    1.2,
    1.44,
    '2011-01-23 17:14',
    '2011-01-23',
    '17:14',
    32.71,
    -32.71,
    123456.7895,
    -123456.7895,
    86753090000.8675309
), "INSERT in $table");

my $cursor2 = $dbh->prepare("SELECT * FROM $table", {
    ib_timestampformat => '%Y-%m-%d %H:%M',
    ib_dateformat => '%Y-%m-%d',
    ib_timeformat => '%H:%M',
});

ok($cursor2->execute);

ok(my $res = $cursor2->fetchall_arrayref, 'FETCHALL arrayref');

my ($types, $names, $fields) = @{$cursor2}{qw(TYPE NAME NUM_OF_FIELDS)};
for (my $i = 0; $i < $fields; $i++) {
    is($res->[0][$i], $expected{$i}, "TEST No $i");
}

#
#  Drop the test table
#
ok($dbh->do("DROP TABLE $table"), "DROP TABLE '$table'");

#
#   Finally disconnect.
#
ok($dbh->disconnect());
