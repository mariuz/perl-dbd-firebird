package App::Info::Lib::Iconv;

# $Id: Iconv.pm 3929 2008-05-18 03:58:14Z david $

=head1 NAME

App::Info::Lib::Iconv - Information about libiconv

=head1 SYNOPSIS

  use App::Info::Lib::Iconv;

  my $iconv = App::Info::Lib::Iconv->new;

  if ($iconv->installed) {
      print "App name: ", $iconv->name, "\n";
      print "Version:  ", $iconv->version, "\n";
      print "Bin dir:  ", $iconv->bin_dir, "\n";
  } else {
      print "libiconv is not installed. :-(\n";
  }

=head1 DESCRIPTION

App::Info::Lib::Iconv supplies information about the libiconv library
installed on the local system. It implements all of the methods defined by
App::Info::Lib. Methods that trigger events will trigger them only the first
time they're called (See L<App::Info|App::Info> for documentation on handling
events). To start over (after, say, someone has installed libiconv) construct
a new App::Info::Lib::Iconv object to aggregate new meta data.

Some of the methods trigger the same events. This is due to cross-calling of
shared subroutines. However, any one event should be triggered no more than
once. For example, although the info event "Searching for 'iconv.h'" is
documented for the methods C<version()>, C<major_version()>, and
C<minor_version()>, rest assured that it will only be triggered once, by
whichever of those four methods is called first.

=cut

use strict;
use File::Basename ();
use App::Info::Util;
use App::Info::Lib;
use vars qw(@ISA $VERSION);
@ISA = qw(App::Info::Lib);
$VERSION = '0.55';
use constant WIN32 => $^O eq 'MSWin32';

my $u = App::Info::Util->new;

##############################################################################

=head1 INTERFACE

=head2 Constructor

=head3 new

  my $iconv = App::Info::Lib::Iconv->new(@params);

Returns an App::Info::Lib::Iconv object. See L<App::Info|App::Info> for a
complete description of argument parameters.

When called, C<new()> searches the the list of directories returned by the
C<search_bin_dirs()> method for an executable file with a name returned by the
C<search_exe_names()> method. If the executable is found, libiconv will be
assumed to be installed. Otherwise, most of the object methods will return
C<undef>.

B<Events:>

=over 4

=item info

Searching for iconv

=item unknown

Path to iconv executable?

=item confirm

Path to iconv executable?

=back

=cut

sub new {
    my $self = shift->SUPER::new(@_);
    # Find iconv.
    $self->info("Searching for iconv");

    if (my $exe = $u->first_cat_exe([$self->search_exe_names],
                                    $self->search_bin_dirs)) {
        # We found it. Confirm.
        $self->{executable} = $self->confirm(
            key      => 'path to iconv',
            prompt   => 'Path to iconv executable?',
            value    => $exe,
            callback => sub { -x },
            error    => 'Not an executable'
        );
    } else {
        # No luck. Ask 'em for it.
        $self->{executable} = $self->unknown(
            key      => 'path to iconv',
            prompt   => 'Path to iconv executable?',
            callback => sub { -x },
            error    => 'Not an executable'
        );
    }

    return $self;
}

##############################################################################

=head2 Class Method

=head3 key_name

  my $key_name = App::Info::Lib::Iconv->key_name;

Returns the unique key name that describes this class. The value returned is
the string "libiconv".

=cut

sub key_name { 'libiconv' }

##############################################################################

=head2 Object Methods

=head3 installed

  print "libiconv is ", ($iconv->installed ? '' : 'not '),
    "installed.\n";

Returns true if libiconv is installed, and false if it is not.
App::Info::Lib::Iconv determines whether libiconv is installed based on the
presence or absence of the F<iconv> application, as found when C<new()>
constructed the object. If libiconv does not appear to be installed, then most
of the other object methods will return empty values.

=cut

sub installed { $_[0]->{executable} ? 1 : undef }

##############################################################################

