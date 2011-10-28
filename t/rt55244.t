#!/usr/bin/perl -w
# test for https://rt.cpan.org/Public/Bug/Display.html?id=55244

use strict;
use warnings;

use Test::More;
use lib 't','.';

use TestFirebird;
my $T = TestFirebird->new;

my ( $dbh, $error_str )
    = $T->connect_to_database( { AutoCommit => 0, RaiseError => 1 } );

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

my $table = find_new_table($dbh);
ok( $dbh->do("CREATE TABLE $table(i INTEGER NOT NULL)"),
    'table $table created' );

$dbh->commit;

my $insert_sql = "INSERT INTO $table(i) VALUES(42)";
my $sth = $dbh->prepare_cached($insert_sql);
ok( $sth->execute );

$dbh->rollback;

$sth = $dbh->prepare_cached($insert_sql);
ok( $sth->execute(), 'cached statement execues after rollback' );

ok( $dbh->do("DROP TABLE $table") );
$dbh->commit;
ok( $dbh->disconnect );

