#!/usr/bin/perl
#
# 2011-03-30 modified to use environment vars or helper subs to locate
# Firebird (only MinGW support)
# Inspired by the App::Info module:
# Info.pm - 2008-07-18 16:17:45Z by david
#
# 2011-01-21 addapted for DBD::Firebird by stefansbv from the
# DBD::Pg - Makefile.PL 2010-11-21 04:19:18Z by turnstep
#
# Based on:
# DBD::InterBase - Makefile.PL 2008-01-08 05:29:19Z by edpratomo

use strict;
use warnings;

use Carp;
use 5.008;

use File::Spec;
use ExtUtils::MakeMaker;
use Config;

my $os = $^O;

# my $lib;
# BEGIN {
#     use vars qw/$sep/;
#     my %sep = (
#                MacOS   => ':',
#                MSWin32 => '\\',
#                os2     => '\\',
#                VMS     => '\\',
#                NetWare => '\\',
#                dos     => '\\',
#                );
#     $sep = $sep{$os} || '/';
#     $lib = join $sep, 't', 'lib';
# }

# use lib $lib;
# if ($VERSION =~ /_/) {
#     print "WARNING! This is a test version ($VERSION)!\n";
#     print " Should not be used in production!\n";
# }

if (grep { /help/ } @ARGV) {
    help_message();
    exit 1;
}

print "Configuring DBD::Firebird\n";
print "OS: $os\n";

# We set FIREBIRD_HOME from the first found of:
# 1. Environment variable
# 2. Subdirectory of FIREBIRD_HOME
# 3. Helper subs

# 1. Environment variable
my $fb_HOME = $ENV{FIREBIRD_HOME};
my $fb_INC  = $ENV{FIREBIRD_INCLUDE};
my $fb_LIB  = $ENV{FIREBIRD_LIB};

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

