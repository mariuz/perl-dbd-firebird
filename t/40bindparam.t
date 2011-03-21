#!/usr/bin/perl
#
#   $Id: 40bindparam.t 328 2005-08-09 08:34:17Z edpratomo $
#

# 2011-01-24 stefansbv
# New version based on t/testlib.pl and Firebird.dbtest

use strict;
#use warnings;
BEGIN {
        $|  = 1;
        $^W = 1;
}

use DBI qw(:sql_types);
use Test::More tests => 37;
#use Test::NoWarnings;

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

#DBI->trace(4, "trace.txt");

#   Connect to the database
my $dbh =
  DBI->connect( $::test_dsn, $::test_user, $::test_password,
    { ChopBlanks => 1 } );
ok($dbh);

#
#   Find a possible new table name
#
my $table = find_new_table($dbh);
#diag $table;
ok($table);

#
#   Create the new table
#
my $def = qq{
CREATE TABLE $table (
    id   INTEGER NOT NULL,
    name CHAR(64) CHARACTER SET ISO8859_1
)
};
ok($dbh->do($def), "CREATE TABLE '$table'");

ok(my $cursor = $dbh->prepare("INSERT INTO $table VALUES (?, ?)"));

#
#   Insert some rows
#

# Automatic type detection
my $numericVal = 1;
my $charVal    = 'Alligator Descartes';
ok($cursor->execute($numericVal, $charVal));

# Does the driver remember the automatically detected type?
ok($cursor->execute("3", "Jochen Wiedmann"));

$numericVal = 2;
$charVal    = "Tim Bunce";
ok($cursor->execute($numericVal, $charVal));

# Now try the explicit type settings
ok($cursor->bind_param(1, ' 4', SQL_INTEGER()));
ok($cursor->bind_param(2, 'Andreas König'));
ok($cursor->execute);

# Works undef -> NULL?
ok($cursor->bind_param(1, 5, SQL_INTEGER()));
ok($cursor->bind_param(2, undef));
ok($cursor->execute);

#
#   Try various mixes of question marks, single and double quotes
#
ok($dbh->do("INSERT INTO $table VALUES (6, '?')"));

#
#   And now retreive the rows using bind_columns
#
ok($cursor = $dbh->prepare("SELECT * FROM $table ORDER BY id"));
ok($cursor->execute);

my ($id, $name);
ok($cursor->bind_columns(undef, \$id, \$name), 'Bind columns');

ok($cursor->fetch);
is($id, 1, 'Check id 1');
is($name, 'Alligator Descartes', 'Check name');

ok($cursor->fetch);
is($id, 2, 'Check id 2');
is($name, 'Tim Bunce', 'Check name');

ok($cursor->fetch);
is($id, 3, 'Check id 3');
is($name, 'Jochen Wiedmann', 'Check name');

ok($cursor->fetch);
is($id, 4, 'Check id 4');
is($name, 'Andreas König', 'Check name');

ok($cursor->fetch);
is($id, 5, 'Check id 5');
is($name, undef, 'Check name');

ok($cursor->fetch);
is($id, 6, 'Check id 6');
is($name, '?', 'Check name');

# Have to call finish
ok($cursor->finish);

#
#   Finally drop the test table.
#
ok($dbh->do("DROP TABLE $table"), "DROP TABLE '$table'");

# -- end test
