/* vim: set noai ts=4 et sw=4: */
/*
   $Id: dbdimp.c 395 2008-01-08 05:33:11Z edpratomo $

   Copyright (c) 1999-2008  Edwin Pratomo
   Portions Copyright (c) 2001-2005  Daniel Ritz

   You may distribute under the terms of either the GNU General Public
   License or the Artistic License, as specified in the Perl README file,
   with the exception that it cannot be placed on a CD-ROM or similar media
   for commercial distribution without the prior approval of the author.

*/

#include "InterBase.h"

DBISTATE_DECLARE;

#define IB_SQLtimeformat(xxh, format, sv)                             \
do {                                                                  \
    STRLEN len;                                                       \
    char *frmt = NULL;                                                \
    char *buf = SvPV(sv, len);                                        \
    if (len < 2 || len > 30)  break;                                  \
    Newx(frmt, len + 1, char);                                        \
    strcpy(frmt, buf);                                                \
    if (format) Safefree(format);                                     \
    format = frmt;                                                    \
} while (0)

#define IB_alloc_sqlda(sqlda, n)                             \
do {                                                         \
    short len = n;                                           \
    if (sqlda)                                               \
    {                                                        \
        Safefree(sqlda);                                     \
        sqlda = NULL;                                        \
    }                                                        \
    Newxz(sqlda, XSQLDA_LENGTH(len), char);                  \
    sqlda->sqln = len;                                       \
    sqlda->version = SQLDA_OK_VERSION;                       \
} while (0)


int create_cursor_name(SV *sth, imp_sth_t *imp_sth)
{
    ISC_STATUS status[ISC_STATUS_LENGTH];

    Newxz(imp_sth->cursor_name, 22, char);
    sprintf(imp_sth->cursor_name, "perl%016.16x", imp_sth->stmt);
    isc_dsql_set_cursor_name(status, &(imp_sth->stmt), imp_sth->cursor_name, 0);
    if (ib_error_check(sth, status))
        return FALSE;
    else
        return TRUE;
}


void dbd_init(dbistate_t *dbistate)
{
    DBISTATE_INIT;
}


void ib_cleanup_st_prepare (imp_sth_t *imp_sth)
{
    FREE_SETNULL(imp_sth->in_sqlda);
    FREE_SETNULL(imp_sth->out_sqlda);
    FREE_SETNULL(imp_sth->dateformat);
#ifdef IB_API_V6
    FREE_SETNULL(imp_sth->timeformat);
    FREE_SETNULL(imp_sth->timestampformat);
#endif
}


void ib_cleanup_st_execute (imp_sth_t *imp_sth)
{
    if (imp_sth->in_sqlda)
    {
        int i;
        XSQLVAR *var = imp_sth->in_sqlda->sqlvar;

        for (i = 0; i < imp_sth->in_sqlda->sqln; i++, var++)
        {
            Safefree(var->sqldata);
            var->sqldata = NULL;
            if (var->sqlind)
                *(var->sqlind) = -1;    /* isNULL */
        }
    }
}


/* lower level error handling */
void do_error(SV *h, int rc, char *what)
{
    D_imp_xxh(h);
    SV *errstr = DBIc_ERRSTR(imp_xxh);

    sv_setiv(DBIc_ERR(imp_xxh), (IV)rc);
    sv_setpv(errstr, what);

    if (DBIc_TRACE_LEVEL(imp_xxh) >= 2)
        PerlIO_printf(DBIc_LOGPIO(imp_xxh), "%s error %d recorded: %s\n", 
            what, rc, SvPV(errstr,na));
}

#define CALC_AVAILABLE(buff) sizeof(buff) - strlen(buff) - 1

/* higher level error handling, check and decode status */
int ib_error_check(SV *h, ISC_STATUS *status)
{
    if (status[0] == 1 && status[1] > 0)
    {
        long sqlcode;
        unsigned int avail = 0;
#if !defined(FB_API_VER) || FB_API_VER < 20
        ISC_STATUS *pvector = status;
#else
        const ISC_STATUS *pvector = status;
#endif
#if defined (INCLUDE_TYPES_PUB_H) 
        ISC_SCHAR msg[1024], *pmsg;
#else
        char msg[1024], *pmsg;
#endif
        Zero(msg, sizeof(msg), char);
        pmsg = msg;

        if ((sqlcode = isc_sqlcode(status)) != 0)
        {
            isc_sql_interprete((short) sqlcode, pmsg, sizeof(msg));
            avail = CALC_AVAILABLE(msg);
            if (avail > 1) {
                while (*pmsg) pmsg++;
                *pmsg++ = '\n';
                *pmsg++ = '-';
                avail = CALC_AVAILABLE(msg);
            }
        }

#if !defined(FB_API_VER) || FB_API_VER < 20
        while (isc_interprete(pmsg, &pvector))
#else
        while (avail > 0 && fb_interpret(pmsg, avail, &pvector))
#endif
        {
            avail = CALC_AVAILABLE(msg);
            if (avail > 1) {
                while (*pmsg) pmsg++;
                *pmsg++ = '\n';
                *pmsg++ = '-';
                avail = CALC_AVAILABLE(msg);
            }
        }
        *--pmsg = '\0';

        do_error(h, sqlcode, msg);
        return FAILURE;
    }
    else return SUCCESS;
}


static int ib2sql_type(int ibtype)
{
    /* InterBase Internal (not external) types */
    switch(ibtype)
    {
        case SQL_TEXT:
        case 453:
            return DBI_SQL_CHAR;

        case SQL_LONG:
        case 497:
            return DBI_SQL_INTEGER;  /* integer */

        case SQL_SHORT:
        case 501:
            return DBI_SQL_SMALLINT; /* smallint */

        case SQL_FLOAT:
        case 483:
            return DBI_SQL_FLOAT;

        case SQL_DOUBLE:
        case 481:
            return DBI_SQL_DOUBLE;

#ifndef IB_API_V6
        case SQL_DATE:
        case 511:
            return DBI_SQL_TIMESTAMP; /* this is correct! */
#else /* V6.0/FB */
        case SQL_TIMESTAMP:
        case 511:
            return DBI_SQL_TIMESTAMP;

        case SQL_TYPE_DATE:
        case 571:
            return DBI_SQL_DATE;

        case SQL_TYPE_TIME:
        case 561:
            return DBI_SQL_TIME;
#endif /* !IB_API_V6 */

        case SQL_VARYING:
        case 449:
            return DBI_SQL_VARCHAR;
    }
    /* else map type into DBI reserved standard range */
    return -9000 - ibtype;
}

#if 0
/* from DBI (ANSI/ISO/ODBC) types to InterBase types */
static int ib_sql_type(imp_sth_t *imp_sth, char *name, int sql_type)
{
    /* XXX should detect DBI reserved standard type range here */
    switch (sql_type) {
    case DBI_SQL_NUMERIC:
    case DBI_SQL_DECIMAL:
    case DBI_SQL_INTEGER:
    case DBI_SQL_BIGINT:
    case DBI_SQL_TINYINT:
    case DBI_SQL_SMALLINT:
    case DBI_SQL_FLOAT:
    case DBI_SQL_REAL:
    case DBI_SQL_DOUBLE:
        return 481;
    case DBI_SQL_VARCHAR:
        return 449;
    case DBI_SQL_CHAR:
        return 453;

    case SQL_DATE:
    case SQL_TIME:
    case SQL_TIMESTAMP:
    default:
    if (DBIc_WARN(imp_sth) && imp_sth && name)
        warn("SQL type %d for '%s' is not fully supported, bound as SQL_VARCHAR instead");
    return ib_sql_type(imp_sth, name, DBI_SQL_VARCHAR);
    }
}
#endif

int dbd_db_login6(SV *dbh, imp_dbh_t *imp_dbh, char *dbname, char *uid,
                  char *pwd, SV *attr)
{
    dTHR;

    ISC_STATUS status[ISC_STATUS_LENGTH];

    HV *hv;
    SV *sv;
    SV **svp;  /* versatile scalar storage */

    unsigned short ib_dialect, ib_cache;
    char *ib_charset, *ib_role;
    char ISC_FAR *dpb_buffer, *dpb;

    char ISC_FAR *database;

    STRLEN len; /* for SvPV */

    char  dbkey_scope   = 0;
    short dpb_length    = 0;
    unsigned int buflen = 0;   /* buffer size is dynamic */
    imp_dbh->db         = 0L;
    imp_dbh->tr         = 0L;
    imp_dbh->tpb_buffer = NULL;
    imp_dbh->tpb_length = 0;
    imp_dbh->sth_ddl    = 0;

    imp_dbh->soft_commit = 0; /* use soft commit (isc_commit_retaining)? */

    /* default date/time formats
       +     *
     * Old API:  dateformat ........ %c
     *           timeformat ........ (none)
     *           timestampformat ... (none)
     *
     * v6 API:   dateformat ........ %x
     *           timeformat ........ %X
     *           timestampformat ... %c
     */
    Newxz(imp_dbh->dateformat, 3, char);
#ifndef IB_API_V6
    strcpy(imp_dbh->dateformat, "%c");
#else
    strcpy(imp_dbh->dateformat, "%x");

    Newxz(imp_dbh->timeformat, 3, char);
    strcpy(imp_dbh->timeformat, "%X");

    Newxz(imp_dbh->timestampformat, 3, char);
    strcpy(imp_dbh->timestampformat, "%c");
#endif

    /* linked list */
    imp_dbh->first_sth = NULL;
    imp_dbh->last_sth  = NULL;

    /* save the current context for thread/multiplicy safety */
#if defined(USE_THREADS) || defined(USE_ITHREADS) || defined(MULTIPLICITY)
    imp_dbh->context = PERL_GET_CONTEXT;
#endif

    /* Parse DSN and init values */
    sv = DBIc_IMP_DATA(imp_dbh);

    if (!sv || !SvROK(sv))
        return FALSE;

    hv = (HV*) SvRV(sv);
    if (SvTYPE(hv) != SVt_PVHV)
        return FALSE;

    if (uid != NULL) {
        buflen += strlen(uid) + 1;
        buflen += 2;
    }

    if (pwd != NULL) {
        buflen += strlen(pwd) + 1;
        buflen += 2;
    }

    /* does't go to DPB -> no buflen inc */
    if ((svp = hv_fetch(hv, "database", 8, FALSE)))
        database = SvPV(*svp, len);
    else database = NULL;


    /* role, cache, charset, sqldialect */

    if ((svp = hv_fetch(hv, "ib_dialect", 10, FALSE)))
        ib_dialect = (unsigned short) SvIV(*svp);
    else
        ib_dialect = DEFAULT_SQL_DIALECT;
    buflen += 5;


    if ((svp = hv_fetch(hv, "ib_cache", 8, FALSE)))
    {
        ib_cache = (unsigned short) SvIV(*svp);
        buflen += 5;
    }
    else
        ib_cache = 0;

    if ((svp = hv_fetch(hv, "ib_charset", 10, FALSE)))
    {
        ib_charset = SvPV(*svp, len);
        buflen += len + 2;
    }
    else
        ib_charset = NULL;

    if ((svp = hv_fetch(hv, "ib_role", 7, FALSE)))
    {
        ib_role = SvPV(*svp, len);
        buflen += len + 2;
    }
    else
        ib_role = NULL;

    if ((svp = hv_fetch(hv, "ib_dbkey_scope", 14, FALSE)))
    {
        dbkey_scope = (char)SvIV(*svp);
        if (dbkey_scope)
            buflen += 5;
    }

    /* add length of other parameters to needed buflen */
    buflen += 1; /* dbpversion */

    DBI_TRACE_imp_xxh(imp_dbh, 2, (DBIc_LOGPIO(imp_dbh), "dbd_db_login6\n"));

    /* Allocate DPB */
    Newx(dpb_buffer, buflen, char);

    /* Default SQL dialect for every statement  */
    imp_dbh->sqldialect = ib_dialect;

    /* Fill DPB */
    dpb = dpb_buffer;
    DPB_FILL_BYTE(dpb, isc_dpb_version1);

    DPB_FILL_BYTE(dpb, isc_dpb_user_name);
    DPB_FILL_STRING(dpb, uid);

    DPB_FILL_BYTE(dpb, isc_dpb_password);
    DPB_FILL_STRING(dpb, pwd);

    if (ib_cache)
    {
        /*
         * Safety check: Do not allocate a cache buffer greater than
         * 10000 pages, so we don't exhaust memory inadvertently.
         */
        if (ib_cache > 10000) ib_cache = 10000;
        DPB_FILL_BYTE(dpb, isc_dpb_num_buffers);
        DPB_FILL_INTEGER(dpb, ib_cache);
    }

#ifdef IB_API_V6
    DPB_FILL_BYTE(dpb, isc_dpb_sql_dialect);
    DPB_FILL_INTEGER(dpb, ib_dialect);
#endif

    if (dbkey_scope)
    {
        DPB_FILL_BYTE(dpb, isc_dpb_dbkey_scope);
        DPB_FILL_INTEGER(dpb, dbkey_scope);
    }

    if (ib_charset)
    {
        DPB_FILL_BYTE(dpb, isc_dpb_lc_ctype);
        DPB_FILL_STRING(dpb, ib_charset);
    }

    if (ib_role)
    {
        DPB_FILL_BYTE(dpb, isc_dpb_sql_role_name);
        DPB_FILL_STRING(dpb, ib_role);
    }

    dpb_length = dpb - dpb_buffer;

    DBI_TRACE_imp_xxh(imp_dbh, 3, (DBIc_LOGPIO(imp_dbh), "dbd_db_login6: attaching to database %s..\n", database));

    isc_attach_database(status,           /* status vector */
                        0,                /* connect string is null-terminated */
                        database,         /* connect string */
                        &(imp_dbh->db),   /* ref to db handle */
                        dpb_length,       /* length of dpb */
                        dpb_buffer);      /* connect options */

    /* freeing database parameter buffer */
    Safefree(dpb_buffer);

    /* return false on failed attach */
    if (ib_error_check(dbh, status))
        return FALSE;

    DBI_TRACE_imp_xxh(imp_dbh, 3, (DBIc_LOGPIO(imp_dbh), "dbd_db_login6: success attaching.\n"));

    /* Tell DBI, that dbh->destroy should be called for this handle */
    DBIc_IMPSET_on(imp_dbh);

    /* Tell DBI, that dbh->disconnect should be called for this handle */
    DBIc_ACTIVE_on(imp_dbh);

    return TRUE;
}


int dbd_db_login(SV *dbh, imp_dbh_t *imp_dbh, char *dbname, char  *uid,
                 char *pwd)
{
    return dbd_db_login6(dbh, imp_dbh, dbname, uid, pwd, Nullsv);
}


int dbd_db_ping(SV *dbh)
{
    D_imp_dbh(dbh);
    ISC_STATUS status[ISC_STATUS_LENGTH];

    char buffer[100];

    DBI_TRACE_imp_xxh(imp_dbh, 1, (DBIc_LOGPIO(imp_dbh), "dbd_db_ping\n"));

    if (isc_database_info(status, &(imp_dbh->db), 0, NULL, sizeof(buffer), buffer))
        if (ib_error_check(dbh, status))
            return FALSE;
    return TRUE;
}


int dbd_db_disconnect(SV *dbh, imp_dbh_t *imp_dbh)
{
    dTHR;
    ISC_STATUS status[ISC_STATUS_LENGTH];

    DBI_TRACE_imp_xxh(imp_dbh, 2, (DBIc_LOGPIO(imp_dbh), "dbd_db_disconnect\n"));

    /* set the database handle to inactive */
    DBIc_ACTIVE_off(imp_dbh);

    /* always do a rollback if there's an open transaction.
     * InterBase requires to close open transactions before
     * detaching a database.
     */
    if (imp_dbh->tr)
    {
        /* rollback and close trans context */
        isc_rollback_transaction(status, &(imp_dbh->tr));
        if (ib_error_check(dbh, status))
            return FALSE;

        imp_dbh->tr = 0L;
    }

    FREE_SETNULL(imp_dbh->tpb_buffer);
    FREE_SETNULL(imp_dbh->dateformat);
#ifdef IB_API_V6
    FREE_SETNULL(imp_dbh->timeformat);
    FREE_SETNULL(imp_dbh->timestampformat);
#endif

    /* detach database */
    isc_detach_database(status, &(imp_dbh->db));
    if (ib_error_check(dbh, status))
        return FALSE;

    return TRUE;
}


void dbd_db_destroy (SV *dbh, imp_dbh_t *imp_dbh)
{
    DBI_TRACE_imp_xxh(imp_dbh, 2, (DBIc_LOGPIO(imp_dbh), "dbd_db_destroy\n"));

    if (DBIc_ACTIVE(imp_dbh))
        dbd_db_disconnect(dbh, imp_dbh);

    /* Nothing in imp_dbh to be freed   */
    DBIc_IMPSET_off(imp_dbh);
}


int dbd_db_commit (SV *dbh, imp_dbh_t *imp_dbh)
{
    DBI_TRACE_imp_xxh(imp_dbh, 2, (DBIc_LOGPIO(imp_dbh), "dbd_db_commit\n"));

    /* no commit if AutoCommit on */
    if (DBIc_has(imp_dbh, DBIcf_AutoCommit))
        return FALSE;

    /* commit the transaction */
    if (!ib_commit_transaction(dbh, imp_dbh))
        return FALSE;

    DBI_TRACE_imp_xxh(imp_dbh, 3, (DBIc_LOGPIO(imp_dbh), "dbd_db_commit succeed.\n"));

    return TRUE;
}


int dbd_db_rollback(SV *dbh, imp_dbh_t *imp_dbh)
{
    DBI_TRACE_imp_xxh(imp_dbh, 2, (DBIc_LOGPIO(imp_dbh), "dbd_db_rollback\n"));

    /* no rollback if AutoCommit = on */
    if (DBIc_has(imp_dbh, DBIcf_AutoCommit) != FALSE)
        return FALSE;

    /* rollback the transaction */
    if (!ib_rollback_transaction(dbh, imp_dbh))
        return FALSE;

    DBI_TRACE_imp_xxh(imp_dbh, 3, (DBIc_LOGPIO(imp_dbh), "dbd_db_rollback succeed.\n"));

    return TRUE;
}


int dbd_db_STORE_attrib(SV *dbh, imp_dbh_t *imp_dbh, SV *keysv, SV *valuesv)
{
    STRLEN  kl;
    char *key   = SvPV(keysv, kl);
    int  on     = SvTRUE(valuesv)? 1: 0;
    int  oldval;
    int  set_frmts = 0;

    DBI_TRACE_imp_xxh(imp_dbh, 2, (DBIc_LOGPIO(imp_dbh), "dbd_db_STORE - %s\n", key));

    /**************************************************************************/
    if ((kl==10) && strEQ(key, "AutoCommit"))
    {
        oldval = DBIc_has(imp_dbh, DBIcf_AutoCommit)? 1: 0;
        DBIc_set(imp_dbh, DBIcf_AutoCommit, on);

        DBI_TRACE_imp_xxh(imp_dbh, 3, (DBIc_LOGPIO(imp_dbh), "dbd_db_STORE: switch AutoCommit from %d to %d\n", oldval, on));

        if (oldval == FALSE && on)
        {
            /* AutoCommit set from 0 to 1, commit any outstanding changes */
            if (imp_dbh->tr)
            {
                if (!ib_commit_transaction(dbh, imp_dbh))
                    return FALSE;

                    DBI_TRACE_imp_xxh(imp_dbh, 3, (DBIc_LOGPIO(imp_dbh), "dbd_db_STORE: commit open transaction\n"));
            }
        }

        return TRUE; /* handled */
    }
    /**************************************************************************/
    else if ((kl==13) && strEQ(key, "ib_softcommit"))
    {
        oldval = imp_dbh->soft_commit;

        DBI_TRACE_imp_xxh(imp_dbh, 3, (DBIc_LOGPIO(imp_dbh), "dbd_db_STORE: switch ib_softcommit from %d to %d\n", oldval, on));

        /* set new value */
        imp_dbh->soft_commit = on;

        /* switching softcommit from 1 to 0 -> make a hard commit */
        if (!on && oldval)
        {
            if (imp_dbh->tr)
            {
                if (!ib_commit_transaction(dbh, imp_dbh))
                    return FALSE;

                DBI_TRACE_imp_xxh(imp_dbh, 3, (DBIc_LOGPIO(imp_dbh), "dbd_db_STORE: commit open transaction\n"));
            }
        }
        return TRUE; /* handled */
    }
    else if ((kl==11) && strEQ(key, "ib_time_all"))
        set_frmts = 1;

    /**************************************************************************/
    if (set_frmts || ((kl==13) && strEQ(key, "ib_dateformat")))
    {
        IB_SQLtimeformat(dbh, imp_dbh->dateformat, valuesv);
        if (!set_frmts) return TRUE;
    }
#ifdef IB_API_V6
    if (set_frmts || ((kl==13) && strEQ(key, "ib_timeformat")))
    {
        IB_SQLtimeformat(dbh, imp_dbh->timeformat, valuesv);
        if (!set_frmts) return TRUE;
    }
    if (set_frmts || ((kl==18) && strEQ(key, "ib_timestampformat")))
    {
        IB_SQLtimeformat(dbh, imp_dbh->timestampformat, valuesv);
        if (!set_frmts) return TRUE;
    }
#endif
    /**************************************************************************/

    if (set_frmts) return TRUE;
    else return FALSE; /* not handled */
}


SV *dbd_db_FETCH_attrib(SV *dbh, imp_dbh_t *imp_dbh, SV *keysv)
{
    STRLEN  kl;
    char *  key = SvPV(keysv, kl);
    SV *    result = NULL;

    DBI_TRACE_imp_xxh(imp_dbh, 2, (DBIc_LOGPIO(imp_dbh), "dbd_db_FETCH - %s\n", key));

    if ((kl==10) && strEQ(key, "AutoCommit"))
        result = boolSV(DBIc_has(imp_dbh, DBIcf_AutoCommit));
    else if ((kl==13) && strEQ(key, "ib_softcommit"))
        result = boolSV(imp_dbh->soft_commit);
    else if ((kl==13) && strEQ(key, "ib_dateformat"))
        result = newSVpvn(imp_dbh->dateformat, strlen(imp_dbh->dateformat));
#ifdef IB_API_V6
    else if ((kl==13) && strEQ(key, "ib_timeformat"))
        result = newSVpvn(imp_dbh->timeformat, strlen(imp_dbh->timeformat));
    else if ((kl==18) && strEQ(key, "ib_timestampformat"))
        result = newSVpvn(imp_dbh->timestampformat,
                          strlen(imp_dbh->timestampformat));
#endif

    if (result == NULL)
        return Nullsv;
    else
    {
        if ((result == &sv_yes) || (result == &sv_no))
            return result;
        else
            return sv_2mortal(result);
    }
}


void dbd_preparse(SV *sth, imp_sth_t *imp_sth, char *statement)
{
    ISC_STATUS status[ISC_STATUS_LENGTH];

    DBI_TRACE_imp_xxh(imp_sth, 2, (DBIc_LOGPIO(imp_sth), "Enter dbd_preparse\n"));

    isc_dsql_describe_bind(status, &(imp_sth->stmt), 1, imp_sth->in_sqlda);

    if (ib_error_check(sth, status))
    {
        ib_cleanup_st_prepare(imp_sth);
        return;
    }

    /* realloc in_sqlda and rebind if not enough XSQLVAR for bind params */
    if (imp_sth->in_sqlda->sqld > imp_sth->in_sqlda->sqln)
    {
        IB_alloc_sqlda(imp_sth->in_sqlda, imp_sth->in_sqlda->sqld);
        if (imp_sth->in_sqlda == NULL)
        {
            do_error(sth, 1, "Fail to reallocate in_slqda");
            ib_cleanup_st_prepare(imp_sth);
            return;
        }
        else
        {
            isc_dsql_describe_bind(status, &(imp_sth->stmt), 1, imp_sth->in_sqlda);
            if (ib_error_check(sth, status))
            {
                ib_cleanup_st_prepare(imp_sth);
                return;
            }
        }
    }

    DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "dbd_preparse: describe_bind passed.\n"
                  "dbd_preparse: exit; in_sqlda: sqld: %d, sqln: %d.\n",
                      imp_sth->in_sqlda->sqld, imp_sth->in_sqlda->sqln));

    DBIc_NUM_PARAMS(imp_sth) = imp_sth->in_sqlda->sqld;
}


