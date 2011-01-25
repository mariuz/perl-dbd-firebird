package App::Info::Lib::Expat;

# $Id: Expat.pm 3929 2008-05-18 03:58:14Z david $

=head1 NAME

App::Info::Lib::Expat - Information about the Expat XML parser

=head1 SYNOPSIS

  use App::Info::Lib::Expat;

  my $expat = App::Info::Lib::Expat->new;

  if ($expat->installed) {
      print "App name: ", $expat->name, "\n";
      print "Version:  ", $expat->version, "\n";
      print "Bin dir:  ", $expat->bin_dir, "\n";
  } else {
      print "Expat is not installed. :-(\n";
  }

=head1 DESCRIPTION

App::Info::Lib::Expat supplies information about the Expat XML parser
installed on the local system. It implements all of the methods defined by
App::Info::Lib. Methods that trigger events will trigger them only the first
time they're called (See L<App::Info|App::Info> for documentation on handling
events). To start over (after, say, someone has installed Expat) construct a
new App::Info::Lib::Expat object to aggregate new meta data.

Some of the methods trigger the same events. This is due to cross-calling of
shared subroutines. However, any one event should be triggered no more than
once. For example, although the info event "Searching for 'expat.h'" is
documented for the methods C<version()>, C<major_version()>,
C<minor_version()>, and C<patch_version()>, rest assured that it will only be
triggered once, by whichever of those four methods is called first.

=cut

use strict;
use App::Info::Util;
use App::Info::Lib;
use Config;
use vars qw(@ISA $VERSION);
@ISA = qw(App::Info::Lib);
$VERSION = '0.55';

my $u = App::Info::Util->new;

##############################################################################

=head1 INTERFACE

=head2 Constructor

=head3 new

  my $expat = App::Info::Lib::Expat->new(@params);

Returns an App::Info::Lib::Expat object. See L<App::Info|App::Info> for a
complete description of argument parameters.

When called, C<new()> searches all of the paths returned by the
C<search_lib_dirs()> method for one of the files returned by the
C<search_lib_names()> method. If any of is found, then Expat is assumed to be
installed. Otherwise, most of the object methods will return C<undef>.

B<Events:>

=over 4

=item info

Searching for Expat libraries

=item confirm

Path to Expat library directory?

=item unknown

Path to Expat library directory?

=back

=cut

sub new {
    # Construct the object.
    my $self = shift->SUPER::new(@_);
    # Find libexpat.
    $self->info("Searching for Expat libraries");

    my @libs = $self->search_lib_names;
    my $cb = sub { $u->first_cat_dir(\@libs, $_) };
    if (my $lexpat = $u->first_cat_dir(\@libs, $self->search_lib_dirs)) {
        # We found libexpat. Confirm.
        $self->{libexpat} =
          $self->confirm( key      => 'expat lib dir',
                          prompt   => 'Path to Expat library directory?',
                          value    => $lexpat,
                          callback => $cb,
                          error    => 'No Expat libraries found in directory');
    } else {
        # Handle an unknown value.
        $self->{libexpat} =
          $self->unknown( key      => 'expat lib dir',
                          prompt   => 'Path to Expat library directory?',
                          callback => $cb,
                          error    => 'No Expat libraries found in directory');
    }

    return $self;
}

##############################################################################

=head2 Class Method

=head3 key_name

  my $key_name = App::Info::Lib::Expat->key_name;

Returns the unique key name that describes this class. The value returned is
the string "Expat".

=cut

sub key_name { 'Expat' }

##############################################################################

=head2 Object Methods

=head3 installed

  print "Expat is ", ($expat->installed ? '' : 'not '),
    "installed.\n";

Returns true if Expat is installed, and false if it is not.
App::Info::Lib::Expat determines whether Expat is installed based on the
presence or absence on the file system of one of the files searched for when
C<new()> constructed the object. If Expat does not appear to be installed,
then most of the other object methods will return empty values.

=cut

