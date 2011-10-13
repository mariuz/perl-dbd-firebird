#!/usr/bin/perl -w
# test for https://rt.cpan.org/Ticket/Display.html?id=54561

use strict;
use warnings;

use Test::More;
use Test::Exception;
use DBI qw(:sql_types);
use lib 't','.';

use TestFirebird;
my $T = TestFirebird->new;

my ($dbh, $error_str) = $T->connect_to_database( { ChopBlanks => 1 } );

if ($error_str) {
    BAIL_OUT("Unknown: $error_str!");
}

unless ( $dbh->isa('DBI::db') ) {
    plan skip_all => 'Connection to database failed, cannot continue testing';
}
else {
    plan tests => 9;
}


ok($dbh);

my $table = find_new_table($dbh);

ok($dbh->do(<<"EOF"));
CREATE TABLE $table (
    ID INT NOT NULL PRIMARY KEY,
    CHARFIELD VARCHAR(100) NOT NULL
)
EOF

ok(my $sth = $dbh->prepare(<<"EOF"));
INSERT INTO $table (ID, CHARFIELD) VALUES (?, ?)
EOF

# the {} on the end is CRITICAL
ok($sth->bind_param_array(1, [qw/1   2   3  /]    ), 'bind_param_array');

lives_and { ok( $sth->bind_param_array( 2, [qw/Foo Bar Baz/], {} ) ) }
'bind_param_array works with attr';

is $sth->execute_array({}), 3, 'execute_array';

$sth = $dbh->prepare("SELECT * FROM $table");
$sth->execute;
is_deeply(
    $sth->fetchall_arrayref,
    [ [ 1, 'Foo' ], [ 2, 'Bar' ], [ 3, 'Baz' ] ],
    'bind_param_array data present'
);

ok($dbh->do("DROP TABLE $table"));
ok($dbh->disconnect);
