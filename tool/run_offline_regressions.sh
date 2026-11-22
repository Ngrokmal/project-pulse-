#!/usr/bin/env bash
# Run each top-level test in a fresh Flutter runner to limit sandbox memory.
# Deliberately exclude live tests: no production mutations or test logins.
set -uo pipefail
export PATH="${FLUTTER_BIN:-/home/user/_tools/flutter/bin}:$PATH"
unset SUPABASE_URL SUPABASE_ANON_KEY PULSE_TEST_EMAIL_A PULSE_TEST_PASSWORD
logdir=/home/user/pulse-phase0/offline-by-file
mkdir -p "$logdir"
: > "$logdir/summary.txt"
failures=0
for file in test/*_test.dart; do
  name=$(basename "$file" .dart)
  if [[ "$name" == live_repository_test ]]; then
    printf 'SKIP live %s\n' "$file" | tee -a "$logdir/summary.txt"
    continue
  fi
  printf 'RUN %s\n' "$file"
  timeout 100 flutter test --no-pub --concurrency=1 "$file" -r expanded > "$logdir/$name.log" 2>&1
  rc=$?
  if [[ $rc -eq 0 ]]; then result=PASS; else result="FAIL($rc)"; failures=$((failures+1)); fi
  printf '%s %s\n' "$result" "$file" | tee -a "$logdir/summary.txt"
done
printf 'FAILURES %d\n' "$failures" | tee -a "$logdir/summary.txt"
exit "$((failures > 0))"
