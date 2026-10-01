#!/usr/bin/env bash
set -euo pipefail

# Get the directory where this script lives
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check for gum (required by mage)
if ! command -v gum >/dev/null 2>&1; then
  echo "gum not found — install with: brew install gum"
fi

# Ensure directory exists
mkdir -p "$HOME/.local/bin"

# Symlink imgopt and mage
ln -sf "$script_dir/imgopt" "$HOME/.local/bin/imgopt"
ln -sf "$script_dir/mage" "$HOME/.local/bin/mage"

echo "Installation complete."
echo "  - Symlinked imgopt and mage to ~/.local/bin"
