use strict;
use warnings;

use Test::More;

use lib 't','.';

use TestFirebird;

my $T = TestFirebird->new;

plan tests => 2;

my( $dbh, $error ) = $T->connect_to_database;
ok(!$error, "Connected to database") or diag($error);

my $is_embedded = ( ref($T) eq 'TestFirebirdEmbedded' );

is( $dbh->{ib_embedded}, $is_embedded,
    'ib_embedded is true only for FirebirdEmbedded' );
