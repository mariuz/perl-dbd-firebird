#!/usr/bin/perl
#
# 2011-04-13 stefan(s.bv.) Modified to run on Windows.
#
# 2011-01-31 stefan(s.bv.) Created new test:
# Playing with very big | small numbers
# Smallest and biggest decimal supported by Firebird:
#   -922337203685477.5808, 922337203685477.5807
#

use strict;
use warnings;

use Math::BigFloat try => 'GMP';
use Test::More;
use DBI;

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
    plan tests => 9;
}

ok($dbh, 'dbh OK');

# ------- TESTS ------------------------------------------------------------- #

# Find a new table name
my $table = find_new_table($dbh);
ok($table, "TABLE is '$table'");

$dbh->do(<<DEF);
CREATE TABLE $table (
    DEC_MIN  NUMERIC(18,4),
    DEC_MAX  NUMERIC(18,4)
)
DEF
$dbh->do(<<DEF);
INSERT INTO $table (
    DEC_MIN,
    DEC_MAX
) VALUES (
    -922337203685477.5808,
    922337203685477.5807
)
DEF

# DBI->trace(4, "trace.txt");

# Expected fetched values
my @correct = (
    [ '-922337203685477.5808', '922337203685477.5807' ],
);

# Select the values
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
        #diag "got: $mresult";
        #diag "exp: $mcorect";
    }
}

# Drop the test table
$dbh->{AutoCommit} = 1;

ok( $dbh->do("DROP TABLE $table"), "DROP TABLE '$table'" );

# Finally disconnect.
ok($dbh->disconnect(), 'DISCONNECT');

#-- end TESTS
