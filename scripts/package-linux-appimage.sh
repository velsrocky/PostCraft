#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="PostCraft"
VERSION="${POSTCRAFT_VERSION:-1.0.0}"
BUILD_DIR="$ROOT/apps/desktop/build/linux/x64/release/bundle"
STAGING="$ROOT/build/linux-appimage/${APP_NAME}.AppDir"

"$ROOT/scripts/validate-linux-bundle.sh" "$BUILD_DIR"
rm -rf "$STAGING"
mkdir -p "$STAGING/usr/bin" "$STAGING/usr/share/applications" "$STAGING/usr/share/metainfo"
cp -a "$BUILD_DIR/." "$STAGING/usr/"
cp "$ROOT/packaging/linux/com.velstech.postcraft.desktop" "$STAGING/usr/share/applications/"
cp "$ROOT/packaging/linux/com.velstech.postcraft.appdata.xml" "$STAGING/usr/share/metainfo/"

cat > "$STAGING/AppRun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$HERE/usr/postcraft" "$@"
EOF
chmod +x "$STAGING/AppRun"

# appimagetool requires desktop entry and icon at AppDir root
cp "$ROOT/packaging/linux/com.velstech.postcraft.desktop" "$STAGING/"
cp "$ROOT/packaging/linux/com.velstech.postcraft.svg" "$STAGING/.DirIcon"
cp "$ROOT/packaging/linux/com.velstech.postcraft.svg" "$STAGING/com.velstech.postcraft.svg"

# Install icons at standard hicolor sizes
mkdir -p "$STAGING/usr/share/icons/hicolor"
for size in 16 22 24 32 48 64 96 128 256; do
  dir="$STAGING/usr/share/icons/hicolor/${size}x${size}/apps"
  mkdir -p "$dir"
  if [[ -f "$ROOT/packaging/linux/com.velstech.postcraft.svg" ]]; then
    if command -v rsvg-convert >/dev/null 2>&1; then
      rsvg-convert -w "$size" -h "$size" \
        "$ROOT/packaging/linux/com.velstech.postcraft.svg" \
        > "$dir/com.velstech.postcraft.png"
    else
      cp "$ROOT/packaging/linux/com.velstech.postcraft.svg" \
         "$dir/com.velstech.postcraft.svg"
    fi
  fi
done

if [[ -z "${APPIMAGETOOL:-}" ]]; then
  printf 'Prepared AppImage staging directory: %s\n' "$STAGING"
  printf 'Set APPIMAGETOOL to create the final artifact.\n'
  exit 0
fi

OUTPUT="$ROOT/build/PostCraft-${VERSION}-x86_64.AppImage"
# -n: skip AppStream validation (no public homepage/release page yet)
"$APPIMAGETOOL" -n "$STAGING" "$OUTPUT"
printf 'Created %s\n' "$OUTPUT"
