#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"

failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures+1)); }

assert_success() {
  local desc="$1" status="$2"
  [[ "$status" -eq 0 ]] && pass "$desc" || fail "$desc (exit $status)"
}

assert_failure() {
  local desc="$1" status="$2"
  [[ "$status" -ne 0 ]] && pass "$desc" || fail "$desc (expected nonzero exit)"
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  [[ "$haystack" == *"$needle"* ]] && pass "$desc" || fail "$desc (didn't contain '$needle')"
}

assert_file_exists() {
  local desc="$1" path="$2"
  [[ -f "$path" ]] && pass "$desc" || fail "$desc (missing: $path)"
}

test_no_args_shows_usage_error() {
  local out status
  out="$(./imgopt 2>&1)"; status=$?
  assert_failure "no args: nonzero exit" "$status"
  assert_contains "no args: usage shown" "$out" "Usage:"
}

test_help_flag() {
  local out status
  out="$(./imgopt --help 2>&1)"; status=$?
  assert_success "--help: exit 0" "$status"
  assert_contains "--help: usage shown" "$out" "Usage:"
}

test_missing_binary_error() {
  local out status
  out="$(PATH=/usr/bin:/bin ./imgopt --webp nope.png 2>&1)"; status=$?
  assert_failure "missing cwebp: nonzero exit" "$status"
  assert_contains "missing cwebp: actionable error" "$out" "brew install webp"
}

test_resize_missing_value() {
  local out status
  out="$(./imgopt --resize 2>&1)"; status=$?
  assert_failure "--resize missing value: nonzero exit" "$status"
  assert_contains "--resize missing value: error shown" "$out" "Usage:"
  assert_contains "--resize missing value: no crash" "$out" "--resize requires a value"
}

test_resize_flag_shaped_value() {
  local out status
  out="$(./imgopt --resize --webp file.png 2>&1)"; status=$?
  assert_failure "--resize flag-shaped value: nonzero exit" "$status"
  assert_contains "--resize flag-shaped value: error shown" "$out" "Usage:"
  assert_contains "--resize flag-shaped value: no silent drop" "$out" "--resize requires a value"
}

# === run all tests ===
test_no_args_shows_usage_error
test_help_flag
test_missing_binary_error
test_resize_missing_value
test_resize_flag_shaped_value

echo
if [[ "$failures" -eq 0 ]]; then
  echo "All tests passed."
  exit 0
else
  echo "$failures test(s) failed."
  exit 1
fi
