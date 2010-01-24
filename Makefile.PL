
#   $Id: Makefile.PL 394 2008-01-08 05:29:19Z edpratomo $
#
#   Copyright (c) 1999-2005 Edwin Pratomo
#   Portions Copyright (c) 2001-2005 Daniel Ritz
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file,
#   with the exception that it cannot be placed on a CD-ROM or similar media
#   for commercial distribution without the prior approval of the author.

BEGIN { $^W = 0 }       # turn warnings off
BEGIN { require 5.004 } # 5.003 fixes very important bugs

use ExtUtils::MakeMaker 5.16, qw(prompt &WriteMakefile $Verbose);
use Config;
use Carp;
use strict;
use File::Basename;
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
my @ib_bin_dirs;
my @ib_inc_dirs;
my $ib_lib_dir = '';

################################################################################
# OS specific configuration
################################################################################
if ($Config::Config{osname} eq 'MSWin32')
{
    $isql_name = 'isql.exe';

    # try to find InterBase installation via the registry
    my $ib_bin_dir = '';

    eval
    {
        require Win32::TieRegistry;
        Win32::TieRegistry->import('$Registry');
        $Registry->Delimiter("/");

        my $sw = $Registry->{"LMachine/Software/"} or die "Can't read LMachine/Software key: $^E\n";
        # We have to check more than one keys, because different
        # releases of InterBase have used different key hierarchies.

        my $key = $sw->{"InterBase Corp/InterBase/CurrentVersion/"} ||
              $sw->{"Borland/InterBase/CurrentVersion/"} ||
              $sw->{"Firebird Project/Firebird Server/Instances/"} ||
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
    @ib_bin_dirs = (qw(/usr/interbase/bin /opt/interbase/bin /opt/firebird/bin /usr/bin /usr/local/bin));
    @ib_inc_dirs = (qw(/usr/interbase/include /opt/interbase/include /opt/firebird/include /usr/include));
}

sub locate_dbi_arch_dir {
    my $dbidir = dbd_dbi_dir();
    my @try = map { "$_/auto/DBI" } @INC;
    my @xst = grep { -f "$_/Driver.xst" } @try;
    Carp::croak("Unable to locate Driver.xst in @try") unless @xst;
    Carp::carp( "Multiple copies of Driver.xst found in: @xst") if @xst > 1;
    return $xst[0];
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
    if (-r $test_conf)
    {
        print "\nReading cached test configuration...";
        open F, $test_conf or die "Can't open $test_conf: $!";
        local @ARGV = ($test_conf);
        ($dsn, $user, $pass) = map {chomp;$_} <>;
        ($db) = $dsn =~ /(?:db|database)=([^;]+);/;
        ($host) = $dsn =~ /(?:host|hostname)=([^;]+);/;
        $path = ($host ? "$host:" : '') . $db;
        close F;
    }

    # ask for database path
    DBPATH: {
        for (1..3) {
            last if $path = prompt("\nFull path to your test database: ", $path);
        }
        die "Must specify a test database" unless $path;

        ($db, $host) = reverse split /:/, $path;

        # no longer necessary
        #PFW - isql on windows doesn't seem to work without the localhost in the db path
        #my $hostpath = $path;
        #if ($path =~ /^localhost:(.+)/) {
        #    $hostpath = $1;
        #}

        # if DB doesn't exist ask for creation
        if ((!$host || $host =~ /localhost/) && !-f $db or
            $host && $host !~ /localhost/)
        {
            print <<"EOM";
$path does not exist.
Trying to create the test database..
Please enter a username with CREATE DATABASE permission.
EOM
            $user = prompt("Username :", $user);
            $pass = prompt("Password :", $pass);
            create_test_db($path, $user, $pass);
            last DBPATH;
        }
        else
        {
            print <<"EOM";
$db exists.
Trying to use an existing database..
Please enter a username to connect.
EOM
            $user = prompt("Username :", $user);
            $pass = prompt("Password :", $pass);

            # check dialect
            my $dialect;
            my $gstat = $IB_Bin_path . "/" . test_files($IB_Bin_path, [qw(gstat gstat.exe)]);
            local *GSTAT;
            open GSTAT, "$gstat -user $user -password $pass -h $path |" or die "Can't execute $gstat: $!";
            while (<GSTAT>) { ($dialect) = $_ =~ /dialect\s+(\d)/i and last }

            unless (defined $dialect) {
                print <<"EOM";

Dialect of $path is UNKNOWN.
This test requires a database of dialect 3. You may specify a non-existent database to create a new one.
EOM
                my $is_proceed = prompt("Proceed anyway or create a NEW test database (P/N)?", "P");
                last DBPATH if $is_proceed =~ /P/i;
                $path = undef, goto DBPATH;
            }
            unless ($dialect == 3) {
                print <<"EOM";
The dialect of $path is: $dialect !!.
This test requires a database of dialect 3. Please specify a non-existent database to create a new one.
EOM
                $path = undef, goto DBPATH;
            }
        }
    }

    # save test config to file
    open F, ">$test_conf" or die "Can't write $test_conf: $!";
    print F 'dbi:InterBase:' . ($host ? "host=$host;" : '') . "db=$db;ib_dialect=3;ib_charset=ISO8859_1\n$user\n$pass\n";
    close F;
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
    open(T, ">./t/create.sql") or die "Can't write to t/create.sql";
    while(<DATA>)
    {
        s/__TESTDB__/$path/;
        s/__USER__/$user/;
        s/__PASS__/$pass/;
        print T;
    }
    close T;

    # try to find isql
    my $isql;
    if (-x "$IB_Bin_path/$isql_name") { 
        $isql = "$IB_Bin_path/$isql_name"; 
    } else {
        for (split /:/, $ENV{PATH})
        {
            s#/+$##g;
            if (-x "$_/$isql_name") {
                $isql = "$_/$isql_name"; last; 
            }
        }
    }

    EXEC:
    {
        for (1..3)
        {
            $isql = prompt("Enter full path to isql: ", $isql);
            last EXEC if (-x $isql);
        }
        die "Unable to execute isql. Aborting..";
    }

    #PFW - isql on windows doesn't seem to work without the localhost in the db path
    my $hostpath = $path;
    if ($path =~ /^localhost:(.+)/) {
        $hostpath = $1;
    }
    # if test db directory doesn't exist -> try to create
    my $dir = dirname $hostpath;
    unless (-d $dir)
    {
        print "Can't find $dir. Trying to mkdir..\n";
        system('mkdir', '-p', $dir) == 0
        or die "Can't mkdir -p $dir";
    }

    # try to execute isql and create the test database
    system($isql, '-sql_dialect', 3, '-i', './t/create.sql') == 0
    or die "Fail calling $isql -i t/create/sql: $?";
}

################################################################################
# MAIN
################################################################################

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

# prompt for InterBase bin directory
$IB_Bin_path = dir_choice("InterBase/Firebird bin directory", [@ib_bin_dirs], [qw(gfix gfix.exe)]);

unless(-x $IB_Bin_path)
{
    carp "I cannot find your InterBase/Firebird installation.\nDBD::InterBase cannot build or run without InterBase.\n";
    exit 1;
}

# get InterBase version
my $IBVERSION;
my $GFIX_PATH = $IB_Bin_path . "/" . test_files($IB_Bin_path, [qw(gfix gfix.exe)]);
chop($IBVERSION = `$GFIX_PATH -z 2>&1`);
$IBVERSION =~ s/^gfix version //o;
my $is_final = $IBVERSION =~ /\.6\d+$/ ? 1 : 0;

# prompt for IB include dir
my $ib_inc = dir_choice("InterBase/Firebird include directory", [@ib_inc_dirs], [qw(gds.h ibase.h)]);


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
    $MakeParams{'ABSTRACT'} = 'DBD::InterBase is a DBI driver for Firebird and InterBase, written using InterBase C API.';

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
LDDLFLAGS = /LIBPATH:\"$vc_lib\" $cur_lddlflags
    '
    } ";
    }
    else
    {
        # Borland C++ 5.5
        my $bcc = $Config::Config{'bcc_path'} . "\\";

        my $BCC_PATH = dir_choice("Borland C++ directory",
            [qw(c:/borland/bcc55), $bcc],
            [qw(bin/bcc32.exe)]);

        unless(-x $BCC_PATH)
        {
            carp "I can't find your Borland C++ installation.\nDBD::InterBase cannot build.\n";
            exit 1;
        }

        my $ib_lib = dir_choice("InterBase lib directory", 
                            [$ib_lib_dir . "SDK\\lib", $ib_lib_dir . "lib"],
                            [qw(gds32.lib fbclient.lib fbclient_ms.lib)]);

        my $lib;
        if (-f "$ib_lib/fbclient.lib")
            { $lib = "$ib_lib/fbclient.lib"; }
        elsif (-f "$ib_lib/fbclient_ms.lib")
        {
            # the borland compiler want omf format libs
            system("\"$BCC_PATH\\bin\\coff2omf\"",
                   "$ib_lib/fbclient_ms.lib",
                   "$ib_lib/fbclient.lib");
            $lib = "$ib_lib/fbclient.lib";
        }
        else
            { $lib = "$ib_lib/gds32.lib"; }

        my $bcc_inc = $BCC_PATH . "include";
        $MakeParams{'CCFLAGS'}    = '-a4 -w- -DWIN32 -DNO_STRICT -DNDEBUG -D_CONSOLE -DHAVE_DES_FCRYPT -DPERL_IMPLICIT_CONTEXT -DPERL_IMPLICIT_SYS -DPERL_MSVCRT_READFIX';
        $MakeParams{'OPTIMIZE'}   = "-O2";
        $MakeParams{'INC'}       .= " -I\"$bcc_inc\"";

        eval "
    sub MY::const_loadlibs {
  '
LDLOADLIBS = \$(LIBC) import32.lib $lib cw32.lib
LDDLFLAGS = -L\"$ib_lib\" -L\"$BCC_PATH\\lib\"
  '
  }
    ";
    }
    # Will I need Cygwin rules too?
}
elsif ($os eq 'solaris')
{
    $MakeParams{'LIBS'} = '-lgdsmt -lm -lc';
}
elsif (($os eq 'linux') || ($os eq 'freebsd'))
{
    my $ib_lib = dir_choice("InterBase/Firebird lib directory",
    [qw(/usr/firebird/lib /opt/firebird/lib /usr/interbase/lib /opt/interbase/lib /usr/lib /usr/local/lib)],
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

    # o Commercial IB 5.1.1 for Red Hat Linux 6.x
    #   requires a compatibilty library to resolve
    #   symbols such as _xstat that were removed
    #   from glibc 2.1.  IB 5.6 and later don't need
    #   this, but it doesn't hurt to list the library.
    if (-f ('/lib/libNoVersion-2.1.2.so'))
  {
     $MakeParams{'LIBS'} .= ' -lNoVersion-2.1.2'
  }
}
elsif ($os eq 'hpux')
{
    $MakeParams{'LIBS'} = '-lgds -ldld';
}
elsif ($os eq 'sco')
{
    # Uncomment this line if you use InterBase 4.0 for SCO OSR5:
    # $LIBS = '-b elf -B dynamic -lgds -lsocket -lcrypt_i';

    # Uncomment this line if you use InterBase 5.5 for SCO OSR5:
    $MakeParams{'LIBS'} = '-lgds -lsocket -lcrypt_i -lc -lm';
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
