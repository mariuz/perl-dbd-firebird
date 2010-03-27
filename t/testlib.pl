#! /usr/bin/env perl

use Test::More;

# testlib.pl
# Consolidation of code for DBD::InterBase's Test::More tests...

my $file;
do {
    if (-f ($file = "t/InterBase.dbtest") ||
        -f ($file = "InterBase.dbtest"))
    {
        eval { require $file };
        BAIL_OUT("Cannot load $file: $@\n") if $@;
    }
};

my $lower_bound = 'TESTAA';
my $upper_bound = 'TESTZZ';

sub find_new_table {
    my $dbh = shift;
    my $try_name = 'TESTAA';
    my $try_name_quoted = $dbh->quote_identifier($try_name);

    my %tables = map { uc($_) => undef } $dbh->tables;

    while (exists $tables{$dbh->quote_identifier($try_name)}) {
        if (++$try_name gt 'TESTZZ') {
            diag("Too many test tables cluttering database ($try_name)\n");
            exit 255;
        }
    }

    $try_name;
}

__END__
# vim: set et ts=4:
