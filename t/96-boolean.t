#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use DBI;

use lib 't','.';

use TestFirebird;
my $T = TestFirebird->new;

my ( $dbh, $error_str ) = $T->connect_to_database( { ChopBlanks => 1 } );

if ($error_str) {
    BAIL_OUT("Unknown: $error_str!");
}

unless ( $dbh->isa('DBI::db') ) {
    plan skip_all => 'Connection to database failed, cannot continue testing';
}
else {
    my $orig_ver = $dbh->func(version => 'ib_database_info')->{version};
    (my $ver = $orig_ver) =~ s/.*\bFirebird\s*//;

    if ($ver =~ /^(\d+)\.(\d+)$/) {
        if ($1 >= 3) {
            plan tests => 23;
        }
        else {
            plan skip_all =>
                "Firebird version $1.$2 doesn't support BOOLEAN data type";
        }
    }
    else {
        plan skip_all =>
            "Unable to determine Firebird version from '$orig_ver'. Assuming no BOOLEAN support";
    }
}

ok($dbh, 'Connected to the database');

# DBI->trace(4, "trace.txt");

# ------- TESTS ------------------------------------------------------------- #

#
#   Find a possible new table name
#
my $table = find_new_table($dbh);
ok($table, "TABLE is '$table'");

# Expected fetched values
# Need to store the decimal precision for 'sprintf'
# Prec must also be the same in CREATE TABLE, of course

my $expected = {
    A_BOOLEAN => {
        test => {
            0 => 1,
            1 => undef,
            2 => 0,
            3 => 1,
            4 => 1,
            5 => 1,
            6 => 1,
        },
    },
};

#
#   Create a new table
#

my $def =<<"DEF";
CREATE TABLE $table (
    a_boolean BOOLEAN
)
DEF
ok( $dbh->do($def), qq{CREATE TABLE '$table'} );

#
#   Insert some values
#

my $stmt =<<"END_OF_QUERY";
INSERT INTO $table (
    a_boolean
) VALUES (?)
END_OF_QUERY

ok(my $insert = $dbh->prepare($stmt), 'PREPARE INSERT');

# Insert positive number
ok($insert->execute(1),
   'INSERT 1 BOOLEAN VALUE'
);

# Insert undef
ok($insert->execute(undef),
   'INSERT NULL BOOLEAN VALUE'
);

# Insert zero number
ok($insert->execute(0),
   'INSERT ZERO BOOLEAN VALUE'
);

# Insert a number greater than 1 (should still be "true")
ok($insert->execute(2),
   'INSERT "2" BOOLEAN VALUE'
);

# Insert negative number (should still be "true")
ok($insert->execute(-1),
   'INSERT -1 BOOLEAN VALUE'
);

# Insert another negative number (should still be "true")
ok($insert->execute(-2),
   'INSERT -2 BOOLEAN VALUE'
);

# Insert positive number
ok($insert->execute(1),
   'INSERT 1 BOOLEAN VALUE (AGAIN)'
);



#
#   Select the values
#
ok( my $cursor = $dbh->prepare( qq{SELECT * FROM $table}, ), 'PREPARE SELECT' );

ok($cursor->execute, 'EXECUTE SELECT');

ok((my $res = $cursor->fetchall_arrayref), 'FETCHALL arrayref');

my ($types, $names, $fields) = @{$cursor}{qw(TYPE NAME NUM_OF_FIELDS)};

for (my $i = 0; $i < @$res; $i++) {
    for (my $j = 0; $j < $fields; $j++) {
        my $result = $res->[$i][$j];
        my $corect = $expected->{$names->[$j]}{test}{$i};
        if (defined($corect)) {
            ok(
                !($result xor $corect),
                "Test $i, Field: $names->[$j], value '$res' matches expected '$corect'"
            );
        }
        else {
            is($result, $corect, "Test $i, Field: $names->[$j]");
        }
    }
}

#
#  Drop the test table
#
$dbh->{AutoCommit} = 1;

ok( $dbh->do("DROP TABLE $table"), "DROP TABLE '$table'" );

#
#   Finally disconnect.
#
ok($dbh->disconnect, 'DISCONNECT');
