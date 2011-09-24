#!/usr/local/bin/perl
#
#
#   This is a memory leak test.
#

use strict;
use warnings;

my $COUNT_CONNECT = 500;    # Number of connect/disconnect iterations
my $COUNT_PREPARE = 10000;  # Number of prepare/execute/finish iterations
my $TOTALMEM      = 0;

use Test::More;
use DBI;

plan skip_all => "Long memory leak test (try with MEMORY_TEST on linux)\n"
  unless ( $^O eq 'linux' && $ENV{MEMORY_TEST} );


use lib 't','.';

require 'tests-setup.pl';

my ($dbh, $error_str) = connect_to_database();

if ($error_str) {
    BAIL_OUT("Unknown: $error_str!");
}

unless ( $dbh->isa('DBI::db') ) {
    plan skip_all => 'Connection to database failed, cannot continue testing';
}
else {
    plan tests => 314;
}

ok($dbh, 'Connected to the database');

#DBI->trace(2, "trace.txt");

#
#   Find a possible new table name
#
my $table = find_new_table($dbh);
ok($table, qq{Table is '$table'});

#
#   Create a new table
#
my $def =<<"DEF";
CREATE TABLE $table (
    id     INTEGER NOT NULL PRIMARY KEY,
    name CHAR(64) CHARACTER SET ISO8859_1
)
DEF
ok( $dbh->do($def), qq{CREATE TABLE '$table'} );

my $ok;

#- Testing memory leaks in connect / disconnect

$ok = 0;
my $nok = 0;
for (my $i = 0;  $i < $COUNT_CONNECT;  $i++) {
    my ($dbh2, $error_str2) = connect_to_database();
    if ($error_str2) {
        print "Cannot connect: $error_str2";
        $ok = 0;
        last;
    }
    $dbh2->disconnect();
    undef $dbh2;

    if ($i == 0) {
        $ok = check_mem(1);     # initialize
    }
    elsif ($i % 100  ==  99) {
        $ok = check_mem();
        $nok++ unless $ok;
        ok($ok, "c/d $i");
    }
}
ok($nok == 0, "Memory leak test in connect/disconnect");

#- Testing memory leaks in prepare / execute / finish

# Reconnect, if necessary
unless ($dbh->ping) {
    ($dbh, $error_str) = connect_to_database();
    ok($dbh, 'reConnected to the database');
}

$ok = 0; $nok = 0;
for (my $i = 0;  $i < $COUNT_PREPARE;  $i++) {
    my $sth = $dbh->prepare("SELECT * FROM $table");
    $sth->execute();
    $sth->finish();
    undef $sth;

    if ($i % 100  ==  99) {
        $ok = check_mem();
        $nok++ unless $ok;
        ok($ok, "p/e/f $i");
    }
}
ok($nok == 0, "Memory leak test in prepare/execute/finish");

# Testing memory leaks in fetchrow_arrayref

# Insert some records into the test table
my $row;
foreach $row (
    [1, 'Jochen Wiedmann'],
    [2, 'Andreas König'],
    [3, 'Tim Bunce'],
    [4, 'Alligator Descartes'],
    [5, 'Jonathan Leffler'] )
    {
        $dbh->do(sprintf("INSERT INTO $table VALUES (%d, %s)",
                         $row->[0], $dbh->quote($row->[1])));
}

$ok = 0; $nok =0;
for ( my $i = 0 ; $i < $COUNT_PREPARE ; $i++ ) {
    {
        my $sth = $dbh->prepare("SELECT * FROM $table");
        $sth->execute();
        my $row;
        while ( $row = $sth->fetchrow_arrayref() ) { }
        $sth->finish();
    }

    if ( $i % 100 == 99 ) {
        $ok = check_mem();
        $nok++ unless $ok;
        ok($ok, "f_a $i");
    }
}
ok($nok == 0, "Memory leak test in fetchrow_arrayref");

# Testing memory leaks in fetchrow_hashref

$ok = 0; $nok = 0;
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
        $nok++ unless $ok;
        ok($ok, "f_h $i");
    }
}
ok($nok == 0, "Memory leak test in fetchrow_hashref");

#
#   ... and drop it.
#
ok( $dbh->do(qq{DROP TABLE $table}), qq{DROP TABLE '$table'} );

#
#   Finally disconnect.
#
ok( $dbh->disconnect, 'Disconnect' );


#-- Stolen from Matt Sergeant's XML::LibXML's memory.t

sub check_mem {
    my $initialise = shift;

    # Log Memory Usage
    local $^W;
    my %mem;
    if ( open( FH, "/proc/self/status" ) ) {
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

        if ( $TOTALMEM != $mem{Total} ) {
            warn( "LEAK! : ", $mem{Total} - $TOTALMEM, " $units\n" )
              unless $initialise;
            $TOTALMEM = $mem{Total};
            return 0;
        }

        print(
            "# Mem Total: $mem{Total} $units, Resident: $mem{Resident} $units\n"
        );
        return 1;
    }
}