sub installed { $_[0]->{libexpat} ? 1 : undef }

##############################################################################

=head3 name

  my $name = $expat->name;

Returns the name of the application. In this case, C<name()> simply returns
the string "Expat".

=cut

sub name { 'Expat' }

##############################################################################

=head3 version

Returns the full version number for Expat. App::Info::Lib::Expat attempts
parse the version number from the F<expat.h> file, if it exists.

B<Events:>

=over 4

=item info

Searching for 'expat.h'

Searching for include directory

=item error

Cannot find include directory

Cannot find 'expat.h'

Failed to parse version from 'expat.h'

=item unknown

Enter a valid Expat include directory

Enter a valid Expat version number

=back

=cut

my $get_version = sub {
    my $self = shift;
    $self->{version} = undef;
    $self->info("Searching for 'expat.h'");
    my $inc = $self->inc_dir
      or ($self->error("Cannot find 'expat.h'")) && return;
    my $header = $u->catfile($inc, 'expat.h');
    my @regexen = ( qr/XML_MAJOR_VERSION\s+(\d+)$/,
                    qr/XML_MINOR_VERSION\s+(\d+)$/,
                    qr/XML_MICRO_VERSION\s+(\d+)$/ );

    my ($x, $y, $z) = $u->multi_search_file($header, @regexen);
    if (defined $x and defined $y and defined $z) {
        # Assemble the version number and store it.
        my $v = "$x.$y.$z";
        @{$self}{qw(version major minor patch)} = ($v, $x, $y, $z);
    } else {
        # Warn them if we couldn't get them all.
        $self->error("Failed to parse version from '$header'");
    }
};

sub version {
    my $self = shift;
    return unless $self->{libexpat};

    # Get data.
    $get_version->($self) unless exists $self->{version};

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
        $self->{version} = $self->unknown( key      => 'expat version number',
                                           callback => $chk_version);
    }
    return $self->{version};
}

##############################################################################

=head3 major_version

  my $major_version = $expat->major_version;

Returns the Expat major version number. App::Info::Lib::Expat attempts to
parse the version number from the F<expat.h> file, if it exists. For example,
if C<version()> returns "1.95.2", then this method returns "1".

B<Events:>

=over 4

=item info

Searching for 'expat.h'

Searching for include directory

=item error

Cannot find include directory

Cannot find 'expat.h'

Failed to parse version from 'expat.h'

=item unknown

Enter a valid Expat include directory

Enter a valid Expat major version number

=back

=cut

# This code reference is used by major_version(), minor_version(), and
# patch_version() to validate a version number entered by a user.
my $is_int = sub { /^\d+$/ };

sub major_version {
    my $self = shift;
    return unless $self->{libexpat};

    # Get data.
    $get_version->($self) unless exists $self->{version};

    # Handle an unknown value.
    $self->{major} = $self->unknown( key      => 'expat major version number',
                                     callback => $is_int)
      unless $self->{major};

    return $self->{major};
}

##############################################################################

=head3 minor_version

  my $minor_version = $expat->minor_version;

Returns the Expat minor version number. App::Info::Lib::Expat attempts to
parse the version number from the F<expat.h> file, if it exists. For example,
if C<version()> returns "1.95.2", then this method returns "95".

B<Events:>

=over 4

=item info

Searching for 'expat.h'

Searching for include directory

=item error

Cannot find include directory

Cannot find 'expat.h'

Failed to parse version from 'expat.h'

=item unknown

Enter a valid Expat include directory

Enter a valid Expat minor version number

=back

=cut

sub minor_version {
    my $self = shift;
    return unless $self->{libexpat};

    # Get data.
    $get_version->($self) unless exists $self->{version};

    # Handle an unknown value.
    $self->{minor} = $self->unknown( key       =>'expat minor version number',
                                     callback  => $is_int)
      unless $self->{minor};

    return $self->{minor};
}

##############################################################################

