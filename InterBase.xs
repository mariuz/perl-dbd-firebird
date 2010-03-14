/*
   $Id: InterBase.xs 394 2008-01-08 05:29:19Z edpratomo $

   Copyright (c) 1999-2008  Edwin Pratomo
   Portions Copyright (c) 2001-2005  Daniel Ritz

   You may distribute under the terms of either the GNU General Public
   License or the Artistic License, as specified in the Perl README file,
   with the exception that it cannot be placed on a CD-ROM or similar media
   for commercial distribution without the prior approval of the author.

*/
/* vim: set noai ts=4 et sw=4: */

#include "InterBase.h"

DBISTATE_DECLARE;

static int _cancel_callback(SV *dbh, IB_EVENT *ev)
{
    ISC_STATUS status[ISC_STATUS_LENGTH];
    D_imp_dbh(dbh);

    int ret = 0;
    if (ev->exec_cb) 
        croak("Can't be called from inside a callback");
    if (ev->perl_cb) {
        ev->state = INACTIVE;
        SvREFCNT_dec(ev->perl_cb);
        ev->perl_cb = (SV*)NULL;
        isc_cancel_events(status, &(imp_dbh->db), &(ev->id));
        if (ib_error_check(dbh, status))
            ret = 0;
        else
            ret = 1;
    } else 
        croak("No callback found for this event handle. Have you called ib_register_callback?");
    return ret;
}

static int _call_perlsub(IB_EVENT ISC_FAR *ev, short length, 
#if defined(INCLUDE_TYPES_PUB_H)
const ISC_UCHAR *updated
#else
char ISC_FAR *updated
#endif
)
{
    int retval = 1;
#if defined(USE_THREADS) || defined(USE_ITHREADS) || defined(MULTIPLICITY)
    /* save context, set context from dbh */
    void *context = PERL_GET_CONTEXT;
    PERL_SET_CONTEXT(ev->dbh->context);
    {
#else
    void *context = PERL_GET_CONTEXT;
    PerlInterpreter *cb_perl = perl_alloc();
    PERL_SET_CONTEXT(cb_perl);
    {
#endif
        dSP;
        int i, count;
        SV **svp;
        HV *posted_events = newHV();
        ISC_ULONG ecount[15];
#if defined(INCLUDE_TYPES_PUB_H)
        ISC_UCHAR *result = ev->result_buffer;
#else
        char ISC_FAR *result = ev->result_buffer;
#endif

        while (length--)
            *result++ = *updated++;
        isc_event_counts(ecount, ev->epb_length, ev->event_buffer,
                         ev->result_buffer);
        for (i = 0; i < ev->num; i++) 
        {
            if (ecount[i])
            {
                svp = hv_store(posted_events, *(ev->names + i), strlen(*(ev->names + i)),
                               newSViv(ecount[i]), 0);
                if (svp == NULL)
                    croak("Bad: key '%s' not stored", *(ev->names + i));
            }
        }
        ENTER;
        SAVETMPS;
        PUSHMARK(SP);
        XPUSHs(sv_2mortal(newRV_noinc((SV*)posted_events)));
        PUTBACK;
        count = perl_call_sv(ev->perl_cb, G_SCALAR);
        SPAGAIN;
        if (count > 0) 
            retval = POPi;
        PUTBACK;
        FREETMPS;
        LEAVE;
#if defined(USE_THREADS) || defined(USE_ITHREADS) || defined(MULTIPLICITY)
    }

    /* restore old context*/
    PERL_SET_CONTEXT(context);
#else
    }
    PERL_SET_CONTEXT(context);
    perl_free(cb_perl);
#endif
    return retval;
}

/* callback function for events, called by InterBase */
/* static isc_callback _async_callback(IB_EVENT ISC_FAR *ev, short length, char ISC_FAR *updated) */
static ISC_EVENT_CALLBACK _async_callback(IB_EVENT ISC_FAR *ev, 
#if defined(INCLUDE_TYPES_PUB_H)
ISC_USHORT length, const ISC_UCHAR *updated
#else
short length, char ISC_FAR *updated
#endif
)
{
    ISC_STATUS status[ISC_STATUS_LENGTH];

    switch (ev->state) {
    case INACTIVE:
        break;
    case ACTIVE:
        ev->exec_cb = 1;
        if (_call_perlsub(ev, length, updated) == 0) {
            ev->state = INACTIVE;
            ev->exec_cb = 0;
            break;
        }
        ev->exec_cb = 0;
        isc_que_events(
            status,
            &(ev->dbh->db),
            &(ev->id),
            ev->epb_length,
            ev->event_buffer,
            (ISC_EVENT_CALLBACK)_async_callback,
            ev
        );
    }
    return (0);
}


MODULE = DBD::InterBase     PACKAGE = DBD::InterBase

INCLUDE: InterBase.xsi

MODULE = DBD::InterBase     PACKAGE = DBD::InterBase::db

