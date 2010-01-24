#!/usr/local/bin/perl
#
#   $Id: 60leaks.t 291 2003-05-20 02:43:57Z edpratomo $
#
#   This is a memory leak test.
#

BEGIN { 
    $^W = 1;

    $COUNT_CONNECT = 500;   # Number of connect/disconnect iterations
    $COUNT_PREPARE = 10000;  # Number of prepare/execute/finish iterations
    $TOTALMEM   = 0;

    #
    #   Make -w happy
    #
    $test_dsn = '';
    $test_user = '';
    $test_password = '';
}


print "1..0 # Skipped: Long running memory leak test\n" and exit 0 unless ($^O eq 'linux' && $ENV{MEMORY_TEST});

#
#   Include lib.pl
#
use DBI;

#DBI->trace(2, "trace.txt");

$mdriver = "";
foreach $file ("lib.pl", "t/lib.pl", "DBD-~~dbd_driver~~/t/lib.pl") {
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

#
#   Main loop; leave this untouched, put tests after creating
#   the new table.
#

while (Testing()) {
    #
    #   Connect to the database
    Test($state or $dbh = DBI->connect($test_dsn, $test_user, $test_password))
    or ServerError();

    #
    #   Find a possible new table name
    #
    Test($state or $table = FindNewTable($dbh))
       or DbiError($dbh->err, $dbh->errstr);

    #
    #   Create a new table; EDIT THIS!
    #
    Test($state or ($def = TableDefinition($table,
                      ["id",   "INTEGER",  4, 0],
                      ["name", "CHAR",    64, 0]),
            $dbh->do($def)))
       or DbiError($dbh->err, $dbh->errstr);

    my($size, $prevSize, $ok, $notOk, $dbh2, $msg);

    if (!$state) {
        print "Testing memory leaks in connect/disconnect\n";
        $msg = "Possible memory leak in connect/disconnect detected";

        $ok = 0;
        $notOk = 0;

        for (my $i = 0;  $i < $COUNT_CONNECT;  $i++) {
            if (!($dbh2 = DBI->connect($test_dsn, $test_user,
                       $test_password))) 
            {
                $ok = 0;
                $msg = "Cannot connect: $DBI::errstr\n";
                last;
            }
            $dbh2->disconnect();
            undef $dbh2;

            if ($i == 0) {
                $ok = check_mem(1);     # initialize
            }
            elsif ($i % 100  ==  99) {
                $ok = check_mem();
            }
        }
    }
    Test($state or ($ok > $notOk))
    or print "$msg\n";


    if (!$state) {
        print "Testing memory leaks in prepare/execute/finish\n";
        $msg = "Possible memory leak in prepare/execute/finish detected";

        $ok = 0;
        $notOk = 0;
        undef $prevSize;

        # reconnect, if necessary
        unless ($dbh->ping) {
            $dbh = DBI->connect($test_dsn, $test_user, $test_password)
                or ServerError();
        }

        for (my $i = 0;  $i < $COUNT_PREPARE;  $i++) {
            my $sth = $dbh->prepare("SELECT * FROM $table");
            $sth->execute();
            $sth->finish();
            undef $sth;

            if ($i % 100  ==  99) {
                $ok = check_mem();
            }
        }
    }
    Test($state or ($ok > $notOk))
    or print "$msg\n";


    if (!$state) {
        print "Testing memory leaks in fetchrow_arrayref\n";
        $msg = "Possible memory leak in fetchrow_arrayref detected";

        # Insert some records into the test table
        my $row;
        foreach $row (
                    [1, 'Jochen Wiedmann'],
                    [2, 'Andreas König'],
                    [3, 'Tim Bunce'],
                    [4, 'Alligator Descartes'],
                    [5, 'Jonathan Leffler']) 
        {
            $dbh->do(sprintf("INSERT INTO $table VALUES (%d, %s)",
                 $row->[0], $dbh->quote($row->[1])));
        }

        $ok = 0;
        $notOk = 0;
        undef $prevSize;

        for (my $i = 0;  $i < $COUNT_PREPARE;  $i++) 
        {
            {
                my $sth = $dbh->prepare("SELECT * FROM $table");
                $sth->execute();
                my $row;
                while ($row = $sth->fetchrow_arrayref()) { }
                $sth->finish();
            }

            if ($i % 100  ==  99) {
                $ok = check_mem();
            }
        }
    }
    Test($state or ($ok > $notOk))
    or print "$msg\n";


    if (!$state) {
        print "Testing memory leaks in fetchrow_hashref\n";
        $msg = "Possible memory leak in fetchrow_hashref detected";

        $ok = 0;
        $notOk = 0;
        undef $prevSize;

        for (my $i = 0;  $i < $COUNT_PREPARE;  $i++) {
            {
                my $sth = $dbh->prepare("SELECT * FROM $table");
                $sth->execute();
                my $row;
                while ($row = $sth->fetchrow_hashref()) { }
                $sth->finish();
            }

            if ($i % 100  ==  99) {
                $ok = check_mem();
            }
        }
    }
    Test($state or ($ok > $notOk))
    or print "$msg\n";


    Test($state or $dbh->do("DROP TABLE $table"))
    or DbiError($dbh->err, $dbh->errstr);

}


# stolen from Matt Sergeant's XML::LibXML's memory.t 
sub check_mem {
    my $initialise = shift;
    # Log Memory Usage
    local $^W;
    my %mem;
    if (open(FH, "/proc/self/status")) {
        my $units;
        while (<FH>) {
            if (/^VmSize.*?(\d+)\W*(\w+)$/) {
                $mem{Total} = $1;
                $units = $2;
            }
            if (/^VmRSS:.*?(\d+)/) {
                $mem{Resident} = $1;
            }
        }
        close FH;

        if ($TOTALMEM != $mem{Total}) {
            warn("LEAK! : ", $mem{Total} - $TOTALMEM, " $units\n") unless $initialise;
            $TOTALMEM = $mem{Total};
            return 0;
        }

        print("# Mem Total: $mem{Total} $units, Resident: $mem{Resident} $units\n");
        return 1;
    }
}
