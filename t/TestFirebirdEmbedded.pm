package TestFirebirdEmbedded;
#
# Helper file for the DBD::FirebirdEmbedded tests
#

use strict;
use warnings;
use Carp;

use DBI 1.43;                   # minimum version for 'parse_dsn'
use File::Spec;
use File::Basename;
use File::Temp;

use Test::More;

use base qw(Exporter TestFirebird);

our @EXPORT = qw(find_new_table);

sub import {
    my $me = shift;
    TestFirebird->import;
    $me->export_to_level(1,undef, qw(find_new_table));
}

use constant is_embedded => 1;
use constant dbd => 'DBD::FirebirdEmbedded';

sub check_credentials {
    # this is embedded, nothing to check, we don't need credentials
}

sub read_cached_configs {
    my $self = shift;
    $self->SUPER::read_cached_configs;

    # this is embedded, no server involved
    $ENV{FIREBIRD} = $ENV{FIREBIRD_LOCK} = '.';
    # no authentication either
    delete $ENV{ISC_USER};
    delete $ENV{ISC_PASSWORD};
    delete $ENV{DBI_USER};
    delete $ENV{DBI_PASS};

    delete $self->{user};
    delete $self->{pass};
    delete $self->{host};

    $self->{tdsn} = $self->get_dsn;
    $self->{path} = $self->get_path;
}

sub save_configs {
    # do nothing as we don't want embedded testing to fiddle with the
    # carefuly created configs
    # embedded overrides are implanted already
}

sub get_dsn {
    my $self = shift;

    return "dbi:FirebirdEmbedded:db=dbd-firebird-test.fdb;ib_dialect=3;ib_charset=ISO8859_1";
}

sub check_dsn {
    return shift->get_dsn;
}

sub get_path { 'dbd-firebird-test.fdb' }

# no authentication for embedded
sub get_user { undef }
sub get_pass { undef }
sub get_host { undef }

sub check_mark {
    my $self = shift;

    # mimic first run if the test database is not present
    -f $self->get_path;
}

=head2 drop_test_database

Cleanup time, drop the test database, warn on failure or sql errors.

=cut

sub drop_test_database {
    my $self = shift;

    return unless scalar %{$self};

    my ( $isql, $path ) = ( $self->{isql}, $self->get_path );

    #-- Create the SQL file with DROP statement
    my $sql_dropdb = File::Temp->new();

    print $sql_dropdb qq{connect "$path";\n};
    print $sql_dropdb qq{drop database;\n};
    print $sql_dropdb qq{quit;\n};

    #-- Try to execute isql

    print 'Drop the test database ... ';
    my $error = 0;              # flag

    my $ocmd = qq("$isql" -sql_dialect 3 -q -i "$sql_dropdb" 2>&1);
    eval {
        print "cmd: $ocmd\n";
        open my $isql_fh, '-|', $ocmd;
        while (<$isql_fh>) {
            print "> $_\n";     # for debug
            $error++ if $_ =~ m{error}i;
        }
        close $isql_fh;
    };

    $error++ if $@;

    diag "Test database at $path dropped";

    return 'warning: drop test database failed.' if $error;
}


1;