=head3 name

  my $name = $iconv->name;

Returns the name of the application. In this case, C<name()> simply returns
the string "libiconv".

=cut

sub name { 'libiconv' }

##############################################################################

=head3 version

  my $version = $iconv->version;

Returns the full version number for libiconv. App::Info::Lib::Iconv attempts
to parse the version number from the F<iconv.h> file, if it exists.

B<Events:>

=over 4

=item info

Searching for 'iconv.h'

Searching for include directory

=item error

Cannot find include directory

Cannot find 'iconv.h'

Cannot parse version number from file 'iconv.h'

=item unknown

Enter a valid libiconv include directory

Enter a valid libiconv version number

=back

=cut

# This code reference is called by version(), major_version(), and
# minor_version() to get the version numbers.
my $get_version = sub {
    my $self = shift;
    $self->{version} = undef;
    $self->info("Searching for 'iconv.h'");
    # Let inc_dir() do the work.
    unless ($self->inc_dir && $self->{inc_file}) {
        # No point in continuing if there's no include file.
        $self->error("Cannot find 'iconv.h'");
        return;
    }

    # This is the line we're looking for:
    # #define _LIBICONV_VERSION 0x0107    /* version number: (major<<8) + minor */
    my $regex = qr/_LIBICONV_VERSION\s+([^\s]+)\s/;
    if (my $ver = $u->search_file($self->{inc_file}, $regex)) {
        # Convert the version number from hex.
        $ver = hex $ver;
            # Shift 8.
        my $major = $ver >> 8;
        # Left shift 8 and subtract from version.
        my $minor = $ver - ($major << 8);
        # Store 'em!
            @{$self}{qw(version major minor)} =
              ("$major.$minor", $major, $minor);
    } else {
        $self->error("Cannot parse version number from file '$self->{inc_file}'");
    }
};


sub version {
    my $self = shift;
    return unless $self->{executable};

    # Get data.
    $get_version->($self) unless exists $self->{version};

    # Handle an unknown value.
    unless ($self->{version}) {
        # Create a validation code reference.
        my $chk_version = sub {
            # Try to get the version number parts.
            my ($x, $y) = /^(\d+)\.(\d+)$/;
            # Return false if we didn't get all three.
            return unless $x and defined $y;
            # Save both parts.
            @{$self}{qw(major minor)} = ($x, $y);
            # Return true.
            return 1;
        };
        $self->{version} = $self->unknown( key     => 'iconv version number',
                                           callback => $chk_version);
    }

    return $self->{version};
}

##############################################################################

=head3 major_version

  my $major_version = $iconv->major_version;

Returns the libiconv major version number. App::Info::Lib::Iconv attempts to
parse the version number from the F<iconv.h> file, if it exists. For example,
if C<version()> returns "1.7", then this method returns "1".

B<Events:>

=over 4

=item info

Searching for 'iconv.h'

Searching for include directory

=item error

Cannot find include directory

Cannot find 'iconv.h'

Cannot parse version number from file 'iconv.h'

=item unknown

Enter a valid libiconv include directory

Enter a valid libiconv version number

=back

=cut

# This code reference is used by major_version() and minor_version() to
# validate a version number entered by a user.
my $is_int = sub { /^\d+$/ };

sub major_version {
    my $self = shift;
    return unless $self->{executable};

    # Get data.
    $get_version->($self) unless exists $self->{version};

    # Handle an unknown value.
    $self->{major} = $self->unknown( key      => 'iconv major version number',
                                     callback => $is_int)
      unless $self->{major};

    return $self->{major};
}

##############################################################################

=head3 minor_version

  my $minor_version = $iconv->minor_version;

Returns the libiconv minor version number. App::Info::Lib::Iconv attempts to
parse the version number from the F<iconv.h> file, if it exists. For example,
if C<version()> returns "1.7", then this method returns "7".

B<Events:>

=over 4

=item info

Searching for 'iconv.h'

