#!/usr/bin/perl -w
# $Id: 91txinfo.t 372 2006-10-25 18:17:44Z edpratomo $
# test for ib_tx_info()

use strict;
use warnings;

use Data::Dumper;

use Test::More;
use lib 't','.';

require 'tests-setup.pl';

my ($dbh1, $error_str) = connect_to_database({AutoCommit => 0});

if ($error_str) {
    BAIL_OUT("Unknown: $error_str!");
}

unless ( $dbh1->isa('DBI::db') ) {
    plan skip_all => 'Connection to database failed, cannot continue testing';
}
else {
    plan tests => 9;
}

ok($dbh1, 'Connected to the database');

ok($dbh1->selectall_arrayref(q{SELECT COUNT(1) FROM RDB$DATABASE}));

my $info = $dbh1->func('ib_tx_info');
ok($info);

print Dumper($info);

ok($dbh1->commit);

ok($dbh1->func(
    -isolation_level => 'read_committed',
    'ib_set_tx_param'
    ),
    "change isolation level"
);

ok($dbh1->selectall_arrayref(q{SELECT COUNT(1) FROM RDB$DATABASE}));

$info = $dbh1->func('ib_tx_info');
ok($info);

print Dumper($info);

ok($dbh1->commit);
ok($dbh1->disconnect);

