#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${1:-$ROOT/resources/ffmpeg/manifest.json}"

if [[ ! -f "$MANIFEST" ]]; then
  printf 'No FFmpeg provenance manifest found: %s\n' "$MANIFEST" >&2
  printf 'Use manifest.example.json as the release input.\n' >&2
  exit 1
fi

command -v jq >/dev/null || {
  printf 'jq is required to validate FFmpeg provenance.\n' >&2
  exit 1
}

for field in version source license architecture ffmpegSha256 ffprobeSha256 buildConfiguration notices; do
  value="$(jq -r --arg field "$field" '.[$field] // empty' "$MANIFEST")"
  if [[ -z "$value" || "$value" == replace-with-* ]]; then
    printf 'FFmpeg provenance field is missing or placeholder: %s\n' "$field" >&2
    exit 1
  fi
done

printf 'FFmpeg provenance manifest is complete: %s\n' "$MANIFEST"
