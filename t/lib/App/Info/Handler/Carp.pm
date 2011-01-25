package App::Info::Handler::Carp;

# $Id: Carp.pm 3929 2008-05-18 03:58:14Z david $

=head1 NAME

App::Info::Handler::Carp - Use Carp to handle App::Info events

=head1 SYNOPSIS

  use App::Info::Category::FooApp;
  use App::Info::Handler::Carp;

  my $carp = App::Info::Handler::Carp->new('carp');
  my $app = App::Info::Category::FooApp->new( on_info => $carp );

  # Or...
  my $app = App::Info::Category::FooApp->new( on_error => 'croak' );

=head1 DESCRIPTION

App::Info::Handler::Carp objects handle App::Info events by passing their
messages to Carp functions. This means that if you want errors to croak or
info messages to carp, you can easily do that. You'll find, however, that
App::Info::Handler::Carp is most effective for info and error events; unknown
and prompt events are better handled by event handlers that know how to prompt
users for data. See L<App::Info::Handler::Prompt|App::Info::Handler::Prompt>
for an example of that functionality.

Upon loading, App::Info::Handler::Carp registers itself with
App::Info::Handler, setting up a number of strings that can be passed to an
App::Info concrete subclass constructor. These strings are shortcuts that
tell App::Info how to create the proper App::Info::Handler::Carp object
for handling events. The registered strings are:

=over

=item carp

Passes the event message to C<Carp::carp()>.

=item warn

An alias for "carp".

=item croak

Passes the event message to C<Carp::croak()>.

=item die

An alias for "croak".

=item cluck

Passes the event message to C<Carp::cluck()>.

=item confess

Passes the event message to C<Carp::confess()>.

=back

=cut

use strict;
use App::Info::Handler;
use vars qw($VERSION @ISA);
$VERSION = '0.55';
@ISA = qw(App::Info::Handler);

my %levels = ( croak   => sub { goto &Carp::croak },
               carp    => sub { goto &Carp::carp },
               cluck   => sub { goto &Carp::cluck },
               confess => sub { goto &Carp::confess }
             );

# A couple of aliases.
$levels{die} = $levels{croak};
$levels{warn} = $levels{carp};

# Register ourselves.
for my $c (qw(croak carp cluck confess die warn)) {
    App::Info::Handler->register_handler
      ($c => sub { __PACKAGE__->new( level => $c ) } );
}

=head1 INTERFACE

=head2 Constructor

=head3 new

  my $carp_handler = App::Info::Handler::Carp->new;
  $carp_handler = App::Info::Handler::Carp->new( level => 'carp' );
  my $croak_handler = App::Info::Handler::Carp->new( level => 'croak' );

Constructs a new App::Info::Handler::Carp object and returns it. It can take a
single parameterized argument, C<level>, which can be any one of the following
values:

=over

=item carp

Constructs a App::Info::Handler::Carp object that passes the event message to
C<Carp::carp()>.

=item warn

An alias for "carp".

=item croak

Constructs a App::Info::Handler::Carp object that passes the event message to
C<Carp::croak()>.

=item die

An alias for "croak".

=item cluck

Constructs a App::Info::Handler::Carp object that passes the event message to
C<Carp::cluck()>.

=item confess

Constructs a App::Info::Handler::Carp object that passes the event message to
C<Carp::confess()>.

=back

If the C<level> parameter is not passed, C<new()> will default to creating an
App::Info::Handler::Carp object that passes App::Info event messages to
C<Carp::carp()>.

=cut

sub new {
    my $pkg = shift;
    my $self = $pkg->SUPER::new(@_);
    if ($self->{level}) {
        Carp::croak("Invalid error handler '$self->{level}'")
          unless $levels{$self->{level}};
    } else {
        $self->{level} = 'carp';
    }
    return $self;
}

sub handler {
    my ($self, $req) = @_;
    # Change package to App::Info to trick Carp into issuing the stack trace
    # from the proper context of the caller.
    package App::Info;
    $levels{$self->{level}}->($req->message);
    # Return true to indicate that we've handled the request.
    return 1;
}

1;
__END__

=head1 BUGS

Please send bug reports to <bug-app-info@rt.cpan.org> or file them at
L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=App-Info>.

=head1 AUTHOR

David Wheeler <david@justatheory.com>

=head1 SEE ALSO

L<App::Info|App::Info> documents the event handling interface.

L<Carp|Carp> of documents the functions used by this class.

L<App::Info::Handler::Print|App::Info::Handler::Print> handles events by
printing their messages to a file handle.

L<App::Info::Handler::Prompt|App::Info::Handler::Prompt> offers event handling
more appropriate for unknown and confirm events.

L<App::Info::Handler|App::Info::Handler> describes how to implement custom
App::Info event handlers.

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2002-2008, David Wheeler. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under the
same terms as Perl itself.

=cut
