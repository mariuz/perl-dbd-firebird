#!/usr/local/bin/perl -w
#
#   Test cases for DBD-InterBase rt.cpan.org #49896
#   "Varchar fields accept data one char over field length (but memory
#   is corrupted)"
#

use strict;
use DBI;
use Test::More tests => 8;
use vars qw( $dbh $table );

END {
  if (defined($dbh) and $table) {
    eval { $dbh->do("DROP TABLE $table"); };
    $dbh->disconnect;
  }
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

# ------- TESTS ------------------------------------------------------------- #

$dbh = DBI->connect($::test_dsn, $::test_user, $::test_password);
ok($dbh);

$table = find_new_table($dbh);
ok($table);

ok($dbh->do("CREATE TABLE $table( c1 varchar(3) )",
            "CREATE TABLE $table(...)"));

ok($dbh->do("INSERT INTO $table(c1) VALUES(?)", undef, 'aa'),
   "INSERT string (length < column size) succeeds");

ok($dbh->do("INSERT INTO $table(c1) VALUES(?)", undef, 'aaa'),
   "INSERT string (length == column size) succeeds");

$dbh->{PrintError} = 0;

ok(! defined $dbh->do("INSERT INTO GGG(c1) VALUES(?)", undef, 'aaa!'),
   "INSERT string (length == column size + 1) fails");

ok(! defined $dbh->do("INSERT INTO GGG(c1) VALUES(?)", undef, 'aaa!!'),
   "INSERT string (length == column size + 2) fails");

ok($dbh->do("DROP TABLE $table"), "DROP TABLE $table");
