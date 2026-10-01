# mage 🧙

A small macOS CLI for the two things you actually do to a screenshot: shrink it and convert it to WebP. Built to replace [OptImage](https://optimage.app) with something that works from the command line.

![mage: quick defaults demo](demo/mage-quick.gif)

## What's here

- **`mage`** — interactive wizard. Prompts for resize/WebP options via [`gum`](https://github.com/charmbracelet/gum), then runs `imgopt` for you.
- **`imgopt`** — the CLI `mage` calls under the hood. Run it directly if you ever want to script this; `imgopt --help` has the flags.

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

This symlinks `imgopt` and `mage` into `~/.local/bin` (add that to your `PATH` if it isn't already). Re-run it any time — it won't break anything if you do.

## Usage

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

Want to skip the prompts and call the underlying tool directly — in a script, a cron job, wherever? See [`imgopt`](imgopt), or run `imgopt --help`.

## Scope

- Input formats: PNG, JPEG, TIFF. HEIC isn't supported.
- No same-format re-optimization (re-encoding a JPEG that stays a JPEG) — only resize and/or WebP conversion.
- No folder recursion — pass files or a shell glob, not a directory.

## Development

```bash
./test.sh
```

One bash smoke-test file, no framework — 45 assertions covering `imgopt`'s pipeline, `mage`'s flag-building, and `install.sh`, all run against a generated fixture image (nothing checked into the repo).

Demo recordings live in [`demo/`](demo) as [VHS](https://github.com/charmbracelet/vhs) `.tape` scripts. They currently expect a sample image already in the working directory (not self-generating) — see the comments at the top of each `.tape` file.

## License

MIT — see [LICENSE](LICENSE).
