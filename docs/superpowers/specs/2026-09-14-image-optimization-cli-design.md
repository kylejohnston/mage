# Image optimization CLI — design spec

Date: 2026-09-14

## Context

Replacing OptImage (macOS app) with a CLI/script-based workflow for two
recurring tasks:

- convert images to WebP for the web
- resize images (mostly large screenshots) by percentage or max width

Must work from any folder (not just a fixed automation folder), and be
usable both by typing commands directly and via
[Tuna](https://tunaformac.com/docs/start-here), a macOS launcher that can
run shell scripts against selected file(s).

Already available on this machine (no new dependencies needed for core
image work): `cwebp`, `magick`/`convert` (ImageMagick), `exiftool`. `gum`
(charmbracelet) will be added for the interactive wizard's prompts.

## Scope

- Operations: resize, and/or convert to WebP. Nothing else — no
  same-format re-compression/optimization (e.g. re-encoding a JPEG that
  stays a JPEG) and no metadata/EXIF handling beyond whatever `cwebp`
  already strips by default.
- Input formats: PNG, JPEG, TIFF — what `cwebp` and `magick` handle
  natively. HEIC is explicitly out of scope for v1 (primary use case is
  PNG screenshots).
- Two entry points, not one interactive-only tool:
  - `imgopt` — fast, non-interactive, flag-driven. Primary target for
    Tuna and for typing directly once flags are memorized.
  - `imgopt-wizard` — interactive, prompts for options via `gum`, for
    ad-hoc terminal use when you don't want to remember flags.

## Non-goals

- Folder recursion / batch-processing a whole directory tree.
- A GUI or Tuna dialog-based option picker (Tuna actions are
  non-interactive; see "Tuna integration" below).
- Format support beyond PNG/JPEG/TIFF.
- Packaging/distribution beyond this one machine.

## File layout

```
image-optimization-2026-09/
├── imgopt                    # main CLI (bash)
├── imgopt-wizard              # interactive wizard (bash + gum)
├── tuna/
│   ├── webp-convert.sh        # Tuna preset: convert to WebP
│   └── webp-resize-1600.sh    # Tuna preset: resize 1600px + WebP
├── test.sh                    # smoke test
└── docs/superpowers/specs/    # this file
```

## `imgopt` (core CLI)

### Usage

```
imgopt [--webp] [--lossless] [--quality N] [--resize VALUE] FILE [FILE...]
```

- At least one of `--webp` or `--resize` is required. Neither given →
  usage error (nothing to do).
- One or more file paths as positional args (this is how Tuna passes a
  multi-file selection with `@tuna.input arguments`). Each file is
  processed independently: one failure prints an error and continues to
  the rest; exit code is non-zero if any file failed.
- `-h`/`--help` prints usage.

### Flags

| Flag | Meaning |
|---|---|
| `--resize VALUE` | `VALUE` ending in `%` → percentage scale (e.g. `50%`). Otherwise → max width in px (e.g. `1600`). Aspect ratio preserved either way. |
| `--webp` | Convert the (possibly resized) result to WebP. |
| `--lossless` | WebP lossless mode instead of lossy. Only meaningful with `--webp`. |
| `--quality N` | Lossy quality 0–100, default 80. Ignored if `--lossless` is set. Only meaningful with `--webp`. |

### Pipeline

1. **Preflight**: verify `cwebp` and `magick` are on `PATH` (only check
   the one(s) actually needed for the requested operation); clear error
   naming the missing binary and the `brew install` command if not.
2. **Resize stage** (only if `--resize` given): run through ImageMagick
   (`magick in -resize <spec> out`), where `<spec>` is `VALUE` as given
   for percentage (`50%`) or `<width>x` for max-width (`1600x`, which
   caps width and lets height scale). This is the single resize code
   path regardless of what happens next — same-format-only and
   webp-after-resize both go through it.
3. **Convert stage** (only if `--webp` given): run `cwebp` on the
   resize stage's output (or the original file, if no resize was
   requested) to produce the final WebP.
4. Whichever stage ran last writes the final output at the inferred
   path (see below); intermediate temp files are cleaned up.

### Output path inference

Same folder as the input, suffixed only when the resize stage ran
(extension swap alone communicates a WebP conversion):

| Input | Flags | Output |
|---|---|---|
| `photo.png` | `--webp` | `photo.webp` |
| `photo.png` | `--resize 1600` | `photo-1600w.png` |
| `photo.png` | `--resize 50%` | `photo-50pct.png` |
| `photo.png` | `--webp --resize 1600` | `photo-1600w.webp` |

Re-running with the same inputs/flags overwrites the same output
deterministically — no separate overwrite confirmation.

## `imgopt-wizard`

Thin `gum`-based prompt layer, no image logic of its own:

1. Prompt for input file(s) if not passed as args.
2. `gum confirm` — resize? If yes, `gum input` for the value
   (percentage or px, same `VALUE` grammar as `--resize`).
3. `gum confirm` — convert to WebP? If yes, `gum choose` lossy/lossless;
   if lossy, `gum input` for quality (default 80).
4. Builds the equivalent `imgopt` flag string, echoes the command it's
   about to run, then executes it via subprocess (`exec` or direct
   call) — `imgopt` remains the single source of truth for all image
   handling, so the wizard can't drift out of sync with the CLI.

## Tuna integration

Per Tuna's script-action model: a script becomes a Tuna action via
`@tuna.*` header comments, discovered from `~/Library/Scripts` by
default (custom `scriptsDirectories` need Tuna Pro — not required
here). `@tuna.input arguments` passes the selected file(s) as argv.
Because a Tuna action can't prompt per-run, each preset is a fixed-flag
wrapper around `imgopt`:

**`tuna/webp-convert.sh`**
```sh
#!/bin/sh
# @tuna.name Convert to WebP
# @tuna.subtitle Lossy WebP, quality 80
# @tuna.input arguments
# @tuna.output text
imgopt --webp "$@"
```

**`tuna/webp-resize-1600.sh`**
```sh
#!/bin/sh
# @tuna.name Resize to 1600px + WebP
# @tuna.subtitle Max width 1600px, converts to WebP
# @tuna.input arguments
# @tuna.output text
imgopt --webp --resize 1600 "$@"
```

Install step copies both into `~/Library/Scripts`.

## Installation

- `imgopt` and `imgopt-wizard` symlinked into `~/.local/bin` (already
  on `PATH` — that's where Tuna itself is installed).
- `tuna/*.sh` copied into `~/Library/Scripts`.
- `gum` installed via `brew install gum` if not already present.

## Testing

`test.sh`: a single bash smoke test, no framework. Runs `imgopt`
against a small fixture PNG through each mode (`--webp`, `--resize`,
both), asserts the expected output file exists with the expected
format/dimensions via `magick identify`, then cleans up. Non-zero exit
on any assertion failure.

## Error handling

- Missing required binary (`cwebp`/`magick`) → named, actionable error
  before any processing starts.
- Missing/unreadable input file → per-file error, other files still
  processed.
- No `--webp`/`--resize` given → usage error, no processing.
- Unsupported input format → per-file error from the underlying tool,
  surfaced as-is (not specially caught — out of scope to pre-validate
  every format `cwebp`/`magick` might reject).
