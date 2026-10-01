# mage

A small macOS CLI for the two things you actually do to a screenshot: shrink it and convert it to WebP. Built to replace [OptImage](https://optimage.app) with something scriptable.

![mage: quick defaults demo](demo/mage-quick.gif)

## What's here

- **`imgopt`** — non-interactive CLI. Flags in, optimized image out. Built for scripting and for [Tuna](https://tunaformac.com) actions.
- **`mage`** — interactive wizard. Prompts for resize/WebP options via [`gum`](https://github.com/charmbracelet/gum), then runs `imgopt` for you.
- **Tuna presets** — two ready-made launcher actions ("Convert to WebP", "Resize to 1600px + WebP") you can run on a file selection in Finder.

Both tools infer the output path from the input: same folder, extension swapped to `.webp` when converting, a width/percentage suffix added when resizing. Originals are never touched or deleted.

## Requirements

macOS, plus:

```bash
brew install imagemagick webp gum
```

(`imagemagick` and `webp` are required; `gum` is only needed for the interactive `mage` wizard — `imgopt` runs without it.)

## Install

```bash
git clone https://github.com/kylejohnston/mage.git
cd mage
./install.sh
```

This symlinks `imgopt` and `mage` into `~/.local/bin` (add that to your `PATH` if it isn't already) and copies the two Tuna preset scripts into `~/Library/Scripts`. Re-run it any time — it's idempotent.

## Usage

### `imgopt` — scriptable

```
Usage: imgopt [--webp] [--lossless] [--quality N] [--resize VALUE] FILE [FILE...]

  --resize VALUE   Percentage (e.g. 50%) or max width in px (e.g. 1600)
  --webp           Convert to WebP
  --lossless       WebP lossless mode (only with --webp)
  --quality N      Lossy quality 0-100, default 80 (only with --webp, ignored if --lossless)
  -h, --help       Show this help

At least one of --webp or --resize is required.
```

```bash
# Convert a screenshot to WebP (lossy, quality 80)
imgopt --webp screenshot.png
# -> screenshot.webp

# Resize to a max width of 1600px, keep the original format
imgopt --resize 1600 screenshot.png
# -> screenshot-1600w.png

# Both at once, lossless
imgopt --webp --lossless --resize 50% screenshot.png
# -> screenshot-50pct.webp

# A whole folder at once — each file processed independently,
# one bad file won't stop the rest
imgopt --webp ~/Desktop/screenshots/*.png
```

### `mage` — interactive

```bash
mage screenshot.png
```

Walks you through resize and WebP/quality choices, then runs `imgopt` with the flags it built — echoing the exact command first, so you always see what's about to run. Works with multiple files/a glob too:

```bash
mage ~/Desktop/screenshots/*.{png,jpg,jpeg}
```

<details>
<summary>More demos (full prompt tour, batch processing)</summary>

**Every prompt, with both defaults overridden:**

![mage: full tour demo](demo/mage-full-tour.gif)

**Multiple files in one run:**

![mage: batch demo](demo/mage-batch.gif)

</details>

### Tuna

After `./install.sh`, open Tuna and refresh its script catalog — "Convert to WebP" and "Resize to 1600px + WebP" show up as actions you can run against a file selection in Finder. Both call the installed `imgopt`, not a copy, so they always use whatever's at `~/.local/bin/imgopt`.

## Scope

- Input formats: PNG, JPEG, TIFF. HEIC isn't supported.
- No same-format re-optimization (re-encoding a JPEG that stays a JPEG) — only resize and/or WebP conversion.
- No folder recursion — pass files or a shell glob, not a directory.

## Development

```bash
./test.sh
```

One bash smoke-test file, no framework — 57 assertions covering `imgopt`'s pipeline, `mage`'s flag-building, the Tuna presets, and `install.sh`, all run against a generated fixture image (nothing checked into the repo).

Demo recordings live in [`demo/`](demo) as [VHS](https://github.com/charmbracelet/vhs) `.tape` scripts. They currently expect a sample image already in the working directory (not self-generating) — see the comments at the top of each `.tape` file.

## License

MIT — see [LICENSE](LICENSE).
