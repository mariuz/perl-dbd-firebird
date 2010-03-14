use strict;

package DBD::InterBase::TableInfo::Firebird21;

use DBD::InterBase::TableInfo::Basic;
use vars qw(@ISA);
@ISA = qw(DBD::InterBase::TableInfo::Basic);

my %FbTableTypes = (
    'SYSTEM TABLE' => '((rdb$system_flag = 1) AND rdb$view_blr IS NULL)',
     'SYSTEM VIEW' => '((rdb$system_flag = 1) AND rdb$view_blr IS NOT NULL)',
           'TABLE' => '((rdb$system_flag = 0 OR rdb$system_flag IS NULL) AND rdb$view_blr IS NULL)',
            'VIEW' => '((rdb$system_flag = 0 OR rdb$system_flag IS NULL) AND rdb$view_blr IS NOT NULL)',
'GLOBAL TEMPORARY' => '((rdb$system_flag = 0 OR rdb$system_flag IS NULL) AND rdb$relation_type IN (4, 5))',
);

sub supported_types {
    sort keys %FbTableTypes;
}

sub list_tables {
    my ($self, $dbh, $table, @types) = @_;
    my (@conditions, @bindvars);
    my $where = '';

    if (defined($table) and length($table)) {
        push @conditions, ($table =~ /[_%]/
                           ? 'TRIM(rdb$relation_name) LIKE ?'
                           : 'rdb$relation_name = ?');
        push @bindvars, $table;
    }

    if (@types) {
        push @conditions, join ' OR ' => map { $FbTableTypes{$_} || '(1=0)' } @types;
    }

    if (@conditions) {
        $where = 'WHERE ' . join(' AND ' => map { "($_)" } @conditions);
    }

    # "The Firebird System Tables Exposed"
    # Martijn Tonies, 6th Worldwide Firebird Conference 2008
    # Bergamo, Italy
    my $sth = $dbh->prepare(<<__eosql);
  SELECT CAST(NULL AS CHAR(1))    AS TABLE_CAT,
         CAST(NULL AS CHAR(1))    AS TABLE_SCHEM,
         TRIM(rdb\$relation_name) AS TABLE_NAME,
         CAST(CASE
                WHEN rdb\$system_flag > 0 THEN
                     CASE WHEN rdb\$view_blr IS NULL THEN 'SYSTEM TABLE'
                                                     ELSE 'SYSTEM VIEW'
                     END
                WHEN rdb\$relation_type IN (4, 5)    THEN 'GLOBAL TEMPORARY'
                WHEN rdb\$view_blr IS NULL           THEN 'TABLE'
                                                     ELSE 'VIEW'
              END AS CHAR(16))                     AS TABLE_TYPE,
         TRIM(rdb\$description)  AS REMARKS,
         TRIM(rdb\$owner_name)   AS ib_owner_name,
         CASE rdb\$relation_type
           WHEN 0 THEN 'Persistent'
           WHEN 1 THEN 'View'
           WHEN 2 THEN 'External'
           WHEN 3 THEN 'Virtual'
           WHEN 4 THEN 'Global Temporary Preserve'
           WHEN 5 THEN 'Global Temporary Delete'
           ELSE        NULL
         END                      AS ib_relation_type
    FROM rdb\$relations
    $where
__eosql

    if ($sth) {
        $sth->{ChopBlanks} = 1;
        $sth->execute(@bindvars) or return undef;
    }
    $sth;
}

1;
__END__
sub fb15_table_info {
  SELECT NULL                     AS TABLE_CAT,
         NULL                     AS TABLE_SCHEM,
         TRIM(rdb\$relation_name) AS TABLE_NAME,
         CASE
           WHEN rdb\$system_flag > 0 THEN 'SYSTEM TABLE'
           WHEN rdb\$view_blr IS NOT NULL THEN 'VIEW'
           ELSE 'TABLE'
         END                      AS TABLE_TYPE,
         rdb\$description         AS REMARKS,
         rdb\$owner_name          AS ib_owner_name,
         rdb\$external_file       AS ib_external_file
    FROM rdb\$relations
}
# vim:set et ts=4:
