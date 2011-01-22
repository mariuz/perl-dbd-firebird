#!/usr/bin/perl
#
# 2011-01-21 addapted for DBD::Firebird by stefansbv from the
# DBD::Pg - Makefile.PL 2010-11-21 04:19:18Z by turnstep
#

use strict;
use warnings;
use 5.008;

use ExtUtils::MakeMaker;
use Config;

my $VERSION = '0.49';           # not yet decided !!!

my $lib;
BEGIN {
    use vars qw/$sep/;
    my %sep = (
               MacOS   => ':',
               MSWin32 => '\\',
               os2     => '\\',
               VMS     => '\\',
               NetWare => '\\',
               dos     => '\\',
               );
    $sep = $sep{$^O} || '/';
    $lib = join $sep, 't', 'lib';
}

use lib $lib;
if ($VERSION =~ /_/) {
    print "WARNING! This is a test version ($VERSION)!\n";
    print " Should not be used in production!\n";
}

if (grep { /help/ } @ARGV) {
    print qq{
Usage: perl $0

No other options are necessary, although you may need to
set some evironment variables. See the README file for full details.

In brief:

By default Makefile.PL uses App::Info to find the location of the
Firebird home, library and include directories.  However, if you want to
control it yourself, define the environment variable FIREBIRD_HOME.

The usual steps to install DBD::Firebird:

1.   perl Makefile.PL
2.   make
3.   make test
4.   make install

Do steps 1 to 3 as a normal user, not as root!

If all else fails, email <maintainer_email\@here> for help.

};
    exit 1;

}

print "Configuring DBD::Firebird $VERSION\n";

# We need the version information to properly set compiler options later
# Use App::Info to get the data we need.
require App::Info::RDBMS::Firebird;
require App::Info::Handler::Prompt;
my $p  = App::Info::Handler::Prompt->new;
my $fb = App::Info::RDBMS::Firebird->new(on_unknown => $p);
my ($major_ver, $minor_ver, $patch, $conf, $bindir) = map {$fb->$_}
    qw/major_version minor_version patch_version cflags bin_dir/;

my $serverversion; # 0
my $defaultport;   # 0;

if (defined $major_ver) {
    $serverversion = sprintf '%d.%d.%d', $major_ver, $minor_ver, $patch;
    $defaultport   = $conf =~ /with-fbport=(\d+)/ ? $1 : 3050;
}

# We set FIREBIRD_HOME from the first found of:
# 1. environment variable
# 2. App::Info::RDBMS::Firebird information

my $FIREBIRD_HOME    = $ENV{FIREBIRD_HOME}    || $fb->home_dir;
# Just for the sake of completeness ;)
my $FIREBIRD_INCLUDE = $ENV{FIREBIRD_INCLUDE} || $fb->inc_dir;
my $FIREBIRD_LIB     = $ENV{FIREBIRD_LIB}     || $fb->lib_dir;

my $os      = $^O;
my $showinc = $FIREBIRD_INCLUDE || '(not set)';
my $showlib = $FIREBIRD_LIB     || '(not set)';

# Show info to the user
print "OS: $os\n";
print "Firebird version: $serverversion (default port: $defaultport)\n";
print "FIREBIRD_HOME   : $FIREBIRD_HOME\n";
print "FIREBIRD_INCLUDE: $showinc\n";
print "FIREBIRD_LIB    : $showlib\n";
print "\n";

my $baddir = 0;
sub does_path_exist {
    my ($path_name, $path) = @_;

    return if ! defined $path or ! length $path or -d $path;
    printf "The value of %s points to a non-existent directory: %s\n",
        $path_name, $path;
    $baddir++;
    return;
}

does_path_exist('FIREBIRD_HOME', $ENV{FIREBIRD_HOME});

if ($baddir) {
    print "Cannot build unless the directories exist, exiting.\n";
    exit 0;
}

