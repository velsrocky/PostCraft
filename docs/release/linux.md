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
- **FFmpeg and ffprobe on `PATH`** for screen recording, timeline render,
  video posters, and audio waveforms, unless explicitly configured with
  `POSTCRAFT_FFMPEG` and `POSTCRAFT_FFPROBE`

Install FFmpeg from your distribution:

```bash
sudo apt install ffmpeg        # Debian / Ubuntu
sudo dnf install ffmpeg        # Fedora
sudo pacman -S ffmpeg          # Arch Linux
```

FFmpeg is not bundled by this repository. A release distributor must provide
the binaries and corresponding license/provenance notices before advertising
video export as available.

## Current support boundary

- Region and full-screen screenshots are supported when the portal advertises
  them.
- Multi-display capture targets are enumerated on X11 via `xrandr` and
  selectable from the capture home screen.
- Global shortcuts are opt-in and capability-gated.
- Window capture (interactive still), system audio, and microphone capture
  remain under active development.
- Windows and macOS have capture/recording adapters compiled in, but the
  primary verified release target remains this Linux AppImage.
