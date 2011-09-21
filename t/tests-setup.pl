#!perl
#
# Helper file for the DBD::Firebird tests
#
# 2011-04-01: Created by stefan(s.bv.)
# Based on the DBD::InterBase - Makefile.PL script
# (2008-01-08 05:29:19Z by edpratomo)
# Inspired by the 't/dbdpg_test_setup.pl' script from DBD::Pg.
#

use strict;
use warnings;
use Carp;

use DBI 1.43;                   # minimum version for 'parse_dsn'
use File::Spec;
use File::Basename;

my $test_conf = 't/tests-setup.tmp.conf';
my $test_mark = 't/tests-setup.tmp.OK';

use Test::More;

my $param = read_cached_configs();

unless ( $param->{use_libfbembed} or $ENV{DBI_PASS} or $ENV{ISC_PASSWORD} ) {
    Test::More->import( skip_all =>
            "Neither DBI_PASS nor ISC_PASSWORD present in the environment" );
    exit 0;    # do not fail with CPAN testers
}


if ( $param->{use_libfbembed} ) {
    # no interaction with anybody else
    $ENV{FIREBIRD} = $ENV{FIREBIRD_LOCK} = '.';
    delete $ENV{ISC_USER};
    delete $ENV{ISC_PASSWORD};
    delete $ENV{DBI_USER};
    delete $ENV{DBI_PASS};
}

=head2 connect_to_database

Initialize setting for the connection.

Connect to database and return handler.

Takes optional parameter for connection attributes.

=cut

sub connect_to_database {
    my $attr = shift;

    my ( $param, $error_str ) = tests_init();

    my $dbh;
    unless ($error_str) {
        my $default_attr =
          { RaiseError => 1, PrintError => 0, AutoCommit => 1 };

        # Merge attributes
        @{$default_attr}{ keys %{$attr} } = values %{$attr};

        # Connect to the database
        eval {
        $dbh =
          DBI->connect( $param->{tdsn}, $param->{user}, $param->{pass},
            $default_attr );
        };
        if ($@) {
            $error_str .= "Connection error: $@";
        }
    }

    return ($dbh, $error_str);
}

=head2 tests_init

Read the configurations from the L<tests-setup.conf> file, and checks if
they are valid.

=cut

sub tests_init {

    my $param = read_cached_configs();

    my $error_str;
    if ( check_mark() ) {
        return ($param, undef);
    }
    else {
        $error_str = check_and_set_cached_configs($param);
        unless ($error_str) {
            $error_str = setup_test_database($param);
        }
    }

    return ($param, $error_str);
}

=head2 check_cached_configs

Simply (double)check every value and return what's missing.

=cut

sub check_and_set_cached_configs {
    my $param = shift;

    my $error_str = q{};

    # Check user and pass, try the get from ENV if missing
    $param->{user} = $param->{user} ? $param->{user} : get_user($param);
    $param->{pass} = $param->{pass} ? $param->{pass} : get_pass($param);

    # Won't try to find isql here, just repport that it's missing
    $error_str .= ( -x $param->{isql} ) ? q{} : q{isql, };

    # The user can control the test database name and path using the
    # DBI_DSN environment var.  Other option is a default made up dsn
    $param->{tdsn}
        = $param->{tdsn} ? check_dsn( $param->{tdsn} ) : get_dsn($param);
    $error_str .= $param->{tdsn} ? q{} : q{wrong dsn,};

    # The database path
    $param->{path} = get_path($param);
    my ($base, $path, $type) = fileparse($param->{path}, '\.fdb' );

    # check database path only if local
    if (   not $path                    # simple file name
        or $path =~ s/^localhost://i    # leading localhost: stripped
        or $path =~ /^[a-z]:\\/i        # c:\
        or $path !~ /^\w\w+:/ )         # /path/to
    {
        $error_str .= 'wrong path, '
            if $type eq q{.fdb} and not( -d $path and $base );
        # if no .fdb extension, then it may be an alias
    }

    save_configs($param);

    return $error_str;
}

sub get_user {
   my $param = shift;

   return if $param->{use_libfbembed};

   return $ENV{DBI_USER} || $ENV{ISC_USER} || q{sysdba};
}

sub get_pass {
   my $param = shift;

   return if $param->{use_libfbembed};

   return $ENV{DBI_PASS} || $ENV{ISC_PASSWORD} || q{masterkey};
}

=head2 check_dsn

Parse and check the DSN.

=cut

sub check_dsn {
    my $dsn = shift;

    # Check user provided DSN
    my ( $scheme, $driver, undef, undef, $driver_dsn ) =
        DBI->parse_dsn($dsn)
            or die "Can't parse DBI DSN '$dsn'";

    return if $scheme !~ m{dbi}i;        # wrong scheme name
    return if $driver ne q(Firebird);    # wrong driver name
    return if !$driver_dsn;              # wrong driver DSN

    return $dsn;
}

=head2 get_dsn

Make a DSN, using a temporary database in the L</tmp> dir for tests as
default.

Save the database path for L<isql>.

=cut

sub get_dsn {

    my $param = shift;

    my $path;

    if ( $param->{use_libfbembed} ) {
        $path = "dbd-fb-testdb.fdb";
    }
    else {
        $path
            = 'localhost:'
            . File::Spec->catfile( File::Spec->tmpdir(),
            'dbd-fb-testdb.fdb' );
    }

    return "dbi:Firebird:db=$path;ib_dialect=3;ib_charset=ISO8859_1";
}

=head2 get_path

Extract the database path from the dsn.

=cut

