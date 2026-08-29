#!/usr/bin/env bash
#
# mayhem/build.sh — build OpenSIPS' four in-tree libFuzzer harnesses (the same
# ones OpenSIPS ships to OSS-Fuzz under test/fuzz/) plus a behavioral KAT oracle.
#
# Fuzz targets (in-process libFuzzer, ADDITIVE reuse of upstream test/fuzz/*.c):
#   fuzz_msg_parser  — parse_msg(): the full SIP message parser (first line,
#                      headers, Via/From/To/CSeq/...); the classic SIP attack surface.
#   fuzz_uri_parser  — parse_uri(): the SIP/SIPS/TEL URI parser + all URI params.
#   fuzz_csv_parser  — parse_csv_record()/_parse_csv_record(): OpenSIPS' CSV lib
#                      (first input byte selects the RFC-4180 vs legacy path).
#   fuzz_core_funcs  — parse_msg() then invokes every parameter-less core script
#                      command + every core pseudo-variable getter, then
#                      build_req_buf_from_sip_req() — the request-rewrite path.
#
# The whole OpenSIPS core (libopensips.a) is compiled with $SANITIZER_FLAGS
# (ASan+UBSan, halting) AND -fsanitize=fuzzer-no-link UNCONDITIONALLY so the
# fuzzed code carries SanCov edges (otherwise 0 edges in Mayhem), plus
# $DEBUG_FLAGS for DWARF<4. Custom OpenSIPS allocators are disabled in favour of
# the system malloc so ASan sees every allocation (this is what upstream's
# test/fuzz/oss-fuzz-build.sh does; we mirror its Makefile.conf edits).
#
# clang-19 rejects OpenSIPS' legacy K&R-era implicit declarations as hard errors;
# OSS-Fuzz's older clang only warned. $COMPAT demotes exactly those diagnostics
# back to warnings — no behavior change, purely a newer-compiler accommodation.
#
# The ORACLE is a SEPARATE clean build (normal flags, no sanitizer): a small KAT
# probe (mayhem/kat/kat_uri.c, built as parser/kat_uri.c so it inherits the
# core's exact -D locking/arch macros) that parses a fixed SIP URI and prints the
# parsed fields. It is dynamically linked so mayhem/test.sh's LD_PRELOAD sabotage
# check reaches it: neuter parse_uri -> no output -> the assertions FAIL.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
SRC="${SRC:-/mayhem}"
export CC
cd "$SRC"

COMPAT="-Wno-implicit-function-declaration -Wno-implicit-int -Wno-int-conversion -Wno-error"
FUZZERS="msg_parser uri_parser csv_parser core_funcs"
LIBS="-ldl -lresolv"

echo "== build.sh: SANITIZER_FLAGS=[$SANITIZER_FLAGS] DEBUG_FLAGS=[$DEBUG_FLAGS] =="

# Generate + patch Makefile.conf exactly as upstream test/fuzz/oss-fuzz-build.sh does:
# system malloc (so ASan sees allocations), disable custom allocators + multicast,
# enable FUZZ_BUILD (extra runtime checks that suppress false-positive crashes).
apply_conf() {
  make Makefile.conf
  sed -i '
    s/^#*DEFS+= -DPKG_MALLOC/DEFS+= -DSYSTEM_MALLOC/g
    s/^\(DEFS+= -DUSE_MCAST\)/#\1/g
    s/^\(DEFS+= -DF_MALLOC\)/#\1/g
    s/^\(DEFS+= -DQ_MALLOC\)/#\1/g
    s/^\(DEFS+= -DHP_MALLOC\)/#\1/g
    s/^\(DEFS+= -DDBG_MALLOC\)/#\1/g
    s/^#\(DEFS+= -DFUZZ_BUILD\)/\1/g
  ' Makefile.conf
}

# Rebuild libopensips.a from all objects EXCEPT main.o and the harness/probe TUs.
build_lib() {
  local out="$1"
  rm -f main.o "$out"
  ar -cr "$out" $(find . -name '*.o' | grep -vE '/(fuzz_.*|kat_.*)\.o$')
}

# Start from a fully clean tree so a re-run (offline PATCH tier, §6.5) can't reuse
# objects compiled with the other build's flags.
make proper >/dev/null 2>&1 || true

# ===========================================================================
# 1) Sanitized fuzz build — the four libFuzzer targets.
# ===========================================================================
apply_conf
# Symlink the harness sources into parser/ so `make static` compiles them with
# the core's exact -D macros/includes (upstream oss-fuzz-build.sh does the same).
ln -sf "$SRC"/test/fuzz/fuzz_*.c ./parser/

export CFLAGS="$SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS $COMPAT"
make -j"$MAYHEM_JOBS" static
build_lib libopensips.a

for f in $FUZZERS; do
  $CC $CFLAGS $LIB_FUZZING_ENGINE ./parser/fuzz_${f}.o libopensips.a $LIBS -o /mayhem/fuzz_${f}
  test -x /mayhem/fuzz_${f}
done

# ===========================================================================
# 2) Oracle — clean build (normal flags, no sanitizer) of the KAT URI probe,
#    dynamically linked so the LD_PRELOAD sabotage shim in test.sh reaches it.
# ===========================================================================
make proper >/dev/null 2>&1 || true
rm -f ./parser/fuzz_*.c          # drop the harness symlinks (avoid recompiling them)
apply_conf
cp "$SRC"/mayhem/kat/kat_uri.c ./parser/kat_uri.c

export CFLAGS="-O2 -g $COMPAT"
make -j"$MAYHEM_JOBS" static
build_lib libopensips_clean.a
$CC $CFLAGS parser/kat_uri.o libopensips_clean.a $LIBS -o /mayhem/kat_uri
test -x /mayhem/kat_uri

if ! file /mayhem/kat_uri | grep -q 'dynamically linked'; then
  echo "FATAL: /mayhem/kat_uri is not dynamically linked — the oracle would be un-neuterable" >&2
  file /mayhem/kat_uri >&2
  exit 1
fi

echo "== build.sh: OK =="
ls -l /mayhem/fuzz_msg_parser /mayhem/fuzz_uri_parser /mayhem/fuzz_csv_parser /mayhem/fuzz_core_funcs /mayhem/kat_uri
