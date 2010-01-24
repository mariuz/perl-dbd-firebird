#!/usr/local/bin/perl
#
#   $Id: 40datetime.t 380 2007-05-20 15:18:40Z edpratomo $
#
#   This is a test for date/time types handling with localtime() style.
#

sub find_new_table {
    my $dbh = shift;
    my $try_name = 'TESTAA';
    my %tables = map { uc($_) => 1 } $dbh->tables;
    while (exists $tables{$try_name}) {
        ++$try_name;
    }
    $try_name;
}

#
#   Make -w happy
#
$test_dsn = '';
$test_user = '';
$test_password = '';

# hmm this must be known prior to test. ugly...
my $num_of_fields = 3;

#
#   Include lib.pl
#
use DBI;
use vars qw($verbose @times);

@times = localtime();

#DBI->trace(5, "40alltypes.txt");

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

my @is_match = (
    sub
    {
        my $ref = shift->[0]->[0];
        return ($$ref[0] == $times[0]) &&
               ($$ref[1] == $times[1]) &&
               ($$ref[2] == $times[2]) &&
               ($$ref[3] == $times[3]) &&
               ($$ref[4] == $times[4]) &&
               ($$ref[5] == $times[5]);
    },
    sub
    {
        my $ref = shift->[0]->[1];
        return ($$ref[3] == $times[3]) &&
               ($$ref[4] == $times[4]) &&
               ($$ref[5] == $times[5]);
    },
    sub
    {
        my $ref = shift->[0]->[2];
        return ($$ref[0] == $times[0]) &&
               ($$ref[1] == $times[1]) &&
               ($$ref[2] == $times[2]);
    }
);

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
    # Test($state or $table = FindNewTable($dbh))
    #   or DbiError($dbh->err, $dbh->errstr);

    #
    #   Create a new table
    #

    my ($def, $table, $stmt);
    $state or do {
        $table = find_new_table($dbh);
        $def =<<"DEF";
CREATE TABLE $table (
    A_TIMESTAMP  TIMESTAMP,
    A_DATE       DATE,
    A_TIME       TIME
)
DEF
    };
    Test($state or ($dbh->do($def)))
       or DbiError($dbh->err, $dbh->errstr);

    $state or do {
        $stmt =<<"END_OF_QUERY";
INSERT INTO $table
    (
    A_TIMESTAMP,
    A_DATE,
    A_TIME
    )
    VALUES (?, ?, ?)
END_OF_QUERY
    };
    
    Test($state or $cursor = $dbh->prepare($stmt))
       or DbiError($dbh->err, $dbh->errstr);

    Test($state or $cursor->execute(
    \@times, \@times, \@times)
    ) or DbiError($cursor->err, $cursor->errstr);

    Test($state or $cursor = $dbh->prepare("SELECT * FROM $table", {
        ib_timestampformat => 'TM',
        ib_dateformat => 'TM',
        ib_timeformat => 'TM',
    })) or DbiError($dbh->err, $dbh->errstr);

    Test($state or $cursor->execute)
        or DbiError($cursor->err, $cursor->errstr);

    Test($state or ($res = $cursor->fetchall_arrayref))
        or DbiError($cursor->err, $cursor->errstr);
    
    if (!$state) {
        my ($types, $names, $fields) = @{$cursor}{TYPE, NAME, NUM_OF_FIELDS};

        for (my $i = 0; $i < $fields; $i++) {
            Test($state or ( $is_match[$i]->($res) ))
                or DbiError(undef,
                "wrong SELECT result for field $names->[$i]: $res->[0]->[$i]");
        }

    } else {
        for (1..$num_of_fields) { Test($state) }
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
