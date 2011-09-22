#!/usr/local/bin/perl -w
#
#
#   This is a test for nested statement handles.
#

use strict;
use warnings;

use Test::More;
use lib 't','.';

require 'tests-setup.pl';

my ( $dbh, $error_str ) = connect_to_database( { AutoCommit => 1 } );

if ($error_str) {
    BAIL_OUT("Unknown: $error_str!");
}

unless ( $dbh->isa('DBI::db') ) {
    plan skip_all => 'Connection to database failed, cannot continue testing';
}
else {
    plan tests => 24;
}

ok($dbh, 'Connected to the database');

# ------- TESTS ------------------------------------------------------------- #

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

