#!/usr/bin/env bash
# Runs simdjson's own unit tests (built by mayhem/build.sh, listed in mayhem/tests.list). Each test
# must exit 0 AND print its success marker: the tests assert parsed values internally, and a
# neutered binary (exit 0, no output) fails the marker check.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

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

B="$SRC/mayhem/build-tests"
passed=0; failed=0
while IFS=$'\t' read -r bin marker; do
  case "$bin" in ''|'#'*) continue ;; esac
  if [ ! -x "$B/$bin" ]; then echo "FAIL $bin: not built (build.sh bug)"; failed=$((failed+1)); continue; fi
  out=$(cd "$B" && "./$bin" 2>&1); rc=$?
  if [ "$rc" -eq 0 ] && grep -qF -- "$marker" <<<"$out"; then
    echo "PASS $bin"; passed=$((passed+1))
  else
    echo "FAIL $bin (rc=$rc, marker '$marker')"; tail -n 5 <<<"$out"; failed=$((failed+1))
  fi
done < "$SRC/mayhem/tests.list"

emit_ctrf "simdjson-unit-tests" "$passed" "$failed" 0