void
_do(dbh, statement, attr=Nullsv)
    SV *        dbh
    SV *    statement
    SV *        attr
  PROTOTYPE: $$;$@
  CODE:
{
    D_imp_dbh(dbh);
    ISC_STATUS status[ISC_STATUS_LENGTH]; /* isc api status vector    */
    STRLEN     slen;
    int        retval;
    char       *sbuf = SvPV(statement, slen);

    DBI_TRACE_imp_xxh(imp_dbh, 1, (DBIc_LOGPIO(imp_dbh), "db::_do\n" "Executing : %s\n", sbuf));

    /* we need an open transaction */
    if (!imp_dbh->tr)
    {
        DBI_TRACE_imp_xxh(imp_dbh, 1, (DBIc_LOGPIO(imp_dbh), "starting new transaction..\n"));

        if (!ib_start_transaction(dbh, imp_dbh))
        {
            retval = -2;
            XST_mUNDEF(0);      /* <= -2 means error        */
            return;
        }

        DBI_TRACE_imp_xxh(imp_dbh, 1, (DBIc_LOGPIO(imp_dbh), "new transaction started.\n"));
    }

    /* we need to count the DDL statement whether in soft / hard commit */
#if 0
    /* only execute_immediate statment if NOT in soft commit mode */
    if (!(imp_dbh->soft_commit))
    {
        isc_dsql_execute_immediate(status, &(imp_dbh->db), &(imp_dbh->tr), 0,
                                   sbuf, imp_dbh->sqldialect, NULL);

        if (ib_error_check(dbh, status))
            retval = -2;
        else
            retval = -1 ;
    }
    else
#endif
    /* count DDL statements is necessary for ib_commit_transaction to work properly */
    {
        isc_stmt_handle stmt = 0L;        /* temp statment handle */
        static char     stmt_info[] = { isc_info_sql_stmt_type };
        char            info_buffer[20];  /* statment info buffer */

        retval = -2;

        do
        {
            /* init statement handle */
            if (isc_dsql_alloc_statement2(status, &(imp_dbh->db), &stmt))
                break;

            /* prepare statement */
            isc_dsql_prepare(status, &(imp_dbh->tr), &stmt, 0, sbuf,
                             imp_dbh->sqldialect, NULL);
            if (ib_error_check(dbh, status))
                break;

            /* get statement type */
            if (!isc_dsql_sql_info(status, &stmt, sizeof(stmt_info), stmt_info,
                              sizeof(info_buffer), info_buffer))
            {
                /* need to count DDL statments */
                short l = (short) isc_vax_integer((char *) info_buffer + 1, 2);
                if (isc_vax_integer((char *) info_buffer + 3, l) == isc_info_sql_stmt_ddl)
                    imp_dbh->sth_ddl++;
            }
            else
                break;

            /* exec the statement */
            isc_dsql_execute(status, &(imp_dbh->tr), &stmt, imp_dbh->sqldialect, NULL);
            if (!ib_error_check(dbh, status))
                retval = -1;

        } while (0);

        /* close statement */
        if (stmt)
           isc_dsql_free_statement(status, &stmt, DSQL_drop);

        if (retval != -2) retval = -1;
    }

    /* for AutoCommit: commit */
    if (DBIc_has(imp_dbh, DBIcf_AutoCommit))
    {
        if (!ib_commit_transaction(dbh, imp_dbh))
            retval = -2;
    }

    if (retval < -1)
        XST_mUNDEF(0);
    else
        XST_mIV(0, retval); /* typically 1, rowcount or -1  */
}

void
_ping(dbh)
    SV *    dbh
    CODE:
{
    int ret;
    ret = dbd_db_ping(dbh);
    if (ret == 0)
        XST_mUNDEF(0);
    else
        XST_mIV(0, ret);
}

