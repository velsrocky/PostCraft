# FFmpeg Release Provenance

PostCraft does not redistribute FFmpeg from this repository. A release build
must either provide a separately licensed FFmpeg/ffprobe pair or document that
the host system supplies them.

Before bundling binaries, record the exact source URL, version, architecture,
build configuration, SHA-256 checksums, and applicable LGPL/GPL notices in this
directory. The release pipeline rejects a bundle manifest without these
fields.
