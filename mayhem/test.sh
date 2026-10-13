#!/usr/bin/env bash
#
# mayhem/test.sh — behavioral oracle for OpenSIPS' SIP URI parser.
#
# Runs the CLEAN (non-sanitized), dynamically-linked KAT probe built by
# mayhem/build.sh (/mayhem/kat_uri) and asserts the EXACT fields parse_uri()
# extracts from a fixed SIP URI. These are known-answer assertions through a
# real, LD_PRELOAD-reachable binary: a PATCH that neuters the parser to a no-op
# (or verify-repo's sabotage shim that _exit(0)s the probe) prints nothing, so
# every assertion FAILS. Exit-code-only / marker-grep oracles are forbidden
# (docs/netnew-worker-prompt.md §4); this asserts computed values.
#
# Emits a CTRF summary + a compact `CTRF {...}` stdout marker; exits non-zero
# iff failed>0.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
SRC="${SRC:-/mayhem}"
cd "$SRC"

KAT=/mayhem/kat_uri

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# Fail loudly if build.sh did not produce the oracle probe (a build bug, not a skip).
if [ ! -x "$KAT" ]; then
  echo "FATAL: $KAT missing/not executable — mayhem/build.sh did not build the oracle" >&2
  emit_ctrf "opensips-uri-kat" 0 1 0
  exit 1
fi

passed=0
failed=0

# The probe parses the fixed URI "sip:alice@example.com:5061;transport=tcp" and
# prints one "key=value" line per parsed field. Assert each exact value.
out="$("$KAT" 2>/dev/null)"

assert() {
  local label="$1" want="$2" got
  got="$(printf '%s\n' "$out" | grep -m1 "^${label}=" | cut -d= -f2-)"
  if [ "$got" = "$want" ]; then
    echo "PASS  $label -> '$got'"
    passed=$((passed + 1))
  else
    echo "FAIL  $label : want='$want' got='$got'"
    failed=$((failed + 1))
  fi
}

assert "user"      "alice"
assert "host"      "example.com"
assert "port"      "5061"
assert "transport" "tcp"

emit_ctrf "opensips-uri-kat" "$passed" "$failed" 0