print "\n";
print 'FIREBIRD_HOME    : ', $fb_HOME, "\n";
print 'FIREBIRD_INCLUDE : ', $fb_INC,  "\n";
print 'FIREBIRD_LIB     : ', $fb_LIB,  "\n";
print "\n";

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
    'OPTIMIZE'      => $Config::Config{'optimize'},
    'XSPROTOARG'    => '-noprototypes',
    'dist'          => {COMPRESS=>'gzip -9f', SUFFIX=>'gz'},
    'clean'         => {FILES => qq(*.xsi *.old t/*.old *~ t/*~ trace.txt t/trace.txt lib/DBD/Firebird/*~ lib/DBD/Firebird/*.old lib/Bundle/DBD/*~ lib/Bundle/DBD/*.old dll.*)},
    'realclean'     => {FILES => "t/test.conf"},
);

# The OS specific build environment setup
SWITCH: {
    $os eq 'MSWin32' && do {
        setup_for_ms();                      # to big to put here ;)
        last SWITCH;
    };
    $os eq 'solaris' && do {
        $MakeParams{'LIBS'} = '-lgdsmt -lm -lc';
        last SWITCH;
    };
    $os eq 'linux' && do {
        my $lib = 'fbclient';
        my $fb_lib = $fb_LIB;
        my $ldl = ($os eq 'linux') ? '-ldl' : '';
        $MakeParams{'LIBS'} = "-L$fb_lib -l$lib $ldl ";
        last SWITCH;
    };
    $os eq 'freebsd' && do {
        my $lib = 'fbclient';
        my $fb_lib = $fb_LIB;
        my $ldl = ($os eq 'linux') ? '-ldl' : '';
        $MakeParams{'LIBS'} = "-L$fb_lib -l$lib $ldl ";
        last SWITCH;
    };
    $os eq 'hpux' && do {
        $MakeParams{'LIBS'} = '-lgds -ldld';
        last SWITCH;
    };
    $os eq 'sunos' && do {
        $MakeParams{'LIBS'} = '-lgdslib -ldl';
        last SWITCH;
    };
    $os eq 'irix' && do {
        $MakeParams{'LIBS'} = '-lgds -lsun';
        last SWITCH;
    };
    $os eq 'aix' && do {
        $MakeParams{'LIBS'} = '-lgdsshr';
        last SWITCH;
    };
    $os eq 'dgux' && do {
        $MakeParams{'LIBS'} = '-lgds -lgdsf -ldl -ldgc';
        last SWITCH;
    };
    $os eq 'osf1' && do {
        $MakeParams{'LIBS'} = '-lgds';
        last SWITCH;
    };
    $os eq 'sysv' && do {
        $MakeParams{'LIBS'} = '-lgds -lnsl -lsocket -ldl';
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

#-- MS specific
# Copy Firebird client library to <system> directory? Yes

sub setup_for_ms {
    # Set up PPM package parameters
    $MakeParams{'AUTHOR'} = 'Edwin Pratomo (edpratomo@users.sourceforge.net)';
    $MakeParams{'ABSTRACT'} =
'DBD::Firebird is a DBI driver for Firebird , written using Firebird C API.';

    # Support for MinGW
    #  ActiveState: cc => V:\absolute\path\to\gcc.exe
    #  Strawberry : cc => gcc
    print "Using MinGW gcc\n";

    # For ActiveState Perl hardwired MinGW path          # other idea?
    my $mingw_path = 'C:\Perl\site\lib\auto\MinGW';

    # Expecting absolute paths in Straberry Perl
    my $mingw_inc = $Config::Config{incpath};

    # For ActiveState Perl is  \include                  # always?
    if ( $mingw_inc eq '\include' ) {
        $mingw_inc = File::Spec->catpath( $mingw_path, $mingw_inc );
    }
    my $mingw_lib = $Config::Config{libpth};

    # For ActiveState Perl is  \lib                      # always?
    if ( $mingw_lib eq '\lib' ) {
        $mingw_lib = File::Spec->catpath( $mingw_path, $mingw_lib );
    }

    # $INC .= " -I\"$mingw_inc\"";

    my $cur_libs      = $Config::Config{libs};
    my $cur_lddlflags = $Config::Config{lddlflags};

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

#-- Helper subs

=head2 locate_firebird

On *nix like systems try different standard paths.

=cut

sub locate_firebird {

    my @bd = search_fb_home_dirs();

    foreach my $dir (@bd) {
        if ( -d $dir ) {

            # File names specific to the Firebird/bin dir
            my @fb_files = qw{isql fbsql};

            my $found = 0;
            while ( !$found ) {
                my $file = shift @fb_files or last;

                $file = File::Spec->catfile( $dir, 'bin', $file );

                if ( -f $file and -x $file ) {
                    # Located
                    check_and_set_devlibs($dir);
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

    my $hp_ref = reg_dirs();
    if (ref $hp_ref) {
        $fb_HOME = File::Spec->canonpath($hp_ref->[0]);
        $fb_INC  = File::Spec->catdir( $fb_HOME, 'include' );
        $fb_LIB  = File::Spec->catdir( $fb_HOME, 'lib' );
    }
}

=head2 reg_dirs

Use the Windows registry to locate Firebird.

=cut

sub reg_dirs {

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

sub help_message {

    my $msg =<<"MSG";

By default Makefile.PL uses the known standard dirs to find the
location of the Firebird home, library and include directories.
However if that fails or you want to control it yourself, define the
environment variable FIREBIRD_HOME.

If FIREBIRD_INCLUDE and FIREBIRD_LIB are not sub directories of
FIREBIRD_HOME, defined them also.

The usual steps to install DBD::Firebird:

1.   perl Makefile.PL
2.   make
3.   make test
4.   make install

Do steps 1 to 3 as a normal user, not as root!

If all else fails, email <maintainer_email\@here> for help.

MSG

    print $msg;
}

exit 0;

# end of Makefile.PL
