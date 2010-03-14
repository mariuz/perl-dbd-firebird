/*
   $Id: dbdimp.h 395 2008-01-08 05:33:11Z edpratomo $

   Copyright (c) 1999-2008  Edwin Pratomo
   Portions Copyright (c) 2001-2005  Daniel Ritz

   You may distribute under the terms of either the GNU General Public
   License or the Artistic License, as specified in the Perl README file,
   with the exception that it cannot be placed on a CD-ROM or similar media
   for commercial distribution without the prior approval of the author.

*/

#include <DBIXS.h>              /* installed by the DBI module  */

/* make it compile with DBI < 1.20 */
#ifndef SQL_TYPE_DATE
#  define SQL_TYPE_DATE    91
#endif
#ifndef SQL_TYPE_TIME
#  define SQL_TYPE_TIME    92
#endif
#ifndef SQL_BLOB
#  define SQL_BLOB         30
#endif
#ifndef SQL_ARRAY
#  define SQL_ARRAY        50
#endif


static const int DBI_SQL_CHAR       = SQL_CHAR;
static const int DBI_SQL_NUMERIC    = SQL_NUMERIC;
static const int DBI_SQL_DECIMAL    = SQL_DECIMAL;
static const int DBI_SQL_INTEGER    = SQL_INTEGER;
static const int DBI_SQL_SMALLINT   = SQL_SMALLINT;
static const int DBI_SQL_FLOAT      = SQL_FLOAT;
static const int DBI_SQL_REAL       = SQL_REAL;
static const int DBI_SQL_DOUBLE     = SQL_DOUBLE;
static const int DBI_SQL_DATE       = SQL_DATE;
static const int DBI_SQL_TIME       = SQL_TIME;
static const int DBI_SQL_TIMESTAMP  = SQL_TIMESTAMP;
static const int DBI_SQL_VARCHAR    = SQL_VARCHAR;
static const int DBI_SQL_TYPE_TIME  = SQL_TYPE_TIME;
static const int DBI_SQL_TYPE_DATE  = SQL_TYPE_DATE;
static const int DBI_SQL_ARRAY      = SQL_ARRAY;
static const int DBI_SQL_BLOB       = SQL_BLOB;

/* conflicts */

#undef  SQL_CHAR
#undef  SQL_NUMERIC
#undef  SQL_DECIMAL
#undef  SQL_INTEGER
#undef  SQL_SMALLINT
#undef  SQL_FLOAT
#undef  SQL_REAL
#undef  SQL_DOUBLE
#undef  SQL_DATE
#undef  SQL_TIME
#undef  SQL_TIMESTAMP
#undef  SQL_VARCHAR
#undef  SQL_TYPE_TIME
#undef  SQL_TYPE_DATE
#undef  SQL_ARRAY
#undef  SQL_BLOB
#undef  SQL_BOOLEAN

#include <ibase.h>
#include <time.h>

/* defines */

/* Firebird API 20 */
#if !defined(FB_API_VER) || FB_API_VER < 20
typedef void (*ISC_EVENT_CALLBACK)();
#endif

#ifndef SQLDA_CURRENT_VERSION
#  define SQLDA_OK_VERSION SQLDA_VERSION1
#else
#  define SQLDA_OK_VERSION SQLDA_CURRENT_VERSION
#endif

/* is IB v6 API present? */
#if defined(_ISC_TIMESTAMP_) || defined(ISC_TIMESTAMP_DEFINED)
#  define IB_API_V6
#endif

#define IB_ALLOC_FAIL   2
#define IB_FETCH_ERROR  1

#ifndef ISC_STATUS_LENGTH
#  define ISC_STATUS_LENGTH 20
#endif

#ifndef SvPV_nolen
#  define SvPV_nolen(sv) SvPV(sv, na)
#endif

#define FREE_SETNULL(ptr) \
do {                      \
    if (ptr)              \
    {                     \
        Safefree(ptr);    \
        ptr = NULL;       \
    }                     \
} while (0)

