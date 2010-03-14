package DBD::InterBase::TableInfo::Basic;
use strict;

=pod

=head1 NAME

DBD::InterBase::TableInfo::Basic - A base class for lowest-common denominator Interbase table_info() querying.

=head1 SYNOPSIS

    # Add support for a hypothetical IB derivative
    package DBD::InterBase::TableInfo::HypotheticalIBDerivative

    @ISA = qw(DBD::InterBase::TableInfo::Basic);

    # What table types are supported?
    sub supported_types {
        ('SYSTEM TABLE', 'TABLE', 'VIEW', 'SPECIAL TABLE TYPE');
    }

    sub table_info {
        my ($self, $dbh, $table, @types) = @_;
    }

=head1 INTERFACE

=over 4

=item I<list_catalogs>

    $ti->list_catalogs($dbh);  # $dbh->table_info('%', '', '')

Returns a statement handle with an empty result set, as IB does not support
the DBI concept of catalogs. (Rule 19a)

=item I<list_schema>

    $ti->list_schema($dbh);    # $dbh->table_info('', '%', '')

Returns a statement handle with an empty result set, as IB does not support
the DBI concept of schema. (Rule 19b)

=item I<list_tables>

    $ti->list_tables($dbh, $table, @types); # $dbh->table_info('', '',
                                            #                  'FOO%',
                                            #                  'TABLE,VIEW');

Called in response to $dbh->table_info($cat, $schem, $table, $types).  C<$cat>
and C<$schem> are presently ignored.

This is the workhorse method that must return an appropriate statement handle
of tables given the requested C<$table> pattern and C<@types>.  A blank
C<$table> pattern means "any table," and an empty C<@types> list means "any
type."

C<@types> is a list of user-supplied, requested types.
C<DBD::InterBase::db::table_info> will normalize the user-supplied types,
stripping quote marks, uppercasing, and removing duplicates.

=item I<list_types>

    $tbl_info->list_types($dbh);  # $dbh->table_info('', '', '', '%')

Called in response to $dbh->table_info('', '', '', '%'), returning a
statement handle with a TABLE_TYPE column populated with the results of
I<supported_types>.  (Rule 19c)

Normally not overridden.  Override I<supported_types>, instead.

=item I<supported_types>

    $tbl_info->supported_types($dbh);

Returns a list of supported DBI TABLE_TYPE entries.  The default
implementation supports 'TABLE', 'SYSTEM TABLE' and 'VIEW'.

This method is called by the default implementation of C<list_types>.

=back

=cut

sub new { bless {}, shift; }

my %IbTableTypes = (
  'SYSTEM TABLE' => '((rdb$system_flag = 1) AND rdb$view_blr IS NULL)',
   'SYSTEM VIEW' => '((rdb$system_flag = 1) AND rdb$view_blr IS NOT NULL)',
         'TABLE' => '((rdb$system_flag = 0 OR rdb$system_flag IS NULL) AND rdb$view_blr IS NULL)',
          'VIEW' => '((rdb$system_flag = 0 OR rdb$system_flag IS NULL) AND rdb$view_blr IS NOT NULL)',
);

sub supported_types {
    sort keys %IbTableTypes;
}

sub sponge {
    # no warnings 'once';
    my ($self, $dbh, $stmt, $attrib_hash) = @_;
    my $sponge = DBI->connect('dbi:Sponge:', '', '')
                   or return $dbh->DBI::set_err($DBI::err, "DBI::Sponge: $DBI::errstr");
    return ($sponge->prepare($stmt, $attrib_hash)
            or
            $dbh->DBI::set_err($sponge->err(), $sponge->errstr()));
}

sub list_catalogs {
	my ($self, $dbh) = @_;
	return $self->sponge($dbh, 'catalog_info', {
            NAME => [qw(TABLE_CAT TABLE_SCHEM TABLE_NAME TABLE_TYPE REMARKS)],
            rows => [],
        });
}

sub list_schema {
	my ($self, $dbh) = @_;
	$self->sponge($dbh, 'schema_info', {
        NAME => [qw(TABLE_CAT TABLE_SCHEM TABLE_NAME TABLE_TYPE REMARKS)],
        rows => [],
    });
}

sub list_types {
    my ($self, $dbh) = @_;
    my @rows = map { [undef, undef, undef, $_, undef] } $self->supported_types;
    $self->sponge($dbh, 'supported_type_info', {
        NAME => [qw(TABLE_CAT TABLE_SCHEM TABLE_NAME TABLE_TYPE REMARKS)],
        rows => \@rows
    });
}

#
# Fetch a listing of tables matching the desired TABLE_NAME pattern
# and desired TABLE_TYPEs.  Do not presume support for CASE/END,
# COALESCE nor derived tables.
#
# We could put more work on the server than we do here.  However,
# rdb$relation_name is very likely to be space padded, and we cannot
# presume a TRIM() function.  So, $dbh->table_info('', '', 'F%T')
# cannot be implemented as "rdb$relation_name LIKE 'F%T'", since, in
# strict SQL, the padded string 'FOOT   ' is NOT LIKE 'F%T'.
#
sub list_tables { my ($self, $dbh, $name_pattern, @types) = @_; my
    ($name_ok, $type_ok); my @data;

    # no warnings 'uninitialized'
    if ($name_pattern eq '%' or $name_pattern eq '') {
        $name_ok = sub {1};
    } else {
        my $re = quotemeta($name_pattern);
        for ($re) { s/_/./g; s/%/.*/g; }
        $name_ok = sub { $_[0] =~ /$re/ };
    }

    if (@types) {
        my %desired = map { $_ => 1 } grep { exists $IbTableTypes{$_} } @types;
        $type_ok = sub { exists $desired{$_[0]} };
    } else {
        $type_ok = sub { 1 };
    }

    my $sth = $dbh->prepare(<<'__eosql');
SELECT v.rdb$relation_name      AS TABLE_NAME,
       CAST('VIEW' AS CHAR(5))  AS TABLE_TYPE,
       v.rdb$description        AS REMARKS,
       v.rdb$owner_name         AS ib_owner_name,
       v.rdb$system_flag        AS flag_sys
FROM   rdb$relations v
WHERE  v.rdb$view_blr IS NOT NULL
UNION ALL
SELECT t.rdb$relation_name      AS TABLE_NAME,
       CAST('TABLE' AS CHAR(5)) AS TABLE_TYPE,
       t.rdb$description        AS REMARKS,
       t.rdb$owner_name         AS ib_owner_name,
       t.rdb$system_flag        AS flag_sys
FROM   rdb$relations t
WHERE  t.rdb$view_blr IS NULL
__eosql

    if ($sth) {
        $sth->{ChopBlanks} = 1;
        $sth->execute or return undef;
    }

    while (my $r = $sth->fetch) {
        my ($name, $type, $remarks, $owner, $flag_sys) = @$r;
        $type = "SYSTEM $type" if $flag_sys;

        next unless $name_ok->($name);
        next unless $type_ok->($type);

        push @data, [undef, undef, $name, $type, $remarks, $owner];
    }

	return $self->sponge($dbh, 'table_info', {
        NAME => [qw(TABLE_CAT TABLE_SCHEM TABLE_NAME TABLE_TYPE REMARKS ib_owner_name)],
        rows => \@data
    });
}

1;
__END__
# vim:set et ts=4:
