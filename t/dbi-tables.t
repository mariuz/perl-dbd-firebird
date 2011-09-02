#! /usr/bin/env perl

#
# Verify that $dbh->tables() returns a list of (quoted) tables.
#

use strict;
use warnings;

use Test::More;
use lib 't','.';

require 'tests-setup.pl';

my ($dbh, $error_str) = connect_to_database();

if ($error_str) {
    BAIL_OUT("Unknown: $error_str!");
}

unless ( $dbh->isa('DBI::db') ) {
    plan skip_all => 'Connection to database failed, cannot continue testing';
}
else {
    plan tests => 6;
}

ok($dbh, 'Connected to the database');

# ------- TESTS ------------------------------------------------------------- #

#
#   Find a possible new table name
#
my $table = find_new_table($dbh);
ok($table, qq{Table is '$table'});

ok($dbh->do(<<__eocreate), "CREATE TABLE $table");
CREATE TABLE $table(
    i INTEGER NOT NULL,
    vc VARCHAR(64) NOT NULL
)
__eocreate

my %tables = map { uc($_) => 1 } $dbh->tables;

ok(exists $tables{ $dbh->quote_identifier(uc($table)) },
   "tables() returned uppercased, quoted $table");
#diag join(' ', sort keys %tables);

ok($dbh->do("DROP TABLE $table"), "DROP TABLE $table");

%tables = map { uc($_) => 1 } $dbh->tables;
#diag join(' ', sort keys %tables);

ok(!exists($tables{ $dbh->quote_identifier(uc($table)) }),
   "$table no longer in tables()");

__END__
# vim: set et ts=4:
