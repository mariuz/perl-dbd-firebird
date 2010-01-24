#!/usr/local/bin/perl
#
#   $Id: 40blobs.t 326 2005-01-13 23:32:29Z danielritz $
#
#   This is a test for correct handling of BLOBS; namely $dbh->quote
#   is expected to work correctly.
#


#
#   Make -w happy
#
$test_dsn = '';
$test_user = '';
$test_password = '';


#
#   Include lib.pl
#
require DBI;
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
if ($dbdriver eq 'mSQL'  ||  $dbdriver eq 'mSQL1') {
    print "1..0\n";
    exit 0;
}

sub ServerError() {
    my $err = $DBI::errstr; # Hate -w ...
    print STDERR ("Cannot connect: ", $DBI::errstr, "\n",
    "\tEither your server is not up and running or you have no\n",
    "\tpermissions for acessing the DSN $test_dsn.\n",
    "\tThis test requires a running server and write permissions.\n",
    "\tPlease make sure your server is running and you have\n",
    "\tpermissions, then retry.\n");
    exit 10;
}


sub ShowBlob($) {
    my ($blob) = @_;
    for($i = 0;  $i < 8;  $i++) {
    if (defined($blob)  &&  length($blob) > $i) {
        $b = substr($blob, $i*32);
    } else {
        $b = "";
    }
    printf("%08lx %s\n", $i*32, unpack("H64", $b));
    }
}


#
#   Main loop; leave this untouched, put tests after creating
#   the new table.
#
while (Testing()) {
    #
    #   Connect to the database
    Test($state or $dbh = DBI->connect($test_dsn, $test_user,
$test_password,
 {LongReadLen => 5 * 256}))
    or ServerError();

    #
    #   Find a possible new table name
    #
    Test($state or $table = FindNewTable($dbh))
       or DbiError($dbh->error, $dbh->errstr);

    my($def);
    foreach $size (1..5) {
    #
    #   Create a new table
    #
    if (!$state) {
        $def = TableDefinition($table,
                   ["id",   "INTEGER",      4, 0],
                   ["name", "BLOB",         1, 0]);
        print "Creating table:\n$def\n";
    }
    Test($state or $dbh->do($def))
        or DbiError($dbh->err, $dbh->errstr);

    $dbh->{AutoCommit} = 0;

    #
    #  Create a blob
    #
    my ($blob, $qblob) = "";
    if (!$state) {
        my $b = "";
        for ($j = 0;  $j < 256;  $j++) {
            $b .= chr($j);
        }
        for ($i = 0;  $i < $size;  $i++) {
            $blob .= $b;
        }
    }

    #
    #   Insert a row into the test table.......
    #
    my($query);
    if (!$state) {
        $query = "INSERT INTO $table VALUES(?, ?)";
        if ($ENV{'SHOW_BLOBS'}  &&  open(OUT, ">" . $ENV{'SHOW_BLOBS'})) {
        print OUT $query;
        close(OUT);
        }
    }
    Test($state or $cursor = $dbh->prepare($query))
           or DbiError($dbh->err, $dbh->errstr);

    for (my $i = 0; $i < 10; $i++)
    {
        Test($state or $cursor->execute($i, $blob))
            or DbiError($dbh->err, $dbh->errstr);
    }

    #
    #   Now, try SELECT'ing the row out.
    #
    Test($state or $cursor2 = $dbh->prepare("SELECT * FROM $table"
                           . " WHERE id < 10 ORDER BY id;"))
           or DbiError($dbh->err, $dbh->errstr);

    Test($state or $cursor2->execute())
        or DbiError($dbh->err, $dbh->errstr);

    for (my $i = 0; $i < 10; $i++)
    {
        Test($state or (defined($row = $cursor2->fetchrow_arrayref)))
            or DbiError($cursor2->err, $cursor2->errstr);

        Test($state or (@$row == 2  &&  $$row[0] == $i  &&  $$row[1] eq $blob))
            or (ShowBlob($blob),
            ShowBlob(defined($$row[1]) ? $$row[1] : ""));

        if ($i >= 5)
        {
            Test($state or $cursor->execute($i + 10, $blob));
        }
    }

    Test($state or $cursor2->finish)
        or DbiError($cursor2->err, $cursor2->errstr);

    Test($state or $cursor->finish)
        or DbiError($cursor->err, $cursor->errstr);


    Test($state or undef $cursor2 || 1)
        or DbiError($cursor2->err, $cursor2->errstr);

    Test($state or undef $cursor || 1)
        or DbiError($cursor->err, $cursor->errstr);

    #
    #   Finally drop the test table.
    #
    $dbh->{AutoCommit} = 1;

    Test($state or $dbh->do("DROP TABLE $table"))
        or DbiError($dbh->err, $dbh->errstr);
    }
}
