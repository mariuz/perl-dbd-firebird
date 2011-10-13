
# RT#55841 high-scale numbers incorrectly formatted

use strict;
use warnings;

use Test::More;
use DBI;

use lib 't','.';

use TestFirebird;
my $T = TestFirebird->new;

my ( $dbh, $error_str ) = $T->connect_to_database( { ChopBlanks => 1 } );

if ($error_str) {
    BAIL_OUT("Unknown: $error_str!");
}

unless ( $dbh->isa('DBI::db') ) {
    plan skip_all => 'Connection to database failed, cannot continue testing';
}
else {
    plan tests => 52;
}

ok($dbh, 'Connected to the database');

my @Types = qw|NUMERIC DECIMAL|;
my @Tests = (
#  Literal      Precision   Scale   Expected
   [ '-19.061',     18,       0,     -19     ], # XXX - we coerce Expected
   [ '-19.061',     18,       1,     -19.1   ], #       into a number
   [ '-19.061',     18,       2,     -19.06  ],
   [ '-19.061',     18,       3,     -19.061 ],
   [ '-19.061',     18,       4,     -19.061 ],
   [ '-19.061',     18,       5,     -19.061 ],
   [ '-19.061',     18,       6,     -19.061 ],
   [ '-19.061',     18,       7,     -19.061 ],
   [ '-19.061',     18,       8,     -19.061 ],
   [ '-19.061',     18,       9,     -19.061 ],
   [ '-19.061',     18,      10,     -19.061 ],
   [ '-19.061',     18,      11,     -19.061 ],
   [ '-19.061',     18,      12,     -19.061 ],
   [ '-19.061',     18,      13,     -19.061 ],
   [ '-19.061',     18,      14,     -19.061 ],
   [ '-19.061',     18,      15,     -19.061 ],
   [ '-19.061',     18,      16,     -19.061 ],
   [ '0.00001',     12,      11,     0.00001 ],
   [ '0.00001',     12,      10,     0.00001 ],
   [ '0.00001',     12,       9,     0.00001 ],
   [ '0.00001',     12,       8,     0.00001 ],
   [ '0.00001',     12,       7,     0.00001 ],
   [ '0.00001',     12,       6,     0.00001 ],
   [ '0.00001',     12,       5,     0.00001 ],
   [ '0.00001',     12,       4,           0 ],
);

# plan tests => (2 + (@Types * @Tests));

for my $type (@Types) {
    for (@Tests) {
        my ($literal, $prec, $scale, $expected) = @$_;
        my $cast = "CAST($literal AS $type($prec, $scale))";
        my ($r) = $dbh->selectrow_array("select $cast from RDB\$DATABASE");
        is(0+$r, $expected, "$cast");
    }
}

{
    my ($r) = $dbh->selectrow_array('select 0+1 from RDB$DATABASE');
    is($r, '1', "0+1"); # No decimal point on implicit zero-scale field
}

__END__
# vim: set et ts=4 ft=perl:
