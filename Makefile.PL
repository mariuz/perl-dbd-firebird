#   $Id: Makefile.PL 394 2008-01-08 05:29:19Z edpratomo $
#
#   Copyright (c) 1999-2005 Edwin Pratomo
#   Portions Copyright (c) 2001-2005 Daniel Ritz
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file.

# Changes
#
# 2011-01-31, stefansbv:
# using the three-argument form of open for reading test.conf
#
# 2011-01-26, stefansbv:
# fixed the isql tool path and the command line
#   (using quotes around parameters and canonpath)
# when isql error create the test database and inform the user
# improved support for MinGW (now using the Config module)
# added support for ActivePerl! :)

BEGIN { $^W = 0 }       # turn warnings off
BEGIN { require 5.008_001;} # 5.008 is required by latest dbi version 

use ExtUtils::MakeMaker 5.16, qw(prompt &WriteMakefile $Verbose);
use Config;
use Carp;
use strict;
use File::Basename;
use File::Spec;
use vars qw($Registry);

# This DBI must be installed before we can build a DBD.
# For those not using Dynamic loading this means building a
# new static perl in the DBI directory by saying 'make perl'
# and then using _that_ perl to make this one.
use DBI 1.41 ();
use Test::More 0.4;
use DBI::DBD;   # DBD creation tools

my $ib_dir_prefix;

# init stuff
my $IB_Bin_path = '';
my $isql_name;
my $isql_path;
my @ib_bin_dirs;
my @ib_inc_dirs;
my $ib_lib_dir = '';

################################################################################
# OS specific configuration
################################################################################
if ($Config::Config{osname} eq 'MSWin32')
{
    $isql_name = 'isql.exe';

    # try to find Firebird installation via the registry
    my $ib_bin_dir = '';

    eval
    {
        require Win32::TieRegistry;
        Win32::TieRegistry->import('$Registry');
        $Registry->Delimiter("/");

        my $sw = $Registry->{"LMachine/Software/"}
            or die "Can't read LMachine/Software key: $^E\n";
        # We have to check more than one keys, because different
        # releases of Firebird have used different key hierarchies.

        my $key = $sw->{"Firebird Project/Firebird Server/Instances/"} ||
              $sw->{"FirebirdSQL/Firebird/CurrentVersion/"};

        if (defined($key))
        {
            $ib_bin_dir = $key->{"/ServerDirectory"};
            $ib_bin_dir ||= $key->{"/DefaultInstance"} . "bin";
            $ib_lib_dir = $key->{"/RootDirectory"};
            $ib_lib_dir ||= $key->{"/DefaultInstance"};
        }
    };
    die "Error: $@\n" if $@;

    $ib_lib_dir .= '\\' unless ($ib_lib_dir =~ m|^.*\\$|gi);

    @ib_bin_dirs = ($ib_bin_dir);
    @ib_inc_dirs = ($ib_lib_dir . "SDK\\include", $ib_lib_dir . "include");
}
else
{
    $isql_name = 'isql';
    @ib_bin_dirs = (qw(/opt/firebird/bin /usr/bin /usr/local/bin));
    @ib_inc_dirs = (qw(/opt/firebird/include /usr/include));
}

sub locate_dbi_arch_dir {
    my $dbidir = dbd_dbi_dir();
    my @try = map { "$_/auto/DBI" } @INC;
    my @xst = grep { -f "$_/Driver.xst" } @try;
    Carp::croak("Unable to locate Driver.xst in @try") unless @xst;
    Carp::carp( "Multiple copies of Driver.xst found in: @xst") if @xst > 1;
    return $xst[0];
}

sub get_isql_path
{
    # try to find isql
    return $isql_path if $isql_path;

    for ($IB_Bin_path, split /:/ => $ENV{PATH}) {
        s!/ +$ !!xg;
        next unless $_;
        if (-x "$_/$isql_name") {
            $isql_path = "$_/$isql_name";
            $isql_path = File::Spec->canonpath($isql_path);
            return $isql_path;
        }
    }

    EXEC:
    {
        for (1..3)
        {
            $isql_path = prompt("Enter full path to isql: ", $isql_path);
            $isql_path = File::Spec->canonpath($isql_path);
            last EXEC if (-x $isql_path);
        }
        die "Unable to execute isql. Aborting..";
    }

    return $isql_path;
}

################################################################################
# sub test_files - checks if at least one of the files in the list exists
# Paramters:
#  0: directory
#  1: reference to file list
# Return value: true value if at least on file exists, 0 otherwise
################################################################################
sub test_files
{
    my($dir, $files) = @_;
    local $_;
    -f "$dir/$_" && return $_ for @$files;
    0;
}

################################################################################
# sub dir_choice - prompts for a directory
# Parameters:
#  0: prompt string
#  1: reference to directory list
#  2: reference to file list
# Return value: directory name
################################################################################
sub dir_choice
{
    my($prompt, $dirs, $files) = @_;
    my %dirs;
    my $i;
    my $ret;

    test_files($_, $files) && ($dirs{++$i} = $_) for @$dirs;
    for (1..3)
    {
        foreach my $d (sort keys %dirs) {
            my $choice = prompt("$prompt :", $dirs{$d});
            return $choice if test_files($choice, $files);
        }
    }
    print "Cannot proceed. Aborting..\n";
}

################################################################################
# sub make_test_conf - configure for test (save to ./t/test.conf)
# Parameters: <none>
# Return value: <none>
################################################################################
sub make_test_conf
{
    my $test_conf = './t/test.conf';
    my ($dsn, $user, $pass, $path, $db, $host);

    # read cached config if available
    if (-f $test_conf) {
        print "\nReading cached test configuration...";

        open my $file_fh, '<', $test_conf
            or croak "Can't open file ", $test_conf, ": $!";

        ( $dsn, $user, $pass ) = map { chomp; $_ } <$file_fh>;

        close $file_fh;

        ($db)   = $dsn =~ /(?:db|database)=([^;]+);/;
        ($host) = $dsn =~ /(?:host|hostname)=([^;]+);/;
        $path = ( $host ? "$host:" : '' ) . $db;
    }

    # ask for database path
    DBPATH: {
        for ( 1 .. 3 ) {
            last
              if $path =
                  prompt( "\nFull path to test database to create or use: ",
                      $path );
        }
        die "Must specify a test database" unless $path;

        $path = File::Spec->canonpath($path); # correct path on all platforms
        print "Test database path is $path\n";
        ($db, $host) = reverse split /:/, $path;
        $user = prompt("Username :", $user);
        $pass = prompt("Password :", $pass);

        my $isql = get_isql_path();
        print "The isql path is $isql\n";
        my $dialect;
        my $database_ok = 1;

        # Using isql CLI to connect to the database and retrieve the
        # dialect.  If I/O error then just create a new database
        my $ocmd = qq("$isql" -u "$user" -p "$pass" -x "$path" 2>&1);
        eval {
            open my $fh, '-|', $ocmd;
          LINE:
            while (<$fh>) {
                my $line = $_;
                # Check for I/O error or 'not recognized' ... from cmd.exe
                # print "II $line\n";
                if ($line =~ /error|recognized/i) {
                    $database_ok = 0;
                    last LINE;
                }
                # Check for Firebird login errors
                if ($line =~ /Firebird login/i) {
                    print "!!! Check your Firebird login parameters !!!\n";
                    $path = undef, goto DBPATH; # should change this!
                }
                # Get dialect if got here
                if ($line =~ /DIALECT (\d)/i) {
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
            create_test_db($path, $user, $pass);
            last DBPATH;
        }

        unless (defined $dialect) {
            print <<"EOM";

Dialect of $path is UNKNOWN.
This test requires a database of dialect 3. You may specify a
non-existent database to create a new one.

EOM
            my $is_proceed = prompt("Proceed anyway or create a NEW test database (P/N)?", "P");
            last DBPATH if $is_proceed =~ /P/i;
            $path = undef, goto DBPATH;
        }
        unless ($dialect == 3) {
            print <<"EOM";
The dialect of $path is: $dialect !!!
This test requires a database of dialect 3. Please specify a
non-existent database to create a new one.

EOM
            $path = undef, goto DBPATH;
        }
    }

    # save test config to file
    # TODO: consider using utf8 in the future
    my $isql = get_isql_path();    # we need it in readbigdecimal test ;)
    open my $t_fh, '>', $test_conf or die "Can't write $test_conf: $!";
    print {$t_fh} 'dbi:InterBase:'
      . ( $host ? "host=$host;" : '' )
      . "db=$db;ib_dialect=3;ib_charset=ISO8859_1\n$user\n$pass\n$isql\n";
    close $t_fh;
}

################################################################################
# sub create_test_db - Creates the test database
# Parameters:
#  0: path to testdatabase to be created
#  1: username used to connect to the DB
#  2: password
# Return value: <none>
################################################################################
sub create_test_db
{
    my ($path, $user, $pass) = @_;

    # create the SQL file with CREATE statement
    open my $t_fh, '>', './t/create.sql' or die "Can't write to t/create.sql";
    while(<DATA>)
    {
        s/__TESTDB__/$path/;
        s/__USER__/$user/;
        s/__PASS__/$pass/;
        print {$t_fh} $_;
    }
    close $t_fh;

    # try to execute isql and create the test database
    my $isql = get_isql_path();

    my $ocmd = qq("$isql" -sql_dialect 3 -i ./t/create.sql 2>&1);
    eval {
        #print "cmd is  $ocmd\n";
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
}

################################################################################
# MAIN
################################################################################

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

# prompt for InterBase bin directory
$IB_Bin_path = dir_choice("Firebird bin directory", [@ib_bin_dirs], [qw(gfix gfix.exe)]);

unless(-x $IB_Bin_path)
{
    carp "I cannot find your Firebird installation.\nDBD::InterBase cannot be build or run without Firebird.\n";
    exit 1;
}

# get Firebird version
my $IBVERSION;
my $GFIX_PATH = $IB_Bin_path . "/" . test_files($IB_Bin_path, [qw(gfix gfix.exe)]);
chop($IBVERSION = `$GFIX_PATH -z 2>&1`);
$IBVERSION =~ s/^gfix version //o;
my $is_final = $IBVERSION =~ /\.6\d+$/ ? 1 : 0;

# prompt for Firebird include dir
my $ib_inc = dir_choice("Firebird include directory", [@ib_inc_dirs], [qw(gds.h ibase.h)]);


# we use a hash for the MakeMaker parameters
my %MakeParams = (
    'NAME'          => 'DBD::InterBase',
    'VERSION_FROM'  => 'InterBase.pm', # finds $VERSION
    'C'             => ['dbdimp.c'],
    'H'             => ['dbdimp.h', 'InterBase.h'],
    'CCFLAGS'       => '-Wall -fno-strict-aliasing',
    'INC'           => qq(-I"$ib_inc" -I"${\locate_dbi_arch_dir()}"),
    'OBJECT'        => "InterBase.o dbdimp.o",
    'LIBS'          => [''],
    'OPTIMIZE'      => $Config::Config{'optimize'},
    'XSPROTOARG'    => '-noprototypes',
    'dist'          => {COMPRESS=>'gzip -9f', SUFFIX=>'gz'},
    'clean'         => {FILES => "*.xsi *.old t/*.old *~ t/*~ trace.txt t/trace.txt lib/DBD/InterBase/*~ lib/DBD/InterBase/*.old lib/Bundle/DBD/*~ lib/Bundle/DBD/*.old"},
    'realclean'     => {FILES => "t/test.conf"},
);

# the OS specific build environment setup
my $os = $Config::Config{'osname'};
if ($os eq 'MSWin32')
{
    # set up PPM package parameters
    $MakeParams{'AUTHOR'}   = 'Edwin Pratomo (edpratomo@users.sourceforge.net)';
    $MakeParams{'ABSTRACT'} = 'DBD::InterBase is a DBI driver for Firebird , written using Firebird C API.';

    my $vc_dir = '';
    if ($Config::Config{'cc'} eq "cl")
    {
        # try to find Microsoft Visual C++ compiler
        eval
        {
            require Win32::TieRegistry;
            Win32::TieRegistry->import('$Registry');
            $Registry->Delimiter("/");

            my $sw = $Registry->{"LMachine/Software/"};



            # We have to check more than one keys, because different
            # releases of Visual C++ have used different key hierarchies.
            my $key =
                $sw->{"Microsoft/VisualStudio/6.0/Setup/Microsoft Visual C++"} ||
                $sw->{"Microsoft/VisualStudio/7.0/Setup/VC"};

            if (defined($key))
            {
                $vc_dir = $key->{"/ProductDir"};
            }
        };

        my @vc_dirs = ($vc_dir . "/bin");

        my $VC_PATH = dir_choice("Visual C++ directory", [@vc_dirs], [qw(cl.exe)]);

        unless (-x $VC_PATH){
            carp "I can't find your MS VC++ installation.\nDBD::InterBase cannot build.\n";
            exit 1;
        }

        my $vc_inc = $VC_PATH . "/include";
        my $vc_lib = $VC_PATH . "/lib";

        $INC .= " -I\"$vc_inc\"";

        my $ib_lib = dir_choice("InterBase lib directory",
                            [$ib_lib_dir . "SDK\\lib_ms", $ib_lib_dir . "lib"],
                            [qw(gds32_ms.lib fbclient_ms.lib)]);

        my $cur_libs = $Config::Config{'libs'} ;
        my $cur_lddlflags = $Config::Config{'lddlflags'} ;

        my $lib;
        if (-f "$ib_lib/fbclient_ms.lib")
            { $lib = "$ib_lib/fbclient_ms.lib"; }
        else
            { $lib = "$ib_lib/gds32_ms.lib"; }

        eval "
    sub MY::const_loadlibs {
    '
LDLOADLIBS = \"$lib\" $cur_libs
LDDLFLAGS =  -L\"$vc_lib\" $cur_lddlflags
    '
    } ";
    }
    # Support for MinGW
    #  ActiveState: cc => V:\absolute\path\to\gcc.exe
    #  Strawberry : cc => gcc
    elsif ($Config::Config{'cc'} =~ m{gcc}i ) {
        print "Using MinGW gcc\n";

        # For ActiveState Perl hardwired MinGW path          # other idea?
        my $mingw_path = 'C:\Perl\site\lib\auto\MinGW';

        # Expecting absolute paths in Straberry Perl
        my $mingw_inc = $Config::Config{incpath};
        # For ActiveState Perl is  \include                  # always?
        if ( $mingw_inc eq '\include' ) {
            $mingw_inc = File::Spec->catpath($mingw_path,  $mingw_inc);
        }
        my $mingw_lib =  $Config::Config{libpth};
        # For ActiveState Perl is  \lib                      # always?
        if ( $mingw_lib eq '\lib' ) {
            $mingw_lib = File::Spec->catpath($mingw_path,  $mingw_lib);
        }

        $INC .= " -I\"$mingw_inc\"";

        my $ib_lib = dir_choice("InterBase lib directory",
                            [$ib_lib_dir . "SDK\\lib_ms", $ib_lib_dir . "lib"],
                            [qw(gds32_ms.lib fbclient_ms.lib)]);

        my $cur_libs = $Config::Config{libs} ;
        my $cur_lddlflags = $Config::Config{lddlflags} ;

        my $lib;
        if (-f "$ib_lib/fbclient_ms.lib")
            { $lib = "$ib_lib/fbclient_ms.lib"; }
     else
            { $lib = "$ib_lib/gds32_ms.lib"; }

        eval "
    sub MY::const_loadlibs {
    '
LDLOADLIBS = \"$lib\" $cur_libs
LDDLFLAGS =  -L\"$mingw_lib\" $cur_lddlflags
    '
    } ";
    }
    else
    {

    }
}
elsif ($os eq 'solaris')
{
    $MakeParams{'LIBS'} = '-lgdsmt -lm -lc';
}
elsif (($os eq 'linux') || ($os eq 'freebsd'))
{
    my $ib_lib = dir_choice("InterBase/Firebird lib directory",
    [qw(/usr/firebird/lib /opt/firebird/lib /usr/lib /usr/local/lib)],
    [qw(libgds.a libgds.so libfbclient.so libfbembed.so)]);
    my $lib;

    if (-f "$ib_lib/libfbclient.so")
    {
         my $emb = 0;

         if (-f "$ib_lib/libfbembed.so")
         {
             while ($emb ne 'n' && $emb ne 'y')
                 { $emb = prompt("Build with libfbembed? (y/n)", 'n'); }
         }

         if ($emb eq 'y')
             { $lib = 'fbembed'; }
         else
             { $lib = 'fbclient'; }
    }
    else
         { $lib = 'gds'; }

    my $ldl = ($os eq 'linux') ? '-ldl' : '';

    $MakeParams{'LIBS'} = "-L$ib_lib -l$lib $ldl ";

}
elsif ($os eq 'hpux')
{
    $MakeParams{'LIBS'} = '-lgds -ldld';
}
elsif ($os eq 'sunos')
{
    $MakeParams{'LIBS'} = '-lgdslib -ldl';
}
elsif ($os eq 'irix')
{
    $MakeParams{'LIBS'} = '-lgds -lsun';
}
elsif ($os eq 'aix')
{
    $MakeParams{'LIBS'} = '-lgdsshr';
}
elsif ($os eq 'dgux')
{
    $MakeParams{'LIBS'} = '-lgds -lgdsf -ldl -ldgc';
}
elsif ($os eq 'osf1')
{
    $MakeParams{'LIBS'} = '-lgds';
}
elsif ($os eq 'sysv')
{
   $MakeParams{'LIBS'} = '-lgds -lnsl -lsocket -ldl';
}
else
{
    carp "DBD::InterBase is not supported on platform $os.\n";
    exit 1;
}

# create the test config file
make_test_conf();

# and last but not least write the makefile
WriteMakefile(%MakeParams);

sub MY::postamble
{
    return dbd_postamble(@_);
}

package main;

# the data used to create the database creation script
__DATA__
CREATE DATABASE "__TESTDB__" user "__USER__" password "__PASS__";

quit;
