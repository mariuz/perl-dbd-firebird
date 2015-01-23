use strict;
use warnings;

# Smattering of dbh attribute tests.
# FIXME:  add generic handle attribute tests, FB-specific attribute tests

use Test::More;

use lib 't','.';

use TestFirebird;

my $T = TestFirebird->new;

plan tests => 9;

my( $dbh, $error ) = $T->connect_to_database;
ok(!$error, "Connected to database") or diag($error);

ok($dbh->{Active},
   "Active attribute is true after connect");

ok(defined($dbh->{AutoCommit}),
   "AutoCommit attribute supported");

isa_ok($dbh->{Driver}, 'DBI::dr',
   "Driver attribute returns a DBI::dr");

ok($dbh->{Name} =~ /db=[^;]+/,
   "Name attribute is of the form db=...")
  or diag("\$dbh->{Name} is $dbh->{Name}");

$dbh->prepare('SELECT 1 FROM RDB$DATABASE');

cmp_ok($dbh->{Statement}, 'eq', 'SELECT 1 FROM RDB$DATABASE',
       "Statement attribute is as expected");

# Borrowed from DBD::Pg
is($dbh->{RowCacheSize}, undef,
   "RowCacheSize attribute is undefined");
$dbh->{RowCacheSize} = 42;
is($dbh->{RowCacheSize}, undef,
   "RowCacheSize attribute is undefined after assignment");

$dbh->disconnect();
ok(!$dbh->{Active},
   "Active attribute is false after disconnect");
