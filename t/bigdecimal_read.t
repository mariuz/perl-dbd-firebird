#!/usr/bin/perl

# 2011-01-31 stefan(s.bv.)
# Playing with very big | small numbers
# Smallest and biggest decimal supported by Firebird:
#   -922337203685477.5808, 922337203685477.5807
#
# This test uses isql CLI for the creation of the table and for the
# insertion of the values.  Look at bigdecimal.t for a Perl only
# variant.
#
# This test needs a modified Makefile.PL that adds a row in test.conf
# with the path to isql
#

use strict;

use Math::BigFloat try => 'GMP';
use Test::More;
use DBI;

BEGIN {
    if ( $^O eq 'MSWin32' ) {
        plan skip_all => 'Not for MSWin32!';
        exit 0;
    }
    else {
       plan tests => 11;
    }

    $|  = 1;
    $^W = 1;
}

# Make -w happy
$::test_dsn = '';
$::test_user = '';
$::test_password = '';
$::test_isql     = '';

for my $file ('t/testlib.pl', 'testlib.pl') {
    next unless -f $file;
    eval { require $file };
    BAIL_OUT("Cannot load testlib.pl\n") if $@;
    last;
}

my ($db) = $::test_dsn =~ /(?:db|database)=([^;]+);/;

#   Connect to the database
my $dbh1 =
  DBI->connect( $::test_dsn, $::test_user, $::test_password,
    { ChopBlanks => 1 } );

# DBI->trace(4, "trace.txt");

ok($dbh1, 'dbh1 OK');

# ------- TESTS ------------------------------------------------------------- #

#
#   Find a possible new table name
#
my $table = find_new_table($dbh1);
ok($table, "TABLE is '$table'");

#
#   Prepare isql commands
#
my $insert_sql =<<"ISQLDEF";
CONNECT '$db' USER '$::test_user' PASSWORD '$::test_password';
CREATE TABLE $table (
    DEC_MIN  NUMERIC(18,4),
    DEC_MAX  NUMERIC(18,4)
);
COMMIT;
INSERT INTO $table (
    DEC_MIN,
    DEC_MAX
) VALUES (
    -922337203685477.5808,
    922337203685477.5807
);
COMMIT;
quit;
ISQLDEF

# Use isql to insert test values
my $ocmd = qq(echo '$insert_sql' | '$::test_isql' -sql_dialect 3 2>&1);
eval {
    open my $isql_fh, '-|', $ocmd;
    while (<$isql_fh>) {
        # For debug:
        # print "> $_\n";
    }
    close $isql_fh;
};
if ($@) {
    die "ISQL open error!\n";
}

ok($dbh1->disconnect(), 'DISCONNECT dbh1');

#   ReConnect to the database
my $dbh2 = DBI->connect( $::test_dsn, $::test_user, $::test_password,
                         { ChopBlanks => 1 } );

# DBI->trace(4, "trace.txt");

ok($dbh2, 'dbh2 OK');

#
#   Expected fetched values
#
my @correct = (
    [ '-922337203685477.5808', '922337203685477.5807' ],
);

#
#   Select the values
#
ok( my $cursor = $dbh2->prepare( qq{SELECT * FROM $table} ), 'PREPARE SELECT' );

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

#
#  Drop the test table
#
$dbh2->{AutoCommit} = 1;

ok( $dbh2->do("DROP TABLE $table"), "DROP TABLE '$table'" );

#
#   Finally disconnect.
#
ok($dbh2->disconnect(), 'DISCONNECT');
