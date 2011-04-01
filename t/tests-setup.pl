#!/usr/bin/perl

# Requirements
# - various choices to set dsn, user and pass
#   - from environment vars
#   - command line prompt
# - support for client only installation (test database on remote server)

use strict;
use warnings;
use Carp;

use Data::Dumper;

check_database();
# create_test_database();

sub connect_2_database {

    my ($tdsn, $user, $pass) = get_connection_params();

    #   Connect to the database
    my $dbh = DBI->connect( $tdsn, $user, $pass,
        { RaiseError => 1, PrintError => 0, AutoCommit => 1 } );

    return $dbh;
}

sub get_connection_params {

    #- Check the environment vars

    my $para = check_environment();

    if ( $para->{tdsn} and $para->{user} and $para->{pass} ) {
        return $para;
    }

    # ask for database path

    # ask for user and pass

    return;
}

sub read_cached_configs {

    # read cached config if available

    my $test_conf = './t/test.conf';
    my $record = {};

    if (-f $test_conf) {
        print "\nReading cached test configuration...\n";

        open my $file_fh, '<', $test_conf
            or croak "Can't open file ", $test_conf, ": $!";

        foreach my $line (<$file_fh>) {
            next if $line =~ m{^#+};         # skip comments

            my ($key, $val) = split /:/, $line, 2;
            chomp $val;
            $record->{$key} = $val;
        }

        close $file_fh;
    }

    return $record;
}

sub create_test_database {

    my $record = read_cached_configs();

    my $para = get_connection_params();
    my ( $tdsn, $user, $pass ) =
      ( $para->{tdsn}, $para->{user}, $para->{pass} );

    my $path = '/opt/ibdb/testnew.fdb';

    #- Create test database

    #-- Create the SQL file with CREATE statement

    open my $t_fh, '>', './t/create.sql'
      or die qq{Can't write to t/create.sql};
    while(<DATA>) {
        s/__TESTDB__/$path/;
        s/__USER__/$user/;
        s/__PASS__/$pass/;
        print {$t_fh} $_;
    }
    close $t_fh;

    #-- Try to execute isql and create the test database

    my $isql = $record->{isql};

    print 'Create the test database ... ';
    my $ocmd = qq("$isql" -sql_dialect 3 -i ./t/create.sql 2>&1);
    eval {
        # print "cmd is $ocmd\n";
        open my $isql_fh, '-|', $ocmd;
        while (<$isql_fh>) {
            # For debug:
            # print "> $_\n";
        }
        close $isql_fh;
    };
    if ($@) {
        die "ISQL open error!\n";
    }
    else {
        if ( -f $path ) {
            print " done\n";
        }
        else {
            print " failed!\n";
        }
    }

    return;
}

sub check_database {

    my $record = read_cached_configs();

    my $para = get_connection_params();
    my ( $tdsn, $user, $pass ) =
      ( $para->{tdsn}, $para->{user}, $para->{pass} );

    my $path = '/opt/ibdb/testnew.fdb';

    #- Connect to the test database

    my $isql = $record->{isql};

    print "The isql path is $isql\n";
    my $dialect;
    my $database_ok = 1;

    # Using isql CLI to connect to the database and retrieve the
    # dialect.  If I/O error then the database doesn't exists

    my $ocmd = qq("$isql" -u "$user" -p "$pass" -x "$path" 2>&1);
    eval {
        open my $fh, '-|', $ocmd;
      LINE:
        while (<$fh>) {
            my $line = $_;
            # Check for I/O error or 'not recognized' ... from cmd.exe
            # print "II $line\n";
            if ($line =~ m{error|recognized}i) {
                $database_ok = 0;
                last LINE;
            }
            # Check for Firebird login errors
            if ($line =~ m{Firebird login}i) {
                print "!!! Check your Firebird login parameters !!!\n";
            }
            # Get dialect if got here
            if ($line =~ m{DIALECT (\d)}i) {
                $dialect = $1;
                last LINE;
            }
        }
        close $fh;
    };
    if ($@) {
        die "isql open error!\n";
    }

    unless ($database_ok) {
        print "Creating new database: $path ...";
        # create_test_db($path, $user, $pass);
    }

    unless (defined $dialect) {
        print "No dialect?\n";
    }
    else {
        print "Dialect is $dialect\n";
    }

    return;
}

sub check_environment {

    my $env_rec = {};

    $env_rec->{tdsn} = $ENV{DBI_DSN}  if exists $ENV{DBI_DSN};
    $env_rec->{user} = $ENV{DBI_USER} if exists $ENV{DBI_USER};
    $env_rec->{pass} = $ENV{DBI_PASS} if exists $ENV{DBI_PASS};

    return $env_rec;
}

#- The data used to create the database creation script

__DATA__
CREATE DATABASE "__TESTDB__" user "__USER__" password "__PASS__";

quit;
