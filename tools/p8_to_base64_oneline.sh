#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $(basename "$0") <AuthKey_XXXX.p8>" >&2
  exit 2
fi

p8="$1"
if [[ ! -f "$p8" ]]; then
  echo "File not found: $p8" >&2
  exit 2
fi

# macOS base64 wraps lines by default; strip newlines to make a single-line value.
base64 -i "$p8" | tr -d '\n'
