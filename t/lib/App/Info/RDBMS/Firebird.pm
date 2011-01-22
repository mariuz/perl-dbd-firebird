package App::Info::RDBMS::Firebird;

=head1 NAME

App::Info::RDBMS::Firebird - Information about Firebird

=head1 SYNOPSIS

  use App::Info::RDBMS::Firebird;

  my $fb = App::Info::RDBMS::Firebird->new;

  if ($fb->installed) {
      print "App name: ", $fb->name, "\n";
      print "Version:  ", $fb->version, "\n";
      print "Bin dir:  ", $fb->bin_dir, "\n";
  } else {
      print "Firebird is not installed. :-(\n";
  }

=head1 DESCRIPTION

App::Info::RDBMS::Firebird supplies information about the Firebird
database server installed on the local system. It implements all of the
methods defined by App::Info::RDBMS. Methods that trigger events will trigger
them only the first time they're called (See L<App::Info|App::Info> for
documentation on handling events). To start over (after, say, someone has
installed Firebird) construct a new App::Info::RDBMS::Firebird object to
aggregate new meta data.

Some of the methods trigger the same events. This is due to cross-calling of
shared subroutines. However, any one event should be triggered no more than
once. For example, although the info event "Executing `fb_config --version`"
is documented for the methods C<name()>, C<version()>, C<major_version()>,
C<minor_version()>, and C<patch_version()>, rest assured that it will only be
triggered once, by whichever of those four methods is called first.

=cut

use strict;
use App::Info::RDBMS;
use App::Info::Util;
use vars qw(@ISA $VERSION);
@ISA = qw(App::Info::RDBMS);
$VERSION = '0.01';
use constant WIN32 => $^O eq 'MSWin32';

my $u = App::Info::Util->new;
my @EXES = qw(fb_config fb_lock_print fbguard fbmgr fbmgr.bin fbserver
              fbsvcmgr gbak gdef gfix gpre gsec gsplit gstat isql nbackup qli);

=head1 INTERFACE

=head2 Constructor

=head3 new

  my $fb = App::Info::RDBMS::Firebird->new(@params);

Returns an App::Info::RDBMS::Firebird object. See L<App::Info|App::Info> for
a complete description of argument parameters.

When it called, C<new()> searches the file system for an executable named for
the list returned by C<search_exe_names()>, usually F<fb_config>, in the list
of directories returned by C<search_bin_dirs()>. If found, F<fb_config> will
be called by the object methods below to gather the data necessary for
each. If F<fb_config> cannot be found, then Firebird is assumed not to be
installed, and each of the object methods will return C<undef>.

C<new()> also takes a number of optional parameters in addition to those
documented for App::Info. These parameters allow you to specify alternate
names for Firebird executables (other than F<fb_config>, which you specify
via the C<search_exe_names> parameter). These parameters are:

=over

=item search_firebird_names

=item search_fb_dump_names

=item search_isql_names

=item search_vacuumdb_names

=back

B<Events:>

=over 4

=item info

Looking for fb_config

=item confirm

Path to fb_config?

=item unknown

Path to fb_config?

=back

=cut

sub new {
    # Construct the object.
    my $self = shift->SUPER::new(@_);

    # Find fb_config.
    $self->info("Looking for fb_config");

    my @paths = $self->search_bin_dirs;
    my @exes  = $self->search_exe_names;

    if (my $cfg = $u->first_cat_exe(\@exes, @paths)) {
        # We found it. Confirm.
        $self->{fb_config} = $self->confirm( key      => 'path to fb_config',
                                             prompt   => "Path to fb_config?",
                                             value    => $cfg,
                                             callback => sub { -x },
                                             error    => 'Not an executable');
    } else {
        # Handle an unknown value.
        $self->{fb_config} = $self->unknown( key      => 'path to fb_config',
                                             prompt   => "Path to fb_config?",
                                             callback => sub { -x },
                                             error    => 'Not an executable');
    }

    # Set up search defaults.
    for my $exe (@EXES) {
        my $attr = "search_$exe\_names";
        if ( exists $self->{$attr} ) {
            $self->{$attr} = [ $self->{$attr} ]
              unless ref $self->{$attr} eq 'ARRAY';
        }
        else {
            $self->{$attr} = [];
        }
    }

    return $self;
}

# We'll use this code reference as a common way of collecting data.
my $get_data = sub {
    return unless $_[0]->{fb_config};
    $_[0]->info(qq{Executing `"$_[0]->{fb_config}" $_[1]`});
    my $info = `"$_[0]->{fb_config}" $_[1]`;
    chomp $info;
    return $info;
};

