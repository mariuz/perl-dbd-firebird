#!/usr/local/bin/perl
#
#   $Id: 41numeric.t 349 2005-09-10 16:55:31Z edpratomo $
#
#   This is a test for INT64 type.
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
my $num_of_tests = 15;

#
#   Include lib.pl
#
use DBI;
use vars qw($verbose);

#DBI->trace(2, "41numeric.txt");

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

# expected fetched values
my @correct = (
    [ 123456.79, 86753090000.868, 11 ],
    [ -123456.79, -86753090000.868, -11],
    [ 123456.001, 80.080, 10],
    [ -123456.001, -80.080, 0],
    [ 10.9, 10.9, 11],
);

sub is_match {
    my ($result, $row, $fieldno) = @_;
    $result->[$row]->[$fieldno] == $correct[$row]->[$fieldno];
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
    NUMERIC_AS_INTEGER NUMERIC(9,3),
    NUMERIC_THREE_DIGITS  NUMERIC(18,3),
    NUMERIC_NO_DIGITS NUMERIC(10,0)
)
DEF
    };
    Test($state or ($dbh->do($def)))
       or DbiError($dbh->err, $dbh->errstr);

    $state or do {
        $stmt =<<"END_OF_QUERY";
INSERT INTO $table
    (
    NUMERIC_AS_INTEGER,
    NUMERIC_THREE_DIGITS,
    NUMERIC_NO_DIGITS
    )
    VALUES (?, ?, ?)
END_OF_QUERY
    };

    Test($state or $cursor = $dbh->prepare($stmt))
       or DbiError($dbh->err, $dbh->errstr);

    # insert positive numbers
    Test($state or $cursor->execute(
    123456.7895,
    86753090000.8675309,
    10.9)
    ) or DbiError($cursor->err, $cursor->errstr);

    # insert negative numbers
    Test($state or $cursor->execute(
    -123456.7895,
    -86753090000.8675309,
    -10.9)
    ) or DbiError($cursor->err, $cursor->errstr);

    # insert with some variations in the precision part
    Test($state or $cursor->execute(
    123456.001,
    80.080,
    10.0)
    ) or DbiError($cursor->err, $cursor->errstr);

    Test($state or $cursor->execute(
    -123456.001,
    -80.080,
    -0.0)
    ) or DbiError($cursor->err, $cursor->errstr);

    Test($state or $cursor->execute(
    10.9,
    10.9,
    10.9)
    ) or DbiError($cursor->err, $cursor->errstr);

    # select..
    Test($state or $cursor = $dbh->prepare("SELECT * FROM $table")
    ) or DbiError($dbh->err, $dbh->errstr);

    Test($state or $cursor->execute)
        or DbiError($cursor->err, $cursor->errstr);

    Test($state or ($res = $cursor->fetchall_arrayref))
        or DbiError($cursor->err, $cursor->errstr);
    
    if (!$state) {
        my ($types, $names, $fields) = @{$cursor}{TYPE, NAME, NUM_OF_FIELDS};

        for (my $i = 0; $i < @$res; $i++) {
            for (my $j = 0; $j < $fields; $j++) {
                Test($state or ( is_match($res, $i, $j) ))
                    or DbiError(undef,
                    "wrong SELECT result for row $i, field $names->[$j]: '$res->[$i]->[$j], expected: $correct[$i]->[$j]'");
            }
        }

    } else {
        for (1..$num_of_tests) { Test($state) }
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
