#!/usr/bin/perl
#
#   Test for TIMESTAMP WITH TIME ZONE and TIME WITH TIME ZONE support
#   (Firebird 4.0+ feature).
#
#   Inspired by Jaybird JDBC driver tests:
#   https://github.com/FirebirdSQL/jaybird/commits/master/
#

use strict;
use warnings;

use Test::More;
use DBI qw(:sql_types);

use lib 't', '.';

use TestFirebird;
my $T = TestFirebird->new;

my ( $dbh, $error_str ) = $T->connect_to_database( { ChopBlanks => 1 } );

if ($error_str) {
    BAIL_OUT("Unknown: $error_str!");
}

unless ( $dbh->isa('DBI::db') ) {
    plan skip_all => 'Connection to database failed, cannot continue testing';
}

# Check Firebird server version - TIMESTAMP WITH TIME ZONE requires FB 4.0+
my $orig_ver = $dbh->func( version => 'ib_database_info' )->{version};
( my $ver = $orig_ver ) =~ s/.*\bFirebird\s*//;

if ( $ver =~ /^(\d+)\.(\d+)/ ) {
    my ( $major, $minor ) = ( $1, $2 );
    if ( $major < 4 ) {
        plan skip_all =>
            "Firebird $major.$minor does not support TIMESTAMP/TIME WITH TIME ZONE (requires 4.0+)";
    }
}
else {
    plan skip_all =>
        "Unable to determine Firebird version from '$orig_ver'. Assuming no TIMESTAMP WITH TIME ZONE support";
}

plan tests => 30;

ok( $dbh, 'Connected to the database' );

# ------- TESTS ------------------------------------------------------------- #

my $table = find_new_table($dbh);
ok( $table, "TABLE is '$table'" );

#
# Create a test table with TIMESTAMP WITH TIME ZONE and TIME WITH TIME ZONE
#
my $def = <<"DEF";
CREATE TABLE $table (
    ID              INTEGER,
    A_TIMESTAMP_TZ  TIMESTAMP WITH TIME ZONE,
    A_TIME_TZ       TIME WITH TIME ZONE
)
DEF

ok( $dbh->do($def), qq{CREATE TABLE '$table'} );

#
# Insert test values with various timezone offsets
#
my $insert_sql = <<"END_SQL";
INSERT INTO $table (ID, A_TIMESTAMP_TZ, A_TIME_TZ) VALUES (?, ?, ?)
END_SQL

ok( my $insert = $dbh->prepare($insert_sql), 'PREPARE INSERT' );

# Insert a timestamp with positive offset (UTC+05:30, India)
ok(
    $insert->execute(
        1,
        '2020-01-01 12:00:00.0000 +05:30',
        '12:00:00.0000 +05:30'
    ),
    'INSERT row 1: UTC+05:30 offset'
);

# Insert a timestamp with negative offset (UTC-05:00, Eastern US)
ok(
    $insert->execute(
        2,
        '2020-02-15 20:00:00.0000 -05:00',
        '20:00:00.0000 -05:00'
    ),
    'INSERT row 2: UTC-05:00 offset'
);

# Insert a timestamp with UTC offset (UTC+00:00)
ok(
    $insert->execute(
        3,
        '2020-06-15 00:00:00.0000 +00:00',
        '00:00:00.0000 +00:00'
    ),
    'INSERT row 3: UTC+00:00 offset'
);

# Insert NULL values
ok(
    $insert->execute( 4, undef, undef ),
    'INSERT row 4: NULL values'
);

#
# Select and verify with ISO format (default TZ format)
#
ok(
    my $cursor = $dbh->prepare(
        "SELECT ID, A_TIMESTAMP_TZ, A_TIME_TZ FROM $table ORDER BY ID",
        {
            ib_timestampformat => 'ISO',
            ib_timeformat      => 'ISO',
        }
    ),
    'PREPARE SELECT (ISO format)'
);

ok( $cursor->execute, 'EXECUTE SELECT (ISO format)' );
ok( my $res = $cursor->fetchall_arrayref, 'FETCHALL arrayref (ISO format)' );

is( scalar(@$res), 4, '4 rows returned' );

# Row 1: UTC+05:30 - stored as UTC 06:30, displayed as 12:00 +05:30
like(
    $res->[0][1],
    qr/^2020-01-01 12:00:00\.0000 \+05:30$/,
    'Row 1 TIMESTAMP_TZ ISO format: 2020-01-01 12:00:00.0000 +05:30'
);
like(
    $res->[0][2],
    qr/^12:00:00\.0000 \+05:30$/,
    'Row 1 TIME_TZ ISO format: 12:00:00.0000 +05:30'
);

# Row 2: UTC-05:00 - stored as UTC 01:00 next day, displayed as 20:00 -05:00
like(
    $res->[1][1],
    qr/^2020-02-15 20:00:00\.0000 -05:00$/,
    'Row 2 TIMESTAMP_TZ ISO format: 2020-02-15 20:00:00.0000 -05:00'
);
like(
    $res->[1][2],
    qr/^20:00:00\.0000 -05:00$/,
    'Row 2 TIME_TZ ISO format: 20:00:00.0000 -05:00'
);

# Row 3: UTC+00:00
like(
    $res->[2][1],
    qr/^2020-06-15 00:00:00\.0000 \+00:00$/,
    'Row 3 TIMESTAMP_TZ ISO format: 2020-06-15 00:00:00.0000 +00:00'
);
like(
    $res->[2][2],
    qr/^00:00:00\.0000 \+00:00$/,
    'Row 3 TIME_TZ ISO format: 00:00:00.0000 +00:00'
);

# Row 4: NULL values
is( $res->[3][1], undef, 'Row 4 TIMESTAMP_TZ is NULL' );
is( $res->[3][2], undef, 'Row 4 TIME_TZ is NULL' );

#
# Select with TM format (localtime-style array with offset)
#
ok(
    my $cursor_tm = $dbh->prepare(
        "SELECT ID, A_TIMESTAMP_TZ, A_TIME_TZ FROM $table WHERE ID = 1",
        {
            ib_timestampformat => 'TM',
            ib_timeformat      => 'TM',
        }
    ),
    'PREPARE SELECT (TM format)'
);

ok( $cursor_tm->execute, 'EXECUTE SELECT (TM format)' );
ok( my $res_tm = $cursor_tm->fetchall_arrayref, 'FETCHALL arrayref (TM format)' );

my $ts_tm = $res_tm->[0][1];
ok( ref($ts_tm) eq 'ARRAY', 'TIMESTAMP_TZ TM format returns array reference' );

# TM array: [sec, min, hour, mday, mon, year, wday, yday, isdst, fpsec, offset_min]
# For 2020-01-01 12:00:00.0000 +05:30:
#   offset_minutes = +330 (5*60 + 30)
#   local time: 12:00:00
is( $ts_tm->[2], 12,  'TIMESTAMP_TZ TM: hour = 12' );
is( $ts_tm->[1], 0,   'TIMESTAMP_TZ TM: min = 0' );
is( $ts_tm->[0], 0,   'TIMESTAMP_TZ TM: sec = 0' );
is( $ts_tm->[10], 330, 'TIMESTAMP_TZ TM: offset = +330 minutes (+05:30)' );

#
# Drop the test table
#
$dbh->{AutoCommit} = 1;
ok( $dbh->do("DROP TABLE $table"), "DROP TABLE '$table'" );

#
# Disconnect
#
ok( $dbh->disconnect, 'DISCONNECT' );
