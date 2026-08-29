/* KAT probe (built as parser/kat_uri.c): parse a fixed SIP URI, print parsed
   fields. mayhem/test.sh asserts the exact output. Dynamically linked so the
   verify-repo LD_PRELOAD sabotage shim neuters it and the assertions fail. */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "../context.h"
#include "../core_stats.h"
#include "../dset.h"
#include "../str.h"
#include "parse_uri.h"

const struct scm_version core_scm_ver;

int main(void) {
    static stat_val bu, bm;
    static stat_var _bu = {.u.val = &bu}, _bm = {.u.val = &bm};
    bad_URIs = &_bu; bad_msg_hdr = &_bm;
    if (init_dset() != 0) { fprintf(stderr, "init_dset failed\n"); return 2; }
    if (ensure_global_context() != 0) { fprintf(stderr, "ctx failed\n"); return 2; }

    char uri[] = "sip:alice@example.com:5061;transport=tcp";
    struct sip_uri u;
    memset(&u, 0, sizeof(u));
    if (parse_uri(uri, strlen(uri), &u) != 0) { printf("PARSE_FAIL\n"); return 1; }
    printf("user=%.*s\n", u.user.len, u.user.s);
    printf("host=%.*s\n", u.host.len, u.host.s);
    printf("port=%u\n", u.port_no);
    printf("transport=%.*s\n", u.transport_val.len, u.transport_val.s);
    return 0;
}