Searching for include directory

=item error

Cannot find include directory

Cannot find 'iconv.h'

Cannot parse version number from file 'iconv.h'

=item unknown

Enter a valid libiconv include directory

Enter a valid libiconv version number

=back

=cut

sub minor_version {
    my $self = shift;
    return unless $self->{executable};

    # Get data.
    $get_version->($self) unless exists $self->{version};

    # Handle an unknown value.
    $self->{minor} = $self->unknown( key      => 'iconv minor version number',
                                     callback => $is_int)
      unless $self->{minor};

    return $self->{minor};
}

##############################################################################

=head3 patch_version

  my $patch_version = $iconv->patch_version;

Since libiconv has no patch number in its version number, this method will
always return false.

=cut

sub patch_version { return }

##############################################################################

=head3 executable

  my $executable = $iconv->executable;

Returns the path to the Iconv executable, which will be defined by one of the
names returned by C<search_exe_names()>. The executable is searched for in
C<new()>, so there are no events for this method.

=cut

sub executable { shift->{executable} }

##############################################################################

=head3 bin_dir

  my $bin_dir = $iconv->bin_dir;

Returns the path of the directory in which the F<iconv> application was found
when the object was constructed by C<new()>.

B<Events:>

=over 4

=item info

Searching for bin directory

=item error

Cannot find bin directory

=item unknown

Enter a valid libiconv bin directory

=back

=cut

# This code reference is used by inc_dir() and so_lib_dir() to validate a
# directory entered by the user.
my $is_dir = sub { -d };

sub bin_dir {
    my $self = shift;
    return unless $self->{executable};
    unless (exists $self->{bin_dir}) {
        # This is all probably redundant, but let's do the drill, anyway.
        $self->info("Searching for bin directory");
        if (my $bin = File::Basename::dirname($self->{executable})) {
            # We found it!
            $self->{bin_dir} = $bin;
        } else {
            $self->{bin_dir} = $self->unknown(
                key      => 'iconv bin dir',
                callback => $is_dir
            );
        }
    }
    return $self->{bin_dir};
}

##############################################################################

=head3 inc_dir

  my $inc_dir = $iconv->inc_dir;

Returns the directory path in which the file F<iconv.h> was found.
App::Info::Lib::Iconv searches for F<iconv.h> in the following directories:

=over 4

=item /usr/local/include

=item /usr/include

=item /sw/include

=back

B<Events:>

=over 4

=item info

Searching for include directory

=item error

Cannot find include directory

=item unknown

Enter a valid libiconv include directory

=back

=cut

sub inc_dir {
    my $self = shift;
    return unless $self->{executable};
    unless (exists $self->{inc_dir}) {
        $self->info("Searching for include directory");
        my @incs = $self->search_inc_names;
        if (my $dir = $u->first_cat_dir(\@incs, $self->search_inc_dirs)) {
            $self->{inc_dir} = $dir;
        } else {
            $self->error("Cannot find include directory");
            my $cb = sub { $u->first_cat_dir(\@incs, $_) };
            $self->{inc_dir} =
              $self->unknown( key      => 'iconv inc dir',
                              callback => $cb,
                              error    => "Iconv include file not found in " .
                                          "directory");
        }
        # So which is the include file? Needed for the version number.
        $self->{inc_file} = $u->first_file(
            map { $u->catfile($self->{inc_dir}, $_) } @incs
        ) if $self->{inc_dir};
    }
    return $self->{inc_dir};
}

##############################################################################

=head3 lib_dir

  my $lib_dir = $iconv->lib_dir;

Returns the directory path in which a libiconv library was found. The search
looks for a file with a name returned by C<search_lib_names()> in a directory
returned by C<search_lib_dirs()>.

B<Events:>

=over 4

=item info

Searching for library directory

=item error

Cannot find library directory

=item unknown

Enter a valid libiconv library directory

=back

=cut