int dbd_st_prepare(SV *sth, imp_sth_t *imp_sth, char *statement, SV *attribs)
{
    D_imp_dbh_from_sth;
    ISC_STATUS  status[ISC_STATUS_LENGTH];
    int         i;
    short       dtype;
    static char stmt_info[1];
    char        info_buffer[20], count_item;
    XSQLVAR     *var;

    DBI_TRACE_imp_xxh(imp_sth, 2, (DBIc_LOGPIO(imp_sth), "Enter dbd_st_prepare\n"));

    if (!DBIc_ACTIVE(imp_dbh))
    {
        do_error(sth, -1, "Database disconnected");
        return FALSE;
    }

    /* init values */
    count_item = 0;

    imp_sth->count_item  = 0;
    imp_sth->fetched     = -1;
    imp_sth->in_sqlda    = NULL;
    imp_sth->out_sqlda   = NULL;
    imp_sth->cursor_name = NULL;

    imp_sth->dateformat      = NULL;
#ifdef IB_API_V6
    imp_sth->timestampformat = NULL;
    imp_sth->timeformat      = NULL;
#endif

    /* double linked list */
    imp_sth->prev_sth = NULL;
    imp_sth->next_sth = NULL;

    if (attribs)
    {
        SV **svp;

        if ((svp = DBD_ATTRIB_GET_SVP(attribs, "ib_time_all", 11)) != NULL)
        {
            IB_SQLtimeformat(sth, imp_sth->dateformat, *svp);
#ifdef IB_API_V6
            IB_SQLtimeformat(sth, imp_sth->timestampformat, *svp);
            IB_SQLtimeformat(sth, imp_sth->timeformat, *svp);
#endif
        }


        if ((svp = DBD_ATTRIB_GET_SVP(attribs, "ib_dateformat", 13)) != NULL)
            IB_SQLtimeformat(sth, imp_sth->dateformat, *svp);

#ifdef IB_API_V6
        if ((svp = DBD_ATTRIB_GET_SVP(attribs, "ib_timestampformat", 18)) != NULL)
            IB_SQLtimeformat(sth, imp_sth->timestampformat, *svp);

        if ((svp = DBD_ATTRIB_GET_SVP(attribs, "ib_timeformat", 13)) != NULL)
            IB_SQLtimeformat(sth, imp_sth->timeformat, *svp);
#endif
    }


    /* allocate 1 XSQLVAR to in_sqlda */
    IB_alloc_sqlda(imp_sth->in_sqlda, 1);
    if (imp_sth->in_sqlda == NULL)
    {
        do_error(sth, 2, "Fail to allocate in_sqlda");
        return FALSE;
    }

    /* allocate 1 XSQLVAR to out_sqlda */
    IB_alloc_sqlda(imp_sth->out_sqlda, 1);
    if (imp_sth->out_sqlda == NULL)
    {
        do_error(sth, 2, "Fail to allocate out_sqlda");
        ib_cleanup_st_prepare(imp_sth);
        return FALSE;
    }

    /* init statement handle */
    isc_dsql_alloc_statement2(status, &(imp_dbh->db), &(imp_sth->stmt));
    if (ib_error_check(sth, status))
    {
        ib_cleanup_st_prepare(imp_sth);
        return FALSE;
    }

    DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "dbd_st_prepare: sqldialect: %d.\n", imp_dbh->sqldialect));

    if (!imp_dbh->tr)
    {
        /* start a new transaction using current TPB */
        if (!ib_start_transaction(sth, imp_dbh))
        {
            ib_cleanup_st_prepare(imp_sth);
            return FALSE;
        }
    }

    DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "dbd_st_prepare: statement: %s.\n", statement));

    isc_dsql_prepare(status, &(imp_dbh->tr), &(imp_sth->stmt), 0, statement,
                     imp_dbh->sqldialect, imp_sth->out_sqlda);

    if (ib_error_check(sth, status))
    {
        ib_cleanup_st_prepare(imp_sth);
        return FALSE;
    }

    DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "dbd_st_prepare: isc_dsql_prepare succeed..\n"));

    stmt_info[0] = isc_info_sql_stmt_type;
    isc_dsql_sql_info(status, &(imp_sth->stmt), sizeof (stmt_info), stmt_info,
                      sizeof (info_buffer), info_buffer);

    if (ib_error_check(sth, status))
    {
        ib_cleanup_st_prepare(imp_sth);
        return FALSE;
    }

    {
        short l = (short) isc_vax_integer((char *) info_buffer + 1, 2);
        imp_sth->type = isc_vax_integer((char *) info_buffer + 3, l);
    }

    /* sanity check of statement type */
    DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "dbd_st_prepare: statement type: %ld.\n", imp_sth->type));

    switch (imp_sth->type)
    {
        /* Implemented statement types. */
        case isc_info_sql_stmt_select:
        case isc_info_sql_stmt_select_for_upd:
            /*
             * Unfortunately, select count item doesn't work
             * in current versions of InterBase.
             * isql does it literally by fetching everything
             * and counting the number of rows it fetched.
             * InterBase doesn't seem to be able to estimate
             * the number of rows before the client app
             * fetches them all.
             */
             //count_item = isc_info_req_select_count;
             break;

        case isc_info_sql_stmt_insert:
            count_item = isc_info_req_insert_count;
            break;

        case isc_info_sql_stmt_update:
            count_item = isc_info_req_update_count;
            break;

        case isc_info_sql_stmt_delete:
            count_item = isc_info_req_delete_count;
            break;

        case isc_info_sql_stmt_ddl:
        case isc_info_sql_stmt_exec_procedure:
            /* no count_item to gather */
            break;

        /*
         * Unimplemented statement types. Some may be implemented in the future.
         */
        case isc_info_sql_stmt_get_segment:
        case isc_info_sql_stmt_put_segment:
        case isc_info_sql_stmt_start_trans:
        case isc_info_sql_stmt_commit:
        case isc_info_sql_stmt_rollback:
        default:
            do_error(sth, 10, "Statement type is not implemented in this version of DBD::InterBase");
            return FALSE;
            break;
    }

    imp_sth->count_item = count_item;

    /* scan statement for '?', ':1' and/or ':foo' style placeholders    */
    /* realloc in_sqlda where needed */
    dbd_preparse(sth, imp_sth, statement);

    DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "dbd_st_prepare: dbd_describe passed.\n"
                            "out_sqlda: sqld: %d, sqln: %d.\n",
                            imp_sth->out_sqlda->sqld, imp_sth->out_sqlda->sqln));

    /* enough output parameter block ? */
    if (imp_sth->out_sqlda->sqld > imp_sth->out_sqlda->sqln)
    {
        DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "dbd_st_prepare: realloc out_sqlda..\n"));

        IB_alloc_sqlda(imp_sth->out_sqlda, imp_sth->out_sqlda->sqld);

        if (imp_sth->out_sqlda == NULL)
        {
            do_error(sth, IB_ALLOC_FAIL, "Fail to reallocate out_sqlda");
            ib_cleanup_st_prepare(imp_sth);
            return FALSE;
        }
        else
        {
            DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "dbd_st_prepare: calling isc_dsql_describe again..\n"));

            isc_dsql_describe(status, &(imp_sth->stmt), 1, imp_sth->out_sqlda);
            if (ib_error_check(sth, status))
            {
                ib_cleanup_st_prepare(imp_sth);
                return FALSE;
            }

            DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "dbd_st_prepare: success calling isc_dsql_describe.\n"));
        }
    }
    else if (imp_sth->out_sqlda->sqld == 0) /* not a select statement */
    {
        Safefree(imp_sth->out_sqlda);
        imp_sth->out_sqlda = NULL;
    }

    if (imp_sth->out_sqlda)
    {
        for (i = 0, var = imp_sth->out_sqlda->sqlvar;
             i < imp_sth->out_sqlda->sqld;
             i++, var++)
        {
            dtype = (var->sqltype & ~1);
            var->sqlind = NULL;

            DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "dbd_st_prepare: field type: %d.\n", dtype));

            /* Alloc space for sqldata */
            Newx(var->sqldata,
                 var->sqllen + (dtype == SQL_VARYING ? sizeof(short) : 0),
                 ISC_SCHAR);

            /* Nullable? */
            if (var->sqltype & 1)
                Newx(var->sqlind, 1, short);
        }
    }


    /* statment is valid -> insert into linked list (at begin) */
    imp_sth->next_sth = imp_dbh->first_sth;

    if (imp_dbh->first_sth == NULL)
        imp_dbh->last_sth = imp_sth;
    else
        imp_dbh->first_sth->prev_sth = imp_sth;

    imp_dbh->first_sth = imp_sth;

    DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "dbd_st_prepare: sth inserted into linked list.\n"));

    /* tell DBI that we have a real statement handle now */
    DBIc_IMPSET_on(imp_sth);
    return TRUE;
}


int dbd_st_execute(SV *sth, imp_sth_t *imp_sth)
{
    D_imp_dbh_from_sth;
    ISC_STATUS status[ISC_STATUS_LENGTH];
    int        result = -2;
    int        row_count = 0;

    DBI_TRACE_imp_xxh(imp_sth, 2, (DBIc_LOGPIO(imp_sth), "dbd_st_execute\n"));

    /* if not already done: start new transaction */
    if (!imp_dbh->tr)
        if (!ib_start_transaction(sth, imp_dbh))
            return result;

    DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "dbd_st_execute: statement type: %ld.\n", imp_sth->type));

    /* we count DDL statments */
    if (imp_sth->type == isc_info_sql_stmt_ddl)
        imp_dbh->sth_ddl++;


    /* exec procedure statement */
    if (imp_sth->type == isc_info_sql_stmt_exec_procedure)
    {
        DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "dbd_st_execute: calling isc_dsql_execute2 (exec procedure)..\n"));

        isc_dsql_execute2(status, &(imp_dbh->tr), &(imp_sth->stmt),
                          imp_dbh->sqldialect,
                          (imp_sth->in_sqlda && (imp_sth->in_sqlda->sqld > 0))?
                           imp_sth->in_sqlda: NULL,
                          (imp_sth->out_sqlda && (imp_sth->out_sqlda->sqld > 0))?
                           imp_sth->out_sqlda: NULL);

        if (ib_error_check(sth, status))
        {
            ib_cleanup_st_execute(imp_sth);
            return result;
        }

        DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "dbd_st_execute: isc_dsql_execute2 succeed.\n"));

        imp_sth->fetched = 0;
    }
    else /* all other types of SQL statements */
    {
        DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "dbd_st_execute: calling isc_dsql_execute..\n"));

        /* check for valid in_sqlda */
        if (!imp_sth->in_sqlda)
            return FALSE;

        isc_dsql_execute(status, &(imp_dbh->tr), &(imp_sth->stmt),
                         imp_dbh->sqldialect,
                         imp_sth->in_sqlda->sqld > 0 ? imp_sth->in_sqlda: NULL);

        if (ib_error_check(sth, status))
        {
            ib_cleanup_st_execute(imp_sth);

            /* rollback any active transaction */
            if (DBIc_has(imp_dbh, DBIcf_AutoCommit) && imp_dbh->tr)
                ib_commit_transaction(sth, imp_dbh);

            return result;
        }

        DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "dbd_st_execute: isc_dsql_execute succeed.\n"));
    }

    /* Jika AutoCommit On, commit_transaction() (bukan retaining),
     * dan reset imp_dbh->tr == 0L
     * For SELECT statement, commit_transaction() is called after fetch,
     * or within finish()
     */
    if (DBIc_has(imp_dbh, DBIcf_AutoCommit)
        && imp_sth->type != isc_info_sql_stmt_select
        && imp_sth->type != isc_info_sql_stmt_select_for_upd
        && imp_sth->type != isc_info_sql_stmt_exec_procedure)
    {
        DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "dbd_st_execute: calling ib_commit_transaction..\n"));

        if (!ib_commit_transaction(sth, imp_dbh))
        {
            ib_cleanup_st_execute(imp_sth);
            return result;
        }

        DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "dbd_st_execute: ib_commit_transaction succeed.\n"));
    }

    /* Declare a unique cursor for this query */
    if (imp_sth->type == isc_info_sql_stmt_select_for_upd)
    {
        /* We free the cursor_name buffer in dbd_st_destroy. */
        if (!create_cursor_name(sth, imp_sth))
        {
            ib_cleanup_st_execute(imp_sth);
            return result;
        }
    }


    switch (imp_sth->type)
    {
        case isc_info_sql_stmt_select:
        case isc_info_sql_stmt_select_for_upd:
        case isc_info_sql_stmt_exec_procedure:
            DBIc_NUM_FIELDS(imp_sth) = (imp_sth->out_sqlda)?
                                        imp_sth->out_sqlda->sqld: 0;
            DBIc_ACTIVE_on(imp_sth);
            break;
    }

    if (imp_sth->count_item)
    {
        //PerlIO_printf(PerlIO_stderr(), "calculating row count\n");
        row_count = ib_rows(sth, &(imp_sth->stmt), imp_sth->count_item);
        if (row_count <= -2)
            ib_cleanup_st_execute(imp_sth);
        else
            result = row_count;
    } else 
        result = -1;

    DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "dbd_st_execute: row count: %d.\n"
                            "dbd_st_execute: count_item: %d.\n",
                            row_count, imp_sth->count_item));

    return result;
}