##############################################################################

=head2 Class Method

=head3 key_name

  my $key_name = App::Info::RDBMS::Firebird->key_name;

Returns the unique key name that describes this class. The value returned is
the string "Firebird".

=cut

sub key_name { 'Firebird' }

##############################################################################

=head2 Object Methods

=head3 installed

  print "Firebird is ", ($fb->installed ? '' : 'not '), "installed.\n";

Returns true if Firebird is installed, and false if it is not.
App::Info::RDBMS::Firebird determines whether Firebird is installed based
on the presence or absence of the F<fb_config> application on the file system
as found when C<new()> constructed the object. If Firebird does not appear
to be installed, then all of the other object methods will return empty
values.

=cut

sub installed { return $_[0]->{fb_config} ? 1 : undef }

##############################################################################

=head3 name

  my $name = $sqlite->name;

Returns the name of the application. App::Info::RDBMS::Firebird simply
returns the value returned by C<key_name> if Firebird is installed,
and C<undef> if it is not installed.

=cut

sub name { $_[0]->installed ? $_[0]->key_name : undef }

# This code reference is used by version(), major_version(),
# minor_version(), and patch_version() to aggregate the data they
# need.
my $get_version = sub {
    my $self = shift;
    $self->{'--version'} = 1;
    my $data = $get_data->($self, '--version');
    unless ($data) {
        $self->error("Failed to find Firebird version with ".
                     "`$self->{fb_config} --version`");
            return;
    }

    chomp $data;
    my $version = $data;

    # Assign the name.
    $self->{name} = 'Firebird';              # hardwired ;)

    # Parse the version number.
    if ($version) {
        my ($x, $y, $z) = $version =~ /(\d+)\.(\d+).(\d+)/;
        if (defined $x and defined $y and defined $z) {
            # Beta/devel/release candidates are treated as patch level "0"
            @{$self}{qw(version major minor patch)} =
              ($version, $x, $y, $z);
        } elsif ($version =~ /(\d+)\.(\d+)/) {
            # New versions, such as "7.4", are treated as patch level "0"
            @{$self}{qw(version major minor patch)} =
              ($version, $1, $2, 0);
        } else {
            $self->error("Failed to parse Firebird version parts from " .
                         "string '$version'");
        }
    } else {
        $self->error("Unable to parse version from string '$data'");
    }
};

##############################################################################

=head3 version

  my $version = $fb->version;

Returns the Firebird version number. App::Info::RDBMS::Firebird parses the
version number from the system call C<`fb_config --version`>.

B<Events:>

=over 4

=item info

Executing `fb_config --version`

=item error

Failed to find Firebird version with `fb_config --version`

Unable to parse version from string

Failed to parse Firebird version parts from string

=item unknown

Enter a valid Firebird version number

=back

=cut

sub version {
    my $self = shift;
    return unless $self->{fb_config};

    # Load data.
    $get_version->($self) unless $self->{'--version'};

    # Handle an unknown value.
    unless ($self->{version}) {
        # Create a validation code reference.
        my $chk_version = sub {
            # Try to get the version number parts.
            my ($x, $y, $z) = /^(\d+)\.(\d+).(\d+)$/;
            # Return false if we didn't get all three.
            return unless $x and defined $y and defined $z;
            # Save all three parts.
            @{$self}{qw(major minor patch)} = ($x, $y, $z);
            # Return true.
            return 1;
        };
        $self->{version} = $self->unknown( key     => 'version number',
                                           callback => $chk_version);
    }

    return $self->{version};
}

##############################################################################

=head3 major version

  my $major_version = $fb->major_version;

Returns the Firebird major version number. App::Info::RDBMS::Firebird
parses the major version number from the system call C<`fb_config --version`>.
For example, if C<version()> returns "7.1.2", then this method returns "7".

B<Events:>

=over 4

=item info

Executing `fb_config --version`

=item error

Failed to find Firebird version with `fb_config --version`

Unable to parse name from string

Unable to parse version from string

Failed to parse Firebird version parts from string

=item unknown

Enter a valid Firebird major version number

=back

=cut

# This code reference is used by major_version(), minor_version(), and
# patch_version() to validate a version number entered by a user.
my $is_int = sub { /^\d+$/ };

sub major_version {
    my $self = shift;
    return unless $self->{fb_config};
    # Load data.
    $get_version->($self) unless exists $self->{'--version'};
    # Handle an unknown value.
    $self->{major} = $self->unknown( key      => 'major version number',
                                     callback => $is_int)
      unless $self->{major};
    return $self->{major};
}

##############################################################################

