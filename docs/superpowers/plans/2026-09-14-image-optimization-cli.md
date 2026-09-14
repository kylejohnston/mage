# Image Optimization CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a bash CLI (`imgopt`) and interactive wizard (`imgopt-wizard`) that resize images and/or convert them to WebP, plus Tuna preset scripts that wrap `imgopt` for launcher-driven use — replacing OptImage.

**Architecture:** `imgopt` is the single source of truth for all image logic (arg parsing → preflight → resize via ImageMagick → convert via cwebp → inferred output path). `imgopt-wizard` is a thin `gum`-based prompt layer with no image logic of its own — it builds flags and calls `imgopt` as a subprocess. Tuna presets are one-line wrappers calling `imgopt` with fixed flags, discovered by Tuna via `@tuna.*` header comments.

**Tech Stack:** bash, ImageMagick (`magick`), `cwebp`/libwebp, `gum` (charmbracelet, for the wizard's interactive prompts).

**Spec:** [docs/superpowers/specs/2026-09-14-image-optimization-cli-design.md](../specs/2026-09-14-image-optimization-cli-design.md)

## Global Constraints

- Input formats: PNG, JPEG, TIFF only — HEIC explicitly out of scope (spec "Scope").
- No same-format re-optimization and no metadata handling beyond whatever `cwebp` strips by default (spec "Scope").
- Output always lands in the same folder as the input; a suffix is added only when the resize stage ran; extension swaps to `.webp` when `--webp` is given (spec "Output path inference").
- Default lossy WebP quality is 80; `--quality` is ignored when `--lossless` is set (spec "Flags").
- At least one of `--webp`/`--resize` is required; multiple files are processed independently and one failure must not stop the rest (spec "Usage", "Pipeline").
- `imgopt`/`imgopt-wizard` install to `~/.local/bin`; Tuna presets install to `~/Library/Scripts` (spec "Installation").
- No new dependencies beyond `gum` — `cwebp`, `magick`, `exiftool` are already installed (spec "Context").
- Target bash 3.2 syntax (macOS's default `/bin/bash`) — no associative arrays, no `${var,,}`, no `mapfile`.

---

### Task 1: `imgopt` — arg parsing, validation, preflight

**Files:**
- Create: `imgopt`
- Create: `test.sh`

**Interfaces:**
- Produces (globals set by arg parsing, consumed by later tasks): `resize_value` (string, empty if `--resize` not given), `do_webp` (`0`/`1`), `lossless` (`0`/`1`), `quality` (string, default `"80"`), `files` (bash array of positional args), `PROG` (string, `basename "$0"`).
- Produces: `usage()` — prints usage text to stdout.
- Produces: `need_bin(bin_name, install_hint)` — exits 1 with an actionable message if `bin_name` isn't on `PATH`.
- Produces (test helpers in `test.sh`, used by every later task): `pass(desc)`, `fail(desc)`, `assert_success(desc, status)`, `assert_failure(desc, status)`, `assert_contains(desc, haystack, needle)`, `assert_file_exists(desc, path)`.

- [ ] **Step 1: Write the failing tests**

Create `test.sh`:

```bash
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

# === run all tests ===
test_no_args_shows_usage_error
test_help_flag
test_missing_binary_error

echo
if [[ "$failures" -eq 0 ]]; then
  echo "All tests passed."
  exit 0
else
  echo "$failures test(s) failed."
  exit 1
fi
```

```bash
chmod +x test.sh
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./test.sh`
Expected: `./imgopt` doesn't exist yet — every test fails (e.g. `bash: ./imgopt: No such file or directory`), summary reports `3 test(s) failed`.

- [ ] **Step 3: Write minimal implementation**

Create `imgopt`:

```bash
#!/usr/bin/env bash
set -uo pipefail

PROG="$(basename "$0")"

usage() {
  cat <<'EOF'
Usage: imgopt [--webp] [--lossless] [--quality N] [--resize VALUE] FILE [FILE...]

  --resize VALUE   Percentage (e.g. 50%) or max width in px (e.g. 1600)
  --webp           Convert to WebP
  --lossless       WebP lossless mode (only with --webp)
  --quality N      Lossy quality 0-100, default 80 (only with --webp, ignored if --lossless)
  -h, --help       Show this help

At least one of --webp or --resize is required.
EOF
}

# === arg parsing ===
resize_value=""
do_webp=0
lossless=0
quality=80
files=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --resize) resize_value="$2"; shift 2 ;;
    --webp) do_webp=1; shift ;;
    --lossless) lossless=1; shift ;;
    --quality) quality="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; files+=("$@"); break ;;
    -*) echo "$PROG: unknown flag: $1" >&2; usage >&2; exit 1 ;;
    *) files+=("$1"); shift ;;
  esac
done

if [[ -z "$resize_value" && "$do_webp" -eq 0 ]]; then
  echo "$PROG: nothing to do — pass --webp and/or --resize" >&2
  usage >&2
  exit 1
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "$PROG: no input files given" >&2
  usage >&2
  exit 1
fi

# === preflight ===
need_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "$PROG: '$1' not found. Install with: $2" >&2
    exit 1
  }
}

[[ -n "$resize_value" ]] && need_bin magick "brew install imagemagick"
[[ "$do_webp" -eq 1 ]] && need_bin cwebp "brew install webp"

# === pipeline ===

# === main ===
```

```bash
chmod +x imgopt
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./test.sh`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add imgopt test.sh
git commit -m "feat: imgopt arg parsing, validation, and preflight checks"
```

---

### Task 2: `imgopt` — resize-only pipeline + output naming

**Files:**
- Modify: `imgopt`
- Modify: `test.sh`

**Interfaces:**
- Consumes: `resize_value`, `do_webp`, `PROG` from Task 1.
- Produces: `resize_spec(value) -> string` (ImageMagick `-resize` argument), `resize_suffix(value) -> string` (filename suffix, without the leading `-`), `output_path(input) -> string` (full inferred output path), `process_file(input) -> 0|1` (processes one file, prints `"$input -> $out"` on success, an error to stderr and returns 1 on failure).
- Produces (test.sh): `FIXTURE_DIR`, `FIXTURE` (a generated 2000×1000 PNG), reused by every later image test.

- [ ] **Step 1: Write the failing test**

In `test.sh`, find:

```bash
assert_file_exists() {
  local desc="$1" path="$2"
  [[ -f "$path" ]] && pass "$desc" || fail "$desc (missing: $path)"
}

test_no_args_shows_usage_error() {
```

Replace with:

```bash
assert_file_exists() {
  local desc="$1" path="$2"
  [[ -f "$path" ]] && pass "$desc" || fail "$desc (missing: $path)"
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

test_no_args_shows_usage_error() {
```

Find:

```bash
# === run all tests ===
test_no_args_shows_usage_error
test_help_flag
test_missing_binary_error
```

Replace with:

```bash
# === run all tests ===
test_no_args_shows_usage_error
test_help_flag
test_missing_binary_error
test_resize_only
```

- [ ] **Step 2: Run tests to verify the new test fails**

Run: `./test.sh`
Expected: `resize-only: output created` and `resize-only: width is 1600` fail (no output produced — `imgopt` has no pipeline yet). Other tests still pass.

- [ ] **Step 3: Implement the resize pipeline**

In `imgopt`, find:

```bash
# === pipeline ===

# === main ===
```

Replace with:

```bash
# === pipeline ===
resize_spec() {
  local value="$1"
  if [[ "$value" == *% ]]; then
    printf '%s' "$value"
  else
    printf '%sx' "$value"
  fi
}

resize_suffix() {
  local value="$1"
  if [[ "$value" == *% ]]; then
    printf '%spct' "${value%\%}"
  else
    printf '%sw' "$value"
  fi
}

output_path() {
  local input="$1"
  local dir base ext stem out_ext suffix
  dir="$(dirname "$input")"
  base="$(basename "$input")"
  ext="${base##*.}"
  stem="${base%.*}"

  if [[ "$do_webp" -eq 1 ]]; then
    out_ext="webp"
  else
    out_ext="$ext"
  fi

  if [[ -n "$resize_value" ]]; then
    suffix="-$(resize_suffix "$resize_value")"
  else
    suffix=""
  fi

  printf '%s/%s%s.%s' "$dir" "$stem" "$suffix" "$out_ext"
}

process_file() {
  local input="$1"
  [[ -f "$input" ]] || { echo "$PROG: $input: no such file" >&2; return 1; }

  local out
  out="$(output_path "$input")"

  if [[ -n "$resize_value" ]]; then
    magick "$input" -resize "$(resize_spec "$resize_value")" "$out" || {
      echo "$PROG: $input: resize failed" >&2
      return 1
    }
  fi

  echo "$input -> $out"
}

# === main ===
status=0
for f in "${files[@]}"; do
  process_file "$f" || status=1
done
exit "$status"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./test.sh`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add imgopt test.sh
git commit -m "feat: imgopt resize-only pipeline and output path inference"
```

---

### Task 3: `imgopt` — WebP-only pipeline (lossy default, lossless, quality)

**Files:**
- Modify: `imgopt`
- Modify: `test.sh`

**Interfaces:**
- Consumes: `do_webp`, `lossless`, `quality`, `output_path()`, `process_file()` from Task 2.
- Produces: `process_file()` extended to also handle the webp-only case (resize branch unchanged; this task's combined-flags case is still handled in Task 4).

- [ ] **Step 1: Write the failing test**

In `test.sh`, find:

```bash
test_resize_only() {
  local status width
  ./imgopt --resize 1600 "$FIXTURE" >/dev/null 2>&1; status=$?
  assert_success "resize-only: exit 0" "$status"
  assert_file_exists "resize-only: output created" "$FIXTURE_DIR/photo-1600w.png"
  width="$(magick identify -format '%w' "$FIXTURE_DIR/photo-1600w.png")"
  [[ "$width" -eq 1600 ]] && pass "resize-only: width is 1600" || fail "resize-only: width is 1600 (got $width)"
}
```

Replace with:

```bash
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
```

Find:

```bash
test_no_args_shows_usage_error
test_help_flag
test_missing_binary_error
test_resize_only
```

Replace with:

```bash
test_no_args_shows_usage_error
test_help_flag
test_missing_binary_error
test_resize_only
test_webp_only
test_webp_lossless_and_quality
```

- [ ] **Step 2: Run tests to verify the new tests fail**

Run: `./test.sh`
Expected: `webp-only: output created` and `webp-only: format is WEBP` fail (webp branch not implemented). The lossless/quality test may pass trivially (no-op still exits 0) or fail — either way, it's not yet meaningful; proceed to implementation.

- [ ] **Step 3: Implement the webp branch**

In `imgopt`, find:

```bash
process_file() {
  local input="$1"
  [[ -f "$input" ]] || { echo "$PROG: $input: no such file" >&2; return 1; }

  local out
  out="$(output_path "$input")"

  if [[ -n "$resize_value" ]]; then
    magick "$input" -resize "$(resize_spec "$resize_value")" "$out" || {
      echo "$PROG: $input: resize failed" >&2
      return 1
    }
  fi

  echo "$input -> $out"
}
```

Replace with:

```bash
process_file() {
  local input="$1"
  [[ -f "$input" ]] || { echo "$PROG: $input: no such file" >&2; return 1; }

  local out
  out="$(output_path "$input")"

  if [[ -n "$resize_value" && "$do_webp" -eq 0 ]]; then
    magick "$input" -resize "$(resize_spec "$resize_value")" "$out" || {
      echo "$PROG: $input: resize failed" >&2
      return 1
    }
  elif [[ -z "$resize_value" && "$do_webp" -eq 1 ]]; then
    local cwebp_args=(-q "$quality")
    [[ "$lossless" -eq 1 ]] && cwebp_args=(-lossless)
    cwebp "${cwebp_args[@]}" "$input" -o "$out" >/dev/null 2>&1 || {
      echo "$PROG: $input: webp conversion failed" >&2
      return 1
    }
  fi

  echo "$input -> $out"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./test.sh`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add imgopt test.sh
git commit -m "feat: imgopt webp conversion (lossy default, lossless, quality override)"
```

---

### Task 4: `imgopt` — combined resize+webp pipeline, multi-file error handling

**Files:**
- Modify: `imgopt`
- Modify: `test.sh`

**Interfaces:**
- Consumes: everything from Tasks 1–3.
- Produces: `process_file()` in its final form (handles resize-only, webp-only, and combined resize+webp via a temp directory; already-existing main loop in Task 1 already tracks per-file exit status — no change needed there).

- [ ] **Step 1: Write the failing tests**

In `test.sh`, find:

```bash
test_webp_lossless_and_quality() {
  local status
  ./imgopt --webp --lossless "$FIXTURE" >/dev/null 2>&1; status=$?
  assert_success "webp lossless: exit 0" "$status"
  ./imgopt --webp --quality 40 "$FIXTURE" >/dev/null 2>&1; status=$?
  assert_success "webp quality override: exit 0" "$status"
}
```

Replace with:

```bash
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
  out="$(./imgopt --webp "$FIXTURE" "$FIXTURE_DIR/missing.png" 2>&1)"; status=$?
  assert_failure "multi-file: nonzero exit when one file missing" "$status"
  assert_contains "multi-file: error names missing file" "$out" "no such file"
  assert_file_exists "multi-file: good file still processed" "$FIXTURE_DIR/photo.webp"
}
```

Find:

```bash
test_resize_only
test_webp_only
test_webp_lossless_and_quality
```

Replace with:

```bash
test_resize_only
test_webp_only
test_webp_lossless_and_quality
test_combined_resize_webp
test_multi_file_continues_on_error
```

- [ ] **Step 2: Run tests to verify the new tests fail**

Run: `./test.sh`
Expected: `combined: *` tests fail (current `process_file` does nothing when both `resize_value` and `do_webp` are set — neither branch condition matches). `multi-file: *` tests should already pass (loop/error-continue behavior existed since Task 1/2) — confirm they do.

- [ ] **Step 3: Implement the combined pipeline**

In `imgopt`, find:

```bash
process_file() {
  local input="$1"
  [[ -f "$input" ]] || { echo "$PROG: $input: no such file" >&2; return 1; }

  local out
  out="$(output_path "$input")"

  if [[ -n "$resize_value" && "$do_webp" -eq 0 ]]; then
    magick "$input" -resize "$(resize_spec "$resize_value")" "$out" || {
      echo "$PROG: $input: resize failed" >&2
      return 1
    }
  elif [[ -z "$resize_value" && "$do_webp" -eq 1 ]]; then
    local cwebp_args=(-q "$quality")
    [[ "$lossless" -eq 1 ]] && cwebp_args=(-lossless)
    cwebp "${cwebp_args[@]}" "$input" -o "$out" >/dev/null 2>&1 || {
      echo "$PROG: $input: webp conversion failed" >&2
      return 1
    }
  fi

  echo "$input -> $out"
}
```

Replace with:

```bash
process_file() {
  local input="$1"
  [[ -f "$input" ]] || { echo "$PROG: $input: no such file" >&2; return 1; }

  local out
  out="$(output_path "$input")"

  local work="$input"
  local tmp_dir=""

  if [[ -n "$resize_value" ]]; then
    local resize_target="$out"
    if [[ "$do_webp" -eq 1 ]]; then
      tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/imgopt.XXXXXX")"
      resize_target="$tmp_dir/resized.${input##*.}"
    fi
    magick "$input" -resize "$(resize_spec "$resize_value")" "$resize_target" || {
      echo "$PROG: $input: resize failed" >&2
      [[ -n "$tmp_dir" ]] && rm -rf "$tmp_dir"
      return 1
    }
    work="$resize_target"
  fi

  if [[ "$do_webp" -eq 1 ]]; then
    local cwebp_args=(-q "$quality")
    [[ "$lossless" -eq 1 ]] && cwebp_args=(-lossless)
    cwebp "${cwebp_args[@]}" "$work" -o "$out" >/dev/null 2>&1 || {
      echo "$PROG: $input: webp conversion failed" >&2
      [[ -n "$tmp_dir" ]] && rm -rf "$tmp_dir"
      return 1
    }
  fi

  [[ -n "$tmp_dir" ]] && rm -rf "$tmp_dir"
  echo "$input -> $out"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./test.sh`
Expected: `All tests passed.` `imgopt` is now feature-complete per the spec.

- [ ] **Step 5: Commit**

```bash
git add imgopt test.sh
git commit -m "feat: imgopt combined resize+webp pipeline via temp dir"
```

---

### Task 5: `imgopt-wizard`

**Files:**
- Create: `imgopt-wizard`
- Modify: `test.sh`

**Interfaces:**
- Consumes: `imgopt`'s flag grammar (`--resize VALUE`, `--webp`, `--lossless`, `--quality N`) from Tasks 1–4.
- Produces: `build_flags(resize_value, webp_enabled, webp_mode, quality) -> newline-separated flags` — pure function, no I/O, independently testable. `main(args...)` — the interactive driver (prompts via `gum`, calls `build_flags`, execs `imgopt`).

- [ ] **Step 1: Write the failing test**

In `test.sh`, find:

```bash
test_multi_file_continues_on_error() {
  local out status
  out="$(./imgopt --webp "$FIXTURE" "$FIXTURE_DIR/missing.png" 2>&1)"; status=$?
  assert_failure "multi-file: nonzero exit when one file missing" "$status"
  assert_contains "multi-file: error names missing file" "$out" "no such file"
  assert_file_exists "multi-file: good file still processed" "$FIXTURE_DIR/photo.webp"
}
```

Replace with:

```bash
test_multi_file_continues_on_error() {
  local out status
  out="$(./imgopt --webp "$FIXTURE" "$FIXTURE_DIR/missing.png" 2>&1)"; status=$?
  assert_failure "multi-file: nonzero exit when one file missing" "$status"
  assert_contains "multi-file: error names missing file" "$out" "no such file"
  assert_file_exists "multi-file: good file still processed" "$FIXTURE_DIR/photo.webp"
}

test_wizard_build_flags() {
  local out
  out="$(source ./imgopt-wizard >/dev/null 2>&1; build_flags "1600" "1" "lossy" "80")"
  assert_contains "wizard flags: resize" "$out" "--resize"
  assert_contains "wizard flags: webp" "$out" "--webp"
  assert_contains "wizard flags: quality" "$out" "--quality"

  out="$(source ./imgopt-wizard >/dev/null 2>&1; build_flags "" "1" "lossless" "")"
  assert_contains "wizard flags: lossless" "$out" "--lossless"
  [[ "$out" != *"--resize"* ]] && pass "wizard flags: no resize when unset" || fail "wizard flags: no resize when unset"

  out="$(source ./imgopt-wizard >/dev/null 2>&1; build_flags "50%" "0" "lossy" "")"
  assert_contains "wizard flags: percent resize" "$out" "--resize 50%"
  [[ "$out" != *"--webp"* ]] && pass "wizard flags: no webp when disabled" || fail "wizard flags: no webp when disabled"
}
```

Find:

```bash
test_combined_resize_webp
test_multi_file_continues_on_error
```

Replace with:

```bash
test_combined_resize_webp
test_multi_file_continues_on_error
test_wizard_build_flags
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./test.sh`
Expected: `source ./imgopt-wizard` fails (`No such file or directory`), so `test_wizard_build_flags` assertions fail.

- [ ] **Step 3: Write the implementation**

Create `imgopt-wizard`:

```bash
#!/usr/bin/env bash
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMGOPT="$DIR/imgopt"

# === flag building (pure, testable) ===
build_flags() {
  local resize_value="$1" webp_enabled="$2" webp_mode="$3" quality="$4"
  local -a flags=()

  [[ -n "$resize_value" ]] && flags+=(--resize "$resize_value")

  if [[ "$webp_enabled" == "1" ]]; then
    flags+=(--webp)
    if [[ "$webp_mode" == "lossless" ]]; then
      flags+=(--lossless)
    elif [[ -n "$quality" ]]; then
      flags+=(--quality "$quality")
    fi
  fi

  printf '%s\n' "${flags[@]}"
}

# === interactive driver ===
main() {
  local -a input_files=("$@")
  if [[ ${#input_files[@]} -eq 0 ]]; then
    echo "Enter file paths (space-separated):"
    # ponytail: naive whitespace split, doesn't handle spaces in paths — pass files as args instead if needed
    read -r -a input_files
  fi

  local resize_value="" webp_enabled="0" webp_mode="lossy" quality=""

  if gum confirm "Resize?"; then
    resize_value="$(gum input --placeholder '1600 or 50%' --prompt 'Resize to: ')"
  fi

  if gum confirm "Convert to WebP?"; then
    webp_enabled="1"
    webp_mode="$(gum choose lossy lossless)"
    if [[ "$webp_mode" == "lossy" ]]; then
      quality="$(gum input --placeholder '80' --prompt 'Quality (blank = default 80): ')"
    fi
  fi

  local -a flags=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && flags+=("$line")
  done < <(build_flags "$resize_value" "$webp_enabled" "$webp_mode" "$quality")

  echo "Running: imgopt ${flags[*]} ${input_files[*]}"
  "$IMGOPT" "${flags[@]}" "${input_files[@]}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
```

```bash
chmod +x imgopt-wizard
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./test.sh`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add imgopt-wizard test.sh
git commit -m "feat: imgopt-wizard interactive gum-based prompt layer"
```

---

### Task 6: Tuna preset scripts

**Files:**
- Create: `tuna/webp-convert.sh`
- Create: `tuna/webp-resize-1600.sh`
- Modify: `test.sh`

**Interfaces:**
- Consumes: `imgopt`'s CLI contract from Tasks 1–4 (invoked via `"$HOME/.local/bin/imgopt"`, the post-install symlink location — not a relative path, since Tuna copies these scripts into `~/Library/Scripts`, detached from the project directory).

- [ ] **Step 1: Write the failing test**

In `test.sh`, find:

```bash
test_wizard_build_flags() {
```

and locate its closing `}` followed by the next section. Find this exact block (the end of `test_wizard_build_flags` through the runner list):

```bash
  out="$(source ./imgopt-wizard >/dev/null 2>&1; build_flags "50%" "0" "lossy" "")"
  assert_contains "wizard flags: percent resize" "$out" "--resize 50%"
  [[ "$out" != *"--webp"* ]] && pass "wizard flags: no webp when disabled" || fail "wizard flags: no webp when disabled"
}

# === run all tests ===
test_no_args_shows_usage_error
test_help_flag
test_missing_binary_error
test_resize_only
test_webp_only
test_webp_lossless_and_quality
test_combined_resize_webp
test_multi_file_continues_on_error
test_wizard_build_flags
```

Replace with:

```bash
  out="$(source ./imgopt-wizard >/dev/null 2>&1; build_flags "50%" "0" "lossy" "")"
  assert_contains "wizard flags: percent resize" "$out" "--resize 50%"
  [[ "$out" != *"--webp"* ]] && pass "wizard flags: no webp when disabled" || fail "wizard flags: no webp when disabled"
}

test_tuna_headers() {
  grep -q '@tuna.name' tuna/webp-convert.sh && pass "webp-convert.sh: has @tuna.name" || fail "webp-convert.sh: has @tuna.name"
  grep -q '@tuna.input arguments' tuna/webp-convert.sh && pass "webp-convert.sh: input arguments" || fail "webp-convert.sh: input arguments"
  grep -q '@tuna.name' tuna/webp-resize-1600.sh && pass "webp-resize-1600.sh: has @tuna.name" || fail "webp-resize-1600.sh: has @tuna.name"
  grep -q '@tuna.input arguments' tuna/webp-resize-1600.sh && pass "webp-resize-1600.sh: input arguments" || fail "webp-resize-1600.sh: input arguments"
}

test_tuna_presets_run() {
  local fake_home bin_dir status
  fake_home="$(mktemp -d)"
  bin_dir="$fake_home/.local/bin"
  mkdir -p "$bin_dir"
  ln -sf "$(pwd)/imgopt" "$bin_dir/imgopt"

  HOME="$fake_home" sh ./tuna/webp-convert.sh "$FIXTURE" >/dev/null 2>&1; status=$?
  assert_success "tuna webp-convert: exit 0" "$status"
  assert_file_exists "tuna webp-convert: output created" "$FIXTURE_DIR/photo.webp"

  rm -f "$FIXTURE_DIR/photo-1600w.webp"
  HOME="$fake_home" sh ./tuna/webp-resize-1600.sh "$FIXTURE" >/dev/null 2>&1; status=$?
  assert_success "tuna webp-resize-1600: exit 0" "$status"
  assert_file_exists "tuna webp-resize-1600: output created" "$FIXTURE_DIR/photo-1600w.webp"

  rm -rf "$fake_home"
}

# === run all tests ===
test_no_args_shows_usage_error
test_help_flag
test_missing_binary_error
test_resize_only
test_webp_only
test_webp_lossless_and_quality
test_combined_resize_webp
test_multi_file_continues_on_error
test_wizard_build_flags
test_tuna_headers
test_tuna_presets_run
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./test.sh`
Expected: `tuna_headers`/`tuna_presets_run` tests fail — `tuna/webp-convert.sh` and `tuna/webp-resize-1600.sh` don't exist yet.

- [ ] **Step 3: Write the implementation**

Create `tuna/webp-convert.sh`:

```sh
#!/bin/sh
# @tuna.name Convert to WebP
# @tuna.subtitle Lossy WebP, quality 80
# @tuna.input arguments
# @tuna.output text

"$HOME/.local/bin/imgopt" --webp "$@"
```

Create `tuna/webp-resize-1600.sh`:

```sh
#!/bin/sh
# @tuna.name Resize to 1600px + WebP
# @tuna.subtitle Max width 1600px, converts to WebP
# @tuna.input arguments
# @tuna.output text

"$HOME/.local/bin/imgopt" --webp --resize 1600 "$@"
```

```bash
chmod +x tuna/webp-convert.sh tuna/webp-resize-1600.sh
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./test.sh`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add tuna/webp-convert.sh tuna/webp-resize-1600.sh test.sh
git commit -m "feat: Tuna preset scripts for WebP convert and resize+webp"
```

---

### Task 7: `install.sh` and final wiring

**Files:**
- Create: `install.sh`
- Modify: `test.sh`

**Interfaces:**
- Consumes: `imgopt`, `imgopt-wizard`, `tuna/webp-convert.sh`, `tuna/webp-resize-1600.sh` (all prior tasks).
- Produces: `install.sh` — idempotent, symlinks the CLI/wizard into `~/.local/bin`, copies the Tuna presets into `~/Library/Scripts`, warns if `gum` is missing.

- [ ] **Step 1: Write the failing test**

In `test.sh`, find:

```bash
test_tuna_presets_run
```

Find the block ending in the runner list (the last two lines shown):

```bash
  rm -rf "$fake_home"
}

# === run all tests ===
test_no_args_shows_usage_error
test_help_flag
test_missing_binary_error
test_resize_only
test_webp_only
test_webp_lossless_and_quality
test_combined_resize_webp
test_multi_file_continues_on_error
test_wizard_build_flags
test_tuna_headers
test_tuna_presets_run
```

Replace with:

```bash
  rm -rf "$fake_home"
}

test_install_script() {
  local fake_home status
  fake_home="$(mktemp -d)"
  HOME="$fake_home" bash ./install.sh >/dev/null 2>&1; status=$?
  assert_success "install.sh: exit 0" "$status"
  [[ -L "$fake_home/.local/bin/imgopt" ]] && pass "install.sh: imgopt symlinked" || fail "install.sh: imgopt symlinked"
  [[ -L "$fake_home/.local/bin/imgopt-wizard" ]] && pass "install.sh: imgopt-wizard symlinked" || fail "install.sh: imgopt-wizard symlinked"
  [[ -f "$fake_home/Library/Scripts/imgopt-webp-convert.sh" ]] && pass "install.sh: webp-convert copied" || fail "install.sh: webp-convert copied"
  [[ -f "$fake_home/Library/Scripts/imgopt-webp-resize-1600.sh" ]] && pass "install.sh: webp-resize-1600 copied" || fail "install.sh: webp-resize-1600 copied"
  rm -rf "$fake_home"
}

# === run all tests ===
test_no_args_shows_usage_error
test_help_flag
test_missing_binary_error
test_resize_only
test_webp_only
test_webp_lossless_and_quality
test_combined_resize_webp
test_multi_file_continues_on_error
test_wizard_build_flags
test_tuna_headers
test_tuna_presets_run
test_install_script
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./test.sh`
Expected: `install.sh: *` tests fail — `install.sh` doesn't exist yet.

- [ ] **Step 3: Write the implementation**

Create `install.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
SCRIPTS_DIR="$HOME/Library/Scripts"

mkdir -p "$BIN_DIR" "$SCRIPTS_DIR"

ln -sf "$DIR/imgopt" "$BIN_DIR/imgopt"
ln -sf "$DIR/imgopt-wizard" "$BIN_DIR/imgopt-wizard"
echo "Linked imgopt and imgopt-wizard into $BIN_DIR"

cp "$DIR/tuna/webp-convert.sh" "$SCRIPTS_DIR/imgopt-webp-convert.sh"
cp "$DIR/tuna/webp-resize-1600.sh" "$SCRIPTS_DIR/imgopt-webp-resize-1600.sh"
chmod +x "$SCRIPTS_DIR/imgopt-webp-convert.sh" "$SCRIPTS_DIR/imgopt-webp-resize-1600.sh"
echo "Copied Tuna presets into $SCRIPTS_DIR"

if ! command -v gum >/dev/null 2>&1; then
  echo "gum not found — install with: brew install gum"
fi

echo "Done. Restart Tuna (or refresh its script catalog) to pick up the new actions."
```

```bash
chmod +x install.sh
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./test.sh`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add install.sh test.sh
git commit -m "feat: install.sh symlinks CLI/wizard and installs Tuna presets"
```

- [ ] **Step 6: Run the real install and do a manual end-to-end check**

Run: `./install.sh`
Expected: `imgopt`/`imgopt-wizard` symlinked into `~/.local/bin`, both Tuna preset scripts copied into `~/Library/Scripts`.

This step has effects outside the project directory (your actual `~/.local/bin` and `~/Library/Scripts`) — confirm with the user before running it if there's any doubt.

Then, manually (not automatable from here):
1. Confirm `~/.local/bin` is on `PATH` (`echo $PATH`) — if not, add it in your shell profile.
2. Open Tuna, refresh/re-scan its script catalog, and confirm "Convert to WebP" and "Resize to 1600px + WebP" appear as actions.
3. Select a real screenshot in Finder, run each Tuna action, and confirm the expected `.webp` file appears next to it.