/* from out_sqlda to AV */
AV *dbd_st_fetch(SV *sth, imp_sth_t *imp_sth)
{
    D_imp_dbh_from_sth;     /* declare imp_dbh from sth */
    ISC_STATUS  fetch = 0;
    ISC_STATUS  status[ISC_STATUS_LENGTH];
    int         chopBlanks; /* chopBlanks ?             */
    AV          *av;        /* array buffer             */
    SV          *sv, **svp; /* buffers */
    XSQLVAR     *var;       /* working pointer XSQLVAR  */
    int         i;          /* loop */
    short       dtype;

    DBI_TRACE_imp_xxh(imp_sth, 2, (DBIc_LOGPIO(imp_sth), "dbd_st_fetch\n"));

    if (!DBIc_ACTIVE(imp_sth))
    {
        do_error(sth, 0, "no statement executing (perhaps you need to call execute first)\n");
        return Nullav;
    }

    chopBlanks = DBIc_is(imp_sth, DBIcf_ChopBlanks);

    av = DBIS->get_fbav(imp_sth);
    svp = AvARRAY(av);

    /*
     * if it's an execute procedure, we've already got the
     * output from the isc_dsql_execute2() call in dbd_st_execute().
     */
    if (imp_sth->type != isc_info_sql_stmt_exec_procedure)
    {
        fetch = isc_dsql_fetch(status, &(imp_sth->stmt), imp_dbh->sqldialect,
                               imp_sth->out_sqlda);

        if (ib_error_check(sth, status))
            return Nullav;

        /*
         * Code 100 means we've reached the end of the set
         * of rows that the SELECT will return.
         */

        DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "dbd_st_fetch: fetch result: %d\n", fetch));

        if (imp_sth->fetched < 0)
            imp_sth->fetched = 0;

        if (fetch == 100)
        {
            /* close the cursor */
            isc_dsql_free_statement(status, &(imp_sth->stmt), DSQL_close);

            if (ib_error_check(sth, status))
                return Nullav;

            DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "isc_dsql_free_statement succeed.\n"));

            DBIc_ACTIVE_off(imp_sth); /* dbd_st_finish is no longer needed */

            /* if AutoCommit on XXX. what to return if fails? */
            if (DBIc_has(imp_dbh, DBIcf_AutoCommit))
            {
                if (!ib_commit_transaction(sth, imp_dbh))
                    return Nullav;

                DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "fetch ends: ib_commit_transaction succeed.\n"));
            }

            return Nullav;
        }
        else if (fetch != 0) /* something bad */
        {   do_error(sth, 0, "Fetch error");
            DBIc_ACTIVE_off(imp_sth);
            return Nullav;
        }
    } /* !exec_procedure */
    else
    {
        /* we only fetch one row for exec procedure */
        if (imp_sth->fetched)
            return Nullav;
    }

    var = imp_sth->out_sqlda->sqlvar;
    for (i = 0; i < imp_sth->out_sqlda->sqld; i++, var++)
    {
        sv = svp[i];
        dtype = var->sqltype & ~1;

        if ((var->sqltype & 1) && (*(var->sqlind) == -1))
        /* if nullable field */
        {
            /* isNULL */
            SvOK_off(sv);
        }
        else
        {
            /*
             * Got a non-null field.  Got to pass it back to the
             * application, which means some datatype dependant code.
             */
            switch (dtype)
            {
                case SQL_SHORT:
                    if (var->sqlscale) /* handle NUMERICs */
                    {
                        double numeric;

                        numeric = ((double) (*(short *) var->sqldata)) /
                                   pow(10.0, (double) -var->sqlscale);
                        sv_setnv(sv, numeric);
                    }
                    else
                        sv_setiv(sv, *(short *) (var->sqldata));
                    break;

                case SQL_LONG:
                    if (var->sqlscale) /* handle NUMERICs */
                    {
                        double numeric;

                        numeric = ((double) (*(ISC_LONG *) var->sqldata)) /
                                   pow(10.0, (double) -var->sqlscale);
                        sv_setnv(sv, numeric);
                    }
                    else
                        sv_setiv(sv, *(ISC_LONG *) (var->sqldata));
                    break;
#ifdef SQL_INT64
                case SQL_INT64:
                /*
                 * This seemed difficult at first to return
                 * a 64-bit scaled numeric to Perl through the
                 * SV interface.  But as luck would have it,
                 * Perl treats strings and numerics identically.
                 * I can return this numeric as a string and
                 * nobody has a problem with it.
                 */
                {
                    ISC_INT64 q, r;
                    char buf[25], prec_buf[25];
                    long double prec;
                    q = *((ISC_INT64 *) (var->sqldata));

                    /*
                     * I deliberately use two integers instead
                     * of casting the scaled int64 to a double.
                     * This avoids rounding errors in conversions
                     * to IEEE float, which is the whole reason
                     * for InterBase support of INT64.
                     */
/*
 * Define INT64 printf formats for various platforms
 * using #defines eases the adding of a new platform (compiler/library)
 */

#if defined(_MSC_VER)        /* Microsoft C compiler/library */
#  define P_INT64_RPEC "%.*I64f"
#  define P_INT64_FULL "%s%I64d%s"
#elif defined(__BORLANDC__)  /* Borland compiler/library */
#  define P_INT64_RPEC "%.*Lf"
#  define P_INT64_FULL "%s%Ld%s"
#elif defined (__FreeBSD__)  /* FreeBSD */
#  define P_INT64_RPEC "%.*Lf"
#  define P_INT64_FULL "%s%qd%s"
#else                        /* others: linux, various unices */
#  define P_INT64_RPEC "%.*Lf"
#  define P_INT64_FULL "%s%lld%s"
#endif

                    prec = abs((int) (q % (int)
                      pow(10.0, (double) -var->sqlscale))) /
                      (long double) pow(10.0, (double) -var->sqlscale);

                    sprintf(prec_buf, P_INT64_RPEC, (int) -var->sqlscale, prec);

                    r = (ISC_INT64) (q / (int) pow(10.0, (double) -var->sqlscale));
                    sprintf(buf, P_INT64_FULL, ((q < 0) && !(r < 0))? "-": "", r,
                            prec ? prec_buf + 1 : "");

                    sv_setpvn(sv, buf, strlen(buf));
                }
                break;
#endif

                case SQL_FLOAT:
                    sv_setnv(sv, (double)(*(float *) (var->sqldata)));
                    break;

                case SQL_DOUBLE:
                    if (var->sqlscale) /* handle NUMERICs */
                    {
                        double d = *(double *)var->sqldata;
                        short  q = -var->sqlscale;

                        sv_setnv(sv, d > 0?
                                 floor(d * pow(10.0, (double) q)) /
                                       pow(10.0, (double) q):
                                 ceil(d * pow(10.0, (double) q)) /
                                       pow(10.0, (double) q));
                    }
                    else
                        sv_setnv(sv, *(double *) (var->sqldata));
                    break;

                case SQL_TEXT:
                /*
                 * Thanks to DAM for pointing out that I
                 * don't need to null-terminate this
                 * buffer, and in fact it's a buffer
                 * overrun if I do!
                 */

                    DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "Fill in TEXT type..\nLength: %d\n", var->sqllen));

                    if (chopBlanks && (var->sqllen > 0))
                    {
                        short len = var->sqllen;
                        char *p = (char*)(var->sqldata);
                        while (len && (p[len-1] == ' ')) len--;
                        sv_setpvn(sv, p, len);
                    }
                    else
                        sv_setpvn(sv, var->sqldata, var->sqllen);
                    break;

                case SQL_VARYING:
                {
                    DBD_VARY *vary = (DBD_VARY *) var->sqldata;
                    sv_setpvn(sv, vary->vary_string, vary->vary_length);
                    /* Note that sqllen for VARCHARs is the max length */
                    break;
                }


                /*
                 * If user specifies a TimestampFormat, TimeFormat, or
                 * DateFormat property of the Statement class, then that
                 * string is the format string for strftime().
                 *
                 * If the user doesn't specify an XxxFormat, then format
                 * is %c, defined in /usr/lib/locale/<locale>/LC_TIME/time,
                 * where <locale> is the host's chosen locale.
                 */
#ifndef IB_API_V6
                case SQL_DATE:
#else
                case SQL_TIMESTAMP:
                case SQL_TYPE_DATE:
                case SQL_TYPE_TIME:
#endif
                {
                    char     *format = NULL, buf[100];
                    struct tm times;
                    int       fpsec;

#ifndef IB_API_V6
                    isc_decode_date((ISC_QUAD *) var->sqldata, &times);
                    format = imp_sth->dateformat;
#else
                    switch (dtype)
                    {
                        case SQL_TIMESTAMP:
                            isc_decode_timestamp((ISC_TIMESTAMP *) var->sqldata, &times);
                            format = imp_sth->timestampformat ?
                                imp_sth->timestampformat :
                                imp_dbh->timestampformat;
                            fpsec = TIMESTAMP_FPSECS(var->sqldata);
                            break;

                        case SQL_TYPE_DATE:
                            isc_decode_sql_date((ISC_DATE *) var->sqldata, &times);
                            format = imp_sth->dateformat ?
                                imp_sth->dateformat :
                                imp_dbh->dateformat;
                            fpsec = 0;
                            break;

                        case SQL_TYPE_TIME:
                            isc_decode_sql_time((ISC_TIME *) var->sqldata, &times);
                            format = imp_sth->timeformat ?
                                imp_sth->timeformat :
                                imp_dbh->timeformat;
                            fpsec = TIME_FPSECS(var->sqldata);
                            break;
                    }

                    DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "Decode passed.\n"));


                    /* hardcoded output format.... */
                    if (strEQ(format, "iso") || strEQ(format, "ISO"))
                    {
                        switch (dtype)
                        {
#ifndef IB_API_V6
                            case SQL_DATE:
#else
                            case SQL_TIMESTAMP:
#endif
                                sprintf(buf, "%04d-%02d-%02d %02d:%02d:%02d.%04d",
                                        times.tm_year + 1900,
                                        times.tm_mon  + 1,
                                        times.tm_mday,
                                        times.tm_hour,
                                        times.tm_min,
                                        times.tm_sec,
                                        TIMESTAMP_FPSECS(var->sqldata));
                                break;
#ifdef IB_API_V6
                            case SQL_TYPE_DATE:
                                sprintf(buf, "%04d-%02d-%02d",
                                        times.tm_year + 1900,
                                        times.tm_mon  + 1,
                                        times.tm_mday);
                                break;

                            case SQL_TYPE_TIME:
                                sprintf(buf, "%02d:%02d:%02d.%04d",
                                        times.tm_hour,
                                        times.tm_min,
                                        times.tm_sec,
                                        TIME_FPSECS(var->sqldata));
                                break;
                        }
#endif

                        sv_setpvn(sv, buf, strlen(buf));
                        break;
                    }


