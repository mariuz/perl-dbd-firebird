#!perl
#-----------------------------------------------------------------------------
#
#   Copyright (c) 2011 Stefan Suciu <stefbv70@gmail.com>
#   Copyright (c) 2011 Damyan Ivanov <dmn@debian.org>
#   Copyright (c) 2011 Marius Popa <mapopa@gmail.com>
#   Copyright (c) 2011 Alexandr Ciornii <alexchorny@gmail.com>
#   Copyright (c) 1999-2008 Edwin Pratomo
#   Portions Copyright (c) 2001-2005 Daniel Ritz
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file.
#
#-----------------------------------------------------------------------------
# Changes:
#
# 2011-09-02: Integrated patch from real-dam
# Do not link with libdl.so on GNU/Linux
#
# 2011-04-04: Integrated patch from Alexandr Ciornii regarding
# WriteMakefile sub.
# Moved prompting to subs, other layout changes.
#
# 2011-04-03, Added CLI prompting with optional -interactive command
# line parameter.
# Added support for VC++ copy-paste from the original (NOT tested!)
#
# 2011-03-30, Refactored.
# Modified to use environment vars or helper subs to locate Firebird
# (only MinGW support), removed the CLI prompts.
# inspired by the App::Info module: Info.pm - 2008-07-18 16:17:45Z by david
# and             DBD::Pg - Makefile.PL 2010-11-21 04:19:18Z by turnstep
#
# 2011-01-31, stefansbv:
# using the three-argument form of open for reading tests-setup.tmp.conf
#
# 2011-01-26, stefansbv:
# fixed the isql tool path and the command line
#   (using quotes around parameters and canonpath)
# when isql error create the test database and inform the user
# improved support for MinGW (now using the Config module)
# added support for ActivePerl! :)
#
# Notes: MS specific required Firebird installation setting: Copy
# Firebird client library to <system> directory? - Yes, unless the
# Firebird HOME is in your path.
#

package MY;

our $postamble;

sub postamble {
    return $postamble;
}

1;

package main;

use strict;
use warnings;
use Carp;
use 5.008;

use Getopt::Long;
use File::Spec;
use File::Basename;
use ExtUtils::MakeMaker 5.16, qw(prompt &WriteMakefile $Verbose);
use Config;

# Globals vars

our $EMBEDDED = 0;
BEGIN {
    # Theory of operation:
    #  we copy this Makefile.PL to embed/ and set $EMBEDDED to 1 there
    #  this way we have to maintain one code base with special cases for
    #  the embedded module build
    #  See create_embedded_Makefile_PL below

    unless ($EMBEDDED) {
        unshift @INC, 'inc';
        require FirebirdMaker;
        FirebirdMaker->import;
    }
}

my $interactive;
my $help;
my $os = $^O;

GetOptions(
    interactive => \$interactive,
    help        => \$help,
) unless $EMBEDDED;

if ($help) {
    help_message();
    exit;
}

my $module_name = $EMBEDDED ? 'DBD::FirebirdEmbedded' : 'DBD::Firebird';

print "Configuring $module_name (on $os)\n";

$FB::libfbembed_available = 0;

# We set FIREBIRD_HOME from the first found of:
# 1. Environment variable
# 2. Subdirectory of FIREBIRD_HOME
# 3. Helper subs (search Firebird in the known locations)

unless ($EMBEDDED) {
    # 1. Environment variables
    $FB::HOME = $ENV{FIREBIRD_HOME};
    $FB::INC  = $ENV{FIREBIRD_INCLUDE};
    $FB::LIB  = $ENV{FIREBIRD_LIB};

    if ($FB::HOME) {

        # 2. Subdirectory of FIREBIRD_HOME
        if ($os eq 'darwin') {
            $FB::INC ||= (grep -d, (
                # could be set to Resources/ or not
                File::Spec->catdir( $FB::HOME, '..', 'Headers' ),
                File::Spec->catdir( $FB::HOME, 'Headers' ),
                File::Spec->catdir( $FB::HOME, 'include' ),
            ))[0];
            $FB::LIB ||= (grep -d, (
                File::Spec->catdir( $FB::HOME, '..', 'Libraries' ),
                File::Spec->catdir( $FB::HOME, 'Libraries' ),
                File::Spec->catdir( $FB::HOME, 'lib' ),
            ))[0];
        }
        else {
            $FB::INC ||= File::Spec->catdir( $FB::HOME, 'include' );
            $FB::LIB ||= File::Spec->catdir( $FB::HOME, 'lib' );
        }
    }
    else {
        # No FIREBIRD_HOME
        # We could check FIREBIRD_INCLUDE and FIREBIRD_LIB and set
        # FIREBIRD_HOME as parent dir, but maybe is to weird :)
        # Anyway their value take precedence in locate_firebird sub.

        # Try to locate Firebird in the ususal places
        if ($os eq 'MSWin32' || $os eq 'cygwin') {
            locate_firebird_ms();
        }
        elsif ($os eq 'darwin') {
            $FB::HOME = '/Library/Frameworks/Firebird.framework/Resources';
            $FB::INC  = '/Library/Frameworks/Firebird.framework/Headers';
            $FB::LIB  = '/Library/Frameworks/Firebird.framework/Libraries';
        }
        else {
            locate_firebird();
        }
    }
}

my $client_lib = $EMBEDDED ? 'fbembed' : 'fbclient';