# if ($serverversion < 11) {
#     print "Could not determine the Firebird library version.\n".
#     "Please ensure that a valid path is given to the 'fb_config' command,\n".
#     "either manually or by setting the environment variables\n".
#     "FIREBIRD_DATA, FIREBIRD_INCLUDE, and FIREBIRD_LIB\n";
#     exit 0;
# }

### This may be used for version dependent builds
## Warn about older versions
# if ($serverversion < 70400) {
#     print "\n****************\n";
#     print "WARNING! DBD::Firebird no longer supports versions less than ...\n";
#     print "You must upgrade Firebird to a newer version.\n";
#     print "****************\n\n";
#     exit 1;
# }

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

my $defines = " -DFBLIBVERSION=$serverversion -DFBDEFPORT=$defaultport";
my $comp_opts = $Config{q{ccflags}} . $defines;

### This are from the DBD::Pg make file, someone have to check each of
### them if apply for Firebird !!!
if ($ENV{DBDFB_GCCDEBUG}) {
    warn "Enabling many compiler options\n";
    $comp_opts .= ' -Wchar-subscripts -Wcomment';
    $comp_opts .= ' -Wformat=2'; ## does -Wformat,-Wformat-y2k,-Wformat-nonliteral,-Wformat-security
    $comp_opts .= ' -Wnonnull';
    $comp_opts .= ' -Wuninitialized -Winit-self'; ## latter requires the former
    $comp_opts .= ' -Wimplicit'; ## does -Wimplicit-int and -Wimplicit-function-declaration
    $comp_opts .= ' -Wmain -Wmissing-braces -Wparentheses -Wsequence-point -Wreturn-type -Wswitch -Wswitch-enum -Wtrigraphs';
    $comp_opts .= ' -Wunused'; ## contains -Wunused- function,label,parameter,variable,value
    $comp_opts .= ' -Wunknown-pragmas -Wstrict-aliasing';
    $comp_opts .= ' -Wall'; ## all of above, but we enumerate anyway
    $comp_opts .= ' -Wextra -Wdeclaration-after-statement -Wendif-labels -Wpointer-arith';
    $comp_opts .= ' -Wbad-function-cast -Wcast-qual -Wcast-align -Wsign-compare -Waggregate-return';
    $comp_opts .= ' -Wmissing-prototypes -Wmissing-declarations -Wmissing-format-attribute -Wpacked -Winline -Winvalid-pch';
    $comp_opts .= ' -Wdisabled-optimization';
    $comp_opts .= ' -Wnested-externs';
    $comp_opts .= " -Wstrict-prototypes"; ## Still hits a couple places in types.h
    $comp_opts .= " -Wswitch-default";
    $comp_opts .= " -Wsystem-headers";
    $comp_opts .= " -Wmissing-noreturn";
    $comp_opts .= " -Wfloat-equal"; ## Does not like SvTRUE() calls
    $comp_opts .= " -Wpadded"; ## Use when adding/changing our structs
}

### Should change the name of the module to DBD::Firebird, ASAP
my %opts =
    (
     NAME           => 'DBD::InterBase',
     VERSION_FROM   => 'InterBase.pm',
     INC            => "-I". $fb->inc_dir . " -I$dbi_arch_dir",
     OBJECT         => "InterBase\$(OBJ_EXT) dbdimp\$(OBJ_EXT)",
     LIBS           => [ $fb->libs . ' -ldl'],
     AUTHOR         => 'Edwin Pratomo',
     ABSTRACT       => 'InterBase database driver for the DBI module',
     PREREQ_PM      => {
                        'ExtUtils::MakeMaker' => '6.11',
                        'DBI'                 => '1.52',
                        'Test::More'          => '0.61',
                        'version'             => '0',
                       },
     CCFLAGS        => $comp_opts,
     PERL_MALLOC_OK => 1,
     NEEDS_LINKING  => 1,
     NO_META        => 1,
     NORECURS       => 1,
     clean          => { FILES => 'trace.txt InterBase.xsi' },
     #realclean      => { FILES => 'dbdfb_test_database/' },
);

### This should be checked: !!!

