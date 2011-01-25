package App::Info::Lib::OSSPUUID;

# $Id: OSSPUUID.pm 3929 2008-05-18 03:58:14Z david $

=head1 NAME

App::Info::Lib::OSSPUUID - Information about the OSSP UUID library

=head1 SYNOPSIS

  use App::Info::Lib::OSSPUUID;

  my $uuid = App::Info::Lib::OSSPUUID->new;

  if ($uuid->installed) {
      print "App name: ", $uuid->name, "\n";
      print "Version:  ", $uuid->version, "\n";
      print "Bin dir:  ", $uuid->bin_dir, "\n";
  } else {
      print "Expat is not installed. :-(\n";
  }

=head1 DESCRIPTION

App::Info::Lib::OSSPUUID supplies information about the OSSP UUID library
installed on the local system. It implements all of the methods defined by
App::Info::Lib. Methods that trigger events will trigger them only the first
time they're called (See L<App::Info|App::Info> for documentation on handling
events). To start over (after, say, someone has installed the OSSP UUID
library) construct a new App::Info::Lib::OSSPUUID object to aggregate new
meta data.

Some of the methods trigger the same events. This is due to cross-calling of
shared subroutines. However, any one event should be triggered no more than
once. For example, although the info event "Executing `uuid-config --version`"
is documented for the methods C<name()> C<version()>, C<major_version()>,
C<minor_version()>, and C<patch_version()>, rest assured that it will only be
triggered once, by whichever of those four methods is called first.

=cut

use strict;
use App::Info::Util;
use App::Info::Lib;
use File::Spec::Functions 'catfile';
use Config;
use vars qw(@ISA $VERSION);
@ISA = qw(App::Info::Lib);
$VERSION = '0.55';
use constant WIN32 => $^O eq 'MSWin32';

my $u = App::Info::Util->new;

##############################################################################

=head1 INTERFACE

=head2 Constructor

=head3 new

  my $expat = App::Info::Lib::OSSPUUID->new(@params);

Returns an App::Info::Lib::OSSPUUID object. See L<App::Info|App::Info> for a
complete description of argument parameters.

When called, C<new()> searches all of the paths returned by the
C<search_lib_dirs()> method for one of the files returned by the
C<search_lib_names()> method. If any of is found, then the OSSP UUID library
is assumed to be installed. Otherwise, most of the object methods will return
C<undef>.

B<Events:>

=over 4

=item info

Looking for uuid-config

=item confirm

Path to uuid-config?

=item unknown

Path to uuid-config?

=back

=cut

sub new {
    # Construct the object.
    my $self = shift->SUPER::new(@_);

    # Find uuid-config.
    $self->info("Looking for uuid-config");

    my @paths = $self->search_bin_dirs;
    my @exes  = $self->search_exe_names;

    if (my $cfg = $u->first_cat_exe(\@exes, @paths)) {
        # We found it. Confirm.
        $self->{uuid_config} = $self->confirm(
            key      => 'path to uuid-config',
            prompt   => "Path to uuid-config?",
            value    => $cfg,
            callback => sub { -x },
            error    => 'Not an executable'
        );
    } else {
        # Handle an unknown value.
        $self->{uuid_config} = $self->unknown(
            key      => 'path to uuid-config',
            prompt   => "Path to uuid-config?",
            callback => sub { -x },
            error    => 'Not an executable'
        );
    }

    # Set up search defaults.
    if (exists $self->{search_uuid_names}) {
        $self->{search_uuid_names} = [$self->{search_uuid_names}]
            unless ref $self->{search_uuid_names} eq 'ARRAY';
    } else {
        $self->{search_uuid_names} = [];
    }

    return $self;
}

# We'll use this code reference as a common way of collecting data.
my $get_data = sub {
    return unless $_[0]->{uuid_config};
    $_[0]->info(qq{Executing `"$_[0]->{uuid_config}" $_[1]`});
    my $info = `"$_[0]->{uuid_config}" $_[1]`;
    chomp $info;
    return $info;
};


##############################################################################

=head2 Class Method

=head3 key_name

  my $key_name = App::Info::Lib::OSSPUUID->key_name;

Returns the unique key name that describes this class. The value returned is
the string "OSSP UUID".

=cut

sub key_name { 'OSSP UUID' }

##############################################################################

=head2 Object Methods

=head3 installed

  print "UUID is ", ($uuid->installed ? '' : 'not '), "installed.\n";

Returns true if the OSSP UUID library is installed, and false if it is not.
App::Info::Lib::OSSPUUID determines whether the library is installed based on
the presence or absence on the file system of the C<uuid-config> application,
searched for when C<new()> constructed the object. If the OSSP UUID library
does not appear to be installed, then most of the other object methods will
return empty values.

=cut

sub installed { $_[0]->{uuid_config} ? 1 : undef }

