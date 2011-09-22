#!/usr/bin/perl
#
#   Test the ib_enable_utf8 attribute
#

use strict;
use warnings;

use utf8;
BEGIN {
    binmode(STDERR, ':utf8');
    binmode(STDOUT, ':utf8');
};
use Test::More;
use lib 't','.';

use Encode qw(encode_utf8);

eval "use Test::Exception; 1"
    or plan skip_all => 'Test::Exception needed for this test';
plan tests => 37;

require 'tests-setup.pl';

my $rc = read_cached_configs();

# first connect with charset ASCII
my $dsn = $rc->{tdsn};
$dsn =~ s/ib_charset=\K[^;]+/ASCII/;
my $attr
    = { RaiseError => 1, PrintError => 0, AutoCommit => 1, ChopBlanks => 1 };
my $dbh = DBI->connect( $dsn, $rc->{user}, $rc->{pass}, $attr );

# …and try to turn on ib_enable_utf8 (should fail)

dies_ok(
   sub { $dbh->{ib_enable_utf8} = 1 },
   'Setting ib_enable_utf8 on charset ASCII db throws');

$dbh->disconnect;

# now connect with UTF8 charset
$dsn =~ s/ib_charset=\K[^;]+/UTF8/;
$dbh = DBI->connect( $dsn, $rc->{user}, $rc->{pass}, $attr );

# …and try to set ib_enable_utf8 again
ok( $dbh->{ib_enable_utf8} = 1, 'Set ib_enable_utf8' );
ok( $dbh->{ib_enable_utf8}, 'Get ib_enable_utf8' );


# ------- TESTS ------------------------------------------------------------- #

#
#   Find a possible new table name
#
my $table = find_new_table($dbh);
ok($table, qq{Table is '$table'});

#
#   Create a new table
#
my $def =<<"DEF";
CREATE TABLE $table (
    id     INTEGER PRIMARY KEY,
    varchr VARCHAR(20) CHARACTER SET UTF8,
    chr    CHAR(20) CHARACTER SET UTF8,
    blb    BLOB SUB_TYPE TEXT CHARACTER SET UTF8
)
DEF
ok( $dbh->do($def), qq{CREATE TABLE '$table'} );

#
#   Insert a row into the test table as raw SQL
#
ok( $dbh->do(qq{INSERT INTO $table VALUES (1, 'ASCII varchar', 'ASCII char', 'ASCII blob')}) );


#
#   Now, see if selected data is plain ASCII as it should be
#
ok( my $cursor = $dbh->prepare("SELECT * FROM $table WHERE id = ?"),
    'SELECT' );
ok( $cursor->execute(1) );

my $row = $cursor->fetchrow_arrayref;
$cursor->finish;

ok( !utf8::is_utf8($row->[0]), 'ASCII varchar' );
ok( !utf8::is_utf8($row->[1]), 'ASCII char' );
ok( !utf8::is_utf8($row->[2]), 'ASCII blob' );

#
#   Insert with binding, still ASCII
#
ok( $dbh->do(
        "INSERT INTO $table VALUES (2, ?, ?, ?)",
        {},
        'Still plain varchar',
        'Still plain char',
        'Still plain blob'
    )
);

ok( $cursor->execute(2) );
$row = $cursor->fetchrow_arrayref;
$cursor->finish;

is( $row->[0], 2 );
is( $row->[1], 'Still plain varchar' );
is( $row->[2], 'Still plain char' );
is( $row->[3], 'Still plain blob' );

#
#   Insert UTF8, embedded
#
ok( $dbh->do(
        "INSERT INTO $table VALUES(3, 'Værчàr', 'Tæst', '€÷∞')")
);
ok( $cursor->execute(3) );
$row = $cursor->fetchrow_arrayref;
$cursor->finish;

is( $row->[0], 3 );
is( $row->[1], 'Værчàr' );
is( $row->[2], 'Tæst' );
is( $row->[3], '€÷∞', 'inline unicode blob' );

#
#   Insert UTF8, binding
#
ok( $dbh->do(
        "INSERT INTO $table VALUES(4, ?, ?, ?)",
        {}, 'Værчàr', 'Tæst', '€÷∞'
    )
);
ok( $cursor->execute(4) );
$row = $cursor->fetchrow_arrayref;
$cursor->finish;

is( $row->[0], 4 );
is( $row->[1], 'Værчàr' );
is( $row->[2], 'Tæst' );
is( $row->[3], '€÷∞', 'bound unicode blob' );

#
# Now turn off unicode support. things we fetch should not be flagged as
# unicode anymore
#

$dbh->{ib_enable_utf8} = 0;

ok( !$dbh->{ib_enable_utf8}, 'Turn off ib_enable_utf8' );

ok( $cursor->execute(4) );
$row = $cursor->fetchrow_arrayref;
$cursor->finish;

is( $row->[0], 4 );
is( $row->[1], encode_utf8('Værчàr'), 'non-unicode varchar' );
is( $row->[2], encode_utf8('Tæst'), 'non-unicode char' );
is( $row->[3], encode_utf8('€÷∞'), 'non-unicode blob' );

#
#   ... and drop it.
#
ok($dbh->do("DROP TABLE $table"), "DROP TABLE '$table'");

#
#   Finally disconnect.
#
ok($dbh->disconnect());
