use crate::{MediaError, MediaResult};
use serde::{Deserialize, Serialize};
use std::path::Path;
use std::process::Command;

/// Result of probing the installed FFmpeg toolchain.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[allow(clippy::struct_excessive_bools)]
pub struct MediaStatus {
    pub available: bool,
    pub version: String,
    pub ffmpeg_path: String,
    pub ffprobe_path: String,
    pub h264: bool,
    pub aac: bool,
    pub vp9: bool,
    pub opus: bool,
    pub message: String,
}

impl MediaStatus {
    pub fn unavailable(message: &str) -> Self {
        Self {
            available: false,
            version: String::new(),
            ffmpeg_path: String::new(),
            ffprobe_path: String::new(),
            h264: false,
            aac: false,
            vp9: false,
            opus: false,
            message: message.to_owned(),
        }
    }
}

/// Extracts the version token from an `ffmpeg -version` banner line.
pub fn parse_version(banner: &str) -> Option<String> {
    let line = banner.lines().next()?;
    let mut tokens = line.split_whitespace();
    if tokens.next()? != "ffmpeg" || tokens.next()? != "version" {
        return None;
    }
    tokens.next().map(str::to_owned)
}

/// True if an encoder name appears in `ffmpeg -encoders` output.
pub fn has_encoder(encoders: &str, name: &str) -> bool {
    encoders.lines().any(|line| {
        line.split_whitespace()
            .nth(1)
            .is_some_and(|field| field == name)
    })
}

/// Runs `ffmpeg` to collect version + encoder availability.
pub fn probe(ffmpeg: &Path) -> MediaResult<MediaStatus> {
    let version_out = Command::new(ffmpeg)
        .args(["-hide_banner", "-version"])
        .output()
        .map_err(|error| MediaError::new("ffmpeg_launch_failed", error.to_string()))?;
    if !version_out.status.success() {
        return Err(MediaError::new(
            "ffmpeg_probe_failed",
            "ffmpeg -version exited with an error.",
        ));
    }
    let banner = String::from_utf8_lossy(&version_out.stdout);
    let version = parse_version(&banner).unwrap_or_else(|| "unknown".to_owned());

    let encoders = Command::new(ffmpeg)
        .args(["-hide_banner", "-encoders"])
        .output()
        .ok()
        .filter(|output| output.status.success())
        .map(|output| String::from_utf8_lossy(&output.stdout).into_owned())
        .unwrap_or_default();

    Ok(MediaStatus {
        available: true,
        version,
        ffmpeg_path: ffmpeg.display().to_string(),
        ffprobe_path: crate::discovery::resolve_engines()
            .ffprobe
            .map(|path| path.display().to_string())
            .unwrap_or_default(),
        h264: has_encoder(&encoders, "libx264"),
        aac: has_encoder(&encoders, "aac"),
        vp9: has_encoder(&encoders, "libvpx-vp9"),
        opus: has_encoder(&encoders, "libopus"),
        message: String::new(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_version_token() {
        let banner = "ffmpeg version 8.0.1-3ubuntu2 Copyright (c) the FFmpeg developers";
        assert_eq!(parse_version(banner).as_deref(), Some("8.0.1-3ubuntu2"));
    }

    #[test]
    fn rejects_unexpected_banner() {
        assert_eq!(parse_version("not a banner"), None);
    }

    #[test]
    fn detects_encoders_by_name() {
        let output =
            "Encoders:\n  V....D libx264   libx264 H.264 (codec h264)\n  A....D aac       AAC\n";
        assert!(has_encoder(output, "libx264"));
        assert!(has_encoder(output, "aac"));
        assert!(!has_encoder(output, "libopus"));
    }

    #[test]
    fn live_probe_against_system_ffmpeg_when_present() {
        let path = Path::new("ffmpeg");
        if Command::new(path).arg("-version").output().is_err() {
            eprintln!("ffmpeg not on PATH; skipping live probe");
            return;
        }
        let status = probe(path).expect("probe should succeed");
        assert!(status.available);
        assert!(!status.version.is_empty());
    }
}
