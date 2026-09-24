# PostCraft

PostCraft is a local-first desktop app for screenshot capture, visual annotation, and creator-ready exports.

## Install (Linux)

Download `PostCraft-1.0.0-x86_64.AppImage` from the [latest release](https://github.com/velsrocky/PostCraft/releases/latest), then:

```bash
chmod +x PostCraft-1.0.0-x86_64.AppImage
./PostCraft-1.0.0-x86_64.AppImage
```

Optional integrity check:

```bash
sha256sum -c SHA256SUMS
```

**Runtime requirements:** GTK 3, a D-Bus session, and `xdg-desktop-portal` with a Screenshot backend for capture. **FFmpeg and ffprobe must be on `PATH`** for recording, timeline render, video posters, and audio waveforms (`sudo apt install ffmpeg` / `dnf` / `pacman`). PostCraft does not bundle FFmpeg.

The AppImage is **unsigned**. Prefer the GitHub release page over third-party mirrors.

## Current working slice

> **Platform status:** Capture, global shortcuts, multi-display targeting, and media recording are implemented for **Linux** (XDG portals + X11 xrandr) and compiled for **Windows/macOS** (GDI/CoreGraphics + FFmpeg gdigrab/avfoundation), with Linux as the primary verified ship target. Interactive window stills, system/microphone audio, and social OAuth share remain follow-on work. Local share (copy/save/open folder) ships now.

- Dark Flutter Material 3 workspace for Linux, Windows, and macOS.
- Feature-routed shell: editor, projects, library, templates, settings.
- Interactive editor canvas with rectangle, ellipse, arrow, text, pencil, Gaussian blur, and pixelation/redaction tools.
- Color selection, tool selection, command-based undo/redo, imported source images, and object/layer listing.
- `.postcraft` ZIP bundle save/open for the document, annotation layers, and embedded source image.
- PNG export and native image clipboard copy.
- Rust core over generated `flutter_rust_bridge` bindings; region pixelation and Gaussian blur for final export redaction.
- Linux CMake target builds and bundles the Rust shared library as part of the desktop app.
- Linux region and full-screen capture through the XDG Screenshot portal, when available; multi-display picker on X11.
- Local project library: captures/imports become durable projects; recents list with thumbnails, open, and delete.
- Debounced autosave to a recoverable draft, plus explicit save; interrupted sessions surface a recovery prompt.
- Opt-in system-wide capture shortcuts (Ctrl+Shift+A / F) via the XDG GlobalShortcuts portal, enabled from Settings.
- Content-addressed **media library**: captures/imports are indexed and browsable with search, kind filters, tags, open-in-editor, and delete. Video posters and audio waveforms are generated through the native FFmpeg worker.
- **Templates** apply starter documents into a new project; studio timeline supports trim and split; Export offers local share destinations (copy PNG, save, copy path, open folder).
- Crash/error logs with rotation, bundle migration runner scaffold, Settings update check against GitHub Releases.

The capture integration uses the Freedesktop XDG Screenshot portal on Linux (desktop-controlled, Wayland-friendly; behavior depends on the portal backend). Global shortcuts are off by default and register through the portal when enabled, so enabling never triggers an unexpected consent prompt; when the desktop does not advertise GlobalShortcuts support the toggle is disabled. The same shortcuts also work while the editor is focused without enabling the portal. Interactive window stills, system/microphone audio, and OAuth social providers remain follow-on work. Packaging notes: `packaging/DISTRIBUTION.md` (GitHub Releases, AUR, AppImageHub).

**FFmpeg/ffprobe are required on `PATH`** (or pointed at with `POSTCRAFT_FFMPEG` / `POSTCRAFT_FFPROBE`) for screen recording, timeline render, video posters, and audio waveforms. PostCraft does not bundle FFmpeg — install it from your distribution (see `docs/release/linux.md`).

## Persistence and the Isar decision

The vision specified Isar as the local metadata store. The pinned `isar_generator 3.1.0+1` transitively requires `analyzer 5.13`, which cannot parse this project's Dart 3.7+/3.12 syntax, so Isar codegen is not viable on the current toolchain and Isar 3.x is unmaintained. Rather than fork the codebase backward, both the project store and the media library sit **behind repository interfaces** (`ProjectRepository`, `AssetRepository`) with atomic file-backed implementations today: projects as folders with a `meta.json`, assets content-addressed by SHA-256 under `assets/<id>/` with an `index.json`. The domain and UI depend only on the interfaces, so a maintained Isar (or drift/SQLite) implementation can be dropped in later without touching features. Media bytes are never stored in an index.


## Requirements

- Flutter 3.44+ (Dart 3.12+)
- Rust stable and Cargo
- `flutter_rust_bridge_codegen` 2.13.0 for regenerating the bridge
- Linux desktop: GTK 3 development packages, CMake, Ninja, pkg-config
- Windows/macOS: Flutter desktop build prerequisites for the target OS
- Runtime media features (recording, timeline render, video posters, audio waveforms): **FFmpeg and ffprobe on `PATH`**, or `POSTCRAFT_FFMPEG` / `POSTCRAFT_FFPROBE` overrides. PostCraft does not bundle FFmpeg.

## Run on Linux

Use Flutter from the desktop package directory. FRB uses the platform loader; the Linux CMake runner builds and bundles its shared library for debug and release:

```bash
cd apps/desktop
flutter run -d linux
```

The Linux CMake build invokes Cargo and installs `libpostcraft_core.so` beside the other app libraries. For a release bundle:

```bash
cd apps/desktop
flutter build linux --release
```

Bundle path: `apps/desktop/build/linux/x64/release/bundle/`.

## Development checks

Run from the repository root. The Flutter commands enter `apps/desktop`, the package directory:

```bash
make test
make analyze
make build-linux
make validate-linux-bundle
```

Linux release packaging and runtime requirements are documented in
`docs/release/linux.md`. Distribution steps (GitHub Releases, AUR, AppImageHub)
are in `packaging/DISTRIBUTION.md`. The AppImage is not code-signed and does
not bundle FFmpeg.

Regenerate bindings after editing `rust/crates/postcraft_core/src/api.rs`:

```bash
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
```

The CLI is pinned in development to FRB codegen 2.13.0; keep it aligned with the Dart and Rust bridge dependencies. Generated Dart bindings are checked in so regular builds do not need the generator. After regenerating bindings, run `cargo fmt --all` once (the generator's import ordering differs from rustfmt) before committing.

## Project structure

- `apps/desktop/lib/src/app/`: routes, shell, and visual theme.
- `apps/desktop/lib/src/features/`: capture, editor, projects, library (media), templates, settings.
- `apps/desktop/lib/src/rust/`: generated bridge client.
- `rust/crates/postcraft_core/`: validated image operations, the capture + global-shortcut portal backends, and the FRB API.
- `POSTCRAFT_SPEC.md`: full architecture, schema, product, roadmap, security, and release specification.

## On-disk layout

App data lives under the platform application-support directory (`…/PostCraft/`):

- `projects/<id>/` — a durable project: `meta.json` (lightweight metadata for the recents list), `project.postcraft` (last saved revision), optional `project.postcraft.draft` (recoverable autosave; its presence marks `hasUnsavedDraft`), and `thumbnail.png`.
- `assets/` — the media library: each asset under `assets/<id>/<file>` (content-addressed by SHA-256, de-duplicated) with an atomic `index.json` of queryable metadata (name, kind, size, hash, tags, timestamp).

Every write is atomic (temp file + rename) and bundles are re-validated before they replace an existing revision.

## Project bundle format

The `.postcraft` package is a ZIP archive with `manifest.json` plus `media/source-image.bin` when a source image is present (format version `1`). Import validates archive entries, unsafe paths, symbolic links, file sizes, document dimensions, object identifiers, and geometry, rejecting structurally invalid documents before they reach disk. A save promotes the current document to `project.postcraft` and clears any draft; autosave writes only the draft, so the last durable revision is never lost. A sequential migration runner (`migrateManifest`) is in place for future format steps; today only version `1` is written and accepted.