#endif
                    /* output as array like perl's localtime? */
                    if (strEQ(format, "tm") || strEQ(format, "TM"))
                    {
                        AV *list = newAV();

                        av_push(list, newSViv(times.tm_sec));
                        av_push(list, newSViv(times.tm_min));
                        av_push(list, newSViv(times.tm_hour));
                        av_push(list, newSViv(times.tm_mday));
                        av_push(list, newSViv(times.tm_mon));
                        av_push(list, newSViv(times.tm_year));
                        av_push(list, newSViv(times.tm_wday));
                        av_push(list, newSViv(times.tm_yday));
                        av_push(list, newSViv(times.tm_isdst));

                        /* value returned is a reference to the array */
                        sv_setsv(sv, sv_2mortal(newRV_noinc((SV *) list)));
                        break;
                    }

#ifndef WIN32
                    /*
                     * may be we must here copy additional fields needed on
                     * some platforms for some strftime formats. copy from a
                     * dummy struct passed to mktime(). calling mktime()
                     * directly with &times is wrong.
                     */

                    /* struct tm has 9 fields plus may be some more */
                    if (sizeof(struct tm) > (9*sizeof(int)))
                    {
                        struct tm dummy;
                        Zero(&dummy, 1, struct tm);
                        mktime(&dummy);
                        memcpy(((char *)&times) + 9*sizeof(int),
                               ((char *)&dummy) + 9*sizeof(int),
                               sizeof(struct tm) - (9*sizeof(int)));
                    }
#endif

                    strftime(buf, sizeof(buf), format, &times);
                    sv_setpvn(sv, buf, strlen(buf));
                    break;
                }

                case SQL_BLOB:
                {
                    isc_blob_handle blob_handle = NULL;
                    int blob_stat;
                    char blob_info_buffer[32], *p,
                         blob_segment_buffer[BLOB_SEGMENT];
                    char blob_info_items[] =
                    {
                        isc_info_blob_max_segment,
                        isc_info_blob_total_length
                    };
                    long max_segment = -1L, total_length = -1L, t;
                    unsigned short seg_length;

                    /* Open the Blob according to the Blob id. */
                    isc_open_blob2(status, &(imp_dbh->db), &(imp_dbh->tr),
                                   &blob_handle, (ISC_QUAD *) var->sqldata,
#if defined(INCLUDE_FB_TYPES_H) || defined(INCLUDE_TYPES_PUB_H)
                                   (ISC_USHORT) 0,
                                   (ISC_UCHAR) NULL);
#else                                   
                                   (short) 0,       /* no Blob filter */
                                   (char *) NULL);  /* no Blob filter */
#endif

                    if (ib_error_check(sth, status))
                        return FALSE;

                    /* query blob information to find out the segment size */
                    isc_blob_info(status, &blob_handle, sizeof(blob_info_items),
                                  blob_info_items, sizeof(blob_info_buffer),
                                  blob_info_buffer);

                    if (ib_error_check(sth, status))
                    {
                        isc_cancel_blob(status, &blob_handle);
                        return FALSE;
                    }

                    /* Get the information out of the info buffer. */
                    for (p = blob_info_buffer; *p != isc_info_end; )
                    {
                        short length;
                        char  datum = *p++;

                        length = (short) isc_vax_integer(p, 2);
                        p += 2;
                        switch (datum)
                        {
                          case isc_info_blob_max_segment:
                              max_segment = isc_vax_integer(p, length);
                              break;
                          case isc_info_blob_total_length:
                              total_length = isc_vax_integer(p, length);
                              break;
                        }
                        p += length;
                    }

                    DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth),
                                  "dbd_st_fetch: BLOB info - max_segment: %ld, total_length: %ld\n",
                                  max_segment, total_length));

                    if (max_segment == -1L || total_length == -1L)
                    {
                        isc_cancel_blob(status, &blob_handle);
                        do_error(sth, 1, "Cannot determine Blob dimensions.");
                        return FALSE;
                        break;
                    }

                    /* if maximum segment size is zero, don't pass it to isc_get_segment()  */
                    if (max_segment == 0)
                    {
                        sv_setpv(sv, "");
                        isc_cancel_blob(status, &blob_handle);
                        if (ib_error_check(sth, status))
                            return FALSE;
                        break;
                    }

                    if ((DBIc_LongReadLen(imp_sth) < (unsigned long) total_length) &&
                        (! DBIc_is(imp_dbh, DBIcf_LongTruncOk)))
                    {
                        isc_close_blob(status, &blob_handle);
                        do_error(sth, 1, "Not enough LongReadLen buffer.");
                        return FALSE;
                        break;
                    }

                    if (total_length >= MAX_SAFE_BLOB_LENGTH)
                    {
                        do_error(sth, 1, "Blob exceeds maximum length.");

                        sv_setpvn(sv, "** Blob exceeds maximum safe length **", 38);

                        /* I deliberately don't set FAILURE based on this. */
                        isc_close_blob(status, &blob_handle);
                        if (ib_error_check(sth, status))
                            return FALSE;
                        break;
                    }

                    /* Create a zero-length string. */
                    sv_setpv(sv, "");

                    t = total_length;
                    while (1)
                    {
                        blob_stat = isc_get_segment(status, &blob_handle,
                                                    &seg_length,
                                                    (short) BLOB_SEGMENT,
                                                    blob_segment_buffer);

                        if (status[1] == isc_segstr_eof)
                            break;

                        if (status[1] != isc_segment)
                            if (ib_error_check(sth, status))
                            {
                                isc_cancel_blob(status, &blob_handle);
                                return FALSE;
                            }

                        if (seg_length > DBIc_LongReadLen(imp_sth))
                             break;

    /*
     * As long as the fetch was successful, concatenate the segment we fetched
     * into the growing Perl scalar.
     */
    /*
     * This is dangerous if the Blob is enormous.  But Perl is supposed
     * to be able to grow scalars indefinitely as far as resources allow,
     * so what the heck.  Besides, I limited the max length of a Blob earlier
     * to MAX_SAFE_BLOB_LENGTH.
     */

                        sv_catpvn(sv, blob_segment_buffer, seg_length);
                        t -= seg_length;

                        if (t <= 0) break;
                        if (blob_stat == 100) break;
                    }

                    /* Clean up after ourselves. */
                    isc_close_blob(status, &blob_handle);
                    if (ib_error_check(sth, status))
                        return FALSE;

                    break;
                }

                case SQL_ARRAY:
#ifdef ARRAY_SUPPORT
            !!! NOT IMPLEMENTED YET !!!
#else
                    sv_setpvn(sv, "** array **", 11);
#endif
                    break;

                default:
                    sv_setpvn(sv, "** unknown **", 13);
            }

        /*
         * I use the column's alias name because in the absence
         * of an alias, it contains the column name anyway.
         * Only if the alias AND the column names are zero-length
         * do I want to use a generic "COLUMN%d" header.
         * This happens, for example, when the column is a
         * computed field and the query doesn't use an AS clause
         * to label the column.
         */
/*
            if (var->aliasname_length > 0)
            {
                sv_setpvn(sv, var->aliasname, var->aliasname_length));
            }
            else
            {
                char s[20];
                sprintf(s, "COLUMN%d", i);
                sv_setpvn(sv, s, strlen(s));
            }
*/
        }
    }
    imp_sth->fetched += 1;
    return av;
}


int dbd_st_finish(SV *sth, imp_sth_t *imp_sth)
{
    D_imp_dbh_from_sth;
    ISC_STATUS status[ISC_STATUS_LENGTH];

    DBI_TRACE_imp_xxh(imp_sth, 2, (DBIc_LOGPIO(imp_sth), "dbd_st_finish\n"));

    if (!DBIc_ACTIVE(imp_sth)) /* already finished */
        return TRUE;

    /* Close the cursor, not drop the statement! */
    if (imp_sth->type != isc_info_sql_stmt_exec_procedure)
        isc_dsql_free_statement(status, (isc_stmt_handle *)&(imp_sth->stmt), DSQL_close);

    if (ib_error_check(sth, status))
        return FALSE;

    DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "dbd_st_finish: isc_dsql_free_statement passed.\n"));

    /* set statement to inactive - must be before ib_commit_transaction 'cos
       commit can call dbd_st_finish function again */
    DBIc_ACTIVE_off(imp_sth);

    /* if AutoCommit on */
    if (DBIc_has(imp_dbh, DBIcf_AutoCommit))
    {
        DBI_TRACE_imp_xxh(imp_sth, 4, (DBIc_LOGPIO(imp_sth), "dbd_st_finish: Trying to call ib_commit_transaction.\n"));

        if (!ib_commit_transaction(sth, imp_dbh))
        {
            DBI_TRACE_imp_xxh(imp_sth, 4, (DBIc_LOGPIO(imp_sth), "dbd_st_finish: Call ib_commit_transaction finished returned FALSE.\n"));
            return FALSE;
        }
        DBI_TRACE_imp_xxh(imp_sth, 4, (DBIc_LOGPIO(imp_sth), "dbd_st_finish: Call ib_commit_transaction succeded.\n"));
    }

    return TRUE;
}


void dbd_st_destroy(SV *sth, imp_sth_t *imp_sth)
{
    D_imp_dbh_from_sth;
    ISC_STATUS  status[ISC_STATUS_LENGTH];

    DBI_TRACE_imp_xxh(imp_dbh, 2, (DBIc_LOGPIO(imp_dbh), "dbd_st_destroy\n"));

    /* freeing cursor name */
    FREE_SETNULL(imp_sth->cursor_name);

    /* freeing in_sqlda */
    if (imp_sth->in_sqlda)
    {
        int i;
        XSQLVAR *var = imp_sth->in_sqlda->sqlvar;

        DBI_TRACE_imp_xxh(imp_dbh, 3, (DBIc_LOGPIO(imp_dbh), "dbd_st_destroy: found in_sqlda..\n"));

        for (i = 0; i < imp_sth->in_sqlda->sqld; i++, var++)
        {
            FREE_SETNULL(var->sqldata);
            FREE_SETNULL(var->sqlind);
        }

        DBI_TRACE_imp_xxh(imp_dbh, 3, (DBIc_LOGPIO(imp_dbh), "dbd_st_destroy: freeing in_sqlda..\n"));

        Safefree(imp_sth->in_sqlda);
        imp_sth->in_sqlda = NULL;
    }

    /* freeing out_sqlda */
    if (imp_sth->out_sqlda)
    {
        int i;
        XSQLVAR *var = imp_sth->out_sqlda->sqlvar;
        for (i = 0; i < imp_sth->out_sqlda->sqld; i++, var++)
        {
            FREE_SETNULL(var->sqldata);
            FREE_SETNULL(var->sqlind);
        }
        Safefree(imp_sth->out_sqlda);
        imp_sth->out_sqlda = NULL;
    }

    /* free all other resources */
    FREE_SETNULL(imp_sth->dateformat);
#ifdef IB_API_V6
    FREE_SETNULL(imp_sth->timeformat);
    FREE_SETNULL(imp_sth->timestampformat);
#endif

    /* Drop the statement */
    if (imp_sth->stmt)
    {
        isc_dsql_free_statement(status, &(imp_sth->stmt), DSQL_drop);
        if (ib_error_check(sth, status))
        {
            DBI_TRACE_imp_xxh(imp_dbh, 3, (DBIc_LOGPIO(imp_dbh), "dbd_st_destroy: isc_dsql_free_statement failed.\n"));
        }
        else
            DBI_TRACE_imp_xxh(imp_dbh, 3, (DBIc_LOGPIO(imp_dbh), "dbd_st_destroy: isc_dsql_free_statement succeeded.\n"));

        imp_sth->stmt = 0L;
    }

    /* remove sth from linked list */

    /* handle prev element */
    if (imp_sth->prev_sth == NULL)
        imp_dbh->first_sth = imp_sth->next_sth;
    else
        imp_sth->prev_sth->next_sth = imp_sth->next_sth;

    /* handle next element*/
    if (imp_sth->next_sth == NULL)
        imp_dbh->last_sth = imp_sth->prev_sth;
    else
        imp_sth->next_sth->prev_sth = imp_sth->prev_sth;

    /* set next/prev to NULL */
    imp_sth->prev_sth = imp_sth->next_sth = NULL;

    DBI_TRACE_imp_xxh(imp_dbh, 3, (DBIc_LOGPIO(imp_dbh), "dbd_st_destroy: sth removed from linked list.\n"));


    /* let DBI know we've done it */
    if (sth) DBIc_IMPSET_off(imp_sth);
}