=head3 patch_version

  my $patch_version = $expat->patch_version;

Returns the Expat patch version number. App::Info::Lib::Expat attempts to
parse the version number from the F<expat.h> file, if it exists. For example,
C<version()> returns "1.95.2", then this method returns "2".

B<Events:>

=over 4

=item info

Searching for 'expat.h'

Searching for include directory

=item error

Cannot find include directory

Cannot find 'expat.h'

Failed to parse version from 'expat.h'

=item unknown

Enter a valid Expat include directory

Enter a valid Expat patch version number

=back

=cut

sub patch_version {
    my $self = shift;
    return unless $self->{libexpat};

    # Get data.
    $get_version->($self) unless exists $self->{version};

    # Handle an unknown value.
    $self->{patch} = $self->unknown( key      => 'expat patch version number',
                                     callback => $is_int)
      unless $self->{patch};

    return $self->{patch};
}

##############################################################################

=head3 bin_dir

  my $bin_dir = $expat->bin_dir;

Since Expat includes no binaries, this method always returns false.

=cut

sub bin_dir { return }

##############################################################################

=head3 executable

  my $executable = $expat->executable;

Since Expat includes no executable program, this method always returns false.

=cut

sub executable { return }

##############################################################################

=head3 inc_dir

  my $inc_dir = $expat->inc_dir;

Returns the directory path in which the file F<expat.h> was found.
App::Info::Lib::Expat searches for F<expat.h> in the following directories:

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

Enter a valid Expat include directory

=back

=cut

# This code reference is used by inc_dir() and so_lib_dir() to validate a
# directory entered by the user.
my $is_dir = sub { -d };

sub inc_dir {
    my $self = shift;
    return unless $self->{libexpat};
    unless (exists $self->{inc_dir}) {
        $self->info("Searching for include directory");
        my @incs = $self->search_inc_names;

        if (my $dir = $u->first_cat_dir(\@incs, $self->search_inc_dirs)) {
            $self->{inc_dir} = $dir;
        } else {
            $self->error("Cannot find include directory");
            my $cb = sub { $u->first_cat_dir(\@incs, $_) };
            $self->{inc_dir} =
              $self->unknown( key      => 'explat inc dir',
                              callback => $cb,
                              error    => "No expat include file found in " .
                                          "directory");
        }
    }
    return $self->{inc_dir};
}

##############################################################################

=head3 lib_dir

  my $lib_dir = $expat->lib_dir;

Returns the directory path in which a Expat library was found. The files and
paths searched are as described for the L<"new"|new> constructor, as are
the events.

=cut

sub lib_dir { $_[0]->{libexpat} }

##############################################################################

=head3 so_lib_dir

  my $so_lib_dir = $expat->so_lib_dir;

Returns the directory path in which a Expat shared object library was found.
It searches all of the paths in the C<libsdirs> and C<loclibpth> attributes
defined by the Perl L<Config|Config> module -- plus F</sw/lib> (for all you
Fink fans) -- for one of the following files:

=over

=item libexpat.so

=item libexpat.so.0

=item libexpat.so.0.0.1

=item libexpat.dylib

=item libexpat.0.dylib

=item libexpat.0.0.1.dylib

=back

B<Events:>

=over 4

=item info

Searching for shared object library directory

=item error

Cannot find shared object library directory

=item unknown

Enter a valid Expat shared object library directory

=back

=cut

sub so_lib_dir {
    my $self = shift;
    return unless $self->{libexpat};
    unless (exists $self->{so_lib_dir}) {
        $self->info("Searching for shared object library directory");

    my @libs = $self->search_so_lib_names;
    my $cb = sub { $u->first_cat_dir(\@libs, $_) };
        if (my $dir = $u->first_cat_dir(\@libs, $self->search_lib_dirs)) {
            $self->{so_lib_dir} = $dir;
        } else {
            $self->error("Cannot find shared object library directory");
            $self->{so_lib_dir} =
              $self->unknown( key      => 'expat so dir',
                              callback => $cb,
                              error    => "Shared object libraries not " .
                                          "found in directory");
        }
    }
    return $self->{so_lib_dir};
}

