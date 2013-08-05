#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include <stdio.h>
#include <string.h>

#define PUSH_ERR(err, msg)               \
    if (err) {                           \
        av_push(err, newSVpv((msg), 0)); \
    }

#define CONF_GET(conf, key, default)                    \
    ({                                                  \
        SV** val = hv_fetch(conf, key, strlen(key), 0); \
        val ? SvUV(*val) : (default);                   \
    })

#define STATE_MASK 0xFF
#define PT_HASH 1
#define PT_ARRAY 2
#define DBG1(fmt, ...) if (opts->debug > 0) { fprintf(stderr, fmt, ##__VA_ARGS__); }
#define DBG2(fmt, ...) if (opts->debug > 1) { fprintf(stderr, fmt, ##__VA_ARGS__); }

typedef struct opts {
    U32 nodot;
    U32 nullsplit;
    U32 dclone;
    U32 debug;
} Opts;

typedef enum input {
    I_DT = 0x00, // .
    I_LS = 0x01, // [
    I_RS = 0x02, // ]
    I_LC = 0x03, // {
    I_RC = 0x04, // }
    I_DI = 0x05, // 0-9 digit
    I_CH = 0x06, // any other char
    I_EN = 0x07  // fake end-of-line char
} Input;

typedef enum state {
    S_RD = 0x00, // normal reading
    S_RK = 0x01, // reading key inside {}
    S_RI = 0x02, // reading index inside []
    S_RC = 0x03, // reading controll . [ or {
    S_EN = 0x04, // end state
    S_ER = 0x05  // error state
} State;

typedef enum action {
    A_EC = 0x0200, // eat char
    A_ED = 0x0800, // eat digit
    A_CH = 0x1000, // create hash (vivify)
    A_CA = 0x2000, // create array (vivify)
    A_CV = 0x4000  // create scalar
} Action;

static Input classes[] = {
    I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH,
    I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH,
    I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH,
    I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH,
    I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH,
    I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_DT, I_CH,
    I_DI, I_DI, I_DI, I_DI, I_DI, I_DI, I_DI, I_DI,
    I_DI, I_DI, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH,
    I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH,
    I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH,
    I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH,
    I_CH, I_CH, I_CH, I_LS, I_CH, I_RS, I_CH, I_CH,
    I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH,
    I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH,
    I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH,
    I_CH, I_CH, I_CH, I_LC, I_CH, I_RC, I_CH, I_CH,
    I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH,
    I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH,
    I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH,
    I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH,
    I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH,
    I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH,
    I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH,
    I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH,
    I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH,
    I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH,
    I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH,
    I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH,
    I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH,
    I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH,
    I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH,
    I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH, I_CH
};

static U32 machine[][8] = {
/*          I_DT,         I_LS,         I_RS,       I_LC,         I_RC,     I_DI,       I_CH,       I_EN       
/*S_RD*/ {  S_RD|A_CH,    S_RI|A_CA,    S_ER,       S_RK|A_CH,    S_ER,     S_RD|A_EC,  S_RD|A_EC,  S_EN|A_CV },
/*S_RK*/ {  S_ER,         S_ER,         S_ER,       S_ER,         S_RC,     S_RK|A_EC,  S_RK|A_EC,  S_ER      },
/*S_RI*/ {  S_ER,         S_ER,         S_RC,       S_ER,         S_ER,     S_RI|A_ED,  S_ER,       S_ER      },
/*S_RC*/ {  S_RD|A_CH,    S_RI|A_CA,    S_ER,       S_RK|A_CH,    S_ER,     S_ER,       S_ER,       S_EN|A_CV }
};

SV**
_fetch(void* ptr, const char* part_key, U32 part_klen, U32 part_idx)
{
    if (SvTYPE((SV*)ptr) == SVt_PVHV) {
        return hv_fetch((HV*)ptr, part_key, part_klen, 0);
    }
    else {
        return av_fetch((AV*)ptr, part_idx, 0);
    }
}

void
_store(void* ptr, const char* part_key, U32 part_klen, U32 part_idx, SV* val, Opts* opts)
{
    if (SvTYPE((SV*)ptr) == SVt_PVHV) {
        DBG1("hv_store ptr %p part_key %s park_klen %d val %p (type %d)\n", ptr, part_key, part_klen, val, SvTYPE(val));
        hv_store((HV*)ptr, part_key, part_klen, val, 0);
    }
    else {
        DBG1("av_store ptr %p part_idx %d val %p (type %d)\n", ptr, part_idx, val, SvTYPE(val));
        av_store((AV*)ptr, part_idx, val);
    }
}

