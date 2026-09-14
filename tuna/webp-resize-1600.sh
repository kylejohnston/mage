#!/bin/sh
# @tuna.name Resize to 1600px + WebP
# @tuna.subtitle Max width 1600px, converts to WebP
# @tuna.input arguments
# @tuna.output text

"$HOME/.local/bin/imgopt" --webp --resize 1600 "$@"
