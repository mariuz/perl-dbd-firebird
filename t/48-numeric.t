#!/usr/bin/perl
#
#   $Id: 41numeric.t 349 2005-09-10 16:55:31Z edpratomo $
#
# 2011-01-29 stefan(s.bv.)
# Using string comparison with Test::More's 'is'
#
# 2011-01-29 stefan(s.bv.)
# New version based on t/testlib.pl and Firebird.dbtest

use strict;
use warnings;

use Test::More;
use DBI;

use lib 't','.';

require 'tests-setup.pl';

my ( $dbh, $error_str ) = connect_to_database( { ChopBlanks => 1 } );

if ($error_str) {
    BAIL_OUT("Unknown: $error_str!");
}

unless ( $dbh->isa('DBI::db') ) {
    plan skip_all => 'Connection to database failed, cannot continue testing';
}
else {
    plan tests => 29;
}

ok($dbh, 'Connected to the database');

# DBI->trace(4, "trace.txt");

# ------- TESTS ------------------------------------------------------------- #

#
#   Find a possible new table name
#
my $table = find_new_table($dbh);
ok($table, "TABLE is '$table'");

# Expected fetched values
# Need to store the decimal precision for 'sprintf'
# Prec must also be the same in CREATE TABLE, of course

my $expected = {
    NUMERIC_2_DIGITS => {
        prec => 2,
        test => {
            0 => 123456.79,
            1 => -123456.79,
            2 => 123456.01,
            3 => -123456.09,
            4 => 10.9,
        },
    },
    NUMERIC_3_DIGITS => {
        prec => 3,
        test => {
            0 => 86753090000.868,
            1 => -86753090000.868,
            2 => 80.080,
            3 => -80.080,
            4 => 10.9,
        },
    },
    NUMERIC_NO_DIGITS => {
        prec => 0,
        test => {
            0 => 11,
            1 => -11,
            2 => 10,
            3 => 0,
            4 => 11,
        },
    },
};

#
#   Create a new table
#

my $def =<<"DEF";
CREATE TABLE $table (
    NUMERIC_2_DIGITS   NUMERIC( 9, 2),
    NUMERIC_3_DIGITS   NUMERIC(18, 3),
    NUMERIC_NO_DIGITS  NUMERIC(10, 0)
)
DEF
ok( $dbh->do($def), qq{CREATE TABLE '$table'} );

#
#   Insert some values
#

my $stmt =<<"END_OF_QUERY";
INSERT INTO $table (
    NUMERIC_2_DIGITS,
    NUMERIC_3_DIGITS,
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
    123456.01,
    80.080,
    10.0),
   'INSERT NUMBERS WITH VARIOUS PREC 1'
);

ok($insert->execute(
    -123456.09,
    -80.080,
    0.0),
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
ok( my $cursor = $dbh->prepare( qq{SELECT * FROM $table}, ), 'PREPARE SELECT' );

ok($cursor->execute, 'EXECUTE SELECT');

ok((my $res = $cursor->fetchall_arrayref), 'FETCHALL arrayref');

my ($types, $names, $fields) = @{$cursor}{qw(TYPE NAME NUM_OF_FIELDS)};

for (my $i = 0; $i < @$res; $i++) {
    for (my $j = 0; $j < $fields; $j++) {
        my $prec = $expected->{ $names->[$j] }{prec};
        my $result = sprintf("%.${prec}f", $res->[$i][$j]);
        my $corect = sprintf("%.${prec}f", $expected->{$names->[$j]}{test}{$i});
        is($result, $corect, "Field: $names->[$j]");
    }
}

#
#  Drop the test table
#
$dbh->{AutoCommit} = 1;

ok( $dbh->do("DROP TABLE $table"), "DROP TABLE '$table'" );

#
#   Finally disconnect.
#
ok($dbh->disconnect, 'DISCONNECT');
