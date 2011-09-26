#
#   Copyright (c) 2011  Marius Popa <mapopa@gmail.com>
#   Copyright (c) 2011  Damyan Ivanov <dmn@debian.org>
#   Copyright (c) 1999-2008 Edwin Pratomo
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file

require 5.008_001;

package DBD::Firebird;
use strict;
use Carp;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK $AUTOLOAD);
use DBI 1.41 ();
require Exporter;
require DynaLoader;

@ISA = qw(Exporter DynaLoader);
$VERSION = '0.70';

bootstrap DBD::Firebird $VERSION;

use vars qw($VERSION $err $errstr $drh);

$err = 0;
$errstr = "";
$drh = undef;


sub CLONE
{
    $drh = undef;
}


sub driver
{
    return $drh if $drh;
    my($class, $attr) = @_;

    $class .= "::dr";

    $drh = DBI::_new_drh($class, {'Name' => 'Firebird',
                                  'Version' => $VERSION,
                                  'Err'    => \$DBD::Firebird::err,
                                  'Errstr' => \$DBD::Firebird::errstr,
                                  'Attribution' => 'DBD::Firebird by Edwin Pratomo and Daniel Ritz'});
    $drh;
}

# taken from JWIED's DBD::mysql, with slight modification
sub _OdbcParse($$$) 
{
    my($class, $dsn, $hash, $args) = @_;
    my($var, $val);

    if (!defined($dsn))
       { return; }

    while (length($dsn)) 
    {
        if ($dsn =~ /([^;]*)[;]\r?\n?(.*)/s) 
        {
            $val = $1;
            $dsn = $2;
        } 
        else 
        {
            $val = $dsn;
            $dsn = '';
        }
        if ($val =~ /([^=]*)=(.*)/) 
        {
            $var = $1;
            $val = $2;
            if ($var eq 'hostname') 
                { $hash->{'host'} = $val; } 
            elsif ($var eq 'db'  ||  $var eq 'dbname') 
                { $hash->{'database'} = $val; } 
            else 
                { $hash->{$var} = $val; }
        } 
        else 
        {
            foreach $var (@$args) 
            {
                if (!defined($hash->{$var})) 
                {
                    $hash->{$var} = $val;
                    last;
                }
            }
        }
    }
    $hash->{host} = "$hash->{host}/$hash->{port}" if ($hash->{host} && $hash->{port});
    $hash->{database} = "$hash->{host}:$hash->{database}" if $hash->{host};
}


package DBD::Firebird::dr;

sub connect 
{
    my($drh, $dsn, $dbuser, $dbpasswd, $attr) = @_;

    $dbuser   ||= $ENV{ISC_USER};       #"SYSDBA";
    $dbpasswd ||= $ENV{ISC_PASSWORD};   #"masterkey";

    my ($this, $private_attr_hash);

    $private_attr_hash = {
        'Name' => $dsn,
        'user' => $dbuser,
        'password' => $dbpasswd
    };

    DBD::Firebird->_OdbcParse($dsn, $private_attr_hash,
                               ['database', 'host', 'port', 'ib_role', 'ib_dbkey_scope',
                                'ib_charset', 'ib_dialect', 'ib_cache', 'ib_lc_time']);
    $private_attr_hash->{database} ||= $ENV{ISC_DATABASE}; #"employee.fdb"

    # second attr args will be retrieved using DBIc_IMP_DATA
    my $dbh = DBI::_new_dbh($drh, {}, $private_attr_hash);

    DBD::Firebird::db::_login($dbh, $dsn, $dbuser, $dbpasswd, $attr) 
        or return undef;

    $dbh;
}

package DBD::Firebird::db;
use strict;
use Carp;

sub do 
{
    my($dbh, $statement, $attr, @params) = @_;
    my $rows;
    if (@params) 
    {
        my $sth = $dbh->prepare($statement, $attr) or return undef;
        defined($sth->execute(@params)) or return undef;
        $rows = $sth->rows;
    } 
    else 
    {
        $rows = DBD::Firebird::db::_do($dbh, $statement, $attr);
        return undef unless defined($rows);
    }
    ($rows == 0) ? "0E0" : $rows;
}

sub prepare 
{
    my ($dbh, $statement, $attribs) = @_;
    
    my $sth = DBI::_new_sth($dbh, {'Statement' => $statement });
    DBD::Firebird::st::_prepare($sth, $statement, $attribs)
        or return undef;
    $sth;
}

sub primary_key_info
{
    my ($dbh, undef, undef, $tbl) = @_;

    my $sth = $dbh->prepare(<<'__eosql');
    SELECT CAST(NULL AS CHAR(1))       AS TABLE_CAT,
           CAST(NULL AS CHAR(1))       AS TABLE_SCHEM,
           rc.rdb$relation_name        AS TABLE_NAME,
           ix.rdb$field_name           AS COLUMN_NAME,
           ix.rdb$field_position + 1   AS KEY_SEQ,
           rc.rdb$index_name           AS PK_NAME
      FROM rdb$relation_constraints rc
           INNER JOIN
           rdb$index_segments ix
             ON rc.rdb$index_name = ix.rdb$index_name
     WHERE rc.rdb$relation_name = ?
           AND
           rc.rdb$constraint_type = 'PRIMARY KEY'
  ORDER BY 1, 2, 3, 5
__eosql

    if ($sth) {
        $sth->{ChopBlanks} = 1;
        return unless $sth->execute($tbl);
    }

    $sth;
}

