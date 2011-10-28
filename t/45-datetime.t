#!/usr/local/bin/perl
#
#
#   This is a test for date/time types handling with localtime() style.
#

# 2011-01-29 stefansbv
# New version based on t/testlib.pl and Firebird.dbtest

use strict;
use warnings;

use Test::More;
use DBI qw(:sql_types);

use lib 't','.';

use TestFirebird;
my $T = TestFirebird->new;

my ( $dbh, $error_str ) = $T->connect_to_database( { ChopBlanks => 1 } );

if ($error_str) {
    BAIL_OUT("Unknown: $error_str!");
}

unless ( $dbh->isa('DBI::db') ) {
    plan skip_all => 'Connection to database failed, cannot continue testing';
}
else {
    plan tests => 14;
}

ok($dbh, 'Connected to the database');

# DBI->trace(4, "trace.txt");

# ------- TESTS ------------------------------------------------------------- #

#
#   Find a possible new table name
#
my $table = find_new_table($dbh);
ok($table, "TABLE is '$table'");

my @times = localtime();

my @is_match = (
    sub {
        my $ref = shift->[0]->[0];
        return ($$ref[0] == $times[0]) &&
               ($$ref[1] == $times[1]) &&
               ($$ref[2] == $times[2]) &&
               ($$ref[3] == $times[3]) &&
               ($$ref[4] == $times[4]) &&
               ($$ref[5] == $times[5]);
    },
    sub {
        my $ref = shift->[0]->[1];
        return ($$ref[3] == $times[3]) &&
               ($$ref[4] == $times[4]) &&
               ($$ref[5] == $times[5]);
    },
    sub {
        my $ref = shift->[0]->[2];
        return ($$ref[0] == $times[0]) &&
               ($$ref[1] == $times[1]) &&
               ($$ref[2] == $times[2]);
    }
);

#
#   Create a new table
#

my $def =<<"DEF";
CREATE TABLE $table (
    A_TIMESTAMP  TIMESTAMP,
    A_DATE       DATE,
    A_TIME       TIME
)
DEF

ok( $dbh->do($def), qq{CREATE TABLE '$table'} );

#
#   Insert some values
#
my $stmt =<<"END_OF_QUERY";
INSERT INTO $table
    (
    A_TIMESTAMP,
    A_DATE,
    A_TIME
    )
    VALUES (?, ?, ?)
END_OF_QUERY

ok(my $insert = $dbh->prepare($stmt), 'PREPARE INSERT');

ok($insert->execute(\@times, \@times, \@times));

#
#   Select the values
#
ok(
    my $cursor = $dbh->prepare(
        "SELECT * FROM $table",
        {
            ib_timestampformat => 'TM',
            ib_dateformat      => 'TM',
            ib_timeformat      => 'TM',
        }
    )
);

ok($cursor->execute);

ok((my $res = $cursor->fetchall_arrayref), 'FETCHALL');

my ($types, $names, $fields) = @{$cursor}{qw(TYPE NAME NUM_OF_FIELDS)};

for (my $i = 0; $i < $fields; $i++) {
    ok(( $is_match[$i]->($res) ), "field: $names->[$i] ($types->[$i])");
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
