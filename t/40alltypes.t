#!/usr/local/bin/perl
#
#   $Id: 40alltypes.t 349 2005-09-10 16:55:31Z edpratomo $
#
#   This is a test for all data types handling.
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
my $num_of_fields = 16;

#
#   Include lib.pl
#
use DBI;
use vars qw($verbose $timestamp);

my ($sec, $min, $h, $d, $m, $y) = (localtime())[0..5];
$y += 1900; $m++;
$timestamp = sprintf("%04u-%02u-%02u %02u:%02u", $y, $m, $d, $h, $min);

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
    sub { shift->[0]->[0] == 30000},
    sub { shift->[0]->[1] == 1000},
    sub { shift->[0]->[2] eq 'Edwin        '},
    sub { shift->[0]->[3] eq 'Edwin Pratomo       '},
    sub { shift->[0]->[4] eq 'A string'},
    sub { shift->[0]->[5] == 5000},
    sub { shift->[0]->[6] eq '1.20000004768372'},
    sub { shift->[0]->[7] == 1.44},
    sub { shift->[0]->[8] eq $timestamp},
    sub { shift->[0]->[9] =~ /^\d\d-\d\d-\d{4}$/},
    sub { shift->[0]->[10] =~ /^\d\d:\d\d$/},
    sub { shift->[0]->[11] == 32.71},
    sub { shift->[0]->[12] == -32.71},
    sub { shift->[0]->[13] == 123456.79},
    sub { shift->[0]->[14] == -123456.79},
    sub { shift->[0]->[15] eq '86753090000.868'},
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
    INTEGER_    INTEGER,
    SMALLINT_   SMALLINT,
    CHAR13_     CHAR(13),
    CHAR20_     CHAR(20),
    VARCHAR13_  VARCHAR(13),
    DECIMAL_    DECIMAL,
    FLOAT_      FLOAT,
    DOUBLE_     DOUBLE PRECISION,
    A_TIMESTAMP  TIMESTAMP,
    A_DATE       DATE,
    A_TIME       TIME,
    NUMERIC_AS_SMALLINT  NUMERIC(4,3),
    NUMERIC_AS_SMALLINT2 NUMERIC(4,3),
    NUMERIC_AS_INTEGER   NUMERIC(9,3),
    NUMERIC_AS_INTEGER2  NUMERIC(9,3),
    A_SIXTYFOUR  NUMERIC(18,3)
)
DEF
    };
    Test($state or ($dbh->do($def)))
       or DbiError($dbh->err, $dbh->errstr);

    $state or do { 
        $stmt =<<"END_OF_QUERY";
INSERT INTO $table
    (
    INTEGER_,
    SMALLINT_,
    CHAR13_,
    CHAR20_,
    VARCHAR13_,
    DECIMAL_,
    FLOAT_,
    DOUBLE_,
    A_TIMESTAMP,
    A_DATE,
    A_TIME,
    NUMERIC_AS_SMALLINT,
    NUMERIC_AS_SMALLINT2,
    NUMERIC_AS_INTEGER,
    NUMERIC_AS_INTEGER2,
    A_SIXTYFOUR
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
END_OF_QUERY
    };
    
    Test($state or $cursor = $dbh->prepare($stmt))
       or DbiError($dbh->err, $dbh->errstr);

    Test($state or $cursor->execute(
    30000,
    1000,
    'Edwin',
    'Edwin Pratomo',
    'A string',
    5000,
    1.2,
    1.44,
    $timestamp,
    'TOMORROW',
    'NOW',
    32.71,
    -32.71,
    123456.7895,
    -123456.7895,
    86753090000.8675309)
    ) or DbiError($cursor->err, $cursor->errstr);

    Test($state or $cursor = $dbh->prepare("SELECT * FROM $table", {
        ib_timestampformat => '%Y-%m-%d %H:%M',
        ib_dateformat => '%m-%d-%Y',
        ib_timeformat => '%H:%M',
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