sub table_info
{
    my ($self, $cat, $schem, $name, $type, $attr) = @_;

    require DBD::Firebird::TableInfo;

    my $ti = ($self->{private_table_info}
               ||=
              DBD::Firebird::TableInfo->factory($self));

    no warnings 'uninitialized';
    if ($cat eq '%' and $schem eq '' and $name eq '') {
        return $ti->list_catalogs($self);
    } elsif ($cat eq '' and $schem eq '%' and $name eq '') {
        return $ti->list_schema($self);
    } elsif ($cat eq '' and $schem eq '' and $name eq '' and $type eq '%') {
        return $ti->list_types($self);
    } else {
        my %seen;
        $type = '' if $type eq '%';

        # normalize $type specifiers:  upcase, strip quote and uniqify
        my @types = grep { length and not $seen{$_}++ }
                        map { s/'//g; s/^\s+//; s/\s+$//; uc }
                            split(',' => $type);
        return $ti->list_tables($self, $name, @types);
    }
}

sub ping
{
    my($dbh) = @_;

    local $SIG{__WARN__} = sub { } if $dbh->{PrintError};
    local $dbh->{RaiseError} = 0 if $dbh->{RaiseError};
    my $ret = DBD::Firebird::db::_ping($dbh);

    return $ret;
}

# The get_info function was automatically generated by
# DBI::DBD::Metadata::write_getinfo_pm v1.05.

sub get_info {
    my($dbh, $info_type) = @_;
    require DBD::Firebird::GetInfo;
    my $v = $DBD::Firebird::GetInfo::info{int($info_type)};
    $v = $v->($dbh) if ref $v eq 'CODE';
    return $v;
}

# The type_info_all function was automatically generated by
# DBI::DBD::Metadata::write_typeinfo_pm v1.05.

sub type_info_all
{
    my ($dbh) = @_;
    require DBD::Firebird::TypeInfo;
    return [ @$DBD::Firebird::TypeInfo::type_info_all ];
}

1;

__END__

=head1 NAME

DBD::Firebird - DBI driver for Firebird RDBMS server

=head1 SYNOPSIS

  use DBI;

  $dbh = DBI->connect("dbi:Firebird:db=$dbname", $user, $password);

  # See the DBI module documentation for full details

=head1 DESCRIPTION

DBD::Firebird is a Perl module which works with the DBI module to provide
access to Firebird databases.

=head1 MODULE DOCUMENTATION

This documentation describes driver specific behavior and restrictions. 
It is not supposed to be used as the only reference for the user. In any 
case consult the DBI documentation first !

=head1 THE DBI CLASS

=head2 DBI Class Methods

=over 4

=item B<connect>

To connect to a database with a minimum of parameters, use the 
following syntax: 

  $dbh = DBI->connect("dbi:Firebird:dbname=$dbname", $user, $password);

If omitted, C<$user> defaults to the ISC_USER environment variable
(or, failing that, the DBI-standard DBI_USER environment variable).
Similarly, C<$password> defaults to ISC_PASSWORD (or DBI_PASS).  If
C<$dbname> is blank, that is, I<"dbi:Firebird:dbname=">, the
environment variable ISC_DATABASE is substituted.

The DSN may take several optional parameters, which may be split
over multiple lines.  Here is an example of connect statement which
uses all possible parameters: 

   $dsn =<< "DSN";
 dbi:Firebird:dbname=$dbname;
 host=$host;
 port=$port;
 ib_dialect=$dialect;
 ib_role=$role;
 ib_charset=$charset;
 ib_cache=$cache
 DSN

 $dbh =  DBI->connect($dsn, $username, $password);

The C<$dsn> is prefixed by 'dbi:Firebird:', and consists of key-value
parameters separated by B<semicolons>. New line may be added after the
semicolon. The following is the list of valid parameters and their
respective meanings:

    parameter       meaning                                 optional?
    -----------------------------------------------------------------
    database        path to the database                    required
    dbname          path to the database
    db              path to the database
    hostname        hostname / IP address                   optional
    host            hostname / IP address
    port            port number                             optional
    ib_dialect      the SQL dialect to be used              optional
    ib_role         the role of the user                    optional
    ib_charset      character set to be used                optional
    ib_cache        number of database cache buffers        optional
    ib_dbkey_scope  change default duration of RDB$DB_KEY   optional

B<database> could be used interchangebly with B<dbname> and B<db>. 
To connect to a remote host, use the B<host> parameter. 
Here is an example of DSN to connect to a remote Windows host:

 $dsn = "dbi:Firebird:db=C:/temp/test.gdb;host=example.com;ib_dialect=3";

Database file alias can be used too in connection string. In the following 
example, "billing" is defined in aliases.conf:

 $dsn = 'dbi:Firebird:hostname=192.168.88.5;db=billing;ib_dialect=3';

Firebird as of version 1.0 listens on port specified within the services
file. To connect to port other than the default 3050, add the port number at
the end of host name, separated by a slash. Example:

 $dsn = 'dbi:Firebird:db=/data/test.gdb;host=localhost/3060';

Firebird 1.0 introduces B<SQL dialect> to provide backward compatibility with
databases created by older versions of Firebird (pre 1.0). In short, SQL dialect
controls how Firebird interprets:

 - double quotes
 - the DATE datatype
 - decimal and numeric datatypes
 - new 1.0 reserved keywords

Valid values for B<ib_dialect> are 1 and 3 .The driver's default value is
3 (Currently it is possible to create databases in Dialect 1 and 3 only, however it is recommended that you use Dialect 3 exclusively, since Dialect 1 will eventually be deprecated. Dialect 2 cannot be used to create a database since it only serves to convert Dialect 1 to Dialect 3).

http://www.firebirdsql.org/file/documentation/reference_manuals/user_manuals/html/isql-dialects.html 

B<ib_role> specifies the role of the connecting user. B<SQL role> is
implemented by Firebird to make database administration easier when dealing
with lots of users. A detailed reading can be found at:

 http://www.ibphoenix.com/resources/documents/general/doc_59

If B<ib_cache> is not specified, the default database's cache size value will be 
used. The Firebird Operation Guide discusses in full length the importance of 
this parameter to gain the best performance.

=item B<available_drivers>

  @driver_names = DBI->available_drivers;

Implemented by DBI, no driver-specific impact.

=item B<data_sources>

This method is not yet implemented.

=item B<trace>

  DBI->trace($trace_level, $trace_file)

Implemented by DBI, no driver-specific impact.

=back


=head2 DBI Dynamic Attributes

See Common Methods. 

=head1 METHODS COMMON TO ALL DBI HANDLES

=over 4

=item B<err>

  $rv = $h->err;

Supported by the driver as proposed by DBI. 

=item B<errstr>

  $str = $h->errstr;

Supported by the driver as proposed by DBI. 

=item B<state>

This method is not yet implemented.

=item B<trace>

  $h->trace($trace_level, $trace_filename);

Implemented by DBI, no driver-specific impact.

=item B<trace_msg>

  $h->trace_msg($message_text);

Implemented by DBI, no driver-specific impact.

=item B<func>

See B<Transactions> section for information about invoking C<ib_set_tx_param()>
from func() method.

=back

=head1 ATTRIBUTES COMMON TO ALL DBI HANDLES

=over 4

=item B<Warn> (boolean, inherited)

Implemented by DBI, no driver-specific impact.

=item B<Active> (boolean, read-only)

Supported by the driver as proposed by DBI. A database 
handle is active while it is connected and  statement 
handle is active until it is finished. 

=item B<Kids> (integer, read-only)

Implemented by DBI, no driver-specific impact.

=item B<ActiveKids> (integer, read-only)

Implemented by DBI, no driver-specific impact.

=item B<CachedKids> (hash ref)

Implemented by DBI, no driver-specific impact.

=item B<CompatMode> (boolean, inherited)

Not used by this driver. 

=item B<InactiveDestroy> (boolean)

Implemented by DBI, no driver-specific impact.

=item B<PrintError> (boolean, inherited)

Implemented by DBI, no driver-specific impact.

=item B<RaiseError> (boolean, inherited)

Implemented by DBI, no driver-specific impact.

=item B<ChopBlanks> (boolean, inherited)

Supported by the driver as proposed by DBI. 

=item B<LongReadLen> (integer, inherited)

Supported by the driver as proposed by DBI.The default value is 80 bytes. 

=item B<LongTruncOk> (boolean, inherited)

Supported by the driver as proposed by DBI.

=item B<Taint> (boolean, inherited)

Implemented by DBI, no driver-specific impact.

=back

=head1 DATABASE HANDLE OBJECTS

=head2 Database Handle Methods

=over 4

=item B<selectrow_array>

  @row_ary = $dbh->selectrow_array($statement, \%attr, @bind_values);

Implemented by DBI, no driver-specific impact.

=item B<selectall_arrayref>

  $ary_ref = $dbh->selectall_arrayref($statement, \%attr, @bind_values);

Implemented by DBI, no driver-specific impact.

=item B<selectcol_arrayref>

  $ary_ref = $dbh->selectcol_arrayref($statement, \%attr, @bind_values);

Implemented by DBI, no driver-specific impact.

=item B<prepare>

  $sth = $dbh->prepare($statement, \%attr);

Supported by the driver as proposed by DBI.
When AutoCommit is On, this method implicitly starts a new transaction,
which will be automatically committed after the following execute() or the
last fetch(), depending on the statement type. For select statements,
commit automatically takes place after the last fetch(), or by explicitly 
calling finish() method if there are any rows remaining. For non-select
statements, execute() will implicitly commits the transaction. 

=item B<prepare_cached>

  $sth = $dbh->prepare_cached($statement, \%attr);

Implemented by DBI, no driver-specific impact. 

=item B<do>

  $rv  = $dbh->do($statement, \%attr, @bind_values);

Supported by the driver as proposed by DBI.
This should be used for non-select statements, where the driver doesn't take
the conservative prepare - execute steps, thereby speeding up the execution
time. But if this method is used with bind values, the speed advantage
diminishes as this method calls prepare() for binding the placeholders.
Instead of calling this method repeatedly with bind values, it would be
better to call prepare() once, and execute() many times.

See the notes for the execute method elsewhere in this document. Unlike the
execute method, currently this method doesn't return the number of affected
rows. 

=item B<commit>

  $rc  = $dbh->commit;

Supported by the driver as proposed by DBI. See also the 
notes about B<Transactions> elsewhere in this document. 

=item B<rollback>

  $rc  = $dbh->rollback;

Supported by the driver as proposed by DBI. See also the 
notes about B<Transactions> elsewhere in this document. 

=item B<disconnect>

  $rc  = $dbh->disconnect;

Supported by the driver as proposed by DBI. 

=item B<ping>

  $rc = $dbh->ping;

This driver supports the ping-method, which can be used to check the 
validity of a database-handle. This is especially required by
C<Apache::DBI>.

=item B<primary_key_info>

  $sth = $dbh->primary_key_info('', '', $table_name);
  @pks = $dbh->primary_key('', '', $table_name);

Supported by the driver as proposed by DBI.  Note that catalog and schema
are ignored.

=item B<table_info>

  $sth = $dbh->table_info;

All Firebird versions support the basic DBI-specified columns
(TABLE_NAME, TABLE_TYPE, etc.) as well as C<IB_TABLE_OWNER>.  Peculiar
versions may return additional fields, prefixed by C<IB_>.

Table searching may not work as expected on older Interbase/Firebird engines
which do not natively offer a TRIM() function.  Some engines store TABLE_NAME
in a blank-padded CHAR field, and a search for table name is performed via a
SQL C<LIKE> predicate, which is sensitive to blanks.  That is:

  $dbh->table_info('', '', 'FOO');  # May not find table "FOO", depending on
                                    # FB version
  $dbh->table_info('', '', 'FOO%'); # Will always find "FOO", but also tables
                                    # "FOOD", "FOOT", etc.

Future versions of DBD::Firebird may attempt to work around this irritating
limitation, at the expense of efficiency.

Note that Firebird implementations do not presently support the DBI
concepts of 'catalog' and 'schema', so these parameters are effectively
ignored.

=item B<tables>

  @names = $dbh->tables;

Returns a list of tables, excluding any 'SYSTEM TABLE' types.

=item B<type_info_all>

  $type_info_all = $dbh->type_info_all;

Supported by the driver as proposed by DBI. 

For further details concerning the Firebird specific data-types 
please read the Firebird Data Definition Guide 

http://www.firebirdsql.org/en/reference-manuals/ 

=item B<type_info>

  @type_info = $dbh->type_info($data_type);

Implemented by DBI, no driver-specific impact. 

=item B<quote>

  $sql = $dbh->quote($value, $data_type);

Implemented by DBI, no driver-specific impact. 

=back

=head2 Database Handle Attributes

=over 4

=item B<AutoCommit>  (boolean)

Supported by the driver as proposed by DBI. According to the 
classification of DBI, Firebird is a database, in which a 
transaction must be explicitly started. Without starting a 
transaction, every change to the database becomes immediately 
permanent. The default of AutoCommit is on, which corresponds 
to the DBI's default. When setting AutoCommit to off, a transaction 
will be started and every commit or rollback 
will automatically start a new transaction. For details see the 
notes about B<Transactions> elsewhere in this document. 

=item B<Driver>  (handle)

Implemented by DBI, no driver-specific impact. 

=item B<Name>  (string, read-only)

Not yet implemented.

=item B<RowCacheSize>  (integer)

Implemented by DBI, not used by the driver.

=item B<ib_softcommit>  (driver-specific, boolean)

Set this attribute to TRUE to use Firebird's soft commit feature (default
to FALSE). Soft commit retains the internal transaction handle when
committing a transaction, while the default commit behavior always closes
and invalidates the transaction handle.