#define TX_INFOBUF(name, len) \
if (strEQ(item, #name)) { \
    *p++ = (char) isc_info_tra_##name; \
    res_len += len + 3; \
    item_buf_len++; \
    continue; \
}

#define TX_RESBUF_CASE(name) \
case isc_info_tra_##name:\
{\
    keyname = #name;\
    /* PerlIO_printf(PerlIO_stderr(), "Got %s\n", keyname); */\
    p++;\
    length = isc_vax_integer (p, 2);\
    p += 2;\
    (void)hv_store(RETVAL, keyname, strlen(keyname), \
             newSViv(isc_vax_integer(p, (short) length)), 0);\
    p += length;\
    break;\
}

HV*
ib_tx_info(dbh)
    SV* dbh
    PREINIT:
    char* p;
    char* result = NULL;
    short result_length = 0;
    ISC_STATUS status[ISC_STATUS_LENGTH];
    CODE:
{
    D_imp_dbh(dbh);
    char request[] = {
        isc_info_tra_id, 
#if defined(FB_API_VER) && FB_API_VER >= 20
        /* FB 2.0: */
        isc_info_tra_oldest_interesting,
        isc_info_tra_oldest_active,
        isc_info_tra_oldest_snapshot,
        isc_info_tra_lock_timeout,
        isc_info_tra_isolation,
        isc_info_tra_access,
#endif
        isc_info_end
    };

    RETVAL = newHV();
    if (!RETVAL) {
        if (result) {
            Safefree(result);
        }
        do_error(dbh, 2, "unable to allocate hash return value");
        XSRETURN_UNDEF;
    }

    if (!imp_dbh->tr) {
        do_error(dbh, 2, "No active transaction");
        XSRETURN_UNDEF;
    } 
    
    /* calc required result buffer size */
    for (p = request; *p != isc_info_end; p++) {
        result_length++; /* identifier (1 byte)*/
        switch (*p) {
#if defined(FB_API_VER) && FB_API_VER >= 20
            case isc_info_tra_isolation:
                /* result: 
                length (2 bytes) + first content (1 byte) +
                length (2 bytes) + second content (2 bytes max)
                */
                result_length += 7;
                break;
            case isc_info_tra_access:
                /* result:
                length (2 bytes) + content (1 byte)
                */
                result_length += 3;
                break;
#endif
            default:
                result_length += 2; /* length (2 bytes) */
                result_length += 4; /* pessimistic */
        }
    }

    result_length += 1; /* add 1 byte for isc_info_end */
    /* try insufficient result_length:
    result_length = 40;
    */
    
  try_alloc_result_buffer:
    Newxz(result, result_length, char);
    /* PerlIO_printf(PerlIO_stderr(), "result_length: %d\n", result_length); */

    /* call */
    isc_transaction_info(status, &(imp_dbh->tr), 
                         sizeof(request), request, 
                         result_length, result);

    if (ib_error_check(dbh, status)) {
        XSRETURN_UNDEF;
    } else {
        /* detect truncation */
        for (p = result + result_length - 1; p > result; p--) {
            if (*p != 0) {
                break;
            }
        }
        if (p > result) {
            /* PerlIO_printf(PerlIO_stderr(), "First non-null byte found at: %d\n", (p - result)); */
            if (*p == isc_info_truncated) {
                /* PerlIO_printf(PerlIO_stderr(), "Truncation detected.\n"); */

                /* increase result_length, retry allocation */
                result_length += 10;
                Safefree(result);
                result = NULL;
                goto try_alloc_result_buffer;
            }
        }

        /* parse result */
        for (p = result; p < result + result_length; ) {
            char *keyname;
            short length;
            if (*p == isc_info_end) {
                /* PerlIO_printf(PerlIO_stderr(), "isc_info_end encountered at byte: %d\n", (p - result)); */
                break;
            }
            switch (*p) {
                TX_RESBUF_CASE(id)
#if defined(FB_API_VER) && FB_API_VER >= 20
                TX_RESBUF_CASE(oldest_interesting)
                TX_RESBUF_CASE(oldest_active)
                TX_RESBUF_CASE(oldest_snapshot)
                TX_RESBUF_CASE(lock_timeout)
                case isc_info_tra_isolation:
                {
                    keyname = "isolation";
                    HV* reshv;

                    /* PerlIO_printf(PerlIO_stderr(), "Got 'isolation' at byte: %d\n", (p - result)); */
                    ++p;
                    short length = isc_vax_integer(p, 2);
                    p += 2;
                    /* PerlIO_printf(PerlIO_stderr(), "Content length: %d\n", length); */
                    
                    if (*p == isc_info_tra_consistency) {
                        (void)hv_store(RETVAL, keyname, strlen(keyname), newSVpv("consistency", 0), 0);
                    } else if (*p == isc_info_tra_concurrency) {
                        (void)hv_store(RETVAL, keyname, strlen(keyname), newSVpv("snapshot (concurrency)", 0), 0);
                    } else if (*p == isc_info_tra_read_committed) {
                        /* warn("got 'read_committed'"); */
                        reshv = newHV();
                        if (!reshv) {
                            if (result) {
                                Safefree(result);
                            }
                            do_error(dbh, 2, "unable to allocate hash for read_committed rec/no_rec version");
                            XSRETURN_UNDEF;
                        }
                        if (*(p + 1) == isc_info_tra_no_rec_version) {
                            (void)hv_store(reshv, "read_committed", 14, newSVpv("no_rec_version", 0), 0);
                        } else if (*(p + 1) == isc_info_tra_rec_version) {
                            (void)hv_store(reshv, "read_committed", 14, newSVpv("rec_version", 0), 0);
                        } else {
                            warn("unrecognized byte");
                            continue;
                        }
                        (void)hv_store(RETVAL, keyname, strlen(keyname),
                                 newRV_noinc((SV*) reshv), 0);

                    } else {
                        PerlIO_printf(PerlIO_stderr(), "+2: got unrecognized byte: %d\n", *((char*)p));
                    }
                    p += length;
                    break;
                }
                case isc_info_tra_access: {
                    keyname = "access";
                    /* PerlIO_printf(PerlIO_stderr(), "Got 'access' at byte: %d\n", (p - result)); */
                    p++;
                    short length = isc_vax_integer(p, 2);
                    p += 2;
                    if (*p == isc_info_tra_readonly) {
                        (void)hv_store(RETVAL, keyname, strlen(keyname), newSVpvn("readonly", 8), 0);
                    } else if (*p == isc_info_tra_readwrite) {
                        (void)hv_store(RETVAL, keyname, strlen(keyname), newSVpvn("readwrite", 9), 0);
                    }
                    p += length;
                    break;
                }
#endif
                default:
                    /* PerlIO_printf(PerlIO_stderr(), "now at byte: %d\n", (p - result)); */
                    p++;
            }
        }
    }
}
    OUTPUT: 
    RETVAL
    CLEANUP:
    SvREFCNT_dec(RETVAL);

#undef TX_INFOBUF
#undef TX_RESBUF_CASE

int
ib_set_tx_param(dbh, ...)
    SV *dbh
    ALIAS:
    set_tx_param = 1
    PREINIT:
    STRLEN len;
    char   *tx_key, *tx_val, *tpb, *tmp_tpb;
    int    i, rc = 0;
    int    tpb_len;
    char   am_set = 0, il_set = 0, ls_set = 0;
    I32    j;
    AV     *av;
    HV     *hv;
    SV     *sv, *sv_value;
    HE     *he;

    CODE:
{
    D_imp_dbh(dbh);
#ifdef PERL_UNUSED_VAR
    PERL_UNUSED_VAR(ix); /* -Wall */
#endif
    /* if no params or first parameter = 0 or undef -> reset TPB to NULL */
    if (items < 3)
    {
        if ((items == 1) || !(SvTRUE(ST(1))))
        {
            tpb     = NULL;
            tmp_tpb = NULL;
            tpb_len = 0;
            goto do_set_tpb;
        }
    }

    /* we need to know the max. size of TBP, (buffer overflow problem) */
    /* mem usage: -access_mode:     max. 1 byte                        */
    /*            -isolation_level: max. 2 bytes                       */
    /*            -lock_resolution: max. 1 byte                        */
    /*            -reserving:       max. 4 bytes + strlen(tablename)   */
    tpb_len = 5; /* 4 + 1 for tpb_version                              */

    /* we need to add the length of each table name + 4 bytes */
    for (i = 1; i < items-1; i += 2)
    {
        sv_value = ST(i + 1);
        if (strEQ(SvPV_nolen(ST(i)), "-reserving"))
            if (SvROK(sv_value) && SvTYPE(SvRV(sv_value)) == SVt_PVHV)
            {
                hv = (HV *)SvRV(sv_value);
                hv_iterinit(hv);
                while ((he = hv_iternext(hv)))
                {
                    /* retrieve the size of table name(s) */
                    HePV(he, len);
                    tpb_len += len + 4;
                }
            }
    }

    /* alloc it */
	Newx(tmp_tpb, tpb_len, char);

    /* do set TPB values */
    tpb = tmp_tpb;
    *tpb++ = isc_tpb_version3;

    for (i = 1; i < items; i += 2)
    {
        tx_key   = SvPV_nolen(ST(i));
        sv_value = ST(i + 1);

        /* value specified? */
        if (i >= items - 1)
        {
            Safefree(tmp_tpb);
            croak("You must specify parameter => value pairs, but theres no value for %s", tx_key);
        }

        /**********************************************************************/
        if (strEQ(tx_key, "-access_mode"))
        {
            if (am_set)
            {
                warn("-access_mode already set; ignoring second try!");
                continue;
            }

            tx_val = SvPV_nolen(sv_value);
            if (strEQ(tx_val, "read_write"))
                *tpb++ = isc_tpb_write;
            else if (strEQ(tx_val, "read_only"))
                *tpb++ = isc_tpb_read;
            else
            {
                Safefree(tmp_tpb);
                croak("Unknown -access_mode value %s", tx_val);
            }

            am_set = 1; /* flag */
        }
        /**********************************************************************/
        else if (strEQ(tx_key, "-isolation_level"))
        {
            if (il_set)
            {
                warn("-isolation_level already set; ignoring second try!");
                continue;
            }

            if (SvROK(sv_value) && SvTYPE(SvRV(sv_value)) == SVt_PVAV)
            {
                av = (AV *)SvRV(sv_value);

                /* sanity check */
                for (j = 0; (j <= av_len(av)) && !rc; j++)
                {
                    sv = *av_fetch(av, j, FALSE);
                    if (strEQ(SvPV_nolen(sv), "read_committed"))
                    {
                        rc = 1;
                        *tpb++ = isc_tpb_read_committed;
                    }
                }

                if (!rc)
                {
                    Safefree(tmp_tpb);
                    croak("Invalid -isolation_level value");
                }

                for (j = 0; j <= av_len(av); j++)
                {
                    tx_val = SvPV_nolen(*(av_fetch(av, j, FALSE)));
                    if (strEQ(tx_val, "record_version"))
                    {
                        *tpb++ = isc_tpb_rec_version;
                        break;
                    }
                    else if (strEQ(tx_val, "no_record_version"))
                    {
                        *tpb++ = isc_tpb_no_rec_version;
                        break;
                    }
                    else if (!strEQ(tx_val, "read_committed"))
                    {
                        Safefree(tmp_tpb);
                        croak("Unknown -isolation_level value %s", tx_val);
                    }
                }
            }
            else
            {
                tx_val = SvPV_nolen(sv_value);
                if (strEQ(tx_val, "read_committed"))
                    *tpb++ = isc_tpb_read_committed;
                else if (strEQ(tx_val, "snapshot"))
                    *tpb++ = isc_tpb_concurrency;
                else if (strEQ(tx_val, "snapshot_table_stability"))
                    *tpb++ = isc_tpb_consistency;
                else
                {
                    Safefree(tmp_tpb);
                    croak("Unknown -isolation_level value %s", tx_val);
                }
            }

            il_set = 1; /* flag */
        }
        /**********************************************************************/
        else if (strEQ(tx_key, "-lock_resolution"))
        {
            if (ls_set)
            {
                warn("-lock_resolution already set; ignoring second try!");
                continue;
            }

            if (SvROK(sv_value) && SvTYPE(SvRV(sv_value)) == SVt_PVHV) {
#if defined(FB_API_VER) && FB_API_VER >= 20
                hv = (HV *)SvRV(sv_value);
                if (hv_exists(hv, "wait", 4)) {
                    *tpb++ = isc_tpb_wait;
                    sv = *hv_fetch(hv, "wait", 4, FALSE);
                    if (SvIOK(sv)) {
                        IV lock_timeout = SvIV(sv);
                        if (lock_timeout < 0) {
                            do_error(dbh, 2, "Wait timeout value must be positive integer");
                            XSRETURN_UNDEF;
                        } else if (lock_timeout > 0) {
                            *tpb++ = isc_tpb_lock_timeout;
                            *tpb++ = sizeof(ISC_LONG);      /* length = 4 bytes */
                            *(ISC_LONG*)tpb = lock_timeout; /* infinite timeout */
                            tpb += sizeof(ISC_LONG);
                        }
                    } else {
                        do_error(dbh, 2, "Wait timeout value must be positive integer");
                        XSRETURN_UNDEF;
                    }
                } else {
                    do_error(dbh, 2, "The only valid key is 'wait'");
                    XSRETURN_UNDEF;
                }
#else
                do_error(dbh, 2, "Hashref unsupported. Must be compiled with Firebird 2.0 client library");
                XSRETURN_UNDEF;
#endif
            } else {
                tx_val = SvPV_nolen(sv_value);
                if (strEQ(tx_val, "wait"))
                    *tpb++ = isc_tpb_wait;
                else if (strEQ(tx_val, "no_wait"))
                    *tpb++ = isc_tpb_nowait;
                else
                {
                    Safefree(tmp_tpb);
                    croak("Unknown transaction parameter %s", tx_val);
                }
            }
            ls_set = 1; /* flag */
        }
        /**********************************************************************/
        else if (strEQ(tx_key, "-reserving"))
        {
            if (SvROK(sv_value) && SvTYPE(SvRV(sv_value)) == SVt_PVHV)
            {
                char *table_name;
                HV *table_opts;
                hv = (HV *)SvRV(sv_value);
                hv_iterinit(hv);
                while ((he = hv_iternext(hv)))
                {
                    /* check val type */
                    if (SvROK(HeVAL(he)) && SvTYPE(SvRV(HeVAL(he))) == SVt_PVHV)
                    {
                        table_opts = (HV*)SvRV(HeVAL(he));

                        if (hv_exists(table_opts, "access", 6))
                        {
                            /* access is optional */
                            sv = *hv_fetch(table_opts, "access", 6, FALSE);
                            if (strnEQ(SvPV_nolen(sv), "shared", 6))
                                *tpb++ = isc_tpb_shared;
                            else if (strnEQ(SvPV_nolen(sv), "protected", 9))
                                *tpb++ = isc_tpb_protected;
                            else
                            {
                                Safefree(tmp_tpb);
                                croak("Invalid -reserving access value");
                            }
                        }

                        if (hv_exists(table_opts, "lock", 4))
                        {
                            /* lock is required */
                            sv = *hv_fetch(table_opts, "lock", 4, FALSE);
                            if (strnEQ(SvPV_nolen(sv), "read", 4))
                               *tpb++ = isc_tpb_lock_read;
                            else if (strnEQ(SvPV_nolen(sv), "write", 5))
                               *tpb++ = isc_tpb_lock_write;
                            else
                            {
                              Safefree(tmp_tpb);
                              croak("Invalid -reserving lock value");
                            }
                        }
                        else /* lock */
                        {
                            Safefree(tmp_tpb);
                            croak("Lock value is required in -reserving");
                        }

                        /* add the table name to TPB */
                        table_name = HePV(he, len);
                        *tpb++ = len + 1;
                        {
                            unsigned int k;
                            for (k = 0; k < len; k++)
                                *tpb++ = toupper(*table_name++);
                        }
                        *tpb++ = 0;
                    } /* end hashref check*/
                    else
                    {
                        Safefree(tmp_tpb);
                        croak("Reservation for a given table must be hashref.");
                    }
                } /* end of while() */
            }
            else
            {
                Safefree(tmp_tpb);
                croak("Invalid -reserving value. Must be hashref.");
            }
        } /* end table reservation */
        else
        {
            Safefree(tmp_tpb);
            croak("Unknown transaction parameter %s", tx_key);
        }
    }

    /* an ugly label... */
    do_set_tpb:

    Safefree(imp_dbh->tpb_buffer);
    imp_dbh->tpb_buffer = tmp_tpb;
    imp_dbh->tpb_length = tpb - imp_dbh->tpb_buffer;

    /* for AutoCommit: commit current transaction */
    if (DBIc_has(imp_dbh, DBIcf_AutoCommit))
    {
        imp_dbh->sth_ddl++;
        ib_commit_transaction(dbh, imp_dbh);
    }
    RETVAL = 1;
}
    OUTPUT:
    RETVAL

#*******************************************************************************

# only for use within database_info!
#define DB_INFOBUF(name, len) \
if (strEQ(item, #name)) { \
    *p++ = (char) isc_info_##name; \
    res_len += len + 3; \
    item_buf_len++; \
    continue; \
}

#define DB_RESBUF_CASEHDR(name) \
case isc_info_##name:\
    keyname = #name;


HV *
ib_database_info(dbh, ...)
    SV *dbh
    PREINIT:
    unsigned int i, count;
    char  item_buf[30], *p, *old_p;
    char *res_buf;
    short item_buf_len, res_len;
    AV    *av;
    ISC_STATUS status[ISC_STATUS_LENGTH];
    CODE:
{
    D_imp_dbh(dbh);

    /* process input params, count max. result buffer length */
    p = item_buf;
    res_len = 0;
    item_buf_len = 0;

    /* array or array ref? */
    if (items == 2 && SvROK(ST(1)) && SvTYPE(SvRV(ST(1))) == SVt_PVAV)
    {
        av    = (AV *)SvRV(ST(1));
        count = av_len(av) + 1;
    }
    else
    {
        av    = NULL;
        count = items;
    }

    /* loop thru all elements */
    for (i = 0; i < count; i++)
    {
        char *item;

        /* fetch from array or array ref? */
        if (av)
            item = SvPV_nolen(*av_fetch(av, i, FALSE));
        else
            item = SvPV_nolen(ST(i + 1));

        /* database characteristics */
        DB_INFOBUF(allocation,        4);
        DB_INFOBUF(base_level,        2);
        DB_INFOBUF(db_id,           513);
        DB_INFOBUF(implementation,    3);
        DB_INFOBUF(no_reserve,        1);
#ifdef IB_API_V6
        DB_INFOBUF(db_read_only,      1);
#endif
        DB_INFOBUF(ods_minor_version, 1);
        DB_INFOBUF(ods_version,       1);
        DB_INFOBUF(page_size,         4);
        DB_INFOBUF(version,         257);
#ifdef IB_API_V6
        DB_INFOBUF(db_sql_dialect,    1);
#endif

        /* environmental characteristics */
        DB_INFOBUF(current_memory,    4);
        DB_INFOBUF(forced_writes,     1);
        DB_INFOBUF(max_memory,        4);
        DB_INFOBUF(num_buffers,       4);
        DB_INFOBUF(sweep_interval,    4);
        DB_INFOBUF(user_names,     1024); /* can be more, can be less */

        /* performance statistics */
        DB_INFOBUF(fetches, 4);
        DB_INFOBUF(marks,   4);
        DB_INFOBUF(reads,   4);
        DB_INFOBUF(writes,  4);
#if defined(FB_API_VER) && FB_API_VER >= 20
        /* FB 2.0 */
        DB_INFOBUF(active_tran_count, 4);
        DB_INFOBUF(creation_date,     sizeof(ISC_TIMESTAMP)); /* 2 x 4 bytes */
#endif
        /* database operation counts */
        /* XXX - not implemented (complicated: returns a descriptor for _each_
           table...how to fetch / store this??) but do we really need these? */
    }

    /* the end marker */
    *p++ = isc_info_end;
    item_buf_len++;

    /* allocate the result buffer */
    res_len += 256; /* add some safety...just in case */
	Newx(res_buf, res_len, char);

    /* call the function */
    isc_database_info(status, &(imp_dbh->db), item_buf_len, item_buf,
                      res_len, res_buf);

    if (ib_error_check(dbh, status))
    {
        Safefree(res_buf);
        XSRETURN_UNDEF; // croak("isc_database_info failed!");
    }

    /* fill hash with key/value pairs */
    RETVAL = newHV();
    for (p = res_buf; *p != isc_info_end; )
    {
        char *keyname;
        char item   = *p++;
        int  length = isc_vax_integer (p, 2);
        p += 2;
        old_p = p;

        switch (item)
        {
            /******************************************************************/
            /* database characteristics */
            DB_RESBUF_CASEHDR(allocation)
                (void)hv_store(RETVAL, keyname, strlen(keyname),
                         newSViv(isc_vax_integer(p, (short) length)), 0);
                break;

            DB_RESBUF_CASEHDR(base_level)
                (void)hv_store(RETVAL, keyname, strlen(keyname),
                         newSViv(isc_vax_integer(++p, 1)), 0);
                break;

            DB_RESBUF_CASEHDR(db_id)
            {
                HV *reshv = newHV();
                ISC_LONG slen;

                (void)hv_store(reshv, "connection", 10,
                         (isc_vax_integer(p++, 1) == 2)?
                             newSVpv("local", 0):
                             newSVpv("remote", 0),
                         0);

                slen = isc_vax_integer(p++, 1);
                (void)hv_store(reshv, "database", 8, newSVpvn(p, slen), 0);
                p += slen;

                slen = isc_vax_integer(p++, 1);
                (void)hv_store(reshv, "site", 8, newSVpvn(p, slen), 0);

                (void)hv_store(RETVAL, keyname, strlen(keyname),
                         newRV_noinc((SV *) reshv), 0);
                break;
            }

            DB_RESBUF_CASEHDR(implementation)
            {
                HV *reshv = newHV();

                (void)hv_store(reshv, "implementation", 14,
                         newSViv(isc_vax_integer(++p, 1)), 0);

                (void)hv_store(reshv, "class", 5,
                         newSViv(isc_vax_integer(++p, 1)), 0);

                (void)hv_store(RETVAL, keyname, strlen(keyname),
                         newRV_noinc((SV *) reshv), 0);

                break;
            }

            DB_RESBUF_CASEHDR(no_reserve)
                (void)hv_store(RETVAL, keyname, strlen(keyname),
                         newSViv(isc_vax_integer(p, (short) length)), 0);
                break;
#ifdef IB_API_V6
            DB_RESBUF_CASEHDR(db_read_only)
                (void)hv_store(RETVAL, keyname, strlen(keyname),
                         newSViv(isc_vax_integer(p, (short) length)), 0);
                break;
#endif
            DB_RESBUF_CASEHDR(ods_minor_version)
                (void)hv_store(RETVAL, keyname, strlen(keyname),
                         newSViv(isc_vax_integer(p, (short) length)), 0);
                break;

            DB_RESBUF_CASEHDR(ods_version)
                (void)hv_store(RETVAL, keyname, strlen(keyname),
                         newSViv(isc_vax_integer(p, (short) length)), 0);
                break;

            DB_RESBUF_CASEHDR(page_size)
                (void)hv_store(RETVAL, keyname, strlen(keyname),
                         newSViv(isc_vax_integer(p, (short) length)), 0);
                break;

            DB_RESBUF_CASEHDR(version)
            {
                ISC_LONG slen;
                slen = isc_vax_integer(++p, 1);
                (void)hv_store(RETVAL, keyname, strlen(keyname),
                         newSVpvn(++p, slen), 0);
                break;
            }
#ifdef isc_dpb_sql_dialect
            DB_RESBUF_CASEHDR(db_sql_dialect)
                (void)hv_store(RETVAL, keyname, strlen(keyname),
                         newSViv(isc_vax_integer(p, (short) length)), 0);
                break;
#endif

            /******************************************************************/
            /* environmental characteristics */
            DB_RESBUF_CASEHDR(current_memory)
                (void)hv_store(RETVAL, keyname, strlen(keyname),
                         newSViv(isc_vax_integer(p, (short) length)), 0);
                break;

            DB_RESBUF_CASEHDR(forced_writes)
                (void)hv_store(RETVAL, keyname, strlen(keyname),
                         newSViv(isc_vax_integer(p, (short) length)), 0);
                break;

            DB_RESBUF_CASEHDR(max_memory)
                (void)hv_store(RETVAL, keyname, strlen(keyname),
                         newSViv(isc_vax_integer(p, (short) length)), 0);
                break;

            DB_RESBUF_CASEHDR(num_buffers)
                (void)hv_store(RETVAL, keyname, strlen(keyname),
                         newSViv(isc_vax_integer(p, (short) length)), 0);
                break;

            DB_RESBUF_CASEHDR(sweep_interval)
                (void)hv_store(RETVAL, keyname, strlen(keyname),
                         newSViv(isc_vax_integer(p, (short) length)), 0);
                break;

            DB_RESBUF_CASEHDR(user_names)
            {
                AV *avres;
                SV **svp;
                ISC_LONG slen;

                /* array already existing? no -> create */
                if (!hv_exists(RETVAL, "user_names", 10))
                {
                    avres = newAV();
                    (void)hv_store(RETVAL, "user_names", 10,
                             newRV_noinc((SV *) avres), 0);
                }
                else
                {
                    svp = hv_fetch(RETVAL, "user_names", 10, 0);
                    if (!svp || !SvROK(*svp))
                    {
                        Safefree(res_buf);
                        croak("Error fetching hash value");
                    }

                    avres = (AV *) SvRV(*svp);
                }

                /* add value to the array */
                slen = isc_vax_integer(p++, 1);
                av_push(avres, newSVpvn(p, slen));

                break;
            }

            /******************************************************************/
            /* performance statistics */
            DB_RESBUF_CASEHDR(fetches)
                (void)hv_store(RETVAL, keyname, strlen(keyname),
                         newSViv(isc_vax_integer(p, (short) length)), 0);
                break;

            DB_RESBUF_CASEHDR(marks)
                (void)hv_store(RETVAL, keyname, strlen(keyname),
                         newSViv(isc_vax_integer(p, (short) length)), 0);
                break;

            DB_RESBUF_CASEHDR(reads)
                (void)hv_store(RETVAL, keyname, strlen(keyname),
                         newSViv(isc_vax_integer(p, (short) length)), 0);
                break;

            DB_RESBUF_CASEHDR(writes)
                (void)hv_store(RETVAL, keyname, strlen(keyname),
                         newSViv(isc_vax_integer(p, (short) length)), 0);
                break;
#if defined(FB_API_VER) && FB_API_VER >= 20
            /* FB 2.0 */
            DB_RESBUF_CASEHDR(active_tran_count)
                (void)hv_store(RETVAL, keyname, strlen(keyname),
                        newSViv(isc_vax_integer(p, (short) length)), 0);
                break;

            DB_RESBUF_CASEHDR(creation_date)
            {
                struct tm times;
                ISC_TIMESTAMP cdatetime;
                char tbuf[100];
				Zero(tbuf, sizeof(tbuf), char);
                cdatetime.timestamp_date = isc_vax_integer(p, sizeof(ISC_DATE));
                cdatetime.timestamp_time = isc_vax_integer(p + sizeof(ISC_DATE), sizeof(ISC_TIME));
                isc_decode_timestamp(&cdatetime, &times);
                strftime(tbuf, sizeof(tbuf), "%c", &times);
                (void)hv_store(RETVAL, keyname, strlen(keyname),
                         newSVpvn(tbuf, strlen(tbuf)), 0);
                break;
            }
#endif

            default:
                break;
        }

        p = old_p + length;
    }

    /* don't leak */
    Safefree(res_buf);
}
    OUTPUT:
    RETVAL

    CLEANUP:
    SvREFCNT_dec(RETVAL);

#undef DB_INFOBUF
#undef DB_RESBUF_CASEHDR

#*******************************************************************************

IB_EVENT *
ib_init_event(dbh, ...)
    SV *dbh
    PREINIT:
    char *CLASS = "DBD::InterBase::Event";
    int i;
    D_imp_dbh(dbh);
    CODE:
{
    unsigned short cnt = items - 1;

    DBI_TRACE_imp_xxh(imp_dbh, 2, (DBIc_LOGPIO(imp_dbh), "Entering init_event(), %d items..\n", cnt));

    if (cnt > 0)
    {
        /* check for max number of events in a single call to event block allocation */
        if (cnt > MAX_EVENTS)
            croak("Max number of events exceeded.");

		Newx(RETVAL, 1, IB_EVENT);

        /* init members */
        RETVAL->dbh           = imp_dbh;
        RETVAL->event_buffer  = NULL;
        RETVAL->result_buffer = NULL;
        RETVAL->id            = 0;
        RETVAL->num           = cnt;
        RETVAL->perl_cb       = NULL;
        RETVAL->state         = INACTIVE;
        RETVAL->exec_cb       = 0;

		Newx(RETVAL->names, MAX_EVENTS, char *);

        for (i = 0; i < MAX_EVENTS; i++)
        {
            if (i < cnt) {
                /* dangerous! 
                *(RETVAL->names + i) = SvPV_nolen(ST(i + 1));
                */
				Newx(RETVAL->names[i], SvCUR(ST(i + 1)) + 1, char);
                strcpy(RETVAL->names[i], SvPV_nolen(ST(i + 1)));
            }
            else
                *(RETVAL->names + i) = NULL;
        }

        RETVAL->epb_length = (short) isc_event_block(
            &(RETVAL->event_buffer),
            &(RETVAL->result_buffer),
            cnt,
            *(RETVAL->names +  0),
            *(RETVAL->names +  1),
            *(RETVAL->names +  2),
            *(RETVAL->names +  3),
            *(RETVAL->names +  4),
            *(RETVAL->names +  5),
            *(RETVAL->names +  6),
            *(RETVAL->names +  7),
            *(RETVAL->names +  8),
            *(RETVAL->names +  9),
            *(RETVAL->names + 10),
            *(RETVAL->names + 11),
            *(RETVAL->names + 12),
            *(RETVAL->names + 13),
            *(RETVAL->names + 14));
    }
    else
        croak("Names of the events in interest are not specified");
    {
        ISC_STATUS status[ISC_STATUS_LENGTH];
		ISC_ULONG ecount[15];
        isc_wait_for_event(status, &(imp_dbh->db), RETVAL->epb_length, RETVAL->event_buffer,
                       RETVAL->result_buffer);
        if (ib_error_check(dbh, status))
            XSRETURN_UNDEF; //croak("error in isc_wait_for_event()");
        isc_event_counts(ecount, RETVAL->epb_length, RETVAL->event_buffer,
                       RETVAL->result_buffer);
    }
    DBI_TRACE_imp_xxh(imp_dbh, 2, (DBIc_LOGPIO(imp_dbh), "Leaving init_event()\n"));
}
    OUTPUT:
    RETVAL


int
ib_register_callback(dbh, ev, perl_cb)
    SV *dbh
    IB_EVENT *ev
    SV *perl_cb
    PREINIT:
    ISC_STATUS status[ISC_STATUS_LENGTH];
    D_imp_dbh(dbh);
    CODE:
{
    DBI_TRACE_imp_xxh(imp_dbh, 2, (DBIc_LOGPIO(imp_dbh), "Entering register_callback()..\n"));

    /* save the perl callback function */
    if (ev->perl_cb == (SV*)NULL) 
        ev->perl_cb = newSVsv(perl_cb);
    else {
        if (_cancel_callback(dbh, ev))
            SvSetSV(ev->perl_cb, perl_cb);
        else
            XSRETURN_UNDEF;
    }
    /* set up the events */
    isc_que_events(
        status,
        &(imp_dbh->db),
        &(ev->id),
        ev->epb_length,
        ev->event_buffer,
        (ISC_EVENT_CALLBACK)_async_callback,
        ev);
    if (ib_error_check(dbh, status))
        XSRETURN_UNDEF;
    else
        RETVAL = 1;
    ev->state = ACTIVE;
}
    OUTPUT:
    RETVAL


int
ib_cancel_callback(dbh, ev)
    SV *dbh
    IB_EVENT *ev
    PREINIT:
    CODE:
    RETVAL = _cancel_callback(dbh, ev);
    OUTPUT:
    RETVAL


HV*
ib_wait_event(dbh, ev)
    SV *dbh
    IB_EVENT *ev
    PREINIT:
    int i;
    SV **svp;
    ISC_STATUS status[ISC_STATUS_LENGTH];
    D_imp_dbh(dbh);
    CODE:
{
    isc_wait_for_event(status, &(imp_dbh->db), ev->epb_length, ev->event_buffer,
                       ev->result_buffer);
    if (ib_error_check(dbh, status))
    {
        do_error(dbh, 2, "ib_wait_event() error");
        XSRETURN_UNDEF;
    }
    else
    {
	ISC_ULONG ecount[15];
        isc_event_counts(ecount, ev->epb_length, ev->event_buffer,
                         ev->result_buffer);
        RETVAL = newHV();
        for (i = 0; i < ev->num; i++) 
        {
            if (ecount[i])
            {
                DBI_TRACE_imp_xxh(imp_dbh, 2, (DBIc_LOGPIO(imp_dbh), "Event %s caught %ld times.\n", *(ev->names + i), ecount[i]));
                svp = hv_store(RETVAL, *(ev->names + i), strlen(*(ev->names + i)),
                               newSViv(ecount[i]), 0);
                if (svp == NULL)
                    croak("Bad: key '%s' not stored", *(ev->names + i));
            }
        }
    }
}
    OUTPUT:
    RETVAL


MODULE = DBD::InterBase     PACKAGE = DBD::InterBase::Event
PROTOTYPES: DISABLE

void
DESTROY(evh)
    IB_EVENT *evh
    PREINIT:
    int i;
    ISC_STATUS status[ISC_STATUS_LENGTH];
    CODE:
{
    DBI_TRACE_imp_xxh(evh->dbh, 2, (DBIc_LOGPIO(evh->dbh), "Entering DBD::InterBase::Event::DESTROY..\n"));
#ifdef DBI_USE_THREADS
	if (PERL_GET_CONTEXT != evh->dbh->context) {
		DBI_TRACE_imp_xxh(evh->dbh, 2, (DBIc_LOGPIO(evh->dbh), 
			"DBD::InterBase::Event::DESTROY ignored because owned by thread %p not current thread %p\n",
			evh->dbh->context, (PerlInterpreter *)PERL_GET_CONTEXT)
		);
		XSRETURN(0);
	}
#endif
    for (i = 0; i < evh->num; i++)
        if (*(evh->names + i))
            Safefree(*(evh->names + i));
    if (evh->names)
        Safefree(evh->names);
    if (evh->perl_cb) {
        SvREFCNT_dec(evh->perl_cb);
        isc_cancel_events(status, &(evh->dbh->db), &(evh->id));
    }
    if (evh->event_buffer)
#ifdef INCLUDE_TYPES_PUB_H 
        isc_free((ISC_SCHAR*)evh->event_buffer);
#else
        isc_free(evh->event_buffer);
#endif
    if (evh->result_buffer)
#ifdef INCLUDE_TYPES_PUB_H 
        isc_free((ISC_SCHAR*)evh->result_buffer);
#else
        isc_free(evh->result_buffer);
#endif
}

MODULE = DBD::InterBase     PACKAGE = DBD::InterBase::st

char*
ib_plan(sth)
    SV *sth
    CODE:
{
    D_imp_sth(sth);
    ISC_STATUS  status[ISC_STATUS_LENGTH];
    char plan_info[1];
    char plan_buffer[PLAN_BUFFER_LEN];

    RETVAL = NULL;
	Zero(plan_buffer, sizeof(plan_buffer), char);
    plan_info[0] = isc_info_sql_get_plan;

    if (isc_dsql_sql_info(status, &(imp_sth->stmt), sizeof(plan_info), plan_info,
                  sizeof(plan_buffer), plan_buffer)) 
    {
        if (ib_error_check(sth, status))
        {
            ib_cleanup_st_prepare(imp_sth);
            XSRETURN_UNDEF;
        }
    }
    if (plan_buffer[0] == isc_info_sql_get_plan) {
        short l = (short) isc_vax_integer((char *)plan_buffer + 1, 2);
		Newx(RETVAL, l + 2, char);
        sprintf(RETVAL, "%.*s%s", l, plan_buffer + 3, "\n");
        //PerlIO_printf(PerlIO_stderr(), "Len: %d, orig len: %d\n", strlen(imp_sth->plan), l);
    }
}
    OUTPUT:
    RETVAL
