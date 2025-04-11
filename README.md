DBD::Firebird 
==========================

DBI driver for the Firebird RDBMS server.

- Copyright © 2015  Stefan Roas
- Copyright © 2014  H.Merijn Brand - Tux
- Copyright © 2010-2020  Popa Adrian Marius
- Copyright © 2011-2013  Stefan Suciu
- Copyright © 2011-2015, 2024  Damyan Ivanov
- Copyright © 2011  Alexandr Ciornii
- Copyright © 2010-2014  Mike Pomraning
- Copyright © 1999-2005  Edwin Pratomo
- Portions Copyright © 2001-2005  Daniel Ritz

License
-------

You may distribute under the terms of either the GNU General Public
License or the Artistic License, as specified in the Perl README file.
(https://dev.perl.org/licenses/artistic.html)


Installation
------------

Requirements:

- Perl (Threaded and version 5.8.1 or higher)
- Perl DBI (1.41 or higher)
- Firebird (2.5.1 or higher)
- A C compiler
  * UN*X
    GCC or Clang
    

  * Windows
    - Strawberry perl (https://strawberryperl.com/) comes with it's own compiler (mingw)
    - Visual Studio C++ (https://visualstudio.com) 
    - Cygwin
  * Freebsd
    - Threaded Perl is required (You have to re-install Perl from
    ports and you have to select the config option that says 'build a
    Perl with threads')


*BEFORE* BUILDING, TESTING AND INSTALLING this you will need to:

- Build, test and install Perl 5 (at least 5.8.1).

- Build, test and install the DBI module (at least DBI 1.41).

  On Debian/Ubuntu you can do a simple:
    sudo apt-get install firebird3.0-dev libdbi-perl

- Remember to *read* the DBI README file if you installed it from source

- Make sure that Firebird server is running (for testing telnet localhost 3050)


BUILDING:
  Win32/Win64 with Strawberry
    type 'dmake' from the console

  Win32/Win64 with MS compiler:
    type 'nmake', not just 'make'

  To Configure and build the DBD:
    perl Makefile.PL
    make

TESTING
  To run tests module Test::Exception is required on Debian/Ubuntu systems:
     sudo apt-get install libtest-exception-perl

  Please, set at least DBI_PASS (or ISC_PASSWORD), before 'make test'.
  The default for DBI_USER is 'SYSDBA'.(masterkey password is given here as example only)
    ISC_PASSWORD=masterkey make test

INSTALLING:
    make install