void 
_handle_pair(const char* key, U32 klen, SV* val, AV* err, Opts* opts, HV* ov)
{
    U32 pos = 0;
    U32 mv = 0;
    Input inp = I_CH;
    State st = S_RD;

    U32 part_idx = 0;
    const char* part_key = key;
    U32 part_klen = 0;

    void* ptr = ov;
    void* next = NULL;

    for (pos = 0; pos <= klen && st < S_EN; pos++) {
        inp = pos == klen ? I_EN : classes[key[pos]];
        mv = machine[st][inp];

        DBG1("st %d pos %d chr %c(%d) inp %d -> st %d\n", st, pos, key[pos], (int)key[pos], inp, mv & 0xFF);

        st = mv & 0xFF;
        if (mv & A_EC) {
            part_klen++;
        }
        if (mv & A_ED) {
            part_idx = part_idx * 10 + key[pos] - '0';
        }
        if (mv & A_CH) {
            SV** next_ptr = _fetch(ptr, part_key, part_klen, part_idx);
            if (!next_ptr) {
                next = newHV();
                _store(ptr, part_key, part_klen, part_idx, newRV_noinc((SV*)next), opts);
            }
            else {
                if (SvROK(*next_ptr) && SvTYPE(SvRV(*next_ptr)) == SVt_PVHV) {
                    next = SvRV(*next_ptr);
                }
                else {
                    st = S_ER;
                }
            }
            ptr = next;
            part_key = key + pos + 1; 
            part_klen = 0;
        }
        if (mv & A_CA) {
            SV** next_ptr = _fetch(ptr, part_key, part_klen, part_idx);
            if (!next_ptr) {
                next = newAV();
                _store(ptr, part_key, part_klen, part_idx, newRV_noinc((SV*)next), opts);
            }
            else {
                if (SvROK(*next_ptr) && SvTYPE(SvRV(*next_ptr)) == SVt_PVAV) {
                    next = SvRV(*next_ptr);
                }
                else {
                    st = S_ER;
                }
            }
            ptr = next;
            part_key = key + pos + 1; 
            part_klen = 0;
        }
        if (mv & A_CV) {
            if (opts->nullsplit && SvPOK(val)) {
                char* beg = SvPVX(val);
                char* end = SvEND(val);
                char* zer = (char*) memchr(beg, '\0', SvCUR(val));
                DBG2("splitting beg %p end %p zer %p len %d cur %d\n", beg, end, zer, SvLEN(val), SvLEN(val));
                if (zer && zer < end) {
                    AV* val_arr = newAV();
                    do {
                        DBG2("\tpushing beg %p zer %p part len %d\n", beg, zer, zer - beg);
                        av_push(val_arr, newSVpvn_utf8(beg, zer - beg, SvUTF8(val)));
                        beg = zer + 1;
                        zer = memchr(beg, '\0', end - beg);
                        DBG2("\tnext zer %p\n", zer);
                    } while (zer && zer <= end);
                    if (beg < end) {
                        av_push(val_arr, newSVpvn_utf8(beg, end - beg, SvUTF8(val)));
                    }
                    val = newRV_noinc((SV*)val_arr);
                }
            }
            _store(ptr, part_key, part_klen, part_idx, newSVsv(val), opts);
        }
    }
    DBG1("final state %d\n\n", st);
    if (st == S_EN) {
        return;
    }
    else {
        // TODO: differ errors
        PUSH_ERR(err, "some error");
        return;
    }
}


MODULE = CGI::Struct::XS PACKAGE = CGI::Struct::XS

HV*
build_cgi_struct(HV* iv, ...)
PREINIT:
    AV* err = NULL;
    HV* conf = NULL;
    Opts opts = { 0, 1, 1, 0 };
    HE* pair = NULL;
    char* key = NULL;
    U32 klen = 0;
    SV* val = NULL;
CODE:
    /* prepare args */
    if (items > 1) {
        SV* const xsub_tmp_sv = ST(1);
        SvGETMAGIC(xsub_tmp_sv);
        if (SvROK(xsub_tmp_sv) && SvTYPE(SvRV(xsub_tmp_sv)) == SVt_PVAV) {
            err = (AV*) SvRV(xsub_tmp_sv);
        }
    }
    if (items > 2) {
        SV* const xsub_tmp_sv = ST(2);
        SvGETMAGIC(xsub_tmp_sv);
        if (SvROK(xsub_tmp_sv) && SvTYPE(SvRV(xsub_tmp_sv)) == SVt_PVHV) {
            conf = (HV*) SvRV(xsub_tmp_sv);
            opts.nodot = CONF_GET(conf, "nodot", opts.nodot);
            opts.nullsplit = CONF_GET(conf, "nullsplit", opts.nullsplit);
            opts.dclone = CONF_GET(conf, "dclone", opts.dclone);
            opts.debug = CONF_GET(conf, "debug", opts.debug);
        }
    }

    /* prepare output */
    RETVAL = newHV();
    sv_2mortal((SV*)RETVAL);
    
    /* main loop */
    hv_iterinit(iv);
    while (pair = hv_iternext(iv)) {
        key = hv_iterkey(pair, &klen);
        val = hv_iterval(iv, pair);
        _handle_pair(key, klen, val, err, &opts, RETVAL);
    }
OUTPUT:
    RETVAL