#define DPB_FILL_BYTE(dpb, byte)  \
do {                              \
    *dpb = byte;                  \
    dpb += 1;                     \
} while (0)

#define DPB_FILL_INTEGER(dpb, integer)       \
do {                                         \
    int tmp = integer;                       \
    *(dpb) = 4;                              \
    dpb += 1;                                \
    tmp = isc_vax_integer((char *) &tmp, 4); \
    Copy(&tmp, dpb, 1, sizeof(tmp));         \
    dpb += 4;                                \
} while (0)

#define DPB_FILL_STRING(dpb, string)   \
do {                                   \
    char l = strlen(string) & 0xFF;    \
    *(dpb) = l;                        \
    dpb += 1;                          \
    strncpy(dpb, string, (size_t) l);  \
    dpb += l;                          \
} while (0)


#ifndef IB_API_V6
#  define TIMESTAMP_FPSECS(value) \
   (long)(((ISC_QUAD *)value)->isc_quad_low % 10000L)
#  define TIMESTAMP_ADD_FPSECS(value, inc) \
   ((ISC_QUAD *)value)->isc_quad_low += (inc % 10000L);
#else
#  define TIMESTAMP_FPSECS(value) \
   (long)(((ISC_TIMESTAMP *)value)->timestamp_time % ISC_TIME_SECONDS_PRECISION)
#  define TIMESTAMP_ADD_FPSECS(value, inc) \
   ((ISC_TIMESTAMP *)value)->timestamp_time += (inc % ISC_TIME_SECONDS_PRECISION)

#  define TIME_FPSECS(value) \
   (long)((*(ISC_TIME *)value) % ISC_TIME_SECONDS_PRECISION)
#  define TIME_ADD_FPSECS(value, inc) \
   (*(ISC_TIME *)value) += (inc % ISC_TIME_SECONDS_PRECISION)
#endif


#ifndef NO_TRACE_MSGS
#  define DBI_TRACE(level, args) \
do {                             \
    if (DBIS->debug >= level)    \
        PerlIO_printf args ;     \
} while (0)
#  define DBI_TRACE_imp_xxh(imp_xxh, level, args) \
do { \
    if (DBIc_TRACE_LEVEL(imp_xxh) >= level) \
        PerlIO_printf args;             \
} while (0)
#else
#  define DBI_TRACE(level, args) do {} while (0)
#  define DBI_TRACE_imp_xxh(imp_xxh, level, args) do {} while (0)
#endif

#define BLOB_SEGMENT        (256)
#define DEFAULT_SQL_DIALECT (1)
#define INPUT_XSQLDA        (1)
#define OUTPUT_XSQLDA       (0)
#define PLAN_BUFFER_LEN     2048

#define SUCCESS             (0)
#define FAILURE             (-1)

/*
 * Hardcoded limit on the length of a Blob that can be fetched into a scalar.
 * If you want to fetch Blobs that are bigger, write your own Perl
 */

#define MAX_SAFE_BLOB_LENGTH (1000000)

#define MAX_EVENTS          15

typedef enum { ACTIVE, INACTIVE } IB_EVENT_STATE;

/****************/
/* data types   */
/****************/

/* structs for event */
typedef struct
{
    imp_dbh_t       *dbh;               /* pointer to parent dbh */
    ISC_LONG        id;                 /* event id assigned by IB */
#if defined(INCLUDE_TYPES_PUB_H)
    ISC_UCHAR       *event_buffer;
    ISC_UCHAR       *result_buffer;
#else
    char ISC_FAR    *event_buffer;
    char ISC_FAR    *result_buffer;
#endif
    char ISC_FAR * ISC_FAR *names;      /* names of events of interest */
    unsigned short  num;                /* number of events of interest */
    short           epb_length;         /* length of event parameter buffer */
    SV              *perl_cb;           /* perl callback for this event */
    IB_EVENT_STATE  state;
    char            exec_cb;
} IB_EVENT;

/* Define driver handle data structure */
struct imp_drh_st
{
    dbih_drc_t com;     /* MUST be first element in structure */
};