if ($os eq 'hpux') {
    my $osvers = $Config{osvers};
    if ($osvers < 10) {
        print "Warning: Forced to build static not dynamic on $os $osvers.\a\n";
        $opts{LINKTYPE} = 'static';
    }
}
elsif ($os =~ /Win32/) {
    # my $msdir = $FIREBIRD_LIB;
    # $msdir =~ s{"$}{/ms"};
    # $opts{LIBS}[0] .= " -L$msdir -lsecur32";
}

if ($Config{dlsrc} =~ /dl_none/) {
    $opts{LINKTYPE} = 'static';
}

sub constants {
    my $self = shift;

    my $old_constants = $self->SUPER::constants();
    my $new_constants = '';
    for my $line (split /\n/ => $old_constants) {
        if ($line =~ /^INC = .*strawberry.*/ ) {
            print qq(Strawberry Perl found; adjusting the INC variable;\n);
            $line . ' -I ' . DBI::DBD::dbd_dbi_arch_dir();
            print qq(INC is now $line\n);
        }
        $new_constants .= "$line\n";
    }
    return $new_constants;
}

### What is this for, does apply to Firebird? !!!

# sub MY::postamble { ## no critic ProhibitQualifiedSubDeclarations
#     no strict 'subs'; ## no critic ProhibitNoStrict
#     my $string = DBI::DBD->dbd_postamble();
#     use strict 'subs';
#     ## Evil, evil stuff - but we really want to suppress the "duplicate function" message!
#     $string =~ s/dependancy/dependency/g; ## why not, while we are here
#     $string =~ s{(BASEEXT\)/g)}{$1; s/^do\\\(/dontdo\\\(/};

#         my $tags = <<'MAKE_FRAG';
# .PHONY: tags

# tags:
#     ctags -f tags --recurse --totals \
#         --exclude=blib \
#         --exclude=.svn \
#         --exclude='*~' \
#         --languages=Perl,C --langmap=c:+.h,Perl:+.t \

# MAKE_FRAG
#         $string = "$string\n$tags\n";

#     $string .= <<'MAKE_SPLINT';

# ## This must be version 3.1.2 or better: earlier versions have many
# ## problems parsing the DBI header files
# SPLINT = splint

# ## Temp directory, for use with +keep
# SPLINT_TMP = $(TMP)/splint_dbdfb

# SPLINTFLAGS =            \
#   -message-stream-stdout \
#   -linelen 90            \
#   -boolops               \
#   -tmpdir $(SPLINT_TMP)  \
#   +posixstrictlib        \
#   +ignoresigns           \
#   +showdeephistory       \
#   -predboolint           \
#   -nullpass              \
#   +charint               \
#   +boolint               \
#   +allglobals            \

# SPLINTFLAGS_TEST =

# SDEFINES =

# splint: $(H_FILES) $(C_FILES)
#     $(MKPATH) $(SPLINT_TMP)
#     $(SPLINT) $(SPLINTFLAGS) $(SPLINTFLAGS_TEST) $(SDEFINES) -I$(PERL_INC) $(INC) $(C_FILES)

# MAKE_SPLINT

#     $string =~ s/SDEFINES = /SDEFINES =$defines/;

#     return $string;
# }

my $output = WriteMakefile(%opts);

# if (!exists $output->{EXTRALIBS} or

#     ($output->{EXTRALIBS} !~ /\-lpq/ and $output->{EXTRALIBS} !~ /libpq/)) {

#     my $makefile = exists $output->{MAKEFILE}
#         ? "\nRemoving ($output->{MAKEFILE})\n" : '';

#     warn qq{
# ==========================================================

# WARNING! No firebird libraries were detected!

# You need to install the Firebird client? package for your system,

# or set the FIREBIRD_LIB environment variable to the correct place.
# $makefile
# ===========================================================

# };

#     ## Do not let make proceed
#     unlink $output->{MAKEFILE} if $makefile;

#     exit 1;
# }

exit 0;

# end of Makefile.PL
