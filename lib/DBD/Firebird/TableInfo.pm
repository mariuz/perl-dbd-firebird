use strict;

package DBD::Firebird::TableInfo;

sub factory {
    my (undef, $dbh) = @_;
    my ($vers, $klass);

    $vers = $dbh->func('version', 'ib_database_info')->{version};

    $dbh->trace_msg("TableInfo factory($dbh [$vers])");

    if ($vers =~ /firebird (\d\.\d+)/i and $1 >= 2.1) {
        $klass = 'DBD::Firebird::TableInfo::Firebird21';
    } else {
        $klass = 'DBD::Firebird::TableInfo::Basic';
    }

    eval "require $klass";
    if ($@) {
        $dbh->set_err(1, "DBD::Firebird::TableInfo factory: $@");
        return undef;
    }
    $klass->new() if $klass;
}

1;
