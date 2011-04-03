#!/usr/bin/perl
#
# 2011-04-03: Added support for VC++ compiler
# Copy - paste from the old Makefile.PL (not tested, not finished)
#
# 2011-03-30: Modified to use environment vars or helper subs to locate
# Firebird (only MinGW support), inspired by the App::Info module:
# Info.pm - 2008-07-18 16:17:45Z by david
#
# 2011-01-21: Addapted for DBD::Firebird by stefansbv from the
# DBD::Pg - Makefile.PL 2010-11-21 04:19:18Z by turnstep
#
# Based on:
# DBD::InterBase - Makefile.PL 2008-01-08 05:29:19Z by edpratomo
#
# Notes:
# MS specific required Firebird installation setting:
# Copy Firebird client library to <system> directory? - Yes

use strict;
use warnings;
use 5.008;
use Carp;

use Getopt::Long;
use File::Spec;
use File::Basename;
use ExtUtils::MakeMaker 5.16, qw(prompt &WriteMakefile $Verbose);
use Config;

my $os = $^O;

my $interactive;
my $help;

GetOptions(
    interactive => \$interactive,
    help        => \$help,
);

if ($help) {
    help_message();
    exit;
}

welcome_msg();

print "Configuring DBD::Firebird (on $os)\n";

my $fb_HOME;
my $fb_INC;
my $fb_LIB;

if ($interactive) {

    print qq{\nStarting interactive setup, two attempts for each option,\n};
    print qq{ if both fail, the script will abort ...\n};
    print qq{\n Enter the full paths to the Firebird instalation:\n};
    $fb_HOME = prompt_path("      Home:", $fb_HOME);

    $fb_INC = File::Spec->catdir( $fb_HOME, 'include' );
    $fb_LIB = File::Spec->catdir( $fb_HOME, 'lib' );

    $fb_INC  = prompt_path("   Include:", $fb_INC);
    $fb_LIB  = prompt_path("       Lib:", $fb_LIB);

    print qq{\n Configuring the test environment ...\n};
    print qq{\n Enter the full paths to the Firebird tools:\n};
    my $isql_bin = 'isql';
    $isql_bin .= '.exe' if ($os eq 'MSWin32');
    my $isql_path = File::Spec->catfile( $fb_HOME, 'bin', $isql_bin );
    $isql_path  = prompt_exec("      isql:", $isql_path);

    print qq{\n Enter the full path and file name of the test database (.fdb):\n};
    my $fb_testdb = prompt_new_file("   Test DB:");

    print qq{\n Enter authentication options:\n};
    my ($user, $pass) = (qw{SYSDBA masterkey});
    $user = prompt('  Username:', $user);
    $pass = prompt('  Password:', $pass);
    print "\n";

    save_test_parameters($isql_path, $fb_testdb, $user, $pass);
}
else {

    # We set FIREBIRD_HOME from the first found of:
    # 1. Environment variable
    # 2. Subdirectory of FIREBIRD_HOME
    # 3. Helper subs

    # 1. Environment variables
    $fb_HOME = $ENV{FIREBIRD_HOME};
    $fb_INC  = $ENV{FIREBIRD_INCLUDE};
    $fb_LIB  = $ENV{FIREBIRD_LIB};

    if ($fb_HOME) {
        print "(Using environment vars)\n";

        # 2. Subdirectory of FIREBIRD_HOME
        $fb_INC = $fb_INC || File::Spec->catdir( $fb_HOME, 'include' );
        $fb_LIB = $fb_LIB || File::Spec->catdir( $fb_HOME, 'lib' );
    }
    else {
        print "(No environment vars set)\n";

        # Try to locate Firebird in the ususal places
        if ($os eq 'MSWin32') {
            locate_firebird_ms();
        }
        else {
            locate_firebird();
        }
    }
}

sub prompt_path {
    my ( $msg, $value ) = @_;

  FBPATH: {
        for ( 1 .. 2 ) {
            $value = prompt( $msg, $value );
            $value = File::Spec->canonpath($value);
            last FBPATH if ( -d $value );
        }
        die "Unable to locate path. Aborting ...";
    }

    return $value;
}

sub prompt_exec {
    my ( $msg, $value ) = @_;

  FBEXEC: {
        for ( 1 .. 2 ) {
            $value = prompt( $msg, $value );
            $value = File::Spec->canonpath($value);
            last FBEXEC if ( -x $value );
        }
        die "Unable to locate executable. Aborting ...";
    }

    return $value;
}

=head2 prompt_new_file

Because we can't make difference between a simple path and a path with
a file name without extension, the fdb extension is required for the
test database.

=cut

sub prompt_new_file {
    my ( $msg, $value ) = @_;

  FBPATH: {
        for ( 1 .. 2 ) {
            $value = prompt( $msg, $value );
            $value = File::Spec->canonpath($value);
            my ($base, $path, $type) = fileparse($value, '\.fdb' );
            next if $type ne q{.fdb}; # expecting file with fdb extension
            last FBPATH if ( -d $path and $base );
        }
        die "Unable to locate path. Aborting ...";
    }

    return $value;
}

if ( !$interactive ) {
    print "\n";
    print 'FIREBIRD_HOME    : ', $fb_HOME, "\n";
    print 'FIREBIRD_INCLUDE : ', $fb_INC,  "\n";
    print 'FIREBIRD_LIB     : ', $fb_LIB,  "\n";
    print "\n";
}

my $dbi_arch_dir;
{
    eval {
        require DBI::DBD;
    };
    if ($@) {
        print "Could not load DBI::DBD - is the DBI module installed?\n";
        exit 0;
    }
    local *STDOUT; ## Prevent duplicate debug info as WriteMakefile also calls this
    $dbi_arch_dir = DBI::DBD::dbd_dbi_arch_dir();
}

#my $defines = " -DFBLIBVERSION=$serverversion -DFBDEFPORT=$defaultport";
my $comp_opts = $Config{q{ccflags}}; #. $defines;

