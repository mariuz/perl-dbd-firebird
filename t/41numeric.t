#!/usr/local/bin/perl
#
#   $Id: 41numeric.t 349 2005-09-10 16:55:31Z edpratomo $
#
#   This is a test for INT64 type.
#

# 2011-01-29 stefansbv
# New version based on t/testlib.pl and InterBase.dbtest

use strict;

BEGIN {
        $|  = 1;
        $^W = 1;
}

use DBI;
use Test::More tests => 30;
#use Test::NoWarnings;

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

#   Connect to the database
my $dbh =
  DBI->connect( $::test_dsn, $::test_user, $::test_password,
    { ChopBlanks => 1 } );

# DBI->trace(4, "trace.txt");

# ------- TESTS ------------------------------------------------------------- #

ok($dbh, 'DBH ok');

#
#   Find a possible new table name
#
my $table = find_new_table($dbh);
ok($table, "TABLE is '$table'");

# expected fetched values
my @correct = (
    [ 123456.79,   86753090000.868,  11 ],
    [ -123456.79,  -86753090000.868, -11 ],
    [ 123456.001,  80.080,           10 ],
    [ -123456.001, -80.080,          0 ],
    [ 10.9,        10.9,             11 ],
);

sub is_match {
    my ($result, $row, $fieldno) = @_;
    $result->[$row]->[$fieldno] == $correct[$row]->[$fieldno];
}

#
#   Create a new table
#

my $def =<<"DEF";
CREATE TABLE $table (
    NUMERIC_AS_INTEGER    NUMERIC(9,3),
    NUMERIC_THREE_DIGITS  NUMERIC(18,3),
    NUMERIC_NO_DIGITS     NUMERIC(10,0)
)
DEF
ok( $dbh->do($def), qq{CREATE TABLE '$table'} );

#
#   Insert some values
#

my $stmt =<<"END_OF_QUERY";
INSERT INTO $table (
    NUMERIC_AS_INTEGER,
    NUMERIC_THREE_DIGITS,
    NUMERIC_NO_DIGITS
) VALUES (?, ?, ?)
END_OF_QUERY

ok(my $insert = $dbh->prepare($stmt), 'PREPARE INSERT');

# Insert positive numbers
ok($insert->execute(
    123456.7895,
    86753090000.8675309,
    10.9),
   'INSERT POSITIVE NUMBERS'
);

# Insert negative numbers
ok($insert->execute(
    -123456.7895,
    -86753090000.8675309,
    -10.9),
   'INSERT NEGATIVE NUMBERS'
);

# Insert with some variations in the precision part

ok($insert->execute(
    123456.001,
    80.080,
    10.0),
   'INSERT NUMBERS WITH VARIOUS PREC 1'
);

ok($insert->execute(
    -123456.001,
    -80.080,
    -0.0),
   'INSERT NUMBERS WITH VARIOUS PREC 2'
);

ok($insert->execute(
    10.9,
    10.9,
    10.9),
   'INSERT NUMBERS WITH VARIOUS PREC 3'
);

#
#   Select the values
#
ok( my $cursor = $dbh->prepare( "SELECT * FROM $table", ) );

ok($cursor->execute, 'EXECUTE SELECT');

ok((my $res = $cursor->fetchall_arrayref), 'FETCHALL');

my ($types, $names, $fields) = @{$cursor}{qw(TYPE NAME NUM_OF_FIELDS)};

for (my $i = 0; $i < @$res; $i++) {
    for (my $j = 0; $j < $fields; $j++) {
        ok(is_match($res, $i, $j), "field: $names->[$j] ($types->[$j])");
    }
}

#
#  Drop the test table
#
$dbh->{AutoCommit} = 1;

ok( $dbh->do("DROP TABLE $table"), "DROP TABLE '$table'" );

#  NUM_OF_FIELDS should be zero (Non-Select)
ok(($cursor->{'NUM_OF_FIELDS'}), "NUM_OF_FIELDS == 0");

#
#   Finally disconnect.
#
ok($dbh->disconnect());