sub lib_dir {
    my $self = shift;
    return unless $self->{executable};
    unless (exists $self->{lib_dir}) {
        $self->info("Searching for library directory");
        my @files = $self->search_lib_names;

        if (my $dir = $u->first_cat_dir(\@files, $self->search_lib_dirs)) {
            # Success!
            $self->{lib_dir} = $dir;
        } else {
            $self->error("Cannot not find library direcory");
            my $cb = sub { $u->first_cat_dir(\@files, $_) };
            $self->{lib_dir} = $self->unknown(
                key      => 'iconv lib dir',
                callback => $cb,
                error    => "Library files not found in directory"
            );
        }
    }
    return $self->{lib_dir};
}

##############################################################################

=head3 so_lib_dir

  my $so_lib_dir = $iconv->so_lib_dir;

Returns the directory path in which a libiconv shared object library was
found. The search looks for a file with a name returned by
C<search_so_lib_names()> in a directory returned by C<search_lib_dirs()>.

Returns the directory path in which a libiconv shared object library was
found. App::Info::Lib::Iconv searches for these files:

<Events:>

=over 4

=item info

Searching for shared object library directory

=item error

Cannot find shared object library directory

=item unknown

Enter a valid libiconv shared object library directory

=back

=cut

sub so_lib_dir {
    my $self = shift;
    return unless $self->{executable};
    unless (exists $self->{so_lib_dir}) {
        $self->info("Searching for shared object library directory");
        my @files = $self->search_so_lib_names;

        if (my $dir = $u->first_cat_dir(\@files, $self->search_lib_dirs)) {
            $self->{so_lib_dir} = $dir;
        } else {
            $self->error("Cannot find shared object library directory");
            my $cb = sub { $u->first_cat_dir(\@files, $_) };
            $self->{so_lib_dir} =
              $self->unknown( key      => 'iconv so dir',
                              callback => $cb,
                              error    => "Shared object libraries not " .
                                          "found in directory");
        }
    }
    return $self->{so_lib_dir};
}

##############################################################################

=head3 home_url

  my $home_url = $iconv->home_url;

Returns the libiconv home page URL.

=cut

sub home_url { 'http://www.gnu.org/software/libiconv/' }

##############################################################################

=head3 download_url

  my $download_url = $iconv->download_url;

Returns the libiconv download URL.

=cut

sub download_url { 'ftp://ftp.gnu.org/pub/gnu/libiconv/' }

##############################################################################

=head3 search_exe_names

  my @search_exe_names = $iconv->search_exe_names;

Returns a list of possible names for the Iconv executable. By default, the
only name returned is F<iconv> (F<iconv.exe> on Win32).

=cut

sub search_exe_names {
    my $self = shift;
    my @exes = qw(iconv);
    if (WIN32) { $_ .= ".exe" for @exes }
    return ($self->SUPER::search_exe_names, @exes);
}

##############################################################################

=head3 search_bin_dirs

  my @search_bin_dirs = $iconv->search_bin_dirs;

Returns a list of possible directories in which to search an executable. Used
by the C<new()> constructor to find an executable to execute and collect
application info. The found directory will also be returned by the C<bin_dir>
method. By default, the directories returned are those in your path, followed
by these:

=over 4

=item F</usr/local/bin>

=item F</usr/bin>

=item F</bin>

=item F</sw/bin>

=item F</usr/local/sbin>

=item F</usr/sbin>

=item F</sbin>

=item F</sw/sbin>

=back

=cut

sub search_bin_dirs {
    return (
      shift->SUPER::search_bin_dirs,
      $u->path,
      qw(/usr/local/bin
         /usr/bin
         /bin
         /sw/bin
         /usr/local/sbin
         /usr/sbin/
         /sbin
         /sw/sbin)
    );
}


##############################################################################

=head3 search_lib_names

  my @seach_lib_names = $self->search_lib_nams

Returns a list of possible names for library files. Used by C<lib_dir()> to
search for library files. By default, the list is:

