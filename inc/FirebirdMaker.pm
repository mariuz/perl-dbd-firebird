package FirebirdMaker;

use warnings;
use strict;

use base 'Exporter';
use Carp;
use ExtUtils::MakeMaker;

use Config;

our @EXPORT_OK = qw( WriteMakefile1 setup_for_ms_gcc setup_for_ms_cl
    locate_firebird check_and_set_devlibs alternative_locations
    search_fb_home_dirs search_fb_inc_dirs search_fb_lib_dirs
    locate_firebird_ms registry_lookup read_registry read_data
    save_test_parameters read_test_parameters prompt_for_settings
    prompt_for check_str check_path check_exe check_file help_message
    welcome_msg closing_msg create_embedded_files
    $test_conf $test_mark $use_libfbembed );

our @EXPORT = @EXPORT_OK;

our ( $use_libfbembed );
# Temp file names
our $test_conf = 't/tests-setup.tmp.conf';
our $test_mark = 't/tests-setup.tmp.OK';

# Written by Alexandr Ciornii, version 0.23. Added by eumm-upgrade.
sub WriteMakefile1 {
    my %params       = @_;
    my $eumm_version = $ExtUtils::MakeMaker::VERSION;
    $eumm_version = eval $eumm_version;
    die "EXTRA_META is deprecated" if exists $params{EXTRA_META};
    die "License not specified" if not exists $params{LICENSE};
    if (    $params{AUTHOR}
        and ref( $params{AUTHOR} ) eq 'ARRAY'
        and $eumm_version < 6.5705 )
    {
        $params{META_ADD}{author} = $params{AUTHOR};
        $params{AUTHOR} = join( ', ', @{ $params{AUTHOR} } );
    }
    if ( $params{BUILD_REQUIRES} and $eumm_version < 6.5503 ) {

        #EUMM 6.5502 has problems with BUILD_REQUIRES
        $params{PREREQ_PM} =
          { %{ $params{PREREQ_PM} || {} }, %{ $params{BUILD_REQUIRES} } };
        delete $params{BUILD_REQUIRES};
    }
    delete $params{CONFIGURE_REQUIRES} if $eumm_version < 6.52;
    delete $params{MIN_PERL_VERSION}   if $eumm_version < 6.48;
    delete $params{META_MERGE}         if $eumm_version < 6.46;
    delete $params{META_ADD}           if $eumm_version < 6.46;
    delete $params{LICENSE}            if $eumm_version < 6.31;
    delete $params{AUTHOR}             if $] < 5.005;
    delete $params{ABSTRACT_FROM}      if $] < 5.005;
    delete $params{BINARY_LOCATION}    if $] < 5.005;

    WriteMakefile(%params);
}

#- Helper SUBS ---------------------------------------------------------------#

#-- Subs for OS specific setting

sub setup_for_ms_gcc {

    # Support for MinGW (still experimental, patches welcome!)
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
    if ( -f "$FB::LIB/fbclient_ms.lib" ) {
        $lib = "$FB::LIB/fbclient_ms.lib";
    }
    else { $lib = "$FB::LIB/gds32_ms.lib"; }

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

    # NOT tested !!!

    # Try to find Microsoft Visual C++ compiler
    my $vc_dir = registry_lookup_ms_cl();

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
        [ $FB::LIB . "SDK\\lib_ms", $FB::LIB . "lib" ],
        [qw(gds32_ms.lib fbclient_ms.lib)]
    );

    my $cur_libs      = $Config{libs};
    my $cur_lddlflags = $Config{lddlflags};

    my $lib;
    if (-f "$FB::LIB/fbclient_ms.lib")
        { $lib = "$FB::LIB/fbclient_ms.lib"; }
    else
        { $lib = "$FB::LIB/gds32_ms.lib"; }

    eval "
    sub MY::const_loadlibs {
    '
LDLOADLIBS = \"$lib\" $cur_libs
LDDLFLAGS =  -L\"$vc_lib\" $cur_lddlflags
    '
} ";

return;
}

#-- Subs used to locate Firebird

=head2 locate_firebird

On *nix like systems try different standard paths.

=cut