Since the transaction handle is still open, there is no need to start a new transaction 
upon every commit, so applications can gain performance improvement. Using soft commit is also 
desirable when dealing with nested statement handles under AutoCommit on. 

Switching the attribute's value from TRUE to FALSE will force hard commit thus 
closing the current transaction. 

=item B<ib_enable_utf8>  (driver-specific, boolean)

Setting this attribute to TRUE will cause any Perl Unicode strings supplied as
statement parameters to be downgraded to octet sequences before passing them to
Firebird.

Also, any character data retrieved from the database (CHAR, VARCHAR, BLOB
sub_type TEXT) will be upgraded to Perl Unicode strings.

B<Caveat>: Currently this is supported only if the B<ib_charset> DSN parameter
is C<UTF8>. In the future, encoding and decoding to/from arbitrary character
set may be implemented.

Example:

    $dbh = DBI->connect( 'dbi:Firebird:db=database.fdb;ib_charset=UTF8',
        { ib_enable_utf8 => 1 } );

=back

=head1 STATEMENT HANDLE OBJECTS

=head2 Statement Handle Methods

=over 4

=item B<bind_param>

Supported by the driver as proposed by DBI. 
The SQL data type passed as the third argument is ignored. 

=item B<bind_param_inout>

Not supported by this driver. 

