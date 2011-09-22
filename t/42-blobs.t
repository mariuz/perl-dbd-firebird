#!/usr/local/bin/perl
#
#
#   This is a test for correct handling of BLOBS; namely $dbh->quote
#   is expected to work correctly.
#

# 2011-01-29 stefansbv
# New version based on t/testlib.pl and Firebird.dbtest

use strict;
use warnings;

use Test::More;
use DBI qw(:sql_types);

use lib 't','.';

require 'tests-setup.pl';

my ( $dbh, $error_str ) =
  connect_to_database( { ChopBlanks => 1, LongReadLen => 524288, } );

if ($error_str) {
    BAIL_OUT("Unknown: $error_str!");
}

unless ( $dbh->isa('DBI::db') ) {
    plan skip_all => 'Connection to database failed, cannot continue testing';
}
else {
    plan tests => 262;
}

ok($dbh, 'Connected to the database');

# ------- TESTS ------------------------------------------------------------- #

#
#   Find a possible new table name
#
my $table = find_new_table($dbh);
#diag $table;
ok($table);

# Repeat test?
foreach my $size ( 1 .. 5 ) {

    #
    #   Create a new table
    #
    my $def = qq{
CREATE TABLE $table (
    id   INTEGER NOT NULL PRIMARY KEY,
    name BLOB
)
};
    ok( $dbh->do($def), qq{CREATE TABLE '$table'} );

    $dbh->{AutoCommit} = 0;

    #
    #  Create a blob
    #
    my $blob = q{};    # Empty

    my $b = "";
    for ( my $j = 0 ; $j < 256 ; $j++ ) {
        $b .= chr($j);
    }
    for ( my $i = 0 ; $i < $size ; $i++ ) {
        $blob .= $b;
    }

    #
    #   Insert a row into the test table.......
    #
    my ($query);

    my $sql_insert = "INSERT INTO $table VALUES(?, ?)";

    # if ($ENV{'SHOW_BLOBS'}  &&  open(OUT, ">" . $ENV{'SHOW_BLOBS'})) {
    #     print OUT $query;
    #     close(OUT);
    # }

    ok( my $cursor = $dbh->prepare($sql_insert), 'PREPARE INSERT blobs' );

    # Insert 10 rows
    for ( my $i = 0 ; $i < 10 ; $i++ ) {
        ok( $cursor->execute( $i, $blob ), "EXECUTE INSERT row $i" );
    }

    #
    #   Now, try SELECT'ing the row out.
    #

    my $sql_sele = qq{SELECT * FROM $table WHERE id < 10 ORDER BY id};
    ok( my $cursor2 = $dbh->prepare($sql_sele), 'PREPARE SELECT blobs' );

    ok( $cursor2->execute(), "EXECUTE SELECT blobs" );

    for ( my $i = 0 ; $i < 10 ; $i++ ) {
        ok( ( my $row = $cursor2->fetchrow_arrayref ), 'FETCHROW' );

        is( $$row[0], $i,    'ID matches' );
        is( $$row[1], $blob, 'BLOB matches' );

        # Some supplementary inserts
        if ( $i >= 5 ) {
            my $id = $i + 10;
            ok( $cursor->execute( $id, $blob ), "EXECUTE INSERT $id" );
        }
    }

    ok( $cursor2->finish );
    ok( $cursor->finish );

    #
    #   Finally drop the test table.
    #
    $dbh->{AutoCommit} = 1;

    ok( $dbh->do("DROP TABLE $table"), "DROP TABLE '$table'" );

}                                            # repeat test

#- end test
