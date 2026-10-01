#!/bin/bash
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

assert_line_equals() {
  local desc="$1" haystack="$2" expected="$3"
  while IFS= read -r line; do
    [[ "$line" == "$expected" ]] && { pass "$desc"; return; }
  done <<< "$haystack"
  fail "$desc (no line equals '$expected')"
}

FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT
FIXTURE="$FIXTURE_DIR/photo.png"
magick -size 2000x1000 xc:blue "$FIXTURE"

test_resize_only() {
  local status width
  ./imgopt --resize 1600 "$FIXTURE" >/dev/null 2>&1; status=$?
  assert_success "resize-only: exit 0" "$status"
  assert_file_exists "resize-only: output created" "$FIXTURE_DIR/photo-1600w.png"
  width="$(magick identify -format '%w' "$FIXTURE_DIR/photo-1600w.png")"
  [[ "$width" -eq 1600 ]] && pass "resize-only: width is 1600" || fail "resize-only: width is 1600 (got $width)"
}

test_webp_only() {
  local status fmt
  ./imgopt --webp "$FIXTURE" >/dev/null 2>&1; status=$?
  assert_success "webp-only: exit 0" "$status"
  assert_file_exists "webp-only: output created" "$FIXTURE_DIR/photo.webp"
  fmt="$(magick identify -format '%m' "$FIXTURE_DIR/photo.webp")"
  [[ "$fmt" == "WEBP" ]] && pass "webp-only: format is WEBP" || fail "webp-only: format is WEBP (got $fmt)"
}

test_webp_lossless_and_quality() {
  local status
  ./imgopt --webp --lossless "$FIXTURE" >/dev/null 2>&1; status=$?
  assert_success "webp lossless: exit 0" "$status"
  ./imgopt --webp --quality 40 "$FIXTURE" >/dev/null 2>&1; status=$?
  assert_success "webp quality override: exit 0" "$status"
}

test_combined_resize_webp() {
  local status fmt width
  ./imgopt --webp --resize 1600 "$FIXTURE" >/dev/null 2>&1; status=$?
  assert_success "combined: exit 0" "$status"
  assert_file_exists "combined: output created" "$FIXTURE_DIR/photo-1600w.webp"
  fmt="$(magick identify -format '%m' "$FIXTURE_DIR/photo-1600w.webp")"
  [[ "$fmt" == "WEBP" ]] && pass "combined: format is WEBP" || fail "combined: format is WEBP (got $fmt)"
  width="$(magick identify -format '%w' "$FIXTURE_DIR/photo-1600w.webp")"
  [[ "$width" -eq 1600 ]] && pass "combined: width is 1600" || fail "combined: width is 1600 (got $width)"
}

test_multi_file_continues_on_error() {
  local out status
  rm -f "$FIXTURE_DIR/photo.webp"
  out="$(./imgopt --webp "$FIXTURE_DIR/missing.png" "$FIXTURE" 2>&1)"; status=$?
  assert_failure "multi-file: nonzero exit when one file missing" "$status"
  assert_contains "multi-file: error names missing file" "$out" "no such file"
  assert_file_exists "multi-file: good file still processed" "$FIXTURE_DIR/photo.webp"
}

test_wizard_build_flags() {
  local out
  out="$(source ./mage >/dev/null 2>&1; build_flags "1600" "1" "lossy" "80")"
  assert_contains "wizard flags: resize" "$out" "--resize"
  assert_line_equals "wizard flags: resize value is own line" "$out" "1600"
  assert_contains "wizard flags: webp" "$out" "--webp"
  assert_contains "wizard flags: quality" "$out" "--quality"
  assert_line_equals "wizard flags: quality value is own line" "$out" "80"

  out="$(source ./mage >/dev/null 2>&1; build_flags "" "1" "lossless" "")"
  assert_contains "wizard flags: lossless" "$out" "--lossless"
  [[ "$out" != *"--resize"* ]] && pass "wizard flags: no resize when unset" || fail "wizard flags: no resize when unset"

  out="$(source ./mage >/dev/null 2>&1; build_flags "50%" "0" "lossy" "")"
  assert_contains "wizard flags: resize" "$out" "--resize"
  assert_line_equals "wizard flags: percent value is own line" "$out" "50%"
  [[ "$out" != *"--webp"* ]] && pass "wizard flags: no webp when disabled" || fail "wizard flags: no webp when disabled"
}

test_wizard_main_declines_both() {
  local fake_bin out status
  fake_bin="$(mktemp -d)"
  cat > "$fake_bin/gum" <<'GUMSTUB'
#!/bin/bash
case "$1" in
  confirm) exit 1 ;;
  choose) echo lossy ;;
  input) echo "" ;;
esac
GUMSTUB
  chmod +x "$fake_bin/gum"

  out="$(PATH="$fake_bin:$PATH" ./mage "$FIXTURE" 2>&1)"; status=$?
  [[ "$out" != *"unbound variable"* ]] && pass "wizard main: no crash when declining both" || fail "wizard main: no crash when declining both ($out)"
  assert_contains "wizard main: reaches Running line" "$out" "Running: imgopt"
  assert_failure "wizard main: exits nonzero (nothing to do, not a crash)" "$status"

  rm -rf "$fake_bin"
}

test_install_script() {
  local fake_home status target
  fake_home="$(mktemp -d)"
  HOME="$fake_home" bash ./install.sh >/dev/null 2>&1; status=$?
  assert_success "install.sh: exit 0" "$status"
  [[ -L "$fake_home/.local/bin/imgopt" ]] && pass "install.sh: imgopt symlinked" || fail "install.sh: imgopt symlinked"
  target="$(readlink "$fake_home/.local/bin/imgopt")"
  [[ -f "$target" ]] && pass "install.sh: imgopt symlink target exists" || fail "install.sh: imgopt symlink target exists"
  [[ -L "$fake_home/.local/bin/mage" ]] && pass "install.sh: mage symlinked" || fail "install.sh: mage symlinked"
  target="$(readlink "$fake_home/.local/bin/mage")"
  [[ -f "$target" ]] && pass "install.sh: mage symlink target exists" || fail "install.sh: mage symlink target exists"
  rm -rf "$fake_home"
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
test_resize_only
test_webp_only
test_webp_lossless_and_quality
test_combined_resize_webp
test_multi_file_continues_on_error
test_wizard_build_flags
test_wizard_main_declines_both
test_install_script

echo
if [[ "$failures" -eq 0 ]]; then
  echo "All tests passed."
  exit 0
else
  echo "$failures test(s) failed."
  exit 1
fi