=item B<execute>

  $rv = $sth->execute(@bind_values);

Supported by the driver as proposed by DBI. 

=item B<fetchrow_arrayref>

  $ary_ref = $sth->fetchrow_arrayref;

Supported by the driver as proposed by DBI. 

=item B<fetchrow_array>

  @ary = $sth->fetchrow_array;

Supported by the driver as proposed by DBI. 

=item B<fetchrow_hashref>

  $hash_ref = $sth->fetchrow_hashref;

Supported by the driver as proposed by DBI. 

=item B<fetchall_arrayref>

  $tbl_ary_ref = $sth->fetchall_arrayref;

Implemented by DBI, no driver-specific impact. 

=item B<finish>

  $rc = $sth->finish;

Supported by the driver as proposed by DBI. 

=item B<rows>

  $rv = $sth->rows;

Supported by the driver as proposed by DBI. 
It returns the number of B<fetched> rows for select statements, otherwise
it returns -1 (unknown number of affected rows).

=item B<bind_col>

  $rc = $sth->bind_col($column_number, \$var_to_bind, \%attr);

Supported by the driver as proposed by DBI. 

=item B<bind_columns>

  $rc = $sth->bind_columns(\%attr, @list_of_refs_to_vars_to_bind);

Supported by the driver as proposed by DBI. 

