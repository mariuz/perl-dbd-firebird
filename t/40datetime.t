#!/usr/local/bin/perl
#
#   $Id: 40datetime.t 380 2007-05-20 15:18:40Z edpratomo $
#
#   This is a test for date/time types handling with localtime() style.
#

# 2011-01-29 stefansbv
# New version based on t/testlib.pl and InterBase.dbtest

use strict;

BEGIN {
        $|  = 1;
        $^W = 1;
}

use DBI;
use Test::More tests => 14;
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
