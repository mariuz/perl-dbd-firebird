#!/usr/local/bin/perl
#
#
#   This is a test for CursorName attribute.
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
    plan tests => 17;
}

ok($dbh, 'Connected to the database');

# DBI->trace(4, "trace.txt");

# ------- TESTS ------------------------------------------------------------- #

#
#   Find a possible new table name
#
my $table = find_new_table($dbh);
ok($table, "TABLE is '$table'");

my $def = qq{ CREATE TABLE $table (user_id INTEGER, comment VARCHAR(20)) };
my %values = (
    1 => 'Lazy',
    2 => 'Hubris',
    6 => 'Impatience',
);

ok($dbh->do($def), "CREATE TABLE '$table'");

my $sql_insert = qq{INSERT INTO $table VALUES (?, ?)};
ok(my $cursor = $dbh->prepare($sql_insert), 'PREPARE INSERT');

ok($cursor->execute($_, $values{$_}), "INSERT id $_") for (keys %values);

$dbh->{AutoCommit} = 0;

my $sql_sele = qq{SELECT * FROM $table WHERE user_id < 5 FOR UPDATE OF comment};
ok(my $cursor2 = $dbh->prepare($sql_sele), 'PREPARE SELECT');

ok($cursor2->execute, 'EXCUTE SELECT');

# Before..
while (my @res = $cursor2->fetchrow_array) {
    ok($dbh->do(
        "UPDATE $table SET comment = 'Zzzzz...' WHERE
                CURRENT OF $cursor2->{CursorName}"),
       "DO UPDATE where cursor name is '$cursor2->{CursorName}'"
   );
}

ok(my $cursor3 = $dbh->prepare(
    "SELECT * FROM $table WHERE user_id < 5"), 'PREPARE SELECT');

ok($cursor3->execute, 'EXECUTE SELECT');

# After..
while (my @res = $cursor3->fetchrow_array) {
    is($res[1], 'Zzzzz...', 'FETCHROW result check');
}

ok($dbh->commit, 'COMMIT');

#
#  Drop the test table
#
$dbh->{AutoCommit} = 1;

ok( $dbh->do("DROP TABLE $table"), "DROP TABLE '$table'" );