=item B<dump_results>

  $rows = $sth->dump_results($maxlen, $lsep, $fsep, $fh);

Implemented by DBI, no driver-specific impact. 

=back

=head2 Statement Handle Attributes

=over 4

=item B<NUM_OF_FIELDS>  (integer, read-only)

Implemented by DBI, no driver-specific impact. 

=item B<NUM_OF_PARAMS>  (integer, read-only)

Implemented by DBI, no driver-specific impact. 

=item B<NAME>  (array-ref, read-only)

Supported by the driver as proposed by DBI. 

=item B<NAME_lc>  (array-ref, read-only)

Implemented by DBI, no driver-specific impact. 

=item B<NAME_uc>  (array-ref, read-only)

Implemented by DBI, no driver-specific impact. 

=item B<TYPE>  (array-ref, read-only)

Supported by the driver as proposed by DBI, with 
the restriction, that the types are Firebird
specific data-types which do not correspond to 
international standards.

=item B<PRECISION>  (array-ref, read-only)

Supported by the driver as proposed by DBI. 

=item B<SCALE>  (array-ref, read-only)

Supported by the driver as proposed by DBI. 

=item B<NULLABLE>  (array-ref, read-only)

Supported by the driver as proposed by DBI. 

=item B<CursorName>  (string, read-only)

Supported by the driver as proposed by DBI. 

=item B<Statement>  (string, read-only)

Supported by the driver as proposed by DBI. 

=item B<RowCache>  (integer, read-only)

Not supported by the driver. 

=back

=head1 TRANSACTION SUPPORT

The transaction behavior is controlled with the attribute AutoCommit. 
For a complete definition of AutoCommit please refer to the DBI documentation. 

According to the DBI specification the default for AutoCommit is TRUE. 
In this mode, any change to the database becomes valid immediately. Any 
commit() or rollback() will be rejected. 

If AutoCommit is switched-off, immediately a transaction will be started.
A rollback() will rollback and close the active transaction, then implicitly 
start a new transaction. A disconnect will issue a rollback. 

Firebird provides fine control over transaction behavior, where users can
specify the access mode, the isolation level, the lock resolution, and the 
table reservation (for a specified table). For this purpose,
C<ib_set_tx_param()> database handle method is available. 

Upon a successful C<connect()>, these default parameter values will be used
for every SQL operation:

    Access mode:        read_write
    Isolation level:    snapshot
    Lock resolution:    wait

Any of the above value can be changed using C<ib_set_tx_param()>.

=over 4

=item B<ib_set_tx_param> 

 $dbh->func( 
    -access_mode     => 'read_write',
    -isolation_level => 'read_committed',
    -lock_resolution => 'wait',
    'ib_set_tx_param'
 );

Valid value for C<-access_mode> is C<read_write>, or C<read_only>. 

Valid value for C<-lock_resolution> is C<wait>, or C<no_wait>. 
In Firebird 2.0, a timeout value for wait is introduced. This can be 
specified using hash ref as lock_resolution value:

 $dbh->func(
    -lock_resolution => { wait => 5 }, # wait for 5 seconds
    'ib_set_tx_param'
 );

C<-isolation_level> may be: C<read_committed>, C<snapshot>,
C<snapshot_table_stability>. 

If C<read_committed> is to be used with C<record_version> or
C<no_record_version>, then they should be inside an anonymous array:

 $dbh->func( 
    -isolation_level => ['read_committed', 'record_version'],
    'ib_set_tx_param'
 );

Table reservation is supported since C<DBD::Firebird 0.30>. Names of the
tables to reserve as well as their reservation params/values are specified
inside a hashref, which is then passed as the value of C<-reserving>.

