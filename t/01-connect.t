#!/usr/bin/perl
#
# Test for the connection first ...
#

use strict;
use warnings;

use Test::More;
use lib 't','.';

use TestFirebird;
my $T = TestFirebird->new;

my ($dbh, $error_str) = $T->connect_to_database;

if ($error_str) {
    BAIL_OUT("Error! $error_str!");
}

unless ( $dbh->isa('DBI::db') ) {
    plan skip_all => 'Connection to database failed, cannot continue testing';
}
else {
    plan tests => 2;
}

ok($dbh, 'Connected to the database');

# and disconnect.

ok( $dbh->disconnect );
