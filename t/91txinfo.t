#!/usr/bin/perl -w
# $Id: 91txinfo.t 372 2006-10-25 18:17:44Z edpratomo $
# test for ib_tx_info()

use strict;
use DBI;
use Test::More tests => 9;
use Data::Dumper;

# Make -w happy
$::test_dsn = '';
$::test_user = '';
$::test_password = '';

my $file;
do {
    if (-f ($file = "t/InterBase.dbtest") ||
        -f ($file = "InterBase.dbtest")) 
    {
        eval { require $file };
        if ($@) {
            diag("Cannot execute $file: $@\n");
            exit 0;
        }
    }
};

sub find_new_table {
    my $dbh = shift;
    my $try_name = 'TESTAA';
    my %tables = map { uc($_) => 1 } $dbh->tables;
    while (exists $tables{$try_name}) {
        ++$try_name;
    }
    $try_name;  
}

my $dbh1 = DBI->connect($::test_dsn, $::test_user, $::test_password, {AutoCommit => 0});
ok($dbh1);

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

