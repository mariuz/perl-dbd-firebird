#!/usr/bin/perl
#
#   Test that RT#110979 is fixed
#

use strict;
use warnings;

use Test::More;
use lib 't','.';

use TestFirebird;
my $T = TestFirebird->new;

my ($dbh, $error_str) = $T->connect_to_database();

if ($error_str) {
    BAIL_OUT("Unknown: $error_str!");
}

unless ( $dbh->isa('DBI::db') ) {
    plan skip_all => 'Connection to database failed, cannot continue testing';
}

ok($dbh, 'Connected to the database');


# ------- TESTS ------------------------------------------------------------- #

my $table = find_new_table($dbh);
ok($table, qq{Table is '$table'});

#
#   Create a new table
#
my $def =<<"DEF";
CREATE TABLE $table (
    id     INTEGER PRIMARY KEY,
    name   VARCHAR(200)
)
DEF
ok( $dbh->do($def), qq{CREATE TABLE '$table'} );

ok( $dbh->do("create generator gen_$table"), "create generator gen_$table" );

$def = <<"DEF";
CREATE TRIGGER $table\_bi FOR $table
ACTIVE BEFORE INSERT POSITION 0
AS
BEGIN
    IF (NEW.id IS NULL) THEN
        NEW.id = GEN_ID(gen_$table,1);
END
DEF

ok( $dbh->do($def), "create trigger $table\_bi" );

my $sth
    = $dbh->prepare_cached("INSERT INTO $table(name) VALUES(?) RETURNING id");
ok( $sth->execute('foo'), 'Insert worked' );
is( ($sth->fetchrow_array)[0], 1, 'Autoinc PK retrieved' );
ok( $sth->finish, "finish" );

ok( $dbh->do( "drop trigger $table\_bi", "drop trigger" ) );
ok( $dbh->do( "drop generator gen_$table", "drop generator" ) );
ok($dbh->do("DROP TABLE $table"), "DROP TABLE '$table'");

#
#   Finally disconnect.
#
ok($dbh->disconnect());

done_testing();
