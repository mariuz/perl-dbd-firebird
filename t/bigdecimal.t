#!/usr/bin/perl

# 2011-01-31 stefan(s.bv.)
# Playing with very big | small numbers
# Smallest and biggest decimal supported by Firebird:
#   -922337203685477.5808, 922337203685477.5807
#
# Look at bigdecimal_read.t for a variant that uses isql CLI for the
# creation of the table and for the insertion of the values.
#

use strict;

use Math::BigFloat try => 'GMP';
use Test::More tests => 12;
use DBI;

BEGIN {
    $|  = 1;
    $^W = 1;
}

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

ok($dbh, 'dbh OK');

# ------- TESTS ------------------------------------------------------------- #

#
#   Find a possible new table name
#
my $table = find_new_table($dbh);
ok($table, "TABLE is '$table'");


#
#   Create a new table
#
my $def =<<"DEF";
CREATE TABLE $table (
    DEC_MIN  DECIMAL(18,4),
    DEC_MAX  DECIMAL(18,4)
)
DEF
ok( $dbh->do($def), qq{CREATE TABLE '$table'} );

#
#   Insert some values
#
my $stmt =<<"END_OF_QUERY";
INSERT INTO $table (
    DEC_MIN,
    DEC_MAX
) VALUES (?, ?)
END_OF_QUERY

ok(my $insert = $dbh->prepare($stmt), 'PREPARE INSERT');

# Insert positive numbers
ok( $insert->execute( -922337203685477.5808, 922337203685477.5807 ),
    'INSERT MIN | MAX DECIMALS' );

#
#   Expected fetched values
#
my @correct = (
    [ '-922337203685477.5808', '922337203685477.5807' ],
);

#
#   Select the values
#
ok( my $cursor = $dbh->prepare( qq{SELECT * FROM $table} ), 'PREPARE SELECT' );

ok($cursor->execute, 'EXECUTE SELECT');

ok((my $res = $cursor->fetchall_arrayref), 'FETCHALL');

my ($types, $names, $fields) = @{$cursor}{qw(TYPE NAME NUM_OF_FIELDS)};

for (my $i = 0; $i < @$res; $i++) {
    for (my $j = 0; $j < $fields; $j++) {
        my $result  = qq{$res->[$i][$j]};
        my $mresult = Math::BigFloat->new($result);

        my $corect  = $correct[$i][$j];
        my $mcorect = Math::BigFloat->new($corect);

        is($mresult, $mcorect, "Field: $names->[$j]");
        # diag "got: $mresult";
        # diag "exp: $mcorect";
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
ok($dbh->disconnect(), 'DISCONNECT');