SV* dbd_st_FETCH_attrib(SV *sth, imp_sth_t *imp_sth, SV *keysv)
{
    STRLEN  kl;
    char    *key = SvPV(keysv, kl);
    int     i;
    SV      *result = NULL;
    /* Default to caching results for DBI dispatch quick_FETCH  */
    int cacheit = TRUE;

    DBI_TRACE_imp_xxh(imp_sth, 2, (DBIc_LOGPIO(imp_sth), "dbd_st_FETCH - %s\n", key));

    if (kl==13 && strEQ(key, "NUM_OF_PARAMS"))  /* handled by DBI */
        return Nullsv;

    i = DBIc_NUM_FIELDS(imp_sth);

    /**************************************************************************/
    if (kl==4 && strEQ(key, "TYPE"))
    {
        AV *av;

        if (!imp_sth || !imp_sth->in_sqlda || !imp_sth->out_sqlda)
            return Nullsv;

        av = newAV();
        result = newRV(sv_2mortal((SV*)av));
        while(--i >= 0)
            av_store(av, i,
                     newSViv(ib2sql_type(imp_sth->out_sqlda->sqlvar[i].sqltype)));
    }
    /**************************************************************************/
    else if (kl==5 && strEQ(key, "SCALE"))
    {
        AV *av;

        if (!imp_sth || !imp_sth->in_sqlda || !imp_sth->out_sqlda)
            return Nullsv;

        av = newAV();
        result = newRV(sv_2mortal((SV*)av));
        while(--i >= 0)
            av_store(av, i, newSViv(imp_sth->out_sqlda->sqlvar[i].sqlscale));

    }
    /**************************************************************************/
    else if (kl==9 && strEQ(key, "PRECISION"))
    {
        AV *av;

        if (!imp_sth || !imp_sth->in_sqlda || !imp_sth->out_sqlda)
            return Nullsv;

        av = newAV();
        result = newRV(sv_2mortal((SV*)av));
        while(--i >= 0)
            av_store(av, i, newSViv(imp_sth->out_sqlda->sqlvar[i].sqllen));
    }
    /**************************************************************************/
    else if (kl==4 && strEQ(key, "NAME"))
    {
        AV *av;

        if (!imp_sth || !imp_sth->in_sqlda || !imp_sth->out_sqlda)
            return Nullsv;

        av = newAV();
        result = newRV(sv_2mortal((SV*)av));
        while(--i >= 0)
        {
            if (imp_sth->out_sqlda->sqlvar[i].aliasname_length > 0)
            {
                av_store(av, i,
                         newSVpvn(imp_sth->out_sqlda->sqlvar[i].aliasname,
                         imp_sth->out_sqlda->sqlvar[i].aliasname_length));
            }
            else
            {
                char s[20];
                sprintf(s, "COLUMN%d", i);
                av_store(av, i, newSVpvn(s, strlen(s)));
            }
        }
    }
    /**************************************************************************/
    else if (kl==8 && strEQ(key, "NULLABLE"))
    {
        AV *av;

        if (!imp_sth || !imp_sth->in_sqlda || !imp_sth->out_sqlda)
            return Nullsv;

        av = newAV();
        result = newRV(sv_2mortal((SV*)av));
        while(--i >= 0)
            av_store(av, i, boolSV((imp_sth->out_sqlda->sqlvar[i].sqltype & 1) != 0));
    }
    /**************************************************************************/
    else if (kl==10 && strEQ(key, "CursorName"))
    {
        if (imp_sth->cursor_name == NULL)
            return Nullsv;
        else
            result = newSVpv(imp_sth->cursor_name, strlen(imp_sth->cursor_name));
    }
    else
        return Nullsv;

    if (cacheit)
    { /* cache for next time (via DBI quick_FETCH)  */
        SV **svp = hv_fetch((HV*)SvRV(sth), key, kl, 1);
        sv_free(*svp);
        *svp = result;
        (void)SvREFCNT_inc(result); /* so sv_2mortal won't free it  */
    }
    return sv_2mortal(result);
}


int dbd_st_STORE_attrib(SV *sth, imp_sth_t *imp_sth, SV *keysv, SV *valuesv)
{
    STRLEN  kl;
    char    *key = SvPV(keysv, kl);

    DBI_TRACE_imp_xxh(imp_sth, 2, (DBIc_LOGPIO(imp_sth), "dbd_st_STORE - %s\n", key));

    return FALSE;
}


int dbd_discon_all(SV *drh, imp_drh_t *imp_drh)
{
    dTHR;

    /* The disconnect_all concept is flawed and needs more work */
    if (!SvTRUE(perl_get_sv("DBI::PERL_ENDING", 0)))
    {
        sv_setiv(DBIc_ERR(imp_drh), (IV)1);
        sv_setpv(DBIc_ERRSTR(imp_drh), (char*)"disconnect_all not implemented");
        DBIh_EVENT2(drh, ERROR_event, DBIc_ERR(imp_drh), DBIc_ERRSTR(imp_drh));
        return FALSE;
    }
    if (perl_destruct_level)
        perl_destruct_level = 0;
    return FALSE;
}


int ib_blob_write(SV *sth, imp_sth_t *imp_sth, XSQLVAR *var, SV *value)
{
    D_imp_dbh_from_sth;
    isc_blob_handle handle = NULL;
    ISC_STATUS      status[ISC_STATUS_LENGTH];
    long            total_length;
    char            *p, *seg;
    int             is_text_blob, seg_len;

    DBI_TRACE_imp_xxh(imp_sth, 2, (DBIc_LOGPIO(imp_sth), "ib_blob_write\n"));

    /* we need a transaction  */
    if (!imp_dbh->tr)
        if (!ib_start_transaction(sth, imp_dbh))
            return FALSE;

    /* alloc mem for blob id */
    if (var->sqldata == NULL)
        Newxc(var->sqldata, 1, ISC_QUAD, ISC_SCHAR);

    /* try to create blob handle */
    isc_create_blob2(status, &(imp_dbh->db), &(imp_dbh->tr), &handle,
                     (ISC_QUAD *)(var->sqldata), 0, NULL);
    if (ib_error_check(sth, status))
        return FALSE;


    /* get length, pointer to data */
    total_length = SvCUR(value);
    p = SvPV_nolen(value);

    is_text_blob = (var->sqlsubtype == isc_bpb_type_stream)? 1: 0; /* SUBTYPE TEXT */

    /* write it segment by segment */
    seg_len = BLOB_SEGMENT;
    while (total_length > 0)
    {
        DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "ib_blob_write: %d bytes left\n", total_length));

        /* set new segment start pointer */
        seg = p;

        if (is_text_blob)
        {
            seg_len = 0;
            while ((seg_len < BLOB_SEGMENT) && (total_length > 0))
            {
                total_length--;
                p++;
                seg_len++;

                if (*(p-1) == '\n') break;
            }
        }
        else
        {
            /* no text blob, set seg len to max possible */
            if (total_length < BLOB_SEGMENT)
                seg_len = total_length;

            /* update segment pointer */
            p += seg_len;
            total_length -= seg_len;
        }

        isc_put_segment(status, &handle, (unsigned short) seg_len, seg);
        if (ib_error_check(sth, status))
        {
            isc_cancel_blob(status, &handle);
            return FALSE;
        }

        DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "ib_blob_write: %d bytes written\n", seg_len));

    }

    /* close blob, check for error */
    isc_close_blob(status, &handle);
    if (ib_error_check(sth, status))
        return FALSE;

    return TRUE;
}


/* fill in_sqlda with bind parameters */
static int ib_fill_isqlda(SV *sth, imp_sth_t *imp_sth, SV *param, SV *value,
                          IV sql_type)
{
    STRLEN     len;
    XSQLVAR    *ivar;
    int        retval;
    int        dtype;
    int        i = (int)SvIV(param) - 1;

    retval = TRUE;
    ivar = &(imp_sth->in_sqlda->sqlvar[i]);

    DBI_TRACE_imp_xxh(imp_sth, 2, (DBIc_LOGPIO(imp_sth), "enter ib_fill_isqlda. processing %d XSQLVAR"
                            "   Type %ld"
                            " ivar->sqltype=%ld\n",
                            i + 1,
                            (long) sql_type,
                            ivar->sqltype));

    DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "ib_fill_isqlda: XSQLDA len: %d\n",
                  imp_sth->in_sqlda->sqln));

    /* NULL indicator */
    if (!(ivar->sqlind))
        Newx(ivar->sqlind, 1, ISC_SHORT);

    /* *(ivar->sqlind) = ivar->sqltype & 1 ? 0 : 1; */

    *(ivar->sqlind) = 0; /* default assume non-NULL */

    /* it should be safe not to free here. test it */
#if 0
    if (ivar->sqldata)
    {
        DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "ib_fill_isqlda: Freeing sqldata\n"));
        DBI_TRACE_imp_xxh(imp_sth, 4, (DBIc_LOGPIO(imp_sth), "ib_fill_isqlda: Freeing sqldata, sqltype is %d\n", ivar->sqltype));

        Safefree(ivar->sqldata);
        ivar->sqldata = (char *)NULL;
    }
