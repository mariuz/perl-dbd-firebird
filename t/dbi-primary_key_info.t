#!perl -w
# vim: ft=perl

# Changes 2011-01-21   stefansbv:
# - use testlib.pl instead of lib.pl

use strict;
use warnings;

use Test::More;
use lib 't','.';

require 'tests-setup.pl';

my ( $dbh, $error_str ) =
  connect_to_database( { RaiseError => 1, PrintError => 0, AutoCommit => 0 } );

if ($error_str) {
    BAIL_OUT("Unknown: $error_str!");
}

unless ( $dbh->isa('DBI::db') ) {
    plan skip_all => 'Connection to database failed, cannot continue testing';
}
else {
    plan tests => 13;
}

ok($dbh, 'Connected to the database');

# ------- TESTS ------------------------------------------------------------- #

#
#   Find a possible new table name
#
my $table = find_new_table($dbh);
ok($table, qq{Table is '$table'});

ok($dbh->do(<<__eosql), "CREATE TABLE $table");
  CREATE TABLE $table(
    Z INTEGER NOT NULL,
    Y CHAR(10) NOT NULL,
    X INTEGER NOT NULL,
    K CHAR(3) NOT NULL,
    PRIMARY KEY(Z, Y, X),
    UNIQUE(K)
  )
__eosql

my $sth = $dbh->primary_key_info(undef, undef, $table);
ok($sth, "Got primary key info");
is_deeply($sth->{NAME_uc},
   [qw|TABLE_CAT TABLE_SCHEM TABLE_NAME COLUMN_NAME KEY_SEQ PK_NAME|]);

my $key_info = $sth->fetch;
is_deeply([@$key_info[0..4]], [ undef, undef, $table, 'Z', '1' ]);
ok($key_info->[5] =~ /\S/, "PK_NAME is set"); # Something like RBD$PRIMARY123

$key_info = $sth->fetch;
is_deeply([@$key_info[0..4]], [ undef, undef, $table, 'Y', '2' ]);
ok($key_info->[5] =~ /\S/, "PK_NAME is set");

$key_info = $sth->fetch;
is_deeply([@$key_info[0..4]], [ undef, undef, $table, 'X', '3' ]);
ok($key_info->[5] =~ /\S/, "PK_NAME is set");

$sth->finish;

is_deeply([ $dbh->primary_key(undef, undef, $table) ], [qw|Z Y X|],
          "Check primary_key results");

ok($dbh->do("DROP TABLE $table"), "Dropped table");

$dbh->disconnect();
