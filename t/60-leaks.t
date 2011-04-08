#!/usr/local/bin/perl
#
#   $Id: 60leaks.t 291 2003-05-20 02:43:57Z edpratomo $
#
#   This is a memory leak test.
#

BEGIN {
    $^W = 1;

    $COUNT_CONNECT = 500;    # Number of connect/disconnect iterations
    $COUNT_PREPARE = 10000;  # Number of prepare/execute/finish iterations
    $TOTALMEM   = 0;
}

print "1..0 # Skipped: Long running memory leak test\n" and exit 0
  unless ( $^O eq 'linux' && $ENV{MEMORY_TEST} );

#use strict;

use Test::More;
use DBI;

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
    plan tests => 11;
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

my($size, $prevSize, $ok, $dbh2, $msg);

#- Testing memory leaks in connect / disconnect

$ok = 0;
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
        ok($ok);
    }
}
ok($ok > 0, "Memory leak test in connect/disconnect");

#- Testing memory leaks in prepare / execute / finish

# # reconnect, if necessary
# unless ($dbh->ping) {
#     $dbh = DBI->connect($test_dsn, $test_user, $test_password)
#         or ServerError();
# }

# for (my $i = 0;  $i < $COUNT_PREPARE;  $i++) {
#     my $sth = $dbh->prepare("SELECT * FROM $table");
#     $sth->execute();
#     $sth->finish();
#     undef $sth;

#     if ($i % 100  ==  99) {
#         $ok = check_mem();
#     }
# }

# # Testing memory leaks in fetchrow_arrayref

# # Insert some records into the test table
# my $row;
# foreach $row (
#     [1, 'Jochen Wiedmann'],
#     [2, 'Andreas K�nig'],
#     [3, 'Tim Bunce'],
#     [4, 'Alligator Descartes'],
#     [5, 'Jonathan Leffler'])
#     {
#         $dbh->do(sprintf("INSERT INTO $table VALUES (%d, %s)",
#                          $row->[0], $dbh->quote($row->[1])));
#     }

# $ok = 0;
# $notOk = 0;
# undef $prevSize;

#         for (my $i = 0;  $i < $COUNT_PREPARE;  $i++)
#         {
#             {
#                 my $sth = $dbh->prepare("SELECT * FROM $table");
#                 $sth->execute();
#                 my $row;
#                 while ($row = $sth->fetchrow_arrayref()) { }
#                 $sth->finish();
#             }

#             if ($i % 100  ==  99) {
#                 $ok = check_mem();
#             }
#         }
#     }
#     Test($state or ($ok > $notOk))
#     or print "$msg\n";


#     if (!$state) {
#         print "Testing memory leaks in fetchrow_hashref\n";
#         $msg = "Possible memory leak in fetchrow_hashref detected";

#         $ok = 0;
#         $notOk = 0;
#         undef $prevSize;

#         for (my $i = 0;  $i < $COUNT_PREPARE;  $i++) {
#             {
#                 my $sth = $dbh->prepare("SELECT * FROM $table");
#                 $sth->execute();
#                 my $row;
#                 while ($row = $sth->fetchrow_hashref()) { }
#                 $sth->finish();
#             }

#             if ($i % 100  ==  99) {
#                 $ok = check_mem();
#             }
#         }
#     }
#     Test($state or ($ok > $notOk))
#     or print "$msg\n";

#
#   ... and drop it.
#
ok( $dbh->do(qq{DROP TABLE $table}), qq{DROP TABLE '$table'} );

#
#   Finally disconnect.
#
ok( $dbh->disconnect );

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