sub locate_firebird {

    my @bd = search_fb_home_dirs();

    foreach my $dir (@bd) {
        if ( -d $dir ) {

            # File names specific to the Firebird/bin dir
            my @fb_files = qw{fbsql isql-fb isql};
                                           # fbsql not yet! but 'isql' is
                                           # used by Virtuoso and UnixODBC
                                           # That's why Debian ships it as
                                           # isql-fb

            my $found = 0;
            while ( !$found ) {
                my $file = shift @fb_files or last;

                $file = File::Spec->catfile( $dir, 'bin', $file );

                if ( -f $file and -x $file ) {
                    # Located
                    my $out = `echo 'quit;' | $file -z 2>&1`;
                    next unless $out =~ /firebird/si;   # Firebird's isql?

                    check_and_set_devlibs($dir);
                    $FB::ISQL = File::Spec->canonpath($file);
                    last;
                }
            }
        }
    }

    return;
}

=head2 check_and_set_devlibs

Check and set global variables for home, inc and lib (?...).

=cut

sub check_and_set_devlibs {
    my $fb_dir = shift;

    $FB::HOME = File::Spec->canonpath($fb_dir);

    $FB::INC = $FB::INC || File::Spec->catdir( $FB::HOME, 'include' );
    $FB::INC = alternative_locations('inc') if !-d $FB::INC;

    $FB::LIB = $FB::LIB || File::Spec->catdir( $FB::HOME, 'lib' );
    $FB::LIB = alternative_locations('lib') if !-d $FB::LIB;

    for my $dir ( split(/ /, $Config{libpth} ), $FB::LIB//() ) {
        if ( -e File::Spec->catfile( $dir, 'libfbembed.so' ) ) {
            $FB::libfbembed_available = 1;
            print "libfbembed.so found in $dir\n";
            last;
        }
    }

    return;
}

=head2 alternative_locations

Search lib and inc in alternative locations.

=cut

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

=head2 search_fb_home_dirs

Common places for the Firebird home dir.

There is a potential problem when adding here paths like B</usr>,
because the setup might locate a wrong B<isql> and the connect test
hangs.

=cut

sub search_fb_home_dirs {

    # Add other standard paths here
    return (
        qw{
          /opt/firebird
          /usr/local/firebird
          /usr/lib/firebird
          /usr
          },
    );
}

=head2 search_fb_inc_dirs

Common places for the Firebird include dir.

=cut

sub search_fb_inc_dirs {

    # Add other standard paths here for include
    return (
        qw{
          /usr/include/firebird
          /usr/local/include/firebird
        },
    );
}

=head2 search_fb_lib_dirs

Common places for the Firebird lib dir.

=cut

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

    my $hp_ref = registry_lookup('fb');
    if (ref $hp_ref) {
        $FB::HOME = $FB::HOME || File::Spec->canonpath($hp_ref->[0]);
        $FB::INC  = $FB::INC  || File::Spec->catdir( $FB::HOME, 'include' );
        $FB::LIB  = $FB::LIB  || File::Spec->catdir( $FB::HOME, 'lib' );

        my $isql_file = File::Spec->catfile( $FB::HOME, 'bin', 'isql.exe' );
        $FB::ISQL = File::Spec->canonpath($isql_file);
    }
}

sub registry_lookup {
    my $what = shift;

    my $reg_data = read_data($what);

    my $value;
    foreach my $rec ( @{$reg_data->{$what}} ) {
        $value = read_registry($rec)
    }

    return $value;
}

sub read_registry {
    my $rec = shift;

    my @path;
    eval {
        require Win32::TieRegistry;

        my $path =
          Win32::TieRegistry->new( $rec->{path} )->GetValue( $rec->{key} );

        push @path, $path if $path;
    };
    if ($@) {
        warn "Error: $@!\n";
    }

    return wantarray ? @path : \@path;
}

=head2 read_data

Read various default settings from the DATA section of this script.

=cut

sub read_data {
    my $app_alias = shift;

    my %reg_data;
    while (<DATA>) {
        my ($app, $key, $path) = split /:/, $_, 3;
        chomp $path;
        next if $app ne $app_alias;
        push @{ $reg_data{$app} }, { key => $key, path => $path } ;
    }

    return \%reg_data;
}