##############################################################################

=head3 name

  my $name = $uuid->name;

Returns the name of the library. App::Info::Lib::OSSPUUID parses the name from
the system call C<`uuid-config --version`>.

B<Events:>

=over 4

=item info

Executing `uuid-config --version`

=item error

Failed to find OSSP UUID version with `uuid-config --version`

Unable to parse name from string

Unable to parse version from string

Failed to parse OSSP UUID version parts from string

=item unknown

Enter a valid OSSP UUID version number

=back

=cut

my $get_version = sub {
    my $self = shift;
    $self->{'--version'} = 1;
    my $data = $get_data->($self, '--version');
    unless ($data) {
        $self->error("Failed to find OSSP UUID version with ".
                     "`$self->{uuid_config} --version`");
            return;
    }

    # Parse the verison out of the data.
    chomp $data;
    my ($name, $version, $date) = $data =~ /(\D+)\s+([\d.]+)\s+\(([^)]+)\)/;

    # Check for and assign the name.
    $name
        ? $self->{name} = $name
        : $self->error("Unable to parse name from string '$data'");

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
            $self->error("Failed to parse OSSP UUID version parts from " .
                         "string '$version'");
        }
    } else {
        $self->error("Unable to parse version from string '$data'");
    }
};

sub name {
    my $self = shift;
    return unless $self->{uuid_config};

    # Load data.
    $get_version->($self) unless $self->{'--version'};

    # Handle an unknown name.
    $self->{name} ||= $self->unknown( key => 'OSSP UUID name' );

    # Return the name.
    return $self->{name};
}

##############################################################################

=head3 version

  my $version = $uuid->version;

Returns the OSSP UUID version number. App::Info::Lib::OSSPUUID parses the
version number from the system call C<`uuid-config --version`>.

B<Events:>

=over 4

=item info

Executing `uuid-config --version`

=item error

Failed to find OSSP UUID version with `uuid-config --version`

Unable to parse name from string

Unable to parse version from string

Failed to parse OSSP UUID version parts from string

=item unknown

Enter a valid OSSP UUID version number

=back

=cut

sub version {
    my $self = shift;
    return unless $self->{uuid_config};

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
        $self->{version} = $self->unknown(
            key     => 'OSSP UUID version number',
            callback => $chk_version
        );
    }

    return $self->{version};
}

##############################################################################

=head3 major version

  my $major_version = $uuid->major_version;

Returns the OSSP UUID library major version number. App::Info::Lib::OSSPUUID
parses the major version number from the system call C<`uuid-config
--version`>. For example, if C<version()> returns "1.3.0", then this method
returns "1".

B<Events:>

=over 4

=item info

Executing `uuid-config --version`

=item error

Failed to find OSSP UUID version with `uuid-config --version`

Unable to parse name from string

Unable to parse version from string

Failed to parse OSSP UUID version parts from string

=item unknown

Enter a valid OSSP UUID major version number

=back

=cut

# This code reference is used by major_version(), minor_version(), and
# patch_version() to validate a version number entered by a user.
my $is_int = sub { /^\d+$/ };

sub major_version {
    my $self = shift;
    return unless $self->{uuid_config};
    # Load data.
    $get_version->($self) unless exists $self->{'--version'};
    # Handle an unknown value.
    $self->{major} = $self->unknown(
        key      => 'OSSP UUID major version number',
        callback => $is_int
    ) unless $self->{major};
    return $self->{major};
}

##############################################################################

=head3 minor version

  my $minor_version = $uuid->minor_version;

Returns the OSSP UUID library minor version number. App::Info::Lib::OSSPUUID
parses the minor version number from the system call C<`uuid-config
--version`>. For example, if C<version()> returns "1.3.0", then this method
returns "3".

B<Events:>

=over 4

=item info

Executing `uuid-config --version`

=item error

Failed to find OSSP UUID version with `uuid-config --version`

Unable to parse name from string

Unable to parse version from string

Failed to parse OSSP UUID version parts from string

=item unknown

Enter a valid OSSP UUID minor version number

=back

=cut

sub minor_version {
    my $self = shift;
    return unless $self->{uuid_config};
    # Load data.
    $get_version->($self) unless exists $self->{'--version'};
    # Handle an unknown value.
    $self->{minor} = $self->unknown(
        key      => 'OSSP UUID minor version number',
        callback => $is_int
    ) unless defined $self->{minor};
    return $self->{minor};
}

##############################################################################

=head3 patch version

  my $patch_version = $uuid->patch_version;

Returns the OSSP UUID library patch version number. App::Info::Lib::OSSPUUID
parses the patch version number from the system call C<`uuid-config
--version`>. For example, if C<version()> returns "1.3.0", then this method
returns "0".

B<Events:>

=over 4

=item info

