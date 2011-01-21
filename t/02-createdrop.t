#!/usr/local/bin/perl
#
#   $Id: 20createdrop.t 112 2001-04-19 14:56:06Z edpratomo $
#

# 2011-01-21 stefansbv
# New version based on testlib and InterBase.dbtest

use strict;
use DBI;
use Test::More tests => 5;
#use vars qw( $dbh $table );

# END {
#   if (defined($dbh) and $table) {
#     eval { $dbh->do("DROP TABLE $table"); };
#     $dbh->disconnect;
#   }
# }

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

# sub ServerError() {
#     print STDERR ("Cannot connect: ", $DBI::errstr, "\n",
#     "\tEither your server is not up and running or you have no\n",
#     "\tpermissions for acessing the DSN $test_dsn.\n",
#     "\tThis test requires a running server and write permissions.\n",
#     "\tPlease make sure your server is running and you have\n",
#     "\tpermissions, then retry.\n");
#     exit 10;
# }

#
#   Main loop; leave this untouched, put tests into the loop
#
# use vars qw($state);
# while (Testing()) {
#
#   Connect to the database
#     my $dbh;
#     Test($state or $dbh = DBI->connect($test_dsn, $test_user, $test_password))
#     or ServerError();
my $dbh = DBI->connect($::test_dsn, $::test_user, $::test_password);
ok($dbh);

#
#   Find a possible new table name
#
my $table = find_new_table($dbh);
diag $table;
ok($table);

#
#   Create a new table
#
$::COL_KEY = 0;
$::COL_NULLABLE = 0;
my $def = TableDefinition(
    $table,
    ["id",   "INTEGER",  4, $::COL_KEY],
    ["name", "CHAR",    64, $::COL_NULLABLE],
);
ok($dbh->do($def), "CREATE TABLE '$table'");

#
#   ... and drop it.
#
ok($dbh->do("DROP TABLE $table"), "DROP TABLE '$table'");

#
#   Finally disconnect.
#
ok($dbh->disconnect());