sub get_path {
    my $param = shift;

    my $dsn = $param->{tdsn};

    my ( $scheme, $driver, undef, undef, $driver_dsn ) =
        DBI->parse_dsn($dsn)
            or die "Can't parse DBI DSN '$dsn'";

    my @drv_dsn = split /;/, $driver_dsn;
    ( my $path = $drv_dsn[0] ) =~ s{(db(name)?|database)=}{};

    return $path;
}

=head2 setup_test_database

Create the test database if doesn't exists.

Check if we can connect, get the dialect as test.

=cut

sub setup_test_database {
    my $param = shift;

    my $have_testdb = check_database($param);
    unless ($have_testdb) {
        create_test_database($param);

        # Check again
        die "Failed to create test database!"
          unless $have_testdb = check_database($param);
    }

    # Create a mark
    create_mark();

    return;
}

=head2 find_new_table

Find and return a non existent table name between TESTAA and TESTZZ.

=cut

sub find_new_table {
    my $dbh = shift;

    my $try_name = 'TESTAA';
    my $try_name_quoted = $dbh->quote_identifier($try_name);

    my %tables = map { uc($_) => undef } $dbh->tables;

    while (exists $tables{$dbh->quote_identifier($try_name)}) {
        if (++$try_name gt 'TESTZZ') {
            diag("Too many test tables cluttering database ($try_name)\n");
            exit 255;
        }
    }

    return $try_name;
}

=head2 read_cached_configs

Read the connection parameters from the 'tests-setup.conf' file.

=cut

sub read_cached_configs {

    my $record = {};

    if (-f $test_conf) {
        # print "\nReading cached test configuration...\n";

        open my $file_fh, '<', $test_conf
            or croak "Can't open file ", $test_conf, ": $!";

        foreach my $line (<$file_fh>) {
            next if $line =~ m{^#+};         # skip comments

            my ($key, $val) = split /:=/, $line, 2;
            chomp $val;
            $record->{$key} = $val;
        }

        close $file_fh;
    }

    return $record;
}

=head2 save_configs

Append the connection parameters to the 'tests-setup.conf' file.

=cut

sub save_configs {
    my $param = shift;

    open my $t_fh, '>>', $test_conf or die "Can't write $test_conf: $!";

    my $test_time = scalar localtime();
    my @record = (
        q(# Test section: -- (created by tests-setup.pl) #),
        q(# Time: ) . $test_time,
        qq(tdsn:=$param->{tdsn}),
        qq(path:=$param->{path}),
        $param->{use_libfbembed}
            ? ()
            : (
                qq(user:=$param->{user}),
                qq(pass:=$param->{pass}),
            ),
        q(# This is a temporary file used for test setup #),
    );
    my $rec = join "\n", @record;

    print {$t_fh} $rec, "\n";

    close $t_fh or die "Can't close $test_conf: $!";

    return;
}

=head2 create_test_database

Create the test database.

=cut

sub create_test_database {
    my $param = shift;

    my ( $isql, $user, $pass, $path ) =
      ( $param->{isql}, $param->{user}, $param->{pass}, $param->{path} );

    #- Create test database

    #-- Create the SQL file with CREATE statement

    open my $t_fh, '>', './t/create.sql'
      or die qq{Can't write to t/create.sql};
    print $t_fh qq{create database "$path"};
    print $t_fh qq{ user "$user" password "$pass"}
        unless $param->{use_libfbembed};
    print $t_fh ";\nquit;\n";
    close $t_fh;

    #-- Try to execute isql and create the test database

    print 'Create the test database ... ';
    my $ocmd = qq("$isql" -sql_dialect 3 -i ./t/create.sql 2>&1);
    eval {
        # print "cmd is $ocmd\n";
        open( my $isql_fh, '-|', $ocmd ) or die $!;
        while (<$isql_fh>) {
            # For debug:
            print "> $_\n";
        }
        close $isql_fh;
    };
    if ($@) {
        die "ISQL open error: $@\n";
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

=head2 check_database

Using isql CLI to connect to the database and retrieve the dialect.
If I/O error then conclude that the database doesn't exists.

=cut

sub check_database {
    my $param = shift;

    my ( $isql, $user, $pass, $path ) =
      ( $param->{isql}, $param->{user}, $param->{pass}, $param->{path} );

    #- Connect to the test database

    print "The isql path is $isql\n";
    print "The databse path is $path\n";

    my $dialect;
    my $database_ok = 1;

    local $ENV{ISC_USER};
    local $ENV{ISC_PASSWORD};

    my $ocmd = qq("$isql" -x "$path" 2>&1);

    unless ( $param->{use_libfbembed} ) {
        $ENV{ISC_USER} = $user;
        $ENV{ISC_PASSWORD} = $pass;
    }
    # print "cmd: $ocmd\n";
    eval {
        open my $fh, '-|', $ocmd;
      LINE:
        while (<$fh>) {
            my $line = $_;
            # Check for I/O error or 'not recognized' ... from cmd.exe
            # print "II $line\n";
            # The systems LANG setting may be a problem ...
            if ($line =~ m{error|recognized}i) {
                $database_ok = 0;
                last LINE;
            }
            # Check for Firebird login errors
            if ($line =~ m{Firebird login}i) {
                print "Please, check your Firebird login parameters.\n";
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
        return;
    }

    unless (defined $dialect) {
        print "No dialect?\n";
        return;
    }
    else {
        print "Dialect is $dialect\n";
        return $dialect;
    }
}

=head2 create_mark

Create empty file used as mark, used to run L<setup_test_database> only
the first time L<test_init> is called.

=cut

sub create_mark {

    open my $file_fh, '>', $test_mark
        or croak "Can't open file ",$test_mark, ": $!";
    close $file_fh;

    return;
}

=head2 check_mark

Check is mark file exists.

=cut

sub check_mark {
    return (-f $test_mark);
}

1;