Executing `uuid-config --version`

=item error

Failed to find OSSP UUID version with `uuid-config --version`

Unable to parse name from string

Unable to parse version from string

Failed to parse OSSP UUID version parts from string

=item unknown

Enter a valid OSSP UUID minor version number

=back

=cut

sub patch_version {
    my $self = shift;
    return unless $self->{uuid_config};
    # Load data.
    $get_version->($self) unless exists $self->{'--version'};
    # Handle an unknown value.
    $self->{patch} = $self->unknown(
        key      => 'OSSP UUID patch version number',
        callback => $is_int
    ) unless defined $self->{patch};
    return $self->{patch};
}

##############################################################################

=head3 executable

  my $exe = $uuid->executable;

Returns the full path to the OSSP UUID executable, which is named F<uuid>.
This method does not use the executable names returned by
C<search_exe_names()>; those executable names are used to search for
F<uuid-config> only (in C<new()>).

When it called, C<executable()> checks for an executable named F<uuid> in the
directory returned by C<bin_dir()>.

Note that C<executable()> is simply an alias for C<uuid()>.

B<Events:>

=over 4

=item info

Looking for uuid executable

=item confirm

Path to uuid executable?

=item unknown

Path to uuid executable?

=back

=cut


sub executable {
    my $self = shift;
    my $key  = 'uuid';

    # Find executable.
    $self->info("Looking for $key");

    unless ($self->{$key}) {
        my $bin = $self->bin_dir or return;
        if (my $exe = $u->first_cat_exe([$self->search_uuid_names], $bin)) {
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

*uuid = \&executable;

##############################################################################

=head3 bin_dir

  my $bin_dir = $uuid->bin_dir;

Returns the OSSP UUID binary directory path. App::Info::Lib::OSSPUUID gathers
the path from the system call C<`uuid-config --bindir`>.

B<Events:>

=over 4

=item info

Executing `uuid-config --bindir`

=item error

Cannot find bin directory

=item unknown

Enter a valid OSSP UUID bin directory

=back

=cut

# This code reference is used by bin_dir(), lib_dir(), and so_lib_dir() to
# validate a directory entered by the user.
my $is_dir = sub { -d };

sub bin_dir {
    my $self = shift;
    return unless $self->{uuid_config};
    unless (exists $self->{bin_dir} ) {
        if (my $dir = $get_data->($self, '--bindir')) {
            $self->{bin_dir} = $dir;
        } else {
            # Handle an unknown value.
            $self->error("Cannot find bin directory");
            $self->{bin_dir} = $self->unknown(
                key      => 'OSSP UUID bin dir',
                callback => $is_dir
            );
        }
    }

    return $self->{bin_dir};
}

##############################################################################

=head3 inc_dir

  my $inc_dir = $uuid->inc_dir;

Returns the OSSP UUID include directory path. App::Info::Lib::OSSPUUID gathers
the path from the system call C<`uuid-config --includedir`>.

B<Events:>

=over 4

=item info

Executing `uuid-config --includedir`

=item error

Cannot find include directory

=item unknown

Enter a valid OSSP UUID include directory

=back

=cut

sub inc_dir {
    my $self = shift;
    return unless $self->{uuid_config};
    unless (exists $self->{inc_dir} ) {
        if (my $dir = $get_data->($self, '--includedir')) {
            $self->{inc_dir} = $dir;
        } else {
            # Handle an unknown value.
            $self->error("Cannot find include directory");
            $self->{inc_dir} = $self->unknown(
                key      => 'OSSP UUID include dir',
                callback => $is_dir
            );
        }
    }

    return $self->{inc_dir};
}

##############################################################################

=head3 lib_dir

  my $lib_dir = $uuid->lib_dir;

Returns the OSSP UUID library directory path. App::Info::Lib::OSSPUUID gathers
the path from the system call C<`uuid-config --libdir`>.

B<Events:>

=over 4

=item info

Executing `uuid-config --libdir`

=item error

Cannot find library directory

=item unknown

Enter a valid OSSP UUID library directory

=back

=cut

sub lib_dir {
    my $self = shift;
    return unless $self->{uuid_config};
    unless (exists $self->{lib_dir} ) {
        if (my $dir = $get_data->($self, '--libdir')) {
            $self->{lib_dir} = $dir;
        } else {
            # Handle an unknown value.
            $self->error("Cannot find library directory");
            $self->{lib_dir} = $self->unknown(
                key      => 'OSSP UUID library dir',
                callback => $is_dir
            );
        }
    }

    return $self->{lib_dir};
}

##############################################################################

=head3 so_lib_dir

  my $so_lib_dir = $uuid->so_lib_dir;

Returns the OSSP UUID shared object library directory path. This is actually
just an alias for C<lib_dir()>.

B<Events:>

=over 4

=item info

Executing `uuid-config --libdir`

=item error

Cannot find library directory

=item unknown

Enter a valid OSSP UUID library directory

=back

=cut

*so_lib_dir = \&lib_dir;

##############################################################################

=head3 cflags

  my $configure = $uuid->cflags;

Returns the C flags used when compiling the OSSP UUID library.
App::Info::Lib::OSSPUUID gathers the configure data from the system call
C<`uuid-config --cflags`>.

B<Events:>

=over 4

=item info

Executing `uuid-config --configure`

=item error

Cannot find configure information

=item unknown

Enter OSSP UUID configuration options

=back

=cut

sub cflags {
    my $self = shift;
    return unless $self->{uuid_config};
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

=head3 ldflags

  my $configure = $uuid->ldflags;

Returns the LD flags used when compiling the OSSP UUID library.
App::Info::Lib::OSSPUUID gathers the configure data from the system call
C<`uuid-config --ldflags`>.

B<Events:>

=over 4

=item info

Executing `uuid-config --configure`

=item error

Cannot find configure information

=item unknown

Enter OSSP UUID configuration options

=back

=cut

sub ldflags {
    my $self = shift;
    return unless $self->{uuid_config};
    unless (exists $self->{ldflags} ) {
        if (my $conf = $get_data->($self, '--ldflags')) {
            $self->{ldflags} = $conf;
        } else {
            # Ldflags can be empty, so just make sure it exists and is
            # defined. Don't prompt.
            $self->{ldflags} = '';
        }
    }

    return $self->{ldflags};
}

##############################################################################

=head3 perl_module

  my $bool = $uuid->perl_module;

Return true if C<OSSP::uuid> is installed and can be loaded, and false if not.
C<OSSP::uuid> must be able to be loaded by the currently running instance of
the Perl interpreter.

B<Events:>

=over 4

=item info

Loading OSSP::uuid

=back

=cut

sub perl_module {
    my $self = shift;
    $self->info('Loading OSSP::uuuid');
    $self->{perl_module} ||= do {
        eval 'use OSSP::uuid';
        $INC{catfile qw(OSSP uuid.pm)};
    };
    return $self->{perl_module};
}

##############################################################################

=head3 home_url

  my $home_url = $uuid->home_url;

Returns the OSSP UUID home page URL.

=cut

sub home_url { 'http://www.ossp.org/pkg/lib/uuid/' }

##############################################################################

=head3 download_url

  my $download_url = $uuid->download_url;

Returns the OSSP UUID download URL.

=cut

sub download_url { 'http://www.ossp.org/pkg/lib/uuid/' }

##############################################################################

=head3 search_exe_names

  my @search_exe_names = $app->search_exe_names;

Returns a list of possible names for F<uuid-config> executable. By default, only
F<uuid-config> is returned (or F<uuid-config.exe> on Win32).

Note that this method is not used to search for the OSSP UUID server
executable, only F<uuid-config>.

=cut

sub search_exe_names {
    my $self = shift;
    my $exe = 'uuid-config';
    $exe .= '.exe' if WIN32;
    return ($self->SUPER::search_exe_names, $exe);
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

=item /usr/local/bin

=item /usr/local/sbin

=item /usr/bin

=item /usr/sbin

=item /bin

=item C:\Program Files\uid\bin

=back

=cut

sub search_bin_dirs {
    return shift->SUPER::search_bin_dirs,
      $u->path,
      qw(/usr/local/bin
         /usr/local/sbin
         /usr/bin
         /usr/sbin
         /bin),
      'C:\Program Files\uid\bin';
}

##############################################################################

=head2 Other Executable Methods

These methods function just like the C<executable()> method, except that they
return different executables. OSSP UUID comes with a fair number of them; we
provide these methods to provide a path to a subset of them. Each method, when
called, checks for an executable in the directory returned by C<bin_dir()>.
The name of the executable must be one of the names returned by the
corresponding C<search_*_names> method.

The available executable methods are:

=over

=item uuid

=item uuid_config

=back

And the corresponding search names methods are:

=over

=item search_postgres_names

=item search_createdb_names

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

sub search_uuid_names { @{ shift->{search_uuid_names} } }

1;
__END__

=head1 BUGS

Please send bug reports to <bug-app-info@rt.cpan.org> or file them at
L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=App-Info>.

=head1 AUTHOR

David Wheeler <david@justatheory.com>.

=head1 SEE ALSO

L<App::Info|App::Info> documents the event handling interface.

L<App::Info::Lib|App::Info::Lib> is the App::Info::Lib::Expat parent class.

L<OSSP::uuid|OSSP::uuid> is the Perl interface to the OSSP UUID library.

L<http://www.ossp.org/pkg/lib/uuid/> is the OSSP UUID home page.

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2002-2008, David Wheeler. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