The following example reserves C<foo_table> with C<read> lock and C<bar_table> 
with C<read> lock and C<protected> access:

 $dbh->func(
    -access_mode     => 'read_write',
    -isolation_level => 'read_committed',
    -lock_resolution => 'wait',
    -reserving       =>
        {
            foo_table => {
                lock    => 'read',
            },
            bar_table => {
                lock    => 'read',
                access  => 'protected',
            },
        },
    'ib_set_tx_param'
 );

Possible table reservation parameters are:

=over 4

=item C<access> (optional)

Valid values are C<shared> or C<protected>.

=item C<lock> (required)

Valid values are C<read> or C<write>.

=back

Under C<AutoCommit> mode, invoking this method doesn't only change the
transaction parameters (as with C<AutoCommit> off), but also commits the
current transaction. The new transaction parameters will be used in
any newly started transaction. 

C<ib_set_tx_param()> can also be invoked with no parameter in which it resets
transaction parameters to the default value.

=back

=head1 DATE, TIME, and TIMESTAMP FORMATTING SUPPORT

C<DBD::Firebird> supports various formats for query results of DATE, TIME,
and TIMESTAMP types. 

By default, it uses "%c" for TIMESTAMP, "%x" for DATE, and "%X" for TIME,
and pass them to ANSI C's strftime() function to format your query results.
These values are respectively stored in ib_timestampformat, ib_dateformat,
and ib_timeformat attributes, and may be changed in two ways:

=over 

=item * At $dbh level

This replaces the default values. Example:

 $dbh->{ib_timestampformat} = '%m-%d-%Y %H:%M';
 $dbh->{ib_dateformat} = '%m-%d-%Y';
 $dbh->{ib_timeformat} = '%H:%M';

=item * At $sth level

This overrides the default values only for the currently prepared statement. Example:

 $attr = {
    ib_timestampformat => '%m-%d-%Y %H:%M',
    ib_dateformat => '%m-%d-%Y',
    ib_timeformat => '%H:%M',
 };
 # then, pass it to prepare() method. 
 $sth = $dbh->prepare($sql, $attr);

=back

Since locale settings affect the result of strftime(), if your application
is designed to be portable across different locales, you may consider using these
two special formats: 'TM' and 'ISO'. C<TM> returns a 9-element list, much like
Perl's localtime(). The C<ISO> format applies sprintf()'s pattern
"%04d-%02d-%02d %02d:%02d:%02d.%04d" for TIMESTAMP, "%04d-%02d-%02d" for
DATE, and "%02d:%02d:%02d.%04d" for TIME. 

C<$dbh-E<gt>{ib_time_all}> can be used to specify all of the three formats at
once. Example:

 $dbh->{ib_time_all} = 'TM';


=head1 EVENT ALERT SUPPORT

Event alerter is used to notify client applications whenever something is
happened on the database. For this to work, a trigger should be created,
which then calls POST_EVENT to post the event notification to the interested
client. A client could behave in two ways: wait for the event synchronously,
or register a callback which will be invoked asynchronously each time a
posted event received.

=over

=item C<ib_init_event>

 $evh = $dbh->func(@event_names, 'ib_init_event');

Creates an event handle from a list of event names. 

=item C<ib_wait_event>

 $dbh->func($evh, 'ib_wait_event');

Wait synchronously for particular events registered via event handle $evh.
Returns a hashref containing pair(s) of posted event's name and its corresponding count,
or undef on failure.

=item C<ib_register_callback>

 my $cb = sub { my $posted_events = $_[0]; ++$::COUNT < 6 };
 $dbh->func($evh, $cb, 'ib_register_callback');

 sub inc_count { my $posted_events = shift; ++$::COUNT < 6 };
 $dbh->func($evh, \&inc_count, 'ib_register_callback');

 # or anonyomus subroutine
 $dbh->func(
   $evh, 
   sub { my ($pe) = @_; ++$::COUNT < 6 }, 
   'ib_register_callback'
 );

Associates an event handle with an asynchronous callback. A callback will be
passed a hashref as its argument, this hashref contains pair(s) of posted event's name
and its corresponding count. 

It is safe to call C<ib_register_callback> multiple times for the same event handle. In this 
case, the previously registered callback will be automatically cancelled.

If the callback returns FALSE, the registered callback will be no longer invoked, but internally
it is still there until the event handle goes out of scope (or undef-ed), or you call 
C<ib_cancel_callback> to actually disassociate it from the event handle.

=item C<ib_cancel_callback>

 $dbh->func($evh, 'ib_cancel_callback');

Unregister a callback from an event handle. This function has a limitation,
however, that it can't be called from inside a callback. In many cases, you won't
need this function, since when an event handle goes out of scope, its associated callback(s)
will be automatically cancelled before it is cleaned up. 


=back

=head1 RETRIEVING FIREBIRD / INTERBASE SPECIFIC INFORMATION

=over

=item C<ib_tx_info>

 $hash_ref = $dbh->func('ib_tx_info');

Retrieve information about current active transaction.

=item C<ib_database_info>

 $hash_ref = $dbh->func(@info, 'ib_database_info');
 $hash_ref = $dbh->func([@info], 'ib_database_info');

