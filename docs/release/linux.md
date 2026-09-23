# Linux Release

PostCraft currently ships a Linux desktop bundle for x86_64. The supported
capture path uses the Freedesktop XDG Screenshot portal and requires a working
desktop session with D-Bus and a portal backend.

## Build and validate

From the repository root:

```bash
make build-linux
make validate-linux-bundle
```

The relocatable bundle is written to
`apps/desktop/build/linux/x64/release/bundle/`.

## AppImage staging

The packaging script prepares an AppImage directory and optionally invokes
`appimagetool` when `APPIMAGETOOL` is set:

```bash
APPIMAGETOOL=/path/to/appimagetool make package-linux-appimage
```

Without `APPIMAGETOOL`, the script still validates the Flutter bundle and
creates `build/linux-appimage/PostCraft.AppDir` for a controlled packaging
pipeline.

## Runtime requirements

- GTK 3 and its runtime dependencies
- A D-Bus user session
- `xdg-desktop-portal` with a Screenshot portal backend for capture
- FFmpeg and ffprobe on `PATH` for media conversion, unless explicitly
  configured with `POSTCRAFT_FFMPEG` and `POSTCRAFT_FFPROBE`

FFmpeg is not bundled by this repository. A release distributor must provide
the binaries and corresponding license/provenance notices before advertising
video export as available.

## Current support boundary

- Region and full-screen screenshots are supported when the portal advertises
  them.
- Global shortcuts are opt-in and capability-gated.
- Window capture, screen recording, system audio, and multi-display target
  selection remain under active development.
- Windows and macOS capture adapters are not included in this Linux release.
