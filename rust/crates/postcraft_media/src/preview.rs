use crate::discovery::resolve_engines;
use crate::{MediaError, MediaResult};
use std::path::Path;
use std::process::Command;

/// Generates a bounded PNG poster frame using ffmpeg.
pub fn generate_poster(input: &str, output: &Path, width: u32) -> MediaResult<()> {
    if input.trim().is_empty() || width == 0 || width > 4096 {
        return Err(MediaError::new("invalid_preview", "invalid poster request"));
    }
    let ffmpeg = resolve_engines()
        .ffmpeg
        .ok_or_else(|| MediaError::new("ffmpeg_missing", "FFmpeg was not found."))?;
    let status = Command::new(ffmpeg)
        .args([
            "-hide_banner",
            "-loglevel",
            "error",
            "-nostdin",
            "-y",
            "-i",
            input,
            "-frames:v",
            "1",
            "-vf",
            &format!("scale={width}:-2"),
        ])
        .arg(output)
        .status()
        .map_err(|error| MediaError::new("preview_launch_failed", error.to_string()))?;
    if !status.success() {
        return Err(MediaError::new(
            "preview_failed",
            "FFmpeg could not generate a poster frame.",
        ));
    }
    Ok(())
}

/// Samples mono audio amplitude using ffmpeg's compact `astats` output.
pub fn generate_waveform(input: &str, samples: usize) -> MediaResult<Vec<f32>> {
    if input.trim().is_empty() || samples == 0 || samples > 100_000 {
        return Err(MediaError::new(
            "invalid_waveform",
            "invalid waveform request",
        ));
    }
    let ffmpeg = resolve_engines()
        .ffmpeg
        .ok_or_else(|| MediaError::new("ffmpeg_missing", "FFmpeg was not found."))?;
    let output = Command::new(ffmpeg)
        .args([
            "-hide_banner",
            "-nostdin",
            "-i",
            input,
            "-map",
            "0:a:0",
            "-ac",
            "1",
            "-ar",
            &samples.to_string(),
            "-f",
            "f32le",
            "pipe:1",
        ])
        .output()
        .map_err(|error| MediaError::new("waveform_launch_failed", error.to_string()))?;
    if !output.status.success() {
        return Err(MediaError::new(
            "waveform_failed",
            "FFmpeg could not read an audio stream.",
        ));
    }
    let values = output
        .stdout
        .chunks_exact(4)
        .map(|chunk| {
            f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]])
                .abs()
                .min(1.0)
        })
        .take(samples)
        .collect::<Vec<_>>();
    if values.is_empty() {
        return Err(MediaError::new(
            "waveform_empty",
            "audio stream produced no samples.",
        ));
    }
    Ok(values)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_unbounded_preview_requests() {
        assert_eq!(
            generate_waveform("/tmp/audio.wav", 0).unwrap_err().code,
            "invalid_waveform"
        );
        assert_eq!(
            generate_poster("", Path::new("/tmp/poster.png"), 320)
                .unwrap_err()
                .code,
            "invalid_preview"
        );
    }
}