=head3 minor version

  my $minor_version = $fb->minor_version;

Returns the Firebird minor version number. App::Info::RDBMS::Firebird
parses the minor version number from the system call C<`fb_config --version`>.
For example, if C<version()> returns "7.1.2", then this method returns "2".

B<Events:>

=over 4

=item info

Executing `fb_config --version`

=item error

Failed to find Firebird version with `fb_config --version`

Unable to parse name from string

Unable to parse version from string

Failed to parse Firebird version parts from string

=item unknown

Enter a valid Firebird minor version number

=back

=cut

sub minor_version {
    my $self = shift;
    return unless $self->{fb_config};
    # Load data.
    $get_version->($self) unless exists $self->{'--version'};
    # Handle an unknown value.
    $self->{minor} = $self->unknown( key      => 'minor version number',
                                     callback => $is_int)
      unless defined $self->{minor};
    return $self->{minor};
}

##############################################################################

=head3 patch version

  my $patch_version = $fb->patch_version;

Returns the Firebird patch version number. App::Info::RDBMS::Firebird
parses the patch version number from the system call C<`fb_config --version`>.
For example, if C<version()> returns "7.1.2", then this method returns "1".

B<Events:>

=over 4

=item info

Executing `fb_config --version`

=item error

Failed to find Firebird version with `fb_config --version`

Unable to parse name from string

Unable to parse version from string

Failed to parse Firebird version parts from string

=item unknown

Enter a valid Firebird minor version number

=back

=cut

sub patch_version {
    my $self = shift;
    return unless $self->{fb_config};
    # Load data.
    $get_version->($self) unless exists $self->{'--version'};
    # Handle an unknown value.
    $self->{patch} = $self->unknown( key      => 'patch version number',
                                     callback => $is_int)
      unless defined $self->{patch};
    return $self->{patch};
}

##############################################################################

=head3 executable

  my $exe = $fb->executable;

Returns the full path to the Firebird server executable, which is named
F<fbguard>.  This method does not use the executable names returned by
C<search_exe_names()>; those executable names are used to search for
F<fb_config> only (in C<new()>).

When it called, C<executable()> checks for an executable named F<fbguard> in
the directory returned by C<bin_dir()>.

Note that C<executable()> is simply an alias for C<fbguard()>.

B<Events:>

=over 4

=item info

Looking for fbguard executable

=item confirm

Path to fbguard executable?

=item unknown

Path to fbguard executable?

=back

=cut

my $find_exe = sub  {
    my ($self, $key) = @_;
    my $exe = $key . (WIN32 ? '.exe' : '');
    my $meth = "search_$key\_names";

    # Find executable.
    $self->info("Looking for $key");

    unless ($self->{$key}) {
        my $bin = $self->bin_dir or return;
        if (my $exe = $u->first_cat_exe([$self->$meth(), $exe], $bin)) {
            # We found it. Confirm.
            $self->{$key} = $self->confirm(
                key      => "path to $key",
                prompt   => "Path to $key executable?",
                value    => $exe,
                callback => sub { -x },
                error    => 'Not an executable'
            );
        } else {
            # Handle an unknown value.
            $self->{$key} = $self->unknown(
                key      => "path to $key",
                prompt   => "Path to $key executable?",
                callback => sub { -x },
                error    => 'Not an executable'
            );
        }
    }

    return $self->{$key};
};

for my $exe (@EXES) {
    no strict 'refs';
    *{$exe} = sub { shift->$find_exe($exe) };
    *{"search_$exe\_names"} = sub { @{ shift->{"search_$exe\_names"} } }
}

*executable = \&fbguard;

##############################################################################

=head3 bin_dir

  my $bin_dir = $fb->bin_dir;

Returns the Firebird binary directory path. App::Info::RDBMS::Firebird
gathers the path from the system call C<`fb_config --bindir`>.

B<Events:>

=over 4

=item info

Executing `fb_config --bindir`

=item error

Cannot find bin directory

=item unknown

Enter a valid Firebird bin directory

=back

=cut

# This code reference is used by bin_dir(), lib_dir(), and so_lib_dir() to
# validate a directory entered by the user.
my $is_dir = sub { -d };

sub bin_dir {
    my $self = shift;

    return unless $self->{fb_config};

    unless (exists $self->{bin_dir} ) {
        if (my $dir = $get_data->($self, '--bindir')) {
            $self->{bin_dir} = $dir;
        } else {
            # Handle an unknown value.
            $self->error("Cannot find bin directory");
            $self->{bin_dir} = $self->unknown( key      => 'firebird bin dir',
                                               callback => $is_dir)
        }
    }

    return $self->{bin_dir};
}

