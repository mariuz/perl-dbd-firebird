#!/usr/bin/perl
#
# 2011-04-13 stefan(s.bv.) Modified to run on Windows.
#
# 2011-01-31 stefan(s.bv.) Created new test:
# Playing with very big | small numbers
# Smallest and biggest integer supported by Firebird:
#   -9223372036854775808, 9223372036854775807
#
# This test uses isql CLI for the creation of the table and for the
# insertion of the values.  Look at biginteger.t for a Perl only
# variant.
#

use strict;
use warnings;

use Math::BigFloat try => 'GMP';
use Test::More;
use DBI;

use lib 't','.';

require 'tests-setup.pl';

my ($dbh1, $error_str) = connect_to_database();

if ($error_str) {
    BAIL_OUT("Unknown: $error_str!");
}

unless ( $dbh1->isa('DBI::db') ) {
    plan skip_all => 'Connection to database failed, cannot continue testing';
}
else {
    plan tests => 12;
}

ok($dbh1, 'dbh1 OK');

# ------- TESTS ------------------------------------------------------------- #

# Find a new table name
my $table = find_new_table($dbh1);
ok($table, "TABLE is '$table'");

my $rc = read_cached_configs();
my ( $db, $test_user, $test_password, $test_isql, $host ) =
  ( $rc->{path}, $rc->{user}, $rc->{pass}, $rc->{isql}, $rc->{host} );

my $auth = $test_user ? "USER '$test_user' PASSWORD '$test_password'" : '';

# Prepare isql commands
my $insert_sql =<<"ISQLDEF";
CONNECT '$host:$db' $auth;
CREATE TABLE $table (
    BINT_MIN  BIGINT,
    BINT_MAX  BIGINT
);
COMMIT;
INSERT INTO $table (
    BINT_MIN,
    BINT_MAX
) VALUES (
-9223372036854775808,
 9223372036854775807
);
COMMIT;
quit;
ISQLDEF

my $test_sql_insert = './t/insert.sql';      # temp file name

# Create an SQL file with the SQL statements
open my $t_fh, '>', $test_sql_insert
    or die qq{Can't write to $test_sql_insert};
print {$t_fh} $insert_sql;
close $t_fh;

# Run isql
my $ocmd = qq("$test_isql" -sql_dialect 3 -i "$test_sql_insert" 2>&1);
# print "cmd: $ocmd\n";
system($ocmd) == 0
    or die "system '$ocmd' failed: $?";

ok($dbh1->disconnect(), 'DISCONNECT dbh1');

# reConnect to the database
my ($dbh2, $error_str2) = connect_to_database({ ChopBlanks => 1 });

# DBI->trace(4, "trace.txt");

ok($dbh2, 'dbh2 OK');

# Expected fetched values
my @correct = (
    [ '-9223372036854775808', '9223372036854775807' ],
);

# Select the values
ok( my $cursor = $dbh2->prepare( qq{SELECT * FROM $table} ), 'PREPARE SELECT' );

ok($cursor->execute, 'EXECUTE SELECT');

ok((my $res = $cursor->fetchall_arrayref), 'FETCHALL');

my ($types, $names, $fields) = @{$cursor}{qw(TYPE NAME NUM_OF_FIELDS)};

#my $scale = 0;                               # scale parameter
for (my $i = 0; $i < @$res; $i++) {
    for (my $j = 0; $j < $fields; $j++) {
        my $result  = qq{$res->[$i][$j]};
        my $mresult = Math::BigInt->new($result);

        my $corect  = $correct[$i][$j];
        my $mcorect = Math::BigInt->new($corect);

        #ok($mresult->bacmp($mcorect) == 0, , "Field: $names->[$j]");
        is($mresult, $mcorect, "Field: $names->[$j]");
        # diag "got: $mresult";
        # diag "exp: $mcorect";
    }
}

# Drop the test table
$dbh2->{AutoCommit} = 1;

ok( $dbh2->do("DROP TABLE $table"), "DROP TABLE '$table'" );

# Finally disconnect.
ok($dbh2->disconnect(), 'DISCONNECT');

ok( unlink "$test_sql_insert", 'Cleanup temp file' );

#-- end TESTS
