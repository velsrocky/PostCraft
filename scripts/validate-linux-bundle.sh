#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="${1:-$ROOT/apps/desktop/build/linux/x64/release/bundle}"

required=(
  "$BUNDLE/postcraft"
  "$BUNDLE/lib/libpostcraft_core.so"
  "$BUNDLE/lib/libflutter_linux_gtk.so"
  "$BUNDLE/data/flutter_assets"
)

for path in "${required[@]}"; do
  if [[ ! -e "$path" ]]; then
    printf 'Missing bundle entry: %s\n' "$path" >&2
    exit 1
  fi
done

if [[ ! -x "$BUNDLE/postcraft" ]]; then
  printf 'Bundle executable is not executable: %s\n' "$BUNDLE/postcraft" >&2
  exit 1
fi

if ldd "$BUNDLE/postcraft" | grep -q 'not found'; then
  printf 'Bundle executable has unresolved shared-library dependencies.\n' >&2
  ldd "$BUNDLE/postcraft" >&2
  exit 1
fi

printf 'Linux bundle is structurally valid: %s\n' "$BUNDLE"
