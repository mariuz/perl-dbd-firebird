/*
   $Id: InterBase.h 183 2001-12-20 18:01:23Z danielritz $

   Copyright (c) 1999,2000  Edwin Pratomo

   You may distribute under the terms of either the GNU General Public
   License or the Artistic License, as specified in the Perl README file,
   with the exception that it cannot be placed on a CD-ROM or similar media
   for commercial distribution without the prior approval of the author.

*/

#define NEED_DBIXS_VERSION 7

#include "dbdimp.h"

#include <dbd_xsh.h>

void dbd_init _((dbistate_t *dbistate));

int  dbd_db_login        _((SV *dbh, imp_dbh_t *imp_dbh, char *dbname, char *uid, char *pwd));
int  dbd_db_do           _((SV *sv, char *statement));
int  dbd_db_commit       _((SV *dbh, imp_dbh_t *imp_dbh));
int  dbd_db_rollback     _((SV *dbh, imp_dbh_t *imp_dbh));
int  dbd_db_disconnect   _((SV *dbh, imp_dbh_t *imp_dbh));
void dbd_db_destroy      _((SV *dbh, imp_dbh_t *imp_dbh));
int  dbd_db_STORE_attrib _((SV *dbh, imp_dbh_t *imp_dbh, SV *keysv, SV *valuesv));
SV  *dbd_db_FETCH_attrib _((SV *dbh, imp_dbh_t *imp_dbh, SV *keysv));


int  dbd_st_prepare      _((SV *sth, imp_sth_t* imp_sth, char *statement, SV *attribs));
/* int  dbd_st_rows         _((SV *sth, imp_sth_t *imp_sth)); */
int  dbd_bind_ph         _((SV *sth, imp_sth_t *imp_sth, SV *param, SV *value, IV sqltype, SV *attribs, int is_inout, IV maxlen));
int  dbd_st_execute      _((SV *sv, imp_sth_t *imp_sth));
AV  *dbd_st_fetch        _((SV *sv, imp_sth_t *imp_sth));
int  dbd_st_finish       _((SV *sth, imp_sth_t *imp_sth));
void dbd_st_destroy      _((SV *sth, imp_sth_t *imp_sth));
int  dbd_st_blob_read    _((SV *sth, imp_sth_t *imp_sth, int field, long offset, 
	                       long len, SV *destrv, long destoffset));
int  dbd_st_STORE_attrib _((SV *sth, imp_sth_t *imp_sth, SV *keysv, SV *valuesv));
SV  *dbd_st_FETCH_attrib _((SV *sth, imp_sth_t *imp_sth, SV *keysv));


/* end of InterBase.h */
