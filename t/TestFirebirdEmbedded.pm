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
use File::Path qw(remove_tree);
use File::Temp qw(tempdir);

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

use DBD::FirebirdEmbedded;

sub check_credentials {
    # this is embedded, nothing to check, we don't need credentials
}

sub read_cached_configs {
    my $self = shift;
    $self->SUPER::read_cached_configs;

    unless ($self->{firebird_lock_dir}) {
        my $dir = tempdir( 'dbd-fb.XXXXXXXX', CLEANUP => 0, TMPDIR => 1 );
        note "created $dir\n";
        open( my $fh, '>>', $self->test_conf )
            or die "Unable to open " . $self->test_conf . " for appending: $!";
        print $fh qq(firebird_lock_dir:=$dir\n);
        close($fh) or die "Error closing " . $self->test_conf . ": $!\n";

        $self->{firebird_lock_dir} = $dir;
    }

    # this is embedded, no server involved
    $ENV{FIREBIRD_LOCK} = $self->{firebird_lock_dir};

    # no authentication either
    delete $ENV{ISC_USER};
    delete $ENV{ISC_PASSWORD};
    delete $ENV{DBI_USER};
    delete $ENV{DBI_PASS};

    delete $self->{user};
    delete $self->{pass};
    delete $self->{host};

    if (DBD::FirebirdEmbedded->fb_api_ver >= 30) {
        $self->{user} = 'SYSDBA';
        $self->{pass} = 'any';
    }
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

    return join( ';',
        "dbi:FirebirdEmbedded:db=" . $self->get_path,
        "ib_dialect=3",
        'ib_charset=' . $self->get_charset );
}

sub check_dsn {
    return shift->get_dsn;
}

sub get_path {
    my $self = shift;

    return File::Spec->catfile( $self->{firebird_lock_dir},
        'dbd-firebird-test.fdb' );
}

# no authentication for embedded
sub get_user { undef }
sub get_pass { undef }
sub get_host { undef }

sub check_mark {
    my $self = shift;

    # mimic first run if the test database is not present
    -f $self->get_path;
}

sub cleanup {
    my $self = shift;

    remove_tree( $self->{firebird_lock_dir}, { verbose => 1, safe => 1 } );

    return $self->SUPER::cleanup;
}

1;
