#!/usr/local/bin/perl
#
#   $Id: 40cursoron.t 324 2004-12-04 17:17:11Z danielritz $
#
#   This is a test for CursorName attribute with AutoCommit On.
#


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
#DBI->trace(4, "trace.txt");

$mdriver = "";
foreach $file ("lib.pl", "t/lib.pl") {
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
    #
    #   Connect to the database
    Test($state or $dbh = DBI->connect($test_dsn, $test_user, $test_password))
    or ServerError();

    $dbh->{ib_softcommit} = 1;

    #
    #   Find a possible new table name
    #
    # Test($state or $table = FindNewTable($dbh))
    #   or DbiError($dbh->err, $dbh->errstr);

    #
    #   Create a new table
    #

    my $table = 'orders';

    my $def = "CREATE TABLE $table(user_id INTEGER, comment VARCHAR(20))";
    my %values = (
        '1', 'Lazy',
        '2', 'Hubris',
        '6', 'Impatience',
    );

    Test($state or ($dbh->do($def)))
       or DbiError($dbh->err, $dbh->errstr);

    my $stmt = "INSERT INTO $table VALUES (?, ?)";

    Test($state or $cursor = $dbh->prepare($stmt))
       or DbiError($dbh->err, $dbh->errstr);

    for (keys %values) {
        Test($state or $cursor->execute($_, $values{$_}))
            or DbiError($cursor->err, $cursor->errstr);
    }

    $stmt = "SELECT * FROM $table WHERE user_id < 5 FOR UPDATE OF comment";

    Test($state or ($cursor = $dbh->prepare($stmt)))
        or DbiError($dbh->err, $dbh->errstr);

    Test($state or $cursor->execute)
        or DbiError($cursor->err, $cursor->errstr);

    if ($state) {
        for (1..$rec_num) { Test($state) }
    } else {

    print "Before..\n";
        while (my @res = $cursor->fetchrow_array) {
            print join(", ", @res), "\n";
            Test ($dbh->do(
                "UPDATE ORDERS SET comment = 'Zzzzz...' WHERE
                CURRENT OF $cursor->{CursorName}")
            ) or DbiError($dbh->err, $dbh->errstr);
        }
    }

    Test($state or $cursor = $dbh->prepare(
        "SELECT * FROM $table WHERE user_id < 5"))
        or DbiError($dbh->err, $dbh->errstr);

    Test($state or $cursor->execute)
        or DbiError($cursor->err, $cursor->errstr);

    if ($state) {
        for (1..$rec_num) { Test($state) }
    } else {
        print "After..\n";
        while (@res = $cursor->fetchrow_array) {
            print join(", ", @res), "\n";
            Test($res[1] eq 'Zzzzz...') 
                or DbiError(undef, "Unexpected SELECT result: $res[1]"); 
        }
    }

    #
    #  Drop the test table
    #
    Test($state or ($cursor = $dbh->prepare("DROP TABLE $table")))
    or DbiError($dbh->err, $dbh->errstr);

    Test($state or $cursor->execute)
    or DbiError($cursor->err, $cursor->errstr);


    #  NUM_OF_FIELDS should be zero (Non-Select)
    Test($state or (!$cursor->{'NUM_OF_FIELDS'}))
    or !$verbose or printf("NUM_OF_FIELDS is %s, not zero.\n",
                   $cursor->{'NUM_OF_FIELDS'});

    Test($state or (undef $cursor) or 1);

}
