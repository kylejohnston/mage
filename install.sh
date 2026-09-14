#!/usr/bin/env bash
set -uo pipefail

# Get the directory where this script lives
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check for gum (required by imgopt-wizard)
if ! command -v gum >/dev/null 2>&1; then
  echo "gum not found — install with: brew install gum"
fi

# Ensure directories exist
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/Library/Scripts"

# Symlink imgopt and imgopt-wizard
ln -sf "$script_dir/imgopt" "$HOME/.local/bin/imgopt"
ln -sf "$script_dir/imgopt-wizard" "$HOME/.local/bin/imgopt-wizard"

# Copy Tuna preset scripts with renamed names
cp "$script_dir/tuna/webp-convert.sh" "$HOME/Library/Scripts/imgopt-webp-convert.sh"
chmod +x "$HOME/Library/Scripts/imgopt-webp-convert.sh"
cp "$script_dir/tuna/webp-resize-1600.sh" "$HOME/Library/Scripts/imgopt-webp-resize-1600.sh"
chmod +x "$HOME/Library/Scripts/imgopt-webp-resize-1600.sh"

echo "Installation complete."
echo "  - Symlinked imgopt and imgopt-wizard to ~/.local/bin"
echo "  - Copied Tuna presets to ~/Library/Scripts"