##############################################################################

=head3 inc_dir

  my $inc_dir = $fb->inc_dir;

Returns the Firebird include directory path. MAY NOT BE NEEDED, use
cflags?  App::Info::RDBMS::Firebird gathers the path from the system
call C<`fb_config --bindir`> and replaces L<bin> with L<include>.

B<Events:>

=over 4

=item info

Executing `fb_config --bindir`

=item error

Cannot find bin directory

=item unknown

Enter a valid Firebird include directory

=back

=cut

sub inc_dir {
    my $self = shift;

    return unless $self->{fb_config};

    unless (exists $self->{inc_dir} ) {
        if (my $dir = $get_data->($self, '--bindir')) {
            ($self->{inc_dir} = $dir ) =~ s{bin$}{include};
        } else {
            # Handle an unknown value.
            $self->error("Cannot find include directory");
            $self->{inc_dir} = $self->unknown( key      => 'include dir',
                                               callback => $is_dir)
        }
    }

    return $self->{inc_dir};
}

##############################################################################

=head3 lib_dir

  my $lib_dir = $fb->lib_dir;

Returns the Firebird lib directory path. Not realy needed, useing
L<--libs> option from L<fb_config>. App::Info::RDBMS::Firebird gathers
the path from the system call C<`fb_config --bindir`> and replaces
L<bin> with L<lib>.

B<Events:>

=over 4

=item info

Executing `fb_config --bindir`

=item error

Cannot find bin directory

=item unknown

Enter a valid Firebird lib directory

=back

=cut

sub lib_dir {
    my $self = shift;

    return unless $self->{fb_config};

    unless (exists $self->{lib_dir} ) {
        if (my $dir = $get_data->($self, '--bindir')) {
            ($self->{lib_dir} = $dir ) =~ s{bin$}{lib};
        } else {
            # Handle an unknown value.
            $self->error("Cannot find lib directory");
            $self->{lib_dir} = $self->unknown( key      => 'lib dir',
                                               callback => $is_dir)
        }
    }

    return $self->{lib_dir};
}

##############################################################################

=head3 home_dir

  my $home_dir = $fb->home_dir;

Returns the Firebird home directory path. App::Info::RDBMS::Firebird
gathers the path from the system call C<`fb_config --bindir`> and
removes L<bin>.

B<Events:>

=over 4

=item info

Executing `fb_config --bindir`

=item error

Cannot find bin directory

=item unknown

Enter a valid Firebird home directory

=back

=cut

sub home_dir {
    my $self = shift;

    return unless $self->{fb_config};

    unless (exists $self->{home_dir} ) {
        if (my $dir = $get_data->($self, '--bindir')) {
            ($self->{home_dir} = $dir ) =~ s{bin$}{};
        } else {
            # Handle an unknown value.
            $self->error("Cannot find include directory");
            $self->{inc_dir} = $self->unknown( key      => 'home dir',
                                               callback => $is_dir)
        }
    }

    return $self->{home_dir};
}

##############################################################################

=head3 libs

  my $libs = $fb->libs;

Returns the Firebird library directory path. App::Info::RDBMS::Firebird
gathers the path from the system call C<`fb_config --libs`>.

B<Events:>

=over 4

=item info

Executing `fb_config --libs`

=item error

Cannot find library directory

=item unknown

Enter a valid Firebird library directory

=back

=cut

sub libs {
    my $self = shift;
    return unless $self->{fb_config};
    unless (exists $self->{libs} ) {
        if (my $dir = $get_data->($self, '--libs')) {
            $self->{libs} = $dir;
        } else {
            # Handle an unknown value.
            $self->error("Cannot find library directory");
            $self->{libs} = $self->unknown( key      => 'library dir',
                                               callback => $is_dir)
        }
    }

    return $self->{libs};
}

##############################################################################

=head3 cflags options

  my $cflags = $fb->cflags;

Returns the options with which the Firebird server was
cflagsd. App::Info::RDBMS::Firebird gathers the cflags data from the
system call C<`fb_config --cflags`>.

B<Events:>

=over 4

=item info

Executing `fb_config --cflags`

=item error

Cannot find cflags information

=item unknown

Enter Firebird cflags options

=back

=cut

sub cflags {
    my $self = shift;
    return unless $self->{fb_config};
    unless (exists $self->{cflags} ) {
        if (my $conf = $get_data->($self, '--cflags')) {
            $self->{cflags} = $conf;
        } else {
            # Cflags can be empty, so just make sure it exists and is
            # defined. Don't prompt.
            $self->{cflags} = '';
        }
    }

    return $self->{cflags};
}