sub save_test_parameters {
    my ($db_path, $db_host, $user, $pass) = @_;

    open my $t_fh, '>', $test_conf or die "Can't write $test_conf: $!";

    my $test_time = scalar localtime();

    my @record = (
        q(# This is a temporary file used for test setup #),
        q(# The field separator is :=                    #),
        q(# Should be deleted at the end of installation #),
        q(# Init section ------ (created by Makefile.PL) #),
        q(# Time: ) . $test_time,
        qq(isql:=$FB::ISQL),
    );

    $db_host = $db_host || q{localhost}; # not ||= for compatibility

    # Other settings (interactive mode)
    push @record, qq(host:=$db_host);
    push @record, qq(path:=$db_path) if $db_path;
    push @record, qq(tdsn:=dbi:Firebird:db=$db_path;host=$db_host;ib_dialect=3;ib_charset=ISO8859_1) if $db_path;
    push @record, qq(user:=$user) if $user;
    push @record, qq(pass:=$pass) if $pass;
    push @record, qq(use_libfbembed:=1) if $use_libfbembed;

    my $rec = join "\n", @record;

    print {$t_fh} $rec, "\n";

    close $t_fh or die "Can't close $test_conf: $!";

    # Remove the mark file
    if (-f $test_mark) {
        unlink $test_mark or warn "Could not unlink $test_mark: $!";
    }

    return;
}

sub read_test_parameters {

    my $record = {};

    if (-f $test_conf) {
        print "\nReading cached test configuration...\n";

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

#-- Prompting subs ...

sub prompt_for_settings {

    my $param = read_test_parameters();

    my ($user, $pass) = (qw{SYSDBA masterkey}); # some defaults
    my ($isql, $db_path, $db_host);

    # If saved configs exists set them as defaults
    if ( ref $param ) {
        $user = $param->{user} || $user;
        $pass = $param->{pass} || $pass;
        $isql = $param->{isql} || $FB::ISQL;
        $db_host = $param->{host} || 'localhost';
        $db_path = $param->{path}
          || File::Spec->catfile( File::Spec->tmpdir(), 'dbd-fb-testdb.fdb' );
    }

    print qq{\nStarting interactive setup, two attempts for each option,\n};
    print qq{ if both fail, the script will abort ...\n};
    print qq{\n Enter the full paths to the Firebird instalation:\n};
    $FB::HOME = prompt_for( 'path', '      Home:', $FB::HOME );

    $FB::INC = $FB::INC || File::Spec->catdir( $FB::HOME, 'include' );
    $FB::LIB = $FB::LIB || File::Spec->catdir( $FB::HOME, 'lib' );

    $FB::INC = prompt_for( 'path', '   Include:', $FB::INC );
    $FB::LIB = prompt_for( 'path', '       Lib:', $FB::LIB );

    print qq{\n Configuring the test environment ...\n};
    print qq{\n Enter the full paths to the Firebird tools:\n};
    $isql   = prompt_for( 'exe', '      isql:', $isql );

    $db_host = prompt_for('str', '  Hostname:', $db_host );

    print
      qq{\n Enter the full path and file name of the test database (.fdb):\n};
    $db_path = prompt_for( 'file', '   Test DB:', $db_path );

    unless ($use_libfbembed) {
        print qq{\n Enter authentication options:\n};
        $user = prompt_for('str', '   Username:', $user );
        $pass = prompt_for('str', '   Password:', $pass );
        print "\n";
    }

    save_test_parameters($db_path, $db_host, $user, $pass);

    return;
}

=head2 prompt_for

Show prompt.

=cut

sub prompt_for {
    my ( $type, $msg, $value ) = @_;

  LOOP: {
        for ( 1 .. 2 ) {
            $value = prompt( $msg, $value );
            $value = File::Spec->canonpath($value)
              if ( $type eq q{path} or $type eq q{exe} );

            my $check_sub = qq{check_$type};
            last LOOP if ( main->$check_sub($value) );
        }
        die "Unable to locate $type. Aborting ...";
    }

    return $value;
}

sub check_str  { return ( $_[1] ) }
sub check_path { return ( -d $_[1] ) }
sub check_exe  { return ( -x $_[1] ) }

=head2 prompt_new_file

Because we can't make difference between a simple path and a path with
a file name without extension, the fdb extension is required for the
test database.

=cut

sub check_file {
    my ($self, $value) = @_;

    my ($base, $db_path, $type) = fileparse($value, '\.fdb' );

    return 0 if $type ne q{.fdb}; # expecting file with fdb extension

    return ( -d $db_path and $base );
}

#-- Help and message subs

sub help_message {

    my $msg =<<"MSG";

This script prepares the installation of the DBD::Firebird module,
automatically with minimum user intervention or in interactive mode.
In non interactive mode will try to determine the location of the
Firebird HOME, LIBRARY and INCLUDE directories:

1. From the environment variable FIREBIRD_HOME. Also FIREBIRD_INCLUDE
and FIREBIRD_LIB if they are not sub directories of FIREBIRD_HOME.

2. From the standard (hardwired) locations where Firebird can be
installed on various platforms and distros.

If no success, execute this script with the I<-i[nteractive]> command
line option, or set the required environment variables.

% perl Makefile.PL -i[nteractive]

The tests requires the path to the test database, the user name and
the password.  All options have defaults: DBI_USER = 'SYSDBA',
DBI_PASS = 'masterkey', or run the script in interactive
mode. (ISC_USER and ISC_PASSWORD are recognized also), for DBI_DSN the
default is:

  dbi:Firebird:db=OS_tmp_path/dbd-fb-testdb.fdb;host=localhost;
      ib_dialect=3;ib_charset=ISO8859_1

If all else fails, email <mapopa\@gmail.com> for help.

MSG

    print $msg;
}

sub welcome_msg {

    my $msg =<<"MSG";

This script prepares the installation of the DBD::Firebird module.

Warning: the process will create a temporary file to store the values
required for the testing phase, including the password for access to
the Firebird server in plain text: 't/tests-setup.tmp.conf'.

MSG

    print $msg;
}

sub closing_msg {

    my $msg =<<"MSG";

Please, set at least DBI_PASS (or ISC_PASSWORD), before 'make test'.
The default for DBI_USER is 'SYSDBA'.

MSG

    print $msg unless $use_libfbembed;
}

sub create_embedded_files {
    my $dir = "embed";

    unless (-d $dir) {
        mkdir($dir) or die "Error creating directory $dir: $!\n";
    }

    # Makefile.PL
    my $mf = File::Spec->catfile( $dir, 'Makefile.PL' );
    open( my $mfh, '>', $mf ) or die "Unable to open $mf for writing: $!\n";
    open( my $in, '<', 'Makefile.PL' )
        or die "Unable to open Makefile.PL for reading: $!\n";
    while ( defined( $_ = <$in> ) ) {
        last if /^exit 0/;
        s/^our \$EMBEDDED = \K0/1/;
        print $mfh $_;
    }
    close($mfh) or die "Error closing $mf: $!\n";
    close($in)  or die "Error closing Makefile.PL: $!\n";

    # Simple copies
    use File::Copy qw(copy);
    for my $f (qw( dbdimp.h Firebird.h )) {
        copy $f, File::Spec->catfile( $dir, $f )
            or die "Error copying $f: $!\n";
    }

    # dbdimp.c
    my $target = File::Spec->catfile( $dir, 'dbdimp.c' );
    open( my $target_fh, '>', $target )
        or die "Unable to open $target for writing: $!\n";
    open( my $source_fh, '<', 'dbdimp.c' )
        or die "Unable to open dbdimp.c for reading: $!\n";
    while ( defined( $_ = <$source_fh> ) ) {
        s/^#include "Firebird\K\.h"/Embedded.h"/;
        print $target_fh $_;
    }
    close($target_fh) or die "Error closing $target: $!\n";
    close($source_fh) or die "Error closing dbdimp.c: $!\n";
}

1;

#-- Known registry keys

__DATA__
fb:DefaultInstance:HKEY_LOCAL_MACHINE\SOFTWARE\Firebird Project\Firebird Server\Instances
vc:ProductDir:HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\VisualStudio\6.0\Setup\Microsoft Visual C++
vc:ProductDir:HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\VisualStudio\7.0\Setup\VC
vc:ProductDir:HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\VisualStudio\9.0\Setup\VC
pv:CurrentVersion:HKEY_LOCAL_MACHINE\SOFTWARE\ActiveState\ActivePerl
pl::HKEY_LOCAL_MACHINE\SOFTWARE\ActiveState\ActivePerl\1203