/* Define dbh implementor data structure */
struct imp_dbh_st
{
    dbih_dbc_t      com;                /* MUST be first element in structure */
    isc_db_handle   db;
    isc_tr_handle   tr;
    char ISC_FAR    *tpb_buffer;        /* transaction parameter buffer */
    unsigned short  tpb_length;         /* length of tpb_buffer */
    unsigned short  sqldialect;         /* default sql dialect */
    char            soft_commit;        /* use soft commit ? */

    unsigned int    sth_ddl;            /* number of open DDL statments */
    imp_sth_t       *first_sth;         /* pointer to first statement */
    imp_sth_t       *last_sth;          /* pointer to last statement */

#if defined(USE_THREADS) || defined(USE_ITHREADS) || defined(MULTIPLICITY)
    void            *context;           /* perl context for threads / multiplicity */
#endif

    /* per dbh default strftime() formats */
    char            *dateformat;
#ifdef IB_API_V6
    char            *timestampformat;
    char            *timeformat;
#endif
};

/* Define sth implementor data structure */
struct imp_sth_st
{
    dbih_stc_t      com;                /* MUST be first element in structure */
    isc_stmt_handle stmt;
    XSQLDA          *out_sqlda;         /* for storing select-list items */
    XSQLDA          *in_sqlda;          /* for storing placeholder values */
    char            *cursor_name;
    long            type;               /* statement type */
    char            count_item;
    int             fetched;            /* number of fetched rows */

    char            *dateformat;
#ifdef IB_API_V6
    char            *timestampformat;
    char            *timeformat;
#endif
    imp_sth_t       *prev_sth;                /* pointer to prev statement */
    imp_sth_t       *next_sth;                /* pointer to next statement */
};


/* newer header file defines the struct already */
typedef struct dbd_vary
{
    short vary_length;
    char  vary_string [1];
} DBD_VARY;


/* These defines avoid name clashes for multiple statically linked DBD's */
#define dbd_init            ib_init
#define dbd_discon_all      ib_discon_all
#define dbd_db_login        ib_db_login
#define dbd_db_login6       ib_db_login6
#define dbd_db_do           ib_db_do
#define dbd_db_commit       ib_db_commit
#define dbd_db_rollback     ib_db_rollback
#define dbd_db_disconnect   ib_db_disconnect
#define dbd_db_destroy      ib_db_destroy
#define dbd_db_STORE_attrib ib_db_STORE_attrib
#define dbd_db_FETCH_attrib ib_db_FETCH_attrib
#define dbd_st_prepare      ib_st_prepare
#define dbd_st_rows         ib_st_rows
#define dbd_st_execute      ib_st_execute
#define dbd_st_fetch        ib_st_fetch
#define dbd_st_finish       ib_st_finish
#define dbd_st_destroy      ib_st_destroy
#define dbd_st_blob_read    ib_st_blob_read
#define dbd_st_STORE_attrib ib_st_STORE_attrib
#define dbd_st_FETCH_attrib ib_st_FETCH_attrib
#define dbd_bind_ph         ib_bind_ph

void    do_error _((SV *h, int rc, char *what));

void    dbd_init     _((dbistate_t *dbistate));
void    dbd_preparse _((SV *sth, imp_sth_t *imp_sth, char *statement));
int     dbd_describe _((SV *sth, imp_sth_t *imp_sth));
int     dbd_db_ping   (SV *dbh);

int ib_error_check(SV *h, ISC_STATUS *status);

int ib_start_transaction   (SV *h, imp_dbh_t *imp_dbh);
int ib_commit_transaction  (SV *h, imp_dbh_t *imp_dbh);
int ib_rollback_transaction(SV *h, imp_dbh_t *imp_dbh);
long ib_rows(SV *xxh, isc_stmt_handle *h_stmt, char count_type);
void ib_cleanup_st_prepare (imp_sth_t *imp_sth);

SV* dbd_db_quote(SV* dbh, SV* str, SV* type);

/* end */
