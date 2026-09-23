# PostCraft

PostCraft is a local-first desktop app for screenshot capture, visual annotation, and creator-ready exports.

## Current working slice

> **Platform status:** PostCraft's capture, global shortcuts, and media recording features are implemented for **Linux** via the Freedesktop XDG portals (Screenshot, GlobalShortcuts, ScreenCast) and PipeWire. The Flutter shell and editor build and run on macOS and Windows, but capture, global shortcuts, and recording backends are **Linux-only** in this release. Window capture, multi-display enumeration, and social sharing remain follow-on work across all platforms.

- Dark Flutter Material 3 workspace for Linux, Windows, and macOS.
- Feature-routed shell: editor, projects, library, templates, settings.
- Interactive editor canvas with rectangle, ellipse, arrow, text, pencil, Gaussian blur, and pixelation/redaction tools.
- Color selection, tool selection, command-based undo/redo, imported source images, and object/layer listing.
- `.postcraft` ZIP bundle save/open for the document, annotation layers, and embedded source image.
- PNG export and native image clipboard copy.
- Rust core over generated `flutter_rust_bridge` bindings; region pixelation and Gaussian blur for final export redaction.
- Linux CMake target builds and bundles the Rust shared library as part of the desktop app.
- Linux region and full-screen capture through the XDG Screenshot portal, when available.
- Local project library: captures/imports become durable projects; recents list with thumbnails, open, and delete.
- Debounced autosave to a recoverable draft, plus explicit save; interrupted sessions surface a recovery prompt.
- Opt-in system-wide capture shortcuts (Ctrl+Shift+A / F) via the XDG GlobalShortcuts portal, enabled from Settings.
- Content-addressed **media library**: captures/imports are indexed and browsable with search, kind filters, tags, open-in-editor, and delete. Video posters and audio waveforms are generated through the native FFmpeg worker.

The capture integration uses the Freedesktop XDG Screenshot portal on Linux (desktop-controlled, Wayland-friendly; behavior depends on the portal backend). Global shortcuts are off by default and register through the portal when enabled, so enabling never triggers an unexpected consent prompt; when the desktop does not advertise GlobalShortcuts support the toggle is disabled. The same shortcuts also work while the editor is focused without enabling the portal. Recording, timeline/FFmpeg editing, provider-based social sharing, plugins, and window/multi-monitor capture remain follow-on work.

## Persistence and the Isar decision

The vision specified Isar as the local metadata store. The pinned `isar_generator 3.1.0+1` transitively requires `analyzer 5.13`, which cannot parse this project's Dart 3.7+/3.12 syntax, so Isar codegen is not viable on the current toolchain and Isar 3.x is unmaintained. Rather than fork the codebase backward, both the project store and the media library sit **behind repository interfaces** (`ProjectRepository`, `AssetRepository`) with atomic file-backed implementations today: projects as folders with a `meta.json`, assets content-addressed by SHA-256 under `assets/<id>/` with an `index.json`. The domain and UI depend only on the interfaces, so a maintained Isar (or drift/SQLite) implementation can be dropped in later without touching features. Media bytes are never stored in an index.


## Requirements

- Flutter 3.44+ (Dart 3.12+)
- Rust stable and Cargo
- `flutter_rust_bridge_codegen` 2.13.0 for regenerating the bridge
- Linux desktop: GTK 3 development packages, CMake, Ninja, pkg-config
- Windows/macOS: Flutter desktop build prerequisites for the target OS

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
`docs/release/linux.md`. The current release artifact is a validated x86_64
bundle; it is not yet a signed distribution package and does not bundle
FFmpeg.

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

The `.postcraft` package is a ZIP archive with `manifest.json` plus `media/source-image.bin` when a source image is present (format version `1`). Import validates archive entries, unsafe paths, symbolic links, file sizes, document dimensions, object identifiers, and geometry, rejecting structurally invalid documents before they reach disk. A save promotes the current document to `project.postcraft` and clears any draft; autosave writes only the draft, so the last durable revision is never lost. Migrations remain planned reliability work.