##############################################################################

=head3 home_url

  my $home_url = $fb->home_url;

Returns the Firebird home page URL.

=cut

sub home_url { "http://www.firebirdsql.org/" }

##############################################################################

=head3 download_url

  my $download_url = $fb->download_url;

Returns the Firebird download URL.

=cut

sub download_url { "http://firebirdsql.org/index.php?op=files&id=engine" }

##############################################################################

=head3 search_exe_names

  my @search_exe_names = $app->search_exe_names;

Returns a list of possible names for F<fb_config> executable. By default, only
F<fb_config> is returned (or F<fb_config.exe> on Win32).

Note that this method is not used to search for the Firebird server
executable, only F<fb_config>.

=cut

sub search_exe_names {
    my $self = shift;
    my $exe  = 'fb_config';
    $exe .= '.exe' if WIN32;
    return ( $self->SUPER::search_exe_names, $exe );
}

##############################################################################

=head3 search_bin_dirs

  my @search_bin_dirs = $app->search_bin_dirs;

Returns a list of possible directories in which to search an executable. Used
by the C<new()> constructor to find an executable to execute and collect
application info. The found directory will also be returned by the C<bin_dir>
method.

The list of directories by default consists of the path as defined by
C<< File::Spec->path >>, as well as the following directories:

=over 4

=item $ENV{FIREBIRD_HOME}/bin (if $ENV{FIREBIRD_HOME} exists)

=item $ENV{FIREBIRD_LIB}/../bin (if $ENV{FIREBIRD_LIB} exists)

=item /usr/local/firebird/bin

=item C:\Program Files\Firebird\Firebird(?verstr?)/bin

=back

=cut

sub search_bin_dirs {

    # Search first the registry if on win win32
    if (WIN32) {
        my $reg_path = $_[0]->path_from_registry;

        return shift->SUPER::search_bin_dirs,
            $u->catdir($reg_path, 'bin');
    }

    return shift->SUPER::search_bin_dirs,
      ( exists $ENV{FIREBIRD_HOME}
          ? ($u->catdir($ENV{FIREBIRD_HOME}, "bin"))
          : ()
      ),
      ( exists $ENV{FIREBIRD_LIB}
          ? ($u->catdir($ENV{FIREBIRD_LIB}, $u->updir, "bin"))
          : ()
      ),
      $u->path,
          # Are there other possible paths?
          qw(/opt/firebird/bin /usr/local/firebird/bin)
}

sub path_from_registry {

    my $path;
    eval {
        require Win32::TieRegistry;

        $path = Win32::TieRegistry->new(
"HKEY_LOCAL_MACHINE\\SOFTWARE\\Firebird Project\\Firebird Server\\Instances")
            ->GetValue("DefaultInstance")
        || q{}; # or nothing
        print " path is $path\n";
    };

    return $path;
}

##############################################################################

=head2 Other Executable Methods

These methods function just like the C<executable()> method, except that they
return different executables. Firebird comes with a fair number of them; we
provide these methods to provide a path to a subset of them. Each method, when
called, checks for an executable in the directory returned by C<bin_dir()>.
The name of the executable must be one of the names returned by the
corresponding C<search_*_names> method.

The available executable methods are:

=over

=item firebird

=item createdb

=item fb_dump

=item fb_dumpall

=item fb_restore

=item isql

=back

And the corresponding search names methods are:

=over

=item search_firebird_names

=item search_fb_dump_names

=item search_fb_dumpall_names

=item search_fb_restore_names

=item search_isql_names

=back

B<Events:>

=over 4

=item info

Looking for executable

=item confirm

Path to executable?

=item unknown

Path to executable?

=back

=cut

1;

__END__

=head1 BUGS

Please send bug reports to <bug-app-info@rt.cpan.org> or file them at
L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=App-Info>.

=head1 AUTHOR

Original code by David Wheeler <david@justatheory.com> based on code
by Sam Tregar <sam@tregar.com>, for the PostgresSQL RDBMS.

Stefan Suciu.

=head1 SEE ALSO

L<App::Info|App::Info> documents the event handling interface.

L<App::Info::RDBMS|App::Info::RDBMS> is the App::Info::RDBMS::Firebird
parent class.

L<DBD::Firebird> is the L<DBI> driver for connecting to Firebird
databases.

L<http://www.firebirdsql.org/> is the Firebird home page.

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2002-2008, David Wheeler. Some Rights Reserved.

Copyright (c) 2011, Stefan Suciu. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under the
same terms as Perl itself.

=cut