Retrieve database information from current connection. 

=item C<ib_plan>

 $plan = $sth->func('ib_plan');

Retrieve query plan from a prepared SQL statement. 

 my $sth = $dbh->prepare('SELECT * FROM foo');
 print $sth->func('ib_plan'); # PLAN (FOO NATURAL)

=back


=head1 UNSUPPORTED SQL STATEMENTS

Here is a list of SQL statements which can't be used. But this shouldn't be a 
problem, because their functionality are already provided by the DBI methods.

=over 4

=item * SET TRANSACTION

Use C<$dbh->func(..., 'set_tx_param')> instead.

=item * DESCRIBE

Provides information about columns that are retrieved by a DSQL statement,
or about placeholders in a statement. This functionality is supported by the
driver, and transparent for users. Column names are available via
$sth->{NAME} attributes.

=item * EXECUTE IMMEDIATE

Calling do() method without bind value(s) will do the same.

=item * CLOSE, OPEN, DECLARE CURSOR

$sth->{CursorName} is automagically available upon executing a "SELECT .. FOR
UPDATE" statement. A cursor is closed after the last fetch(), or by calling
$sth->finish(). 

=item * PREPARE, EXECUTE, FETCH

Similar functionalities are obtained by using prepare(), execute(), and 
fetch() methods.

=back

=head1 COMPATIBILITY WITH DBIx::* MODULES 

C<DBD::Firebird> is known to work with C<DBIx::Recordset> 0.21, and
C<Apache::DBI> 0.87. Yuri Vasiliev <I<yuri.vasiliev@targuscom.com>> reported 
successful usage with Apache::AuthDBI (part of C<Apache::DBI> 0.87 
distribution).

The driver is untested with C<Apache::Session::DBI>. Doesn't work with 
C<Tie::DBI>. C<Tie::DBI> calls $dbh->prepare("LISTFIELDS $table_name") on 
which Firebird fails to parse. I think that the call should be made within 
an eval block.

=head1 FAQ

=head2 Why do some operations performing positioned update and delete fail when AutoCommit is on? 

