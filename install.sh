#!/bin/bash
set -uo pipefail

# Get the directory where this script lives
script_dir="$(cd "$(dirname "$0")" && pwd)"

# Ensure directories exist
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/Library/Scripts"

# Symlink imgopt and imgopt-wizard
ln -sf "$script_dir/imgopt" "$HOME/.local/bin/imgopt"
ln -sf "$script_dir/imgopt-wizard" "$HOME/.local/bin/imgopt-wizard"

# Copy Tuna preset scripts with renamed names
cp "$script_dir/tuna/webp-convert.sh" "$HOME/Library/Scripts/imgopt-webp-convert.sh"
cp "$script_dir/tuna/webp-resize-1600.sh" "$HOME/Library/Scripts/imgopt-webp-resize-1600.sh"

echo "Installation complete."
echo "  - Symlinked imgopt and imgopt-wizard to ~/.local/bin"
echo "  - Copied Tuna presets to ~/Library/Scripts"