=head3 home_url

  my $home_url = $expat->home_url;

Returns the libexpat home page URL.

=cut

sub home_url { 'http://expat.sourceforge.net/' }

=head3 download_url

  my $download_url = $expat->download_url;

Returns the libexpat download URL.

=cut

sub download_url { 'http://sourceforge.net/projects/expat/' }

##############################################################################

=head3 search_lib_names

  my @seach_lib_names = $self->search_lib_nams

Returns a list of possible names for library files. Used by C<lib_dir()> to
search for library files. By default, the list is:

=over

=item libexpat.a

=item libexpat.la

=item libexpat.so

=item libexpat.so.0

=item libexpat.so.0.0.1

=item libexpat.dylib

=item libexpat.0.dylib

=item libexpat.0.0.1.dylib

=back

=cut

sub search_lib_names {
    my $self = shift;
    return $self->SUPER::search_lib_names,
      map { "libexpat.$_"} qw(a la so so.0 so.0.0.1 dylib 0.dylib 0.0.1.dylib);
}

##############################################################################

=head3 search_so_lib_names

  my @seach_so_lib_names = $self->search_so_lib_nams

Returns a list of possible names for shared object library files. Used by
C<so_lib_dir()> to search for library files. By default, the list is:

=over

=item libexpat.so

=item libexpat.so.0

=item libexpat.so.0.0.1

=item libexpat.dylib

=item libexpat.0.dylib

=item libexpat.0.0.1.dylib

=back

=cut

sub search_so_lib_names {
    my $self = shift;
    return $self->SUPER::search_so_lib_names,
      map { "libexpat.$_"} qw(so so.0 so.0.0.1 dylib 0.dylib 0.0.1.dylib);
}

##############################################################################

=head3 search_lib_dirs

  my @search_lib_dirs = $expat->search_lib_dirs;

Returns a list of possible directories in which to search for libraries. By
default, it returns all of the paths in the C<libsdirs> and C<loclibpth>
attributes defined by the Perl L<Config|Config> module -- plus F</sw/lib> (in
support of all you Fink users out there).

=cut

sub search_lib_dirs { shift->SUPER::search_lib_dirs, $u->lib_dirs, '/sw/lib' }

##############################################################################

=head3 search_inc_names

  my @search_inc_names = $expat->search_inc_names;

Returns a list of include file names to search for. Used by C<inc_dir()> to
search for an include file. By default, the only name returned is F<expat.h>.

=cut

sub search_inc_names {
    my $self = shift;
    return $self->SUPER::search_inc_names, "expat.h";
}

##############################################################################

=head3 search_inc_dirs

  my @search_inc_dirs = $expat->search_inc_dirs;

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
that ought to be searched for libraries and includes. And if anyone knows
how to get the version numbers, let me know!

The format of the version number seems to have changed recently (1.95.1-2),
and now I don't know where to find the version number. Patches welcome.

=head1 BUGS

Please send bug reports to <bug-app-info@rt.cpan.org> or file them at
L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=App-Info>.

=head1 AUTHOR

David Wheeler <david@justatheory.com> based on code by Sam Tregar
<sam@tregar.com> that Sam, in turn, borrowed from Clark Cooper's
L<XML::Parser|XML::Parser> module.

=head1 SEE ALSO

L<App::Info|App::Info> documents the event handling interface.

L<App::Info::Lib|App::Info::Lib> is the App::Info::Lib::Expat parent class.

L<XML::Parser|XML::Parser> uses Expat to parse XML.

L<Config|Config> provides Perl configure-time information used by
App::Info::Lib::Expat to locate Expat libraries and files.

L<http://expat.sourceforge.net/> is the Expat home page.

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2002-2008, David Wheeler. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under the
same terms as Perl itself.

=cut
