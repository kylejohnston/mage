#!/bin/sh
# @tuna.name Convert to WebP
# @tuna.subtitle Lossy WebP, quality 80
# @tuna.input arguments
# @tuna.output text

"$HOME/.local/bin/imgopt" --webp "$@"
