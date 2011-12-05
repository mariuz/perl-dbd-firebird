#!/usr/bin/perl -w
# test for https://rt.cpan.org/Ticket/Display.html?id=72946

use strict;
use warnings;

use Test::More;
use lib 't','.';

use TestFirebird;
my $T = TestFirebird->new;

my ( $dbh, $error_str )
    = $T->connect_to_database( { AutoCommit => 1, RaiseError => 1 } );

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

ok(my $sth = $dbh->prepare('SELECT rdb$relation_name FROM rdb$relations'),
    'query prepared');

ok($sth->execute, 'query executed');

ok( $dbh->do("CREATE TABLE $table(i INTEGER NOT NULL)"),
    'table $table created' );

ok( $dbh->do("DROP TABLE $table"), 'table dropped' );

ok( $dbh->disconnect, 'disconnected from database' );
