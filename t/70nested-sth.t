#!/usr/local/bin/perl -w
#
#   $Id: 70nested-sth.t 392 2008-01-07 15:33:25Z edpratomo $
#
#   This is a test for nested statement handles.
#

use strict;
use DBI;
use Test::More tests => 24;

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

my $dbh = DBI->connect($::test_dsn, $::test_user, $::test_password, {AutoCommit => 1});
ok($dbh);

my $table = find_new_table($dbh);
ok($table);

{
    my $def = "CREATE TABLE $table(id INTEGER, name VARCHAR(20))";
    ok($dbh->do($def));

    my $stmt = "INSERT INTO $table(id, name) VALUES(?, ?)";
    ok($dbh->do($stmt, undef, 1, 'Crocodile'));
}

# now ready to work

# BOTH hard and soft commit WORKS under AC off
{
    local $dbh->{AutoCommit} = 0;
    TRY_HARD_SOFT_COMMIT:
    {
        my $sth1 = $dbh->prepare("SELECT * FROM $table");
        ok($sth1);

	    my $sth2 = $dbh->prepare("SELECT * FROM $table WHERE id = ?");
    	ok($sth2);

        ok($sth1->execute);

        while (my $row = $sth1->fetchrow_arrayref) {
            ok($sth2->execute($row->[0])); 

            my $res = $sth2->fetchall_arrayref;
            ok($res and @$res);
        }

        ok($dbh->commit);
        not $dbh->{ib_softcommit} and $dbh->{ib_softcommit} = 1
            and goto TRY_HARD_SOFT_COMMIT;
    }
}

# now try AC on
ok($dbh->{AutoCommit});

# AC on ONLY works provided that ib_softcommit is on
$dbh->{ib_softcommit} = 1;

{
    my $sth1 = $dbh->prepare("SELECT * FROM $table");
    ok($sth1);

    my $sth2 = $dbh->prepare("SELECT * FROM $table WHERE id = ?");
    ok($sth2);

    ok($sth1->execute);

    while (my $row = $sth1->fetchrow_arrayref) {
        ok($sth2->execute($row->[0])); 

        my $res = $sth2->fetchall_arrayref;
        ok($res and @$res);
    }
}

#  Drop the test table
ok($dbh->do("DROP TABLE $table"));
ok($dbh->disconnect);