#endif

    if (!SvOK(value)) /* user passed an undef */
    {
        if (ivar->sqltype & 1) /* Field is NULLable */
        {
            /*
            * The user has passed 'undef' for this scalar parameter and we use
            * this to indicate that the parameter should have a NULL state.
            */
            *(ivar->sqlind) = -1; /* NULL */

            /*
            * Hence no need to fill in sqldata for this sqlvar, because it's
            * NULL anyway.Skip to next loop iteration.
            */
            return retval;
        }
        else
        {
            /*
            * User passed an undef to a field that is not nullable.
            */
            char err[80];
            sprintf(err, "You have not provided a value for non-nullable parameter #%d.", i);
            do_error(sth, 1, err);
            retval = FALSE;
            return retval;
        }
    }

    /* data type minus nullable flag */
    dtype = ivar->sqltype & ~1;

    /* workaround for date problem (bug #429820) */
    if (dtype == SQL_TEXT)
    {
        if (ivar->sqlsubtype == 0x77)
#ifndef IB_API_V6
            dtype = SQL_DATE;
#else
            dtype = SQL_TIMESTAMP;
#endif
    }

    switch (dtype)
    {
        /**********************************************************************/
        case SQL_VARYING:
            DBI_TRACE_imp_xxh(imp_sth, 1, (DBIc_LOGPIO(imp_sth), "ib_fill_isqlda: SQL_VARYING\n"));
        {
            char *string;
            STRLEN len;

            string = SvPV(value, len);

            if (len > ivar->sqllen) {
                char err[80];
                sprintf(err, "String truncation (SQL_VARYING): attempted to bind %lu octets to column sized %lu",
                        len, (sizeof(char) * (ivar->sqllen)));
                break;
            }

            if (!(ivar->sqldata))
                Newxz(ivar->sqldata, ivar->sqllen + sizeof(short), char);

            *((short *)ivar->sqldata) = len;
            Copy(string, ivar->sqldata + sizeof(short), len, char);
            break;
        }
        /**********************************************************************/
        case SQL_TEXT:
            DBI_TRACE_imp_xxh(imp_sth, 1, (DBIc_LOGPIO(imp_sth), "ib_fill_isqlda: SQL_TEXT\n"));
        {
            char *string;
            STRLEN len;

            string = SvPV(value, len);

            if (len > ivar->sqllen) {
                char err[80];
                sprintf(err, "String truncation (SQL_TEXT): attempted to bind %lu octets to column sized %lu",
                        len, (sizeof(char) * (ivar->sqllen)));
                break;
            }

            if (!(ivar->sqldata))
                Newxc(ivar->sqldata, ivar->sqllen, char, ISC_SCHAR);

            /* Pad the entire field with blanks */
            PoisonWith(ivar->sqldata, ivar->sqllen, char, ' ');
            Copy(string, ivar->sqldata, len, char);
            break;
        }

        /**********************************************************************/
        case SQL_SHORT:
        case SQL_LONG:
             DBI_TRACE_imp_xxh(imp_sth, 1, (DBIc_LOGPIO(imp_sth), "ib_fill_isqlda: SQL_SHORT/SQL_LONG\n"));

        {
            char format[64];
            long p, q, r, result;
            char *svalue;

            /* we need a bit of mem */
            if (!(ivar->sqldata)) {
                Newxc(ivar->sqldata,
                      (dtype == SQL_SHORT ? sizeof(short) : sizeof(long)),
                      char,
                      ISC_SCHAR);
            }

            /* See case SQL_INT64 for commentary. */

            p = q = r = (long) 0;
            svalue = (char *)SvPV(value, len);

            /* with decimals? */
            if (-ivar->sqlscale)
            {
                /* numeric(?,?) */
                int  scale = (int) (pow(10.0, (double) -ivar->sqlscale));
                int  dscale;
                char *tmp;
                char *neg;

                sprintf(format, "%%ld.%%%dld%%1ld", -ivar->sqlscale);

                /* negative -0.x hack */
                neg = strchr(svalue, '-');
                if (neg)
                {
                    svalue = neg + 1;
                    len = strlen(svalue);
                }

                if (!sscanf(svalue, format, &p, &q, &r))
                {
                    /* here we handle values such as .78 passed as string */
                    sprintf(format, ".%%%dld%%1ld", -ivar->sqlscale);
                    if (!sscanf(svalue, format, &q, &r) && DBIc_WARN(imp_sth))
                        warn("problem parsing SQL_LONG type");
                }

                /* Round up if r is 5 or greater */
                if (r >= 5)
                {
                    q++;            /* round q up by one */
                    p += q / scale; /* round p up by one if q overflows */
                    q %= scale;     /* modulus if q overflows */
                }

                /* decimal scaling */
                tmp    = strchr(svalue, '.');
                dscale = (tmp)? -ivar->sqlscale - (len - (int) (tmp - svalue)) + 1: 0;
                if (dscale < 0) dscale = 0;

                /* final result */
                result = (long) (p * scale + q * (int) (pow(10.0, (double) dscale))) * (neg? -1: 1);
            }
            /******************************************************************/
            else
            {
                /* numeric(?,0): scan for one decimal and do rounding*/

                sprintf(format, "%%ld.%%1ld");

                if (!sscanf(svalue, format, &p, &r))
                {
                    sprintf(format, ".%%1ld");
                    if (!sscanf(svalue, format, &r) && DBIc_WARN(imp_sth))
                        warn("problem parsing SQL_LONG type");
                }

                /* rounding */
                if (r >= 5)
                {
                    if (p < 0) p--; else p++;
                }

                /* the final result */
                result = (long) p;
            }

            /* result in short or long? */
            if (dtype == SQL_SHORT)
                *(short *) (ivar->sqldata) = (short) result;
            else
                *(long *) (ivar->sqldata) = result;

            break;
        }

        /**********************************************************************/
#ifdef SQL_INT64
        case SQL_INT64:
            DBI_TRACE_imp_xxh(imp_sth, 1, (DBIc_LOGPIO(imp_sth), "ib_fill_isqlda: SQL_INT64\n"));

        {
            char     *svalue;
            char     format[64];
            ISC_INT64 p, q, r;

            if (!(ivar->sqldata))
                Newxc(ivar->sqldata, 1, ISC_INT64, ISC_SCHAR);

            /*
             * Here I handle both whole and scaled numerics.
             * The trick is to avoid converting the Perl scalar
             * to an IEEE floating value, because this would
             * introduce exactness errors in the conversion from
             * base-10 to base-2.
             *
             * I create a pattern for scanf() to read the whole
             * number portion (p), then a number of digits for
             * the scale (q), then one more digit (r) for the
             * round-up threshold.
             *
             * Note that sprintf replaces %% with a single %.
             * See the man page for sscanf() for more details
             * about how it interprets %Ld, %1Ld, etc.
             */

/*
 * Define INT64 sscanf formats for various platforms
 * using #defines eases the adding of a new platform (compiler/library)
 */

#if defined(_MSC_VER)        /* Microsoft C compiler/library */
#  define S_INT64_FULL        "%%I64d.%%%dI64d%%1I64d"
#  define S_INT64_NOSCALE     "%%I64d.%%1I64d"
#  define S_INT64_DEC_FULL    ".%%%dI64d%%1I64d"
#  define S_INT64_DEC_NOSCALE ".%%1I64d"
#elif defined(__BORLANDC__)  /* Borland compiler/library)*/
#  define S_INT64_FULL        "%%Ld.%%%dLd%%1Ld"
#  define S_INT64_NOSCALE     "%%Ld.%%1Ld"
#  define S_INT64_DEC_FULL    ".%%%dLd%%1Ld"
#  define S_INT64_DEC_NOSCALE ".%%1Ld"
#elif defined (__FreeBSD__)  /* FreeBSD */
#  define S_INT64_FULL        "%%qd.%%%dqd%%1qd"
#  define S_INT64_NOSCALE     "%%qd.%%1qd"
#  define S_INT64_DEC_FULL    ".%%%dqd%%1qd"
#  define S_INT64_DEC_NOSCALE ".%%1qd"
#else                        /* others: linux, various unices */
#  define S_INT64_FULL        "%%lld.%%%dlld%%1lld"
#  define S_INT64_NOSCALE     "%%lld.%%1lld"
#  define S_INT64_DEC_FULL    ".%%%dlld%%1lld"
#  define S_INT64_DEC_NOSCALE ".%%1lld"
#endif

            p = q = r = (ISC_INT64) 0;
            svalue = (char *)SvPV(value, len);

            /* with decimals? */
            if (-ivar->sqlscale)
            {
                /* numeric(?,?) */
                int  scale = (int) (pow(10.0, (double) -ivar->sqlscale));
                int  dscale;
                char *tmp;
                char *neg;

                sprintf(format, S_INT64_FULL, -ivar->sqlscale);

                /* negative -0.x hack */
                neg = strchr(svalue, '-');
                if (neg)
                {
                    svalue = neg + 1;
                    len = strlen(svalue);
                }

                if (!sscanf(svalue, format, &p, &q, &r))
                {
                    /* here we handle values such as .78 passed as string */
                    sprintf(format, S_INT64_DEC_FULL, -ivar->sqlscale);
                    if (!sscanf(svalue, format, &q, &r) && DBIc_WARN(imp_sth))
                        warn("problem parsing SQL_INT64 type");
                }

#ifdef __BORLANDC__
                p = _atoi64(svalue);
#endif

                /* Round up if r is 5 or greater */
                if (r >= 5)
                {
                    q++;            /* round q up by one */
                    p += q / scale; /* round p up by one if q overflows */
                    q %= scale;     /* modulus if q overflows */
                }

                /* decimal scaling */
                tmp    = strchr(svalue, '.');
                dscale = (tmp)? -ivar->sqlscale - (len - (int) (tmp - svalue)) + 1: 0;
                if (dscale < 0) dscale = 0;

                /* final result */
                *(ISC_INT64 *) (ivar->sqldata) = (ISC_INT64) (p * scale + q * (int) (pow(10.0, (double) dscale))) * (neg? -1: 1);
            }
            /******************************************************************/
            else
            {
                /* numeric(?,0): scan for one decimal and do rounding*/

                sprintf(format, S_INT64_NOSCALE);

                if (!sscanf(svalue, format, &p, &r))
                {
                    sprintf(format, S_INT64_DEC_NOSCALE);
                    if (!sscanf(svalue, format, &r) && DBIc_WARN(imp_sth))
                        warn("problem parsing SQL_INT64 type");
                }

                /* rounding */
                if (r >= 5)
                {
                    if (p < 0) p--; else p++;
                }

                /* the final result */
                *(ISC_INT64 *) (ivar->sqldata) = (ISC_INT64) p;
            }

            break;
        }
#endif

        /**********************************************************************/
        case SQL_FLOAT:
            DBI_TRACE_imp_xxh(imp_sth, 1, (DBIc_LOGPIO(imp_sth), "ib_fill_isqlda: SQL_FLOAT\n"));

            if (!(ivar->sqldata))
                Newxc(ivar->sqldata, 1, float, ISC_SCHAR);
            *(float *) (ivar->sqldata) = (float) SvNV(value);

            break;

        /**********************************************************************/
        case SQL_DOUBLE:
            DBI_TRACE_imp_xxh(imp_sth, 1, (DBIc_LOGPIO(imp_sth), "ib_fill_isqlda: SQL_DOUBLE\n"));

            if (!(ivar->sqldata))
                Newxc(ivar->sqldata, 1, double, ISC_SCHAR);

            *(double *) (ivar->sqldata) = SvNV(value);

            break;

        /**********************************************************************/
#ifndef IB_API_V6
        case SQL_DATE:
#else
        case SQL_TIMESTAMP:
        case SQL_TYPE_TIME:
        case SQL_TYPE_DATE:
#endif
            if (SvPOK(value) || SvTYPE(value) == SVt_PVMG)
            {
                /*
                 * Coerce the date literal into a CHAR string, so as
                 * to allow InterBase's internal date-string parsing
                 * to interpret the date.
                 */
                char *datestring = SvPV(value, len);

                ivar->sqltype = SQL_TEXT | (ivar->sqltype & 1);

                /* prevent overflow */
                if (len > 100) {
                    do_error(sth, 2, "DATE input parameter too long, but will try...\n");
                    len = 100;
                }

                /* workaround for date problem (bug #429820) */
                ivar->sqlsubtype = 0x77; /* (0x77 is a random value) */

                ivar->sqllen = len;
                /*
                 * I should not allocate based on len, I should allocate
                 * a fixed length based on the max date/time string.
                 * For now let's just call it 100.  Okay, 101.
                 */
                if (!(ivar->sqldata))
                    Newx(ivar->sqldata, 101, ISC_SCHAR);
                Copy(datestring, ivar->sqldata, len, ISC_SCHAR);
                ivar->sqldata[len] = '\0';
            }
            else if (SvROK(value))
            {
                struct tm times;               /* unix time struct    */
                AV *list = (AV *) SvRV(value); /* AV with time items  */
                SV **svp = AvARRAY(list);      /* AV as a C array     */
                int items = av_len(list) + 1;  /* item count in array */

                /* check if we have enough items in the list */
                if (items < 5) /* we ignore wday, yday, isdst */
                {
                    do_error(sth, 2, "Cannot bind date/time value. Not enough"
                                     "items in localtime() style array");
                    retval = FALSE;
                    break;
                }

                /* fill in struct tm fields */
                times.tm_sec  = SvIV(svp[0]);
                times.tm_min  = SvIV(svp[1]);
                times.tm_hour = SvIV(svp[2]);
                times.tm_mday = SvIV(svp[3]);
                times.tm_mon  = SvIV(svp[4]);
                times.tm_year = SvIV(svp[5]);

                /* free ivar->sqldata (prior call wasn't necessary an localtimes
                 * style list) */
                if (ivar->sqldata)
                    Safefree(ivar->sqldata);

                /* encode for firebird/interbase, store value*/
#ifndef IB_API_V6
                {
                    ISC_QUAD timestamp;
                    isc_encode_date(&times, &timestamp);

                    Newx(ivar->sqldata, 1, ISC_QUAD, ISC_SCHAR);

                    /* we assume there's a fpsecs part after struct tm elements */
                    if (items >= 10)
                        TIMESTAMP_ADD_FPSECS(&timestamp, SvIV(svp[9]));

                    *(ISC_QUAD *) ivar->sqldata = timestamp;
                }
#else
                switch (dtype)
                {
                    case SQL_TIMESTAMP:
                    {
                        ISC_TIMESTAMP timestamp;
                        isc_encode_timestamp(&times, &timestamp);

                        Newxc(ivar->sqldata, 1, ISC_TIMESTAMP, ISC_SCHAR);

                        if (items >= 10)
                            TIMESTAMP_ADD_FPSECS(&timestamp, SvIV(svp[9]));

                        *(ISC_TIMESTAMP *) ivar->sqldata = timestamp;

                        break;
                    }

                    case SQL_TYPE_TIME:
                    {
                        ISC_TIME sql_time;
                        isc_encode_sql_time(&times, &sql_time);

                        Newxc(ivar->sqldata, 1, ISC_TIME, ISC_SCHAR);

                        if (items >= 10)
                            TIME_ADD_FPSECS(&sql_time, SvIV(svp[9]));

                        *(ISC_TIME *) ivar->sqldata = sql_time;

                        break;
                    }

                    case SQL_TYPE_DATE:
                    {
                        ISC_DATE sql_date;
                        isc_encode_sql_date(&times, &sql_date);

                        Newxc(ivar->sqldata, 1, ISC_DATE, ISC_SCHAR);
                        *(ISC_DATE *) ivar->sqldata = sql_date;

                        break;
                    }
                }
#endif
            }
            break;


        /**********************************************************************/
        case SQL_BLOB:
            DBI_TRACE_imp_xxh(imp_sth, 1, (DBIc_LOGPIO(imp_sth), "ib_fill_isqlda: SQL_BLOB\n"));

            /* SELECT's can't have a blob as in_sqlda. */
            if ((imp_sth->type == isc_info_sql_stmt_select) ||
                (imp_sth->type == isc_info_sql_stmt_select_for_upd))
            {
                do_error(sth, 2, "BLOB as an input param for SELECT is not allowed.\n");
                retval = FALSE;
                break;
            }
            else
                /* we have an extra function for this */
                retval = ib_blob_write(sth, imp_sth, ivar, value);

            break;

        /**********************************************************************/
        case SQL_ARRAY:
#ifdef ARRAY_SUPPORT
        !!! NOT IMPLEMENTED YET !!!
#endif
            break;

        default:
            break;
    }


    DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "exiting ib_fill_isqlda: %d\n", retval));

    return retval;
}