=over

=item libiconv3.a

=item libiconv3.la

=item libiconv3.so

=item libiconv3.so.0

=item libiconv3.so.0.0.1

=item libiconv3.dylib

=item libiconv3.0.dylib

=item libiconv3.0.0.1.dylib

=item libiconv.a

=item libiconv.la

=item libiconv.so

=item libiconv.so.0

=item libiconv.so.0.0.1

=item libiconv.dylib

=item libiconv.2.dylib

=item libiconv.2.0.4.dylib

=item libiconv.0.dylib

=item libiconv.0.0.1.dylib

=back

=cut

sub search_lib_names {
    my $self = shift;
    return $self->SUPER::search_lib_names,
      map { "libiconv.$_"} qw(a la so so.0 so.0.0.1 dylib 2.dylib 2.0.4.dylib
                              0.dylib 0.0.1.dylib);
}

##############################################################################

=head3 search_so_lib_names

  my @seach_so_lib_names = $self->search_so_lib_nams

Returns a list of possible names for shared object library files. Used by
C<so_lib_dir()> to search for library files. By default, the list is:

=over

=item libiconv3.so

=item libiconv3.so.0

=item libiconv3.so.0.0.1

=item libiconv3.dylib

=item libiconv3.0.dylib

=item libiconv3.0.0.1.dylib

=item libiconv.so

=item libiconv.so.0

=item libiconv.so.0.0.1

=item libiconv.dylib

=item libiconv.0.dylib

=item libiconv.0.0.1.dylib

=back

=cut

sub search_so_lib_names {
    my $self = shift;
    return $self->SUPER::search_so_lib_names,
      map { "libiconv.$_"} qw(so so.0 so.0.0.1 dylib 2.dylib 2.0.4.dylib
                              0.dylib 0.0.1.dylib);
}

##############################################################################

=head3 search_lib_dirs

  my @search_lib_dirs = $iconv->search_lib_dirs;

Returns a list of possible directories in which to search for libraries. By
default, it returns all of the paths in the C<libsdirs> and C<loclibpth>
attributes defined by the Perl L<Config|Config> module -- plus F</sw/lib> (in
support of all you Fink users out there).

=cut

sub search_lib_dirs { shift->SUPER::search_lib_dirs, $u->lib_dirs, '/sw/lib' }

##############################################################################

=head3 search_inc_names

  my @search_inc_names = $iconv->search_inc_names;

Returns a list of include file names to search for. Used by C<inc_dir()> to
search for an include file. By default, the only name returned is F<iconv.h>.

=cut

sub search_inc_names {
    my $self = shift;
    return $self->SUPER::search_inc_names, "iconv.h";
}

##############################################################################

=head3 search_inc_dirs

  my @search_inc_dirs = $iconv->search_inc_dirs;

Returns a list of possible directories in which to search for include files.
Used by C<inc_dir()> to search for an include file. By default, the
directories are:

=over 4

=item /usr/local/include

=item /usr/include

=item /sw/include

=back

=cut

sub search_inc_dirs {
    shift->SUPER::search_inc_dirs,
      qw(/usr/local/include
         /usr/include
         /sw/include);
}

1;
__END__

=head1 KNOWN ISSUES

This is a pretty simple class. It's possible that there are more directories
that ought to be searched for libraries and includes.

=head1 TO DO

Improve this class by borrowing code from Matt Seargent's AxKit F<Makefil.PL>.

=head1 BUGS

Please send bug reports to <bug-app-info@rt.cpan.org> or file them at
L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=App-Info>.

=head1 AUTHOR

David Wheeler <david@justatheory.com> based on code by Sam Tregar
<sam@tregar.com>.

=head1 SEE ALSO

L<App::Info|App::Info>,
L<App::Info::Lib|App::Info::Lib>,
L<Text::Iconv|Text::Iconv>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2002-2008, David Wheeler. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under the
same terms as Perl itself.

=cut
