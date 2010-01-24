#!/usr/local/bin/perl -w
#
#   $Id: 61settx.t 229 2002-04-05 03:12:51Z edpratomo $
#
#   This is a test for set_tx_param() private method.
#

use strict;
use vars qw($mdriver $state $test_dsn $test_user $test_password);

#
#   Make -w happy
#
$test_dsn = '';
$test_user = '';
$test_password = '';

my $rec_num = 2;

#
#   Include lib.pl
#
use DBI;
use vars qw($verbose);



$mdriver = "";
foreach my $file ("lib.pl", "t/lib.pl") {
    do $file; if ($@) { print STDERR "Error while executing lib.pl: $@\n";
               exit 10;
              }
    if ($mdriver ne '') {
    last;
    }
}

sub ServerError() {
    print STDERR ("Cannot connect: ", $DBI::errstr, "\n",
    "\tEither your server is not up and running or you have no\n",
    "\tpermissions for acessing the DSN $test_dsn.\n",
    "\tThis test requires a running server and write permissions.\n",
    "\tPlease make sure your server is running and you have\n",
    "\tpermissions, then retry.\n");
    exit 10;
}

while (Testing()) {
    my ($dbh1, $dbh2);

    #
    #   Connect to the database
    Test($state or $dbh1 = DBI->connect($test_dsn, $test_user, $test_password))
    or ServerError();

    Test($state or $dbh2 = DBI->connect($test_dsn, $test_user, $test_password))
    or ServerError();

    #
    #   Find a possible new table name
    #
     Test($state or my $table = FindNewTable($dbh1))
       or DbiError($dbh1->err, $dbh1->errstr);

    #
    #   Create a new table
    #
    my $def;
    unless ($state) {
        $def = "CREATE TABLE $table(id INTEGER, name VARCHAR(20))";
    }

    Test($state or $dbh1->do($def))
    or DbiError($dbh1->err, $dbh1->errstr);

    #
    #   Changes transaction params
    #
    Test($state or $dbh1->func( 
        -access_mode     => 'read_write',
        -isolation_level => 'read_committed',
        -lock_resolution => 'wait',
        'set_tx_param'))
    or DbiError($dbh1->err, $dbh1->errstr);

    Test($state or $dbh2->func(
#        -isolation_level => 'snapshot_table_stability',
        -access_mode     => 'read_only',
        -lock_resolution => 'no_wait',
        'set_tx_param'))
    or DbiError($dbh2->err, $dbh2->errstr);

    #DBI->trace(3, "trace.txt");
    {
        local $dbh1->{AutoCommit} = 0;
        local $dbh2->{PrintError} = 0;

        my ($stmt, $select_stmt);
        unless ($state) {
            $stmt = "INSERT INTO $table VALUES(?, 'Yustina')";
            $select_stmt = "SELECT * FROM $table WHERE 1 = 0";
        }

        Test($state or my $sth2 = $dbh2->prepare($select_stmt))
            or DbiError($dbh2->err, $dbh2->errstr);

        Test($state or $dbh1->do($stmt, undef, 1))
            or DbiError($dbh1->err, $dbh1->errstr);

        # expected failure:
        Test($state or not $dbh2->do($stmt, undef, 2))
            or DbiError($dbh2->err, $dbh2->errstr);

        # reading should be ok here:
        Test($state or $sth2->execute)
            or DbiError($sth2->err, $sth2->errstr);

        Test($state or $sth2->finish)
            or DbiError($sth2->err, $sth2->errstr);

        # committing the first trans
        Test($state or $dbh1->commit)
            or DbiError($dbh1->err, $dbh1->errstr);

        Test($state or $dbh1->func( 
            -access_mode     => 'read_write',
            -isolation_level => 'read_committed',
            -lock_resolution => 'wait',
            -reserving       =>
                {
                    $table => {
                        lock    => 'write',
                        access  => 'protected',
                    },
                },
            'set_tx_param'))
        or DbiError($dbh1->err, $dbh1->errstr);

        Test($state or $dbh2->func(
        #    -isolation_level => 'snapshot_table_stability',
            -lock_resolution => 'no_wait',
            'set_tx_param'))
        or DbiError($dbh2->err, $dbh2->errstr);

        Test($state or $dbh1->do($stmt, undef, 2))
            or DbiError($dbh1->err, $dbh1->errstr);

        Test($state or $dbh2->do($stmt, undef, 3))
            or DbiError($dbh2->err, $dbh2->errstr);

        # committing the first trans
        Test($state or $dbh1->commit)
            or DbiError($dbh1->err, $dbh1->errstr);

    }
    #
    #  Drop the test table
    #
    Test($state or $dbh1->do("DROP TABLE $table"))
       or DbiError($dbh1->err, $dbh1->errstr);

    #
    #   Finally disconnect.
    #
    Test($state or $dbh1->disconnect())
       or DbiError($dbh1->err, $dbh1->errstr);

    Test($state or $dbh2->disconnect())
       or DbiError($dbh2->err, $dbh2->errstr);
}