int dbd_bind_ph(SV *sth, imp_sth_t *imp_sth, SV *param, SV *value,
                IV sql_type, SV *attribs, int is_inout, IV maxlen)
{
    DBI_TRACE_imp_xxh(imp_sth, 2, (DBIc_LOGPIO(imp_sth), "dbd_bind_ph\n"));

    if (SvTYPE(value) > SVt_PVLV)
        croak("Can't bind a non-scalar value (%s)", neatsvpv(value,0));

    /* is_inout for stored procedure is not implemented yet */
    if (is_inout)
        croak("Can't bind ``lvalue'' mode.");

    if (!imp_sth || !imp_sth->in_sqlda)
        return FALSE;

    /* param is the number of parameter: 1, 2, 3, or ... */
    if ((int)SvIV(param) > imp_sth->in_sqlda->sqld)
        return TRUE;

    DBI_TRACE_imp_xxh(imp_sth, 3, (DBIc_LOGPIO(imp_sth), "Binding parameter: %d\n", (int)SvIV(param)));

    return ib_fill_isqlda(sth, imp_sth, param, value, sql_type);
}


int ib_start_transaction(SV *h, imp_dbh_t *imp_dbh)
{
    ISC_STATUS status[ISC_STATUS_LENGTH];

    if (imp_dbh->tr)
    {
        DBI_TRACE_imp_xxh(imp_dbh, 3, (DBIc_LOGPIO(imp_dbh), "ib_start_transaction: trans handle already started.\n"));
        return TRUE;
    }

    /* MUST initialized to 0, before it is used */
    imp_dbh->tr = 0L;

    isc_start_transaction(status, &(imp_dbh->tr), 1, &(imp_dbh->db),
                          imp_dbh->tpb_length, imp_dbh->tpb_buffer);

    if (ib_error_check(h, status))
        return FALSE;

    DBI_TRACE_imp_xxh(imp_dbh, 3, (DBIc_LOGPIO(imp_dbh), "ib_start_transaction: transaction started.\n"));

    return TRUE;
}


int ib_commit_transaction(SV *h, imp_dbh_t *imp_dbh)
{
    ISC_STATUS status[ISC_STATUS_LENGTH];

    DBI_TRACE_imp_xxh(imp_dbh, 4, (DBIc_LOGPIO(imp_dbh), 
        "ib_commit_transaction: DBIcf_AutoCommit = %d, imp_dbh->sth_ddl = %d\n",
        DBIc_has(imp_dbh, DBIcf_AutoCommit), imp_dbh->sth_ddl));

    if (!imp_dbh->tr)
    {
        DBI_TRACE_imp_xxh(imp_dbh, 3, (DBIc_LOGPIO(imp_dbh), 
            "ib_commit_transaction: transaction already NULL.\n"));
        /* In case we switched to use different TPB before we actually use */
        /* This transaction handle                                         */
        imp_dbh->sth_ddl = 0;

        return TRUE;
    }

    /* do commit */
    if ((imp_dbh->sth_ddl == 0) && (imp_dbh->soft_commit))
    {
        DBI_TRACE_imp_xxh(imp_dbh, 2, (DBIc_LOGPIO(imp_dbh), "try isc_commit_retaining\n"));

        /* commit but don't close transaction */
        isc_commit_retaining(status, &(imp_dbh->tr));

        if (ib_error_check(h, status))
            return FALSE;
    }
    else
    {
        /* close all open statement handles */
        /* if ((imp_dbh->sth_ddl > 0) || !(DBIc_has(imp_dbh, DBIcf_AutoCommit))) */
        /* remark: only necessary when we have DDL statement(s) */
        if (imp_dbh->sth_ddl > 0)
        {
            while (imp_dbh->first_sth != NULL)
            {
                /* finish and destroy sth */
                dbd_st_finish((SV*)DBIc_MY_H(imp_dbh->first_sth), imp_dbh->first_sth);
                dbd_st_destroy(NULL, imp_dbh->first_sth);
            }

            imp_dbh->sth_ddl = 0;
        }

        DBI_TRACE_imp_xxh(imp_dbh, 2, (DBIc_LOGPIO(imp_dbh), "try isc_commit_transaction\n"));


        /* commit and close transaction (sets handle to NULL) */
        isc_commit_transaction(status, &(imp_dbh->tr));

        if (ib_error_check(h, status))
            return FALSE;

        imp_dbh->tr = 0L;
    }

    DBI_TRACE_imp_xxh(imp_dbh, 2, (DBIc_LOGPIO(imp_dbh), "ib_commit_transaction succeed.\n"));

    return TRUE;
}

int ib_rollback_transaction(SV *h, imp_dbh_t *imp_dbh)
{
    ISC_STATUS status[ISC_STATUS_LENGTH];

    DBI_TRACE_imp_xxh(imp_dbh, 2, (DBIc_LOGPIO(imp_dbh), "ib_rollback_transaction\n"));


    if (!imp_dbh->tr)
    {
        DBI_TRACE_imp_xxh(imp_dbh, 3, (DBIc_LOGPIO(imp_dbh), "ib_rollback_transaction: transaction already NULL.\n"));

        imp_dbh->sth_ddl = 0;

        return TRUE;
    }

/* no isc_rollback_retaining in IB prior to 6 */
#ifdef IB_API_V6
    if ((imp_dbh->sth_ddl == 0) && (imp_dbh->soft_commit))
    {
        DBI_TRACE_imp_xxh(imp_dbh, 2, (DBIc_LOGPIO(imp_dbh), "try isc_rollback_retaining\n"));

        /* rollback but don't close transaction */
        isc_rollback_retaining(status, &(imp_dbh->tr));

        if (ib_error_check(h, status))
            return FALSE;
    }
    else
#endif /* IB_API_V6 */
    {
        /* close all open statement handles */
        if ((imp_dbh->sth_ddl > 0) || !(DBIc_has(imp_dbh, DBIcf_AutoCommit)))
        {
            while (imp_dbh->first_sth != NULL)
            {
                /* finish and destroy sth */
                dbd_st_finish((SV*)DBIc_MY_H(imp_dbh->first_sth), imp_dbh->first_sth);
                dbd_st_destroy(NULL, imp_dbh->first_sth);
            }

            imp_dbh->sth_ddl = 0;
        }

        DBI_TRACE_imp_xxh(imp_dbh, 2, (DBIc_LOGPIO(imp_dbh), "try isc_rollback_transaction\n"));


        /* rollback and close transaction (sets handle to NULL) */
        isc_rollback_transaction(status, &(imp_dbh->tr));

        if (ib_error_check(h, status))
            return FALSE;

        imp_dbh->tr = 0L;
    }

    DBI_TRACE_imp_xxh(imp_dbh, 2, (DBIc_LOGPIO(imp_dbh), "ib_rollback_transaction succeed\n"));

    return TRUE;
}


int dbd_st_blob_read(SV *sth, imp_sth_t *imp_sth, int field,
    long offset, long len, SV *destrv, long destoffset)
{
    return FALSE;
}


int dbd_st_rows(SV* sth, imp_sth_t* imp_sth)
{
    /* spot common mistake of checking $h->rows just after ->execut
        if (imp_sth->fetched < 0
        && DBIc_WARN(imp_sth)
        ) {
        warn("$h->rows count is incomplete before all rows fetched.\n");
        }
    */
    if (imp_sth->type == isc_info_sql_stmt_select)
        return imp_sth->fetched;
    else
        return -1; /* unknown */
}

long ib_rows(SV *xxh, isc_stmt_handle *h_stmt, char count_type)
{
    ISC_STATUS status[ISC_STATUS_LENGTH];
    short l;
    char count_is;
    char count_info[1], count_buffer[33];
    char *p;
    long row_count = 0;

    count_info[0] = isc_info_sql_records;
    if (isc_dsql_sql_info(status, h_stmt,
                      sizeof(count_info), count_info,
                      sizeof(count_buffer), count_buffer))
    {
        if (ib_error_check(xxh, status))
            return -2;      /* error */
    }
    for (p = count_buffer + 3; *p != isc_info_end;) {
        count_is = *p++;
        l = (short) isc_vax_integer(p, 2);
        p += 2;
        row_count = (long) isc_vax_integer(p, l);
        p += l;
        if (count_is == count_type)
            break;
    }
    return row_count;
}

/* end */