For example, the following code snippet fails:

 $sth = $dbh->prepare(
 "SELECT * FROM ORDERS WHERE user_id < 5 FOR UPDATE OF comment");
 $sth->execute;
 while (@res = $sth->fetchrow_array) {
     $dbh->do("UPDATE ORDERS SET comment = 'Wonderful' WHERE 
     CURRENT OF $sth->{CursorName}");
 }

When B<AutoCommit is on>, a transaction is started within prepare(), and
committed automatically after the last fetch(), or within finish(). Within
do(), a transaction is started right before the statement is executed, and
gets committed right after the statement is executed. The transaction handle
is stored within the database handle. The driver is smart enough not to
override an active transaction handle with a new one. So, if you notice the
snippet above, after the first fetchrow_array(), the do() is still using the
same transaction context, but as soon as it has finished executing the statement, it
B<commits> the transaction, whereas the next fetchrow_array() still needs
the transaction context!

So the secret to make this work is B<to keep the transaction open>. This can be
done in two ways:

=over 4

=item * Using AutoCommit = 0

If yours is default to AutoCommit on, you can put the snippet within a block:

 {
     $dbh->{AutoCommit} = 0;
     # same actions like above ....
     $dbh->commit;
 }

=item * Using $dbh->{ib_softcommit} = 1

This driver-specific attribute is available as of version 0.30. You may want
to look at t/40cursoron.t to see it in action.

=back

=head2 Why do nested statement handles break under AutoCommit mode?

The same explanation as above applies. The workaround is also
much alike:

 {
     $dbh->{AutoCommit} = 0;
     $sth1 = $dbh->prepare("SELECT * FROM $table");
     $sth2 = $dbh->prepare("SELECT * FROM $table WHERE id = ?");
     $sth1->execute;

     while ($row = $sth1->fetchrow_arrayref) {
        $sth2->execute($row->[0]);
        $res = $sth2->fetchall_arrayref;
     }
     $dbh->commit;
 }

You may also use $dbh->{ib_softcommit} introduced in version 0.30, please check
t/70nested-sth.t for an example on how to use it.

=head2 Why do placeholders fail to bind, generating unknown datatype error message?

You can't bind a field name. The following example will fail:

 $sth = $dbh->prepare("SELECT (?) FROM $table");
 $sth->execute('user_id');

There are cases where placeholders can't be used in conjunction with COLLATE
clause, such as this:

 SELECT * FROM $table WHERE UPPER(author) LIKE UPPER(? COLLATE FR_CA);

This deals with the Firebird's SQL parser, not with C<DBD::Firebird>. The
driver just passes SQL statements through the engine.


=head2 How to do automatic increment for a specific field?

Create a sequence and a trigger to associate it with the field. The
following example creates a sequence named PROD_ID_SEQ, and a trigger for
table ORDERS which uses the generator to perform auto increment on field
PRODUCE_ID with increment size of 1.

 $dbh->do("create sequence PROD_ID_SEQ");
 $dbh->do(
 "CREATE TRIGGER INC_PROD_ID FOR ORDERS
 BEFORE INSERT POSITION 0
 AS BEGIN
   NEW.PRODUCE_ID = NEXT VALUE FOR PROD_ID_SEQ;
 END");

From Firebird 3.0 there is Identity support 

=head2 How can I perform LIMIT clause as I usually do in MySQL?

C<LIMIT> clause let users to fetch only a portion rather than the whole 
records as the result of a query. This is particularly efficient and useful 
for paging feature on web pages, where users can navigate back and forth 
between pages. 

Using Firebird 2.5.x this can be implemented by using C<ROWS> .

 http://www.firebirdsql.org/refdocs/langrefupd21-select.html#langrefupd21-select-rows

For example, to display a portion of table employee within your application:

 # fetch record 1 - 5:
 $res = $dbh->selectall_arrayref("SELECT * FROM employee rows 1 to 5)");

 # fetch record 6 - 10: 
 $res = $dbh->selectall_arrayref("SELECT * FROM employee rows 6 to 10)");

=head2 How can I use the date/time formatting attributes?

Those attributes take the same format as the C function strftime()'s.
Examples:

 $attr = {
    ib_timestampformat => '%m-%d-%Y %H:%M',
    ib_dateformat => '%m-%d-%Y',
    ib_timeformat => '%H:%M',
 };

Then, pass it to prepare() method. 

 $sth = $dbh->prepare($stmt, $attr);
 # followed by execute() and fetch(), or:

 $res = $dbh->selectall_arrayref($stmt, $attr);


=head2 Can I set the date/time formatting attributes between prepare and fetch?

No. C<ib_dateformat>, C<ib_timeformat>, and C<ib_timestampformat> can only
be set during $sth->prepare. If this is a problem to you, let me know, and
probably I'll add this capability for the next release.


=head2 Can I change ib_dialect after DBI->connect ?

No. If this is a problem to you, let me know, and probably I'll add this 
capability for the next release.


=head1 OBSOLETE FEATURES

=over 

=item Private Method

C<set_tx_param()> is obsoleted by C<ib_set_tx_param()>.

=back

=head1 TESTED PLATFORMS

=head2 Clients

=over 4

=item Linux

=item FreeBSD

=item SPARC Solaris

=item Win32

=back

=head2 Servers

=over 4

=item Firebird 2.5.x SS , SC and Classic for Linux (32 bits and 64)

=item Firebird 2.5.x for Windows, FreeBSD, SPARC Solaris

=back

=head1 AUTHORS

=over 4

=item * DBI by Tim Bunce <Tim.Bunce@pobox.com>

=item * DBD::Firebird by Edwin Pratomo <edpratomo@cpan.org> and Daniel Ritz 
<daniel.ritz@gmx.ch>.

This module is originally based on the work of Bill Karwin's IBPerl.

=back

=head1 BUGS/LIMITATIONS

Please report bugs and feature suggestions using 
http://rt.cpan.org/Public/Dist/Display.html?Name=DBD-Firebird .

This module doesn't work with MSWin32 ActivePerl iThreads, and its emulated
fork. Tested with MSWin32 ActivePerl build 809 (Perl 5.8.3). The whole
process will block in unpredictable manner.

Under Linux, this module has been tested with several different iThreads
enabled Perl releases: perl-5.8.0-88 from RedHat 9, perl-5.8.5-9 from Fedora
Core 3, perl-5.8.6-15 from Fedora Core 4, and Perl 5.8.[78]. 

No problem occurred so far.. until you try to share a DBI handle ;-)

But if you plan to use thread, you'd better use the latest stable version of
Perl, 5.8.8 has fairly stable iThreads.

Limitations:

=over 4

=item * Arrays are not (yet) supported

=item * Read/Write BLOB fields block by block not (yet) supported. The
maximum size of a BLOB read/write is hardcoded to about 1 MB.

=item * service manager API is not supported.

=back

=head1 SEE ALSO

DBI(3).

=head1 COPYRIGHT & LICENSE

=over

=item Copyright (c) 2010, 2011  Popa Adrian Marius <mapopa@gmail.com>

=item Copyright (c) 2011  Stefan Suciu <stefbv70@gmail.com>

=item Copyright (c) 2011  Damyan Ivanov <dmn@debian.org>

=item Copyright (c) 2011  Alexandr Ciornii <alexchorny@gmail.com>

=item Copyright (c) 2010, 2011  pilcrow <mjp@pilcrow.madison.wi.us>

=item Copyright (c) 1999-2008  Edwin Pratomo

=item Portions Copyright (c) 2001-2005  Daniel Ritz

=back

The DBD::Firebird module is free software. 
You may distribute under the terms of either the GNU General Public
License or the Artistic License, as specified in the Perl README file.

=head1 ACKNOWLEDGEMENTS

An attempt to enumerate all who have contributed patches (may misses some):
Michael Moehle, Igor Klingen, Sergey Skvortsov, Ilya Verlinsky, Pavel
Zheltouhov, Peter Wilkinson, Mark D. Anderson, Michael Samanov, Michael
Arnett, Flemming Frandsen, Mike Shoyher, Christiaan Lademann.


=cut
