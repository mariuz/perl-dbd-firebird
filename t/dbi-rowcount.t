#/usr/bin/perl

# dbi-rowcount.t
#
# Verify behavior of interfaces which report number of rows affected

use strict;
use warnings;
use Test::More;
use DBI;
use vars qw($dbh $table);

BEGIN {
        require 't/tests-setup.pl';
}
END {
       if (defined $dbh and defined $table) {
               eval { $dbh->do("DROP TABLE $table"); };
       }
}

# is() with special case "zero but true" support
sub is_maybe_zbt {
       my ($value, $expected) = @_;
       return ($value == $expected) unless $expected == 0;

       return (($value == 0 and $value));
}

# == Test Initialization =========================================

plan tests => 84;

($dbh) = connect_to_database({RaiseError => 1});
pass("connect");
$table = find_new_table($dbh);
$dbh->do("CREATE TABLE $table(ID INTEGER NOT NULL, NAME VARCHAR(16) NOT NULL)");
pass("CREATE TABLE $table");

my @TEST_PROGRAM = (
       {
               sql      => qq|INSERT INTO $table (ID, NAME) VALUES (1, 'unu')|,
               desc     => 'literal insert',
               expected => 1,
       },
       {
               sql      => qq|INSERT INTO $table (ID, NAME) VALUES (?, ?)|,
               desc     => 'parameterized insert',
               params   => [2, 'du'],
               expected => 1,
       },
       {
               sql      => qq|DELETE FROM $table WHERE 1=0|,
               desc     => 'DELETE WHERE (false)',
               expected => 0,
       },
       {
               sql      => qq|UPDATE $table SET NAME='nomo'|,
               desc     => 'UPDATE all',
               expected => 2,
       },
       {
               sql      => qq|DELETE FROM $table|,
               desc     => 'DELETE all',
               expected => 2,
       },
);

# == Tests ==

# == 1. do()

for my $spec (@TEST_PROGRAM) {
       my @bind = @{$spec->{params}} if $spec->{params};
       my $rv = $dbh->do($spec->{sql}, undef, @bind);

       ok(is_maybe_zbt($rv, $spec->{expected}), "do($spec->{desc})");
       # $DBI::rows is not guaranteed to be correct after $dbh->blah operations
}

# == 2a. single execute() and rows()

for my $spec (@TEST_PROGRAM) {
       my @bind = @{$spec->{params}} if $spec->{params};
       my $sth = $dbh->prepare($spec->{sql});
       my $rv = $sth->execute(@bind);

       ok(is_maybe_zbt($rv, $spec->{expected}), "execute($spec->{desc})");
       is($DBI::rows, $spec->{expected}, "execute($spec->{desc}) (\$DBI::rows)");
       is($sth->rows, $spec->{expected}, "\$sth->rows($spec->{desc})");
}

# == 2b. repeated execute() and rows()
{
    my $i   = 0;
    my $sth = $dbh->prepare("INSERT INTO $table(ID, NAME) VALUES (?, ?)");
    for my $name (qw|unu du tri kvar kvin ses sep ok naux dek|) {
        my $rv = $sth->execute( ++$i, $name );
        is( $rv, 1, "re-execute(INSERT one) -> 1" );
        is( $DBI::rows, 1, "re-execute(INSERT one) -> 1 (\$DBI::rows)" );
        is( $sth->rows, 1, "\$sth->rows(re-executed INSERT)" );
    }

    $sth = $dbh->prepare("DELETE FROM $table WHERE ID<?");
    for ( 6, 11 ) {
        my $rv = $sth->execute($_);
        is( $rv,        5, "re-execute(DELETE five) -> 1" );
        is( $DBI::rows, 5, "re-execute(DELETE five) -> 1 (\$DBI::rows)" );
        is( $sth->rows, 5, "\$sth->rows(re-executed DELETE)" );
    }
    my $rv = $sth->execute(16);
    ok( is_maybe_zbt( $rv, 0 ), "re-execute(DELETE on empty) zero but true" );
    is( $DBI::rows, 0,
        "re-execute(DELETE on empty) (\$DBI::rows) zero but true" );
    is( $sth->rows, 0,
        "\$sth->rows(re-executed DELETE on empty) zero but true" );
}

# == 3. special cases
#       DBD::InterBase tracks the number of FETCHes on a SELECT statement
#       in $sth->rows() as an extension to the DBI.

{
    my $i = 0;
    for my $name (qw|unu du tri kvar kvin ses sep ok naux dek|) {
        $dbh->do( "INSERT INTO $table(ID, NAME) VALUES (?, ?)",
            undef, ++$i, $name );
    }
    my $sth = $dbh->prepare("SELECT ID, NAME FROM $table");
    my $rv  = $sth->execute;
    ok( is_maybe_zbt( $rv, 0 ), "execute(SELECT) -> zero but true" );
    is( $DBI::rows, 0, "execute(SELECT) zero but true (\$DBI::rows)" );
    is( $sth->rows, 0, "\$sth->rows(SELECT) zero but true" );

    my $fetched = 0;
    while ( $sth->fetch ) {
        is( ++$fetched, $sth->rows, "\$sth->rows incrementing on SELECT" );
        is( $fetched,   $DBI::rows, "\$DBI::rows incrementing on SELECT" );
    }
}