if ($interactive) {

    # Interactive mode setup
    welcome_msg();

    prompt_for_settings();
}
else {
    print "\n";
    print 'FIREBIRD_HOME   : ', $FB::HOME || '(none)', "\n";
    print 'FIREBIRD_INCLUDE: ', $FB::INC  || '(none)', "\n";
    print 'FIREBIRD_LIB    : ', $FB::LIB  || '(none)', "\n";
    print 'Client library  : ', $client_lib,"\n";
    print "\n";

    save_test_parameters() unless $EMBEDDED;
}

do {
    eval {
        require DBI::DBD;
    };
    if ($@) {
        print "Could not load DBI::DBD - is the DBI module installed?\n";
        exit 0;
    }
    $MY::postamble ||= DBI::DBD::dbd_postamble();
    ## Prevent duplicate debug info as dbd_postamble also calls this
    local *STDOUT;
    $FB::dbi_arch_dir ||= DBI::DBD::dbd_dbi_arch_dir();
} unless $EMBEDDED;

my $cflags = $Config{q{ccflags}}||'';
$cflags .= " $ENV{CFLAGS}" if $ENV{CFLAGS};

if ($Config{cc} =~ /gcc/) {
    $cflags = "-Wall -fno-strict-aliasing $cflags";
}

my @inc;
for ( $FB::INC, $FB::dbi_arch_dir ) { push @inc, qq(-I"$_") if $_ }

my %MakeParams = (
    NAME         => $module_name,
    VERSION_FROM => $EMBEDDED
        ? 'FirebirdEmbedded.pm'
        : 'Firebird.pm',    # finds $VERSION
    C            => ['dbdimp.c'],
    H => [ 'dbdimp.h', $EMBEDDED ? 'FirebirdEmbedded.h' : 'Firebird.h' ],
    CCFLAGS      => $cflags,
    ( $EMBEDDED ? ( DEFINE => '-DEMBEDDED' ) : () ),
    INC          => join( ' ', @inc ),
    OBJECT => join( ' ',
        $EMBEDDED ? "FirebirdEmbedded.o" : "Firebird.o", "dbdimp.o" ),
    LIBS         => [''],
    OPTIMIZE     => $Config{optimize},
    XSPROTOARG   => '-noprototypes',
    dist         => { COMPRESS => 'gzip -9f', SUFFIX => 'gz' },
    clean        => {
        FILES =>
qq(*.xsi *.old t/*.old *~ t/*~ trace.txt t/trace.txt lib/DBD/Firebird/*~ lib/DBD/Firebird/*.old lib/Bundle/DBD/*~ lib/Bundle/DBD/*.old dll.* fb_init fb_trace_* dbd-fb-testdb.fdb)
    },
    realclean => { FILES => qq($test_conf $test_mark t/*.sql embed t/embed-*.t) },
    AUTHOR => 'Edwin Pratomo (edpratomo@users.sourceforge.net)',
    ABSTRACT =>
'DBD::Firebird is a DBI driver for Firebird, written using Firebird C API.',
    PREREQ_PM          => { DBI          => 1.41 },
    CONFIGURE_REQUIRES => {
        DBI          => 1.41,'
        File::Which' => 0,
    },
    BUILD_REQUIRES     => {
        'Test::More' => 0.4,
        'Test::Exception' => 0.31,
    },
    LICENSE            => 'perl',
    MIN_PERL_VERSION   => '5.008001',
    META_MERGE         => {
        resources =>
          { repository => 'https://github.com/mariuz/perl-dbd-firebird', },
    },
);

# The OS specific build environment setup
SWITCH: {
    $os eq 'MSWin32' && do {

        # Choices for the compiler
        if ( $Config{cc} =~ m{gcc} ) {
            setup_for_ms_gcc();
        }
        elsif ( $Config{cc} eq q{cl} ) {
            setup_for_ms_cl();
        }
        else {
            print "No suitable compiler found\n";
            print "(Try: ppm install MinGW, to install MinGW!)\n";
            exit 1;
        }
        last SWITCH;
    };
    $os eq 'cygwin' && do {
        setup_for_cygwin();
        last SWITCH;
    };
    $os eq 'solaris' && do {
        $MakeParams{LIBS} = '-lgdsmt -lm -lc';
        last SWITCH;
    };
    $os eq 'linux' && do {
        $MakeParams{LIBS} = "-L$FB::LIB -l$client_lib ";
        last SWITCH;
    };
    $os eq 'freebsd' && do {
        $MakeParams{LIBS} = "-L$FB::LIB -l$client_lib ";
        last SWITCH;
    };
    $os eq 'gnukfreebsd' && do {
        $MakeParams{LIBS} = "-L$FB::LIB -l$client_lib ";
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
    $os eq 'darwin' && do {
        $MakeParams{LDDLFLAGS} = $Config{lddlflags} . " -framework Firebird ";
        last SWITCH;
    };

    carp "DBD::Firebird is not supported on platform $os.\n";
    exit 1;
}

unless ($EMBEDDED) {
    if ($FB::libfbembed_available) {
        print "Found libfbembed, will build DBD::FirebirdEmbed too.\n";
        create_embedded_files();
    }
    else {
        print "libfbembed not found, building of DBD::FirebirdEmbed skipped.\n";
        # make sure there is no embedded build involved
        my $mfpl = File::Spec->catfile( 'embed', 'Makefile.PL' );
        unlink $mfpl if -e $mfpl;
    }
}

# And last but not least write the Makefile
WriteMakefile1(%MakeParams);

closing_msg()
    if !$EMBEDDED
        and !$interactive
        and ( !$ENV{DBI_PASS} and !$ENV{ISC_PASSWORD} );


exit 0;

#- end of Makefile.PL