my %MakeParams = (
    'NAME'          => 'DBD::Firebird',
    'VERSION_FROM'  => 'Firebird.pm', # finds $VERSION
    'C'             => ['dbdimp.c'],
    'H'             => ['dbdimp.h', 'Firebird.h'],
    'CCFLAGS'       => '-Wall -fno-strict-aliasing',
    'INC'           => qq(-I"$fb_INC" -I"$dbi_arch_dir"),
    'OBJECT'        => "Firebird.o dbdimp.o",
    'LIBS'          => [''],
    'OPTIMIZE'      => $Config{optimize},
    'XSPROTOARG'    => '-noprototypes',
    'dist'          => {COMPRESS=>'gzip -9f', SUFFIX=>'gz'},
    'clean'         => {FILES => qq(*.xsi *.old t/*.old *~ t/*~ trace.txt t/trace.txt lib/DBD/Firebird/*~ lib/DBD/Firebird/*.old lib/Bundle/DBD/*~ lib/Bundle/DBD/*.old dll.*)},
    'realclean'     => {FILES => "t/test.conf"},
);

# The OS specific build environment setup
SWITCH: {
    $os eq 'MSWin32' && do {
        # Set up PPM package parameters
        # Is the mail address still valid?
        $MakeParams{AUTHOR} =
          'Edwin Pratomo (edpratomo@users.sourceforge.net)';
        $MakeParams{ABSTRACT} =
'DBD::Firebird is a DBI driver for Firebird, written using Firebird C API.';

        # Choices for the compiler
        if ( $Config{cc} eq q{gcc} ) {
            setup_for_ms_gcc();
        }
        elsif ( $Config{cc} eq q{cl} ) {
            setup_for_ms_cl();
        }
        else {
            print "No suitable compiler found\n";
            print "Try: ppm install MinGW, to install MinGW!\n";
            exit 1;
        }
        last SWITCH;
    };
    $os eq 'solaris' && do {
        $MakeParams{LIBS} = '-lgdsmt -lm -lc';
        last SWITCH;
    };
    $os eq 'linux' && do {
        my $lib = 'fbclient';
        my $fb_lib = $fb_LIB;
        my $ldl = ($os eq 'linux') ? '-ldl' : '';
        $MakeParams{LIBS} = "-L$fb_lib -l$lib $ldl ";
        last SWITCH;
    };
    $os eq 'freebsd' && do {
        my $lib = 'fbclient';
        my $fb_lib = $fb_LIB;
        my $ldl = ($os eq 'linux') ? '-ldl' : '';
        $MakeParams{LIBS} = "-L$fb_lib -l$lib $ldl ";
        last SWITCH;
    };
    $os eq 'hpux' && do {
        $MakeParams{LIBS} = '-lgds -ldld';
        last SWITCH;
    };
    $os eq 'sunos' && do {
        $MakeParams{LIBS} = '-lgdslib -ldl';
        last SWITCH;
    };
    $os eq 'irix' && do {
        $MakeParams{LIBS} = '-lgds -lsun';
        last SWITCH;
    };
    $os eq 'aix' && do {
        $MakeParams{LIBS} = '-lgdsshr';
        last SWITCH;
    };
    $os eq 'dgux' && do {
        $MakeParams{LIBS} = '-lgds -lgdsf -ldl -ldgc';
        last SWITCH;
    };
    $os eq 'osf1' && do {
        $MakeParams{LIBS} = '-lgds';
        last SWITCH;
    };
    $os eq 'sysv' && do {
        $MakeParams{LIBS} = '-lgds -lnsl -lsocket -ldl';
        last SWITCH;
    };

    carp "DBD::Firebird is not supported on platform $os.\n";
    exit 1;
}

# And last but not least write the Makefile
WriteMakefile(%MakeParams);

sub MY::postamble {
    return DBI::DBD->dbd_postamble(@_);
}

sub setup_for_ms_gcc {

    # Support for MinGW
    #  ActiveState: cc => V:\absolute\path\to\gcc.exe
    #  Strawberry : cc => gcc
    print "Using MinGW gcc\n";

    # For ActiveState Perl hardwired MinGW path          # other idea?
    my $mingw_path = 'C:\Perl\site\lib\auto\MinGW';

    # Expecting absolute paths in Straberry Perl
    my $mingw_inc = $Config{incpath};

    # For ActiveState Perl is  \include                  # always?
    if ( $mingw_inc eq '\include' ) {
        $mingw_inc = File::Spec->catpath( $mingw_path, $mingw_inc );
    }
    my $mingw_lib = $Config{libpth};

    # For ActiveState Perl is  \lib                      # always?
    if ( $mingw_lib eq '\lib' ) {
        $mingw_lib = File::Spec->catpath( $mingw_path, $mingw_lib );
    }

    $INC .= qq{ -I"$mingw_inc"};

    my $cur_libs      = $Config{libs};
    my $cur_lddlflags = $Config{lddlflags};

    my $lib;
    if   ( -f "$fb_LIB/fbclient_ms.lib" ) { $lib = "$fb_LIB/fbclient_ms.lib"; }
    else                                  { $lib = "$fb_LIB/gds32_ms.lib"; }

    # This is ugly :)
    eval "
    sub MY::const_loadlibs {
    '
LDLOADLIBS = \"$lib\" $cur_libs
LDDLFLAGS =  -L\"$mingw_lib\" $cur_lddlflags
    '
} ";
}

sub setup_for_ms_cl {

    # Try to find Microsoft Visual C++ compiler
    my $vc_dir = registry_lookup_ms_cl(); # not finished, not tested !!!

    my @vc_dirs = ( $vc_dir . "/bin" );

    my $VC_PATH =
        dir_choice( "Visual C++ directory", [@vc_dirs], [qw(cl.exe)] );

    unless ( -x $VC_PATH ) {
        carp
            "I can't find your MS VC++ installation.\nDBD::Firebird cannot build.\n";
        exit 1;
    }

    my $vc_inc = $VC_PATH . "/include";
    my $vc_lib = $VC_PATH . "/lib";

    $INC .= " -I\"$vc_inc\"";

    my $ib_lib = dir_choice(
        "Firebird lib directory",
        [ $fb_LIB . "SDK\\lib_ms", $fb_LIB . "lib" ],
        [qw(gds32_ms.lib fbclient_ms.lib)]
    );

    my $cur_libs      = $Config{libs};
    my $cur_lddlflags = $Config{lddlflags};

    my $lib;
    if (-f "$fb_LIB/fbclient_ms.lib")
        { $lib = "$fb_LIB/fbclient_ms.lib"; }
    else
        { $lib = "$fb_LIB/gds32_ms.lib"; }

    eval "
    sub MY::const_loadlibs {
    '
LDLOADLIBS = \"$lib\" $cur_libs
LDDLFLAGS =  -L\"$vc_lib\" $cur_lddlflags
    '
} ";

return;
}

#-- Helper subs

=head2 locate_firebird

On *nix like systems try different standard paths.

=cut

sub locate_firebird {

    my @bd = search_fb_home_dirs();

    foreach my $dir (@bd) {
        if ( -d $dir ) {

            # File names specific to the Firebird/bin dir
            my @fb_files = qw{isql fbsql};   # fbsql not yet!

            my $found = 0;
            while ( !$found ) {
                my $file = shift @fb_files or last;

                $file = File::Spec->catfile( $dir, 'bin', $file );

                if ( -f $file and -x $file ) {
                    # Located
                    check_and_set_devlibs($dir);
                    my $isql_path = File::Spec->canonpath($file);
                    save_test_parameters($isql_path);
                    last;
                }
            }
        }
    }

    return;
}

sub check_and_set_devlibs {
    my $fb_dir = shift;

    $fb_HOME = File::Spec->canonpath($fb_dir);

    $fb_INC = File::Spec->catdir( $fb_HOME, 'include' );
    $fb_INC = alternative_locations('inc') if !-d $fb_INC;

    $fb_LIB = File::Spec->catdir( $fb_HOME, 'lib' );
    $fb_LIB = alternative_locations('lib') if !-d $fb_LIB;

    return;
}

sub alternative_locations {
    my $find_what = shift;

    my @fid = ();
    @fid = search_fb_lib_dirs() if $find_what eq q{lib};
    @fid = search_fb_inc_dirs() if $find_what eq q{inc};

    foreach my $dir ( @fid ) {
        return $dir if -d $dir;
    }

    help_message();
    die "Firebird '$find_what' dir not located!";
}

sub search_fb_home_dirs {

    # Add other standard paths here
    return (
        qw{
          /opt/firebird
          /usr/local/firebird
          /usr/lib/firebird
          },
    );
}

sub search_fb_inc_dirs {

    # Add other standard paths here for include
    return (
        qw{
          /usr/include/firebird
          /usr/local/include/firebird
        },
    );
}

sub search_fb_lib_dirs {

    # Add other standard paths here for lib
    return (
        qw{
          /usr/lib/firebird
          /usr/local/lib/firebird
        },
    );
}

=head2 locate_firebird_ms

On Windows use the Registry to locate Firebird.

=cut

sub locate_firebird_ms {

    my $hp_ref = registry_lookup_fb();
    if (ref $hp_ref) {
        $fb_HOME = File::Spec->canonpath($hp_ref->[0]);
        $fb_INC  = File::Spec->catdir( $fb_HOME, 'include' );
        $fb_LIB  = File::Spec->catdir( $fb_HOME, 'lib' );
    }
}

=head2 registry_lookup_fb

Use the Windows registry to locate Firebird.

=cut

sub registry_lookup_fb {

    my @path;
    eval {
        require Win32::TieRegistry;

        my $path = Win32::TieRegistry->new(
"HKEY_LOCAL_MACHINE\\SOFTWARE\\Firebird Project\\Firebird Server\\Instances")
            ->GetValue("DefaultInstance");
        push @path, $path if $path;
    };
    if ($@) {
        warn "Only for Win32!";
        die "Failed to locate Firebird!\n";
    }

    return wantarray ? @path : \@path;
}

sub registry_lookup_ms_cl {

    my @path;
    eval {
        require Win32::TieRegistry;

        my $path = Win32::TieRegistry->new("path")
            ->GetValue("DefaultInstance");
        push @path, $path if $path;
    };
    if ($@) {
        warn "Only for Win32!";
        die "Failed to locate Firebird!\n";
    }

    return wantarray ? @path : \@path;

    # my $sw = $Registry->{"LMachine/Software/"};

    # # We have to check more than one keys, because different
    # # releases of Visual C++ have used different key hierarchies.
    # my $key = $sw->{"Microsoft/VisualStudio/6.0/Setup/Microsoft Visual C++"}
    #   || $sw->{"Microsoft/VisualStudio/7.0/Setup/VC"};

    # if ( defined($key) ) {
    #     $vc_dir = $key->{"/ProductDir"};
    # }
}

sub help_message {

    my $msg =<<"MSG";

By default Makefile.PL uses the known standard dirs to find the
location of the Firebird home, library and include directories.
However if that fails or you want to control it yourself, define the
environment variable FIREBIRD_HOME.

If FIREBIRD_INCLUDE and FIREBIRD_LIB are not sub directories of
FIREBIRD_HOME, define them also.

Other option is to execute this script with the interactive option.

The usual steps to install DBD::Firebird:

% perl Makefile.PL [ -i[nteractive] ]
% make
% make test
% make install

Do first 3 steps as a normal user, not as root!

If all else fails, email <maintainer_email\@here> for help.

MSG

    print $msg;
}

sub save_test_parameters {
    my ($isql_path, $path, $user, $pass) = @_;

    my $test_conf = './t/test.conf';

    open my $t_fh, '>', $test_conf or die "Can't write $test_conf: $!";

    my $test_time = scalar localtime();
    my @record = (
        q(# This is a temporary file used for test setup #),
        q(# The field separator is :=                    #),
        q(# Should be automaticaly deleted at tests end! #),
        q(# Init section ------ (created by Makefile.PL) #),
        q(# Time: ) . $test_time,
        qq(isql:=$isql_path),
    );

    if ($path and $user and $pass) {
        push @record, qq(tdsn:=dbi:Firebird:db=$path);
        push @record, qq(user:=$user);
        push @record, qq(pass:=$pass);
    }

    my $rec = join "\n", @record;

    print {$t_fh} $rec, "\n";

    close $t_fh or die "Can't close $test_conf: $!";

    return;
}

sub welcome_msg {

    print "\nWelcome!\n";

    print "This script prepares the instalation of the DBD::Firebird module.\n";
    print "In the instalation will create a temporary file to store\n";
    print "the values required for the testing phase, including the password\n";
    print "for access to the Firebird server\n";
}

exit 0;

# end of Makefile.PL
