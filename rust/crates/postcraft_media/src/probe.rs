use crate::{MediaError, MediaResult};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::path::Path;
use std::process::Command;

/// Minimal stream facts extracted from an `ffprobe` JSON document.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ProbeResult {
    pub duration_us: i64,
    pub width: u32,
    pub height: u32,
    pub has_video: bool,
    pub has_audio: bool,
}

fn as_f64(value: &Value) -> Option<f64> {
    value
        .as_str()
        .and_then(|s| s.parse::<f64>().ok())
        .or_else(|| value.as_f64())
}

fn as_u64(value: &Value) -> Option<u64> {
    value
        .as_u64()
        .or_else(|| value.as_str().and_then(|s| s.parse::<u64>().ok()))
}

/// Pure parser over an ffprobe `-print_format json` document.
pub fn parse_ffprobe_json(json: &Value) -> ProbeResult {
    let mut result = ProbeResult {
        duration_us: 0,
        width: 0,
        height: 0,
        has_video: false,
        has_audio: false,
    };

    if let Some(streams) = json.get("streams").and_then(Value::as_array) {
        for stream in streams {
            match stream.get("codec_type").and_then(Value::as_str) {
                Some("video") => {
                    result.has_video = true;
                    if result.width == 0 {
                        let width = stream.get("width").and_then(as_u64).unwrap_or(0) as u32;
                        let height = stream.get("height").and_then(as_u64).unwrap_or(0) as u32;
                        result.width = width;
                        result.height = height;
                    }
                }
                Some("audio") => result.has_audio = true,
                _ => {}
            }
        }
    }

    let mut duration = json
        .get("format")
        .and_then(|format| format.get("duration"))
        .and_then(as_f64);
    if duration.is_none() {
        duration = json
            .get("streams")
            .and_then(Value::as_array)
            .and_then(|streams| {
                streams
                    .iter()
                    .filter_map(|stream| stream.get("duration").and_then(as_f64))
                    .fold(None, |acc: Option<f64>, value| {
                        Some(acc.map_or(value, |current| current.max(value)))
                    })
            });
    }
    result.duration_us = (duration.unwrap_or(0.0) * 1_000_000.0) as i64;
    result
}

/// Runs ffprobe on a media file.
pub fn probe_file(ffprobe: &Path, path: &str) -> MediaResult<ProbeResult> {
    let output = Command::new(ffprobe)
        .args([
            "-v",
            "error",
            "-show_format",
            "-show_streams",
            "-print_format",
            "json",
            path,
        ])
        .output()
        .map_err(|error| MediaError::new("ffprobe_launch_failed", error.to_string()))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_owned();
        return Err(MediaError::new(
            "ffprobe_failed",
            if stderr.is_empty() {
                "ffprobe could not read the file."
            } else {
                &stderr
            },
        ));
    }
    let parsed: Value = serde_json::from_slice(&output.stdout)
        .map_err(|error| MediaError::new("ffprobe_output", error.to_string()))?;
    Ok(parse_ffprobe_json(&parsed))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn parses_video_and_audio_streams() {
        let doc = json!({
            "format": { "duration": "12.5" },
            "streams": [
                { "codec_type": "video", "width": 1920, "height": 1080 },
                { "codec_type": "audio" }
            ]
        });
        let result = parse_ffprobe_json(&doc);
        assert!(result.has_video);
        assert!(result.has_audio);
        assert_eq!(result.width, 1920);
        assert_eq!(result.height, 1080);
        assert_eq!(result.duration_us, 12_500_000);
    }

    #[test]
    fn falls_back_to_stream_duration_and_string_numbers() {
        let doc = json!({
            "streams": [ { "codec_type": "video", "width": "1280", "height": "720", "duration": "3" } ]
        });
        let result = parse_ffprobe_json(&doc);
        assert!(result.has_video);
        assert!(!result.has_audio);
        assert_eq!(result.width, 1280);
        assert_eq!(result.duration_us, 3_000_000);
    }

    #[test]
    fn handles_empty_document() {
        let result = parse_ffprobe_json(&json!({}));
        assert_eq!(result.duration_us, 0);
        assert!(!result.has_video);
    }
}
