package App::Info::RDBMS;

# $Id: RDBMS.pm 3929 2008-05-18 03:58:14Z david $

use strict;
use App::Info;
use vars qw(@ISA $VERSION);
@ISA = qw(App::Info);
$VERSION = '0.55';

1;
__END__

=head1 NAME

App::Info::RDBMS - Information about databases on a system

=head1 DESCRIPTION

This class is an abstract base class for App::Info subclasses that provide
information about relational databases. Its subclasses are required to
implement its interface. See L<App::Info|App::Info> for a complete description
and L<App::Info::RDBMS::PostgreSQL|App::Info::RDBMS::PostgreSQL> for an example
implementation.

=head1 INTERFACE

Currently, App::Info::RDBMS adds no more methods than those from its parent
class, App::Info.

=head1 BUGS

Please send bug reports to <bug-app-info@rt.cpan.org> or file them at
L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=App-Info>.

=head1 AUTHOR

David Wheeler <david@justatheory.com>

=head1 SEE ALSO

L<App::Info|App::Info>,
L<App::Info::RDBMS::PostgreSQL|App::Info::RDBMS::PostgreSQL>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2002-2008, David Wheeler. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under the
same terms as Perl itself.

=cut



