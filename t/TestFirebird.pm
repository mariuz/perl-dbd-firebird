package TestFirebird;
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
use File::Temp;

use Test::More;

use base 'Exporter';

our @EXPORT = qw(find_new_table);

sub import {
    my $me = shift;
    $me->export_to_level(1,undef, qw(find_new_table));
}

use constant test_conf => 't/tests-setup.tmp.conf';
use constant test_mark => 't/tests-setup.tmp.OK';

sub new {
    my $self = bless {}, shift;

    $self->read_cached_configs;

    return $self;
}

=head2 read_cached_configs

Read the connection parameters from the 'tests-setup.conf' file.

=cut

sub read_cached_configs {
    my $self = shift;

    my $test_conf = $self->test_conf;

    if (-f $test_conf) {
        # print "\nReading cached test configuration...\n";

        open my $file_fh, '<', $test_conf
            or croak "Can't open file ", $test_conf, ": $!";

        foreach my $line (<$file_fh>) {
            next if $line =~ m{^#+};         # skip comments

            my ($key, $val) = split /:=/, $line, 2;
            chomp $val;
            $self->{$key} = $val;
        }

        close $file_fh;
    }
}

=head2 connect_to_database

Initialize setting for the connection.

Connect to database and return handler.

Takes optional parameter for connection attributes.

=cut

sub connect_to_database {
    my $self = shift or confess;
    my $attr = shift;

    my $error_str = $self->tests_init();

    my $dbh;
    unless ($error_str) {
        my $default_attr =
          { RaiseError => 1, PrintError => 0, AutoCommit => 1 };

        # Merge attributes
        @{$default_attr}{ keys %{$attr} } = values %{$attr};

        # Connect to the database
        eval {
        $dbh =
          DBI->connect( $self->{tdsn}, $self->{user}, $self->{pass},
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
    my $self = shift or confess;

    my $error_str;
    if ( $self->check_mark() ) {
        return undef;
    }
    else {
        $error_str = $self->check_and_set_cached_configs;
        unless ($error_str) {
            $error_str = $self->setup_test_database;
        }
    }

    return $error_str;
}

=head2 check_cached_configs

Simply (double)check every value and return what's missing.

=cut

sub check_and_set_cached_configs {
    my $self = shift;

    return qq{Please, run "perl Makefile.PL" (to setup isql path)}
        unless exists $self->{isql};

    my $error_str = q{};

    # Check user and pass, try the get from ENV if missing
    $self->{user} ||= $self->get_user;
    $self->{pass} ||= $self->get_pass;

    # Check host
    $self->{host} ||= $self->get_host;

    # Won't try to find isql here, just repport that it's missing
    $error_str .= ( -x $self->{isql} ) ? q{} : q{isql, };

    # The user can control the test database name and path using the
    # DBI_DSN environment var.  Other option is a default made up dsn
    $self->{tdsn}
        = $self->{tdsn}
        ? $self->check_dsn( $self->{tdsn} )
        : $self->get_dsn;
    $error_str .= $self->{tdsn} ? q{} : q{wrong dsn,};

    # The database path
    $self->{path} = $self->get_path;
    my ( $base, $path, $type ) = $self->fileparse( $self->{path}, '\.fdb' );

    # Check database path only if local
    if ( $self->{host} eq 'localhost' ) {
        $error_str .= 'wrong path, '
            if $type eq q{.fdb} and not( -d $path and $base );

        # if no .fdb extension, then it may be an alias
    }

    $self->save_configs;

    return $error_str;
}

sub get_user {
   my $self = shift;

   return if $self->{use_libfbembed};

   return $ENV{DBI_USER} || $ENV{ISC_USER} || q{sysdba};
}

sub get_pass {
   my $self = shift;

   return if $self->{use_libfbembed};

   return $ENV{DBI_PASS} || $ENV{ISC_PASSWORD} || q{masterkey};
}

sub get_host {
   my $self = shift;

   return if $self->{use_libfbembed};

   return q{localhost};
}

=head2 check_dsn

Parse and check the DSN.

=cut

sub check_dsn {
    my $self = shift;
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
    my $self = shift;

    my $path;
    my $host = $self->{host};

    if ( $self->{use_libfbembed} ) {
        $path = "dbd-fb-testdb.fdb";
    }
    else {
        # $path
        #     = 'localhost:'
        #     . File::Spec->catfile( File::Spec->tmpdir(),
        #     'dbd-fb-testdb.fdb' );
        $path = File::Spec->catfile( File::Spec->tmpdir(),
            'dbd-fb-testdb.fdb' );
    }

    return "dbi:Firebird:db=$path;host=$host;ib_dialect=3;ib_charset=ISO8859_1";
}

=head2 get_path

Extract the database path from the dsn.

=cut

sub get_path {
    my $self = shift;

    my $dsn = $self->{tdsn};

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
    my $self = shift;

    my $have_testdb = $self->check_database;
    unless ($have_testdb) {
        $self->create_test_database;

        # Check again
        return "Failed to create test database!"
          unless $have_testdb = $self->check_database;
    }

    # Create a mark
    $self->create_mark;

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

=head2 save_configs

Append the connection parameters to the 'tests-setup.conf' file.

=cut

sub save_configs {
    my $self = shift;

    open my $t_fh, '>>', $self->test_conf
        or die "Can't write " . $self->test_conf . ": $!";

    my $test_time = scalar localtime();
    my @record = (
        q(# Test section: -- (created by tests-setup.pl) #),
        q(# Time: ) . $test_time,
        qq(tdsn:=$self->{tdsn}),
        qq(path:=$self->{path}),
        $self->{use_libfbembed}
            ? ()
            : (
                qq(user:=$self->{user}),
                qq(pass:=$self->{pass}),
            ),
        q(# This is a temporary file used for test setup #),
    );
    my $rec = join "\n", @record;

    print {$t_fh} $rec, "\n";

    close $t_fh or die "Can't close " . $self->test_conf . ": $!";

    return;
}

=head2 create_test_database

Create the test database.

=cut

sub create_test_database {
    my $self = shift;

    my ( $isql, $gfix, $user, $pass, $path, $host ) = (
        $self->{isql}, $self->{gfix}, $self->{user},
        $self->{pass}, $self->{path}, $self->{host}
    );

    my $db_path = join( ':', $host || (), $path );

    #- Create test database

    #-- Create the SQL file with CREATE statement

    my $sql_create = File::Temp->new();
    print $sql_create qq{create database "$db_path"};
    print $sql_create qq{ user "$user" password "$pass"}
        unless $self->{use_libfbembed};
    print $sql_create ";\nquit;\n";

    #-- Try to execute isql and create the test database

    print 'Create the test database ... ';
    my $ocmd = qq("$isql" -sql_dialect 3 -i "$sql_create" 2>&1);
    eval {
        # print "cmd is $ocmd\n";
        open my $isql_fh, '-|', $ocmd;
        while (<$isql_fh>) {
            # For debug:
            print "> $_\n";
        }
        close $isql_fh;
    };
    if ($@) {
        die "ISQL open error: $@\n";
    }

    #-- turn forced writes off

    if ($gfix) {
        print "Turning forced writes off\n";
        local $ENV{ISC_USER} = $user;
        local $ENV{ISC_PASSWORD} = $pass;
        system($gfix, '-write', 'async', $db_path); # errors here aren't fatal
    }

    return;
}

=head2 check_database

Using isql CLI to connect to the database and retrieve the dialect.
If I/O error then conclude that the database doesn't exists.

=cut

sub check_database {
    my $self = shift;

    my ( $isql, $user, $pass, $path, $host ) = (
        $self->{isql}, $self->{user}, $self->{pass},
        $self->{path}, $self->{host}
    );

    #- Connect to the test database

    print "The isql path is $isql\n";
    print "The databse path is $path\n";

    my $dialect;
    my $database_ok = 1;

    local $ENV{ISC_USER};
    local $ENV{ISC_PASSWORD};

    my $ocmd = qq("$isql" -x "$host:$path" 2>&1);

    unless ( $self->{use_libfbembed} ) {
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
    my $self = shift;

    open my $file_fh, '>', $self->test_mark
        or croak "Can't open file ",$self->test_mark, ": $!";
    close $file_fh;

    return;
}

=head2 check_mark

Check is mark file exists.

=cut

sub check_mark {
    my $self = shift;
    return (-f $self->test_mark);
}

=head2 drop_test_database

Cleanup time, drop the test database, warn on failure or sql errors.

=cut

sub drop_test_database {
    my $self = shift;

    return unless scalar %{$self};

    my ( $isql, $user, $pass, $path, $host ) = (
        $self->{isql}, $self->{user}, $self->{pass},
        $self->{path}, $self->{host}
    );

    #-- Create the SQL file with DROP statement
    my $sql_dropdb = File::Temp->new();

    print $sql_dropdb qq{connect "$host:$path"};
    print $sql_dropdb qq{ user "$user" password "$pass"}
        unless $self->{use_libfbembed};
    print $sql_dropdb qq{;\n};
    print $sql_dropdb qq{drop database;\n};
    print $sql_dropdb qq{quit;\n};

    #-- Try to execute isql

    print 'Drop the test database ... ';
    my $error = 0;              # flag

    my $ocmd = qq("$isql" -sql_dialect 3 -q -i "$sql_dropdb" 2>&1);
    eval {
        print "cmd: $ocmd\n";
        open my $isql_fh, '-|', $ocmd;
        while (<$isql_fh>) {
            print "> $_\n";     # for debug
            $error++ if $_ =~ m{error}i;
        }
        close $isql_fh;
    };

    $error++ if $@;

    return 'warning: drop test database failed.' if $error;
}

=head2 cleanup

Cleanup temporary files, warn on failure.

=cut

sub cleanup {
    my $self = shift;

    my @tmp_files = (
        $self->test_mark,
    );

    my $unlinked = 0;
    foreach my $tmp_file (@tmp_files) {
        print qq{Cleanup $tmp_file };
        if (unlink $tmp_file) {
            $unlinked++;
            print qq{ done\n};
        }
        else {
            print qq{could not unlink: $!\n};
        }
    }

    return 'warning: file cleanup failed.' if $unlinked != scalar @tmp_files;
}

1;
