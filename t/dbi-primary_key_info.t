#!perl -w
# vim: ft=perl

use Test::More;
use DBI;
use strict;
use lib 't', '.';
require 'lib.pl';
$|= 1;

use vars qw($table $test_dsn $test_user $test_password);
my $dbh;
eval {$dbh= DBI->connect($test_dsn, $test_user, $test_password,
                      { RaiseError => 1, PrintError => 0, AutoCommit => 0 });};

if ($@) {
    plan skip_all => "ERROR: $DBI::errstr. Can't continue test";
}
plan tests => 12;

ok(defined $dbh, "Connected to database for key info tests");

$table = FindNewTable($dbh);

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
