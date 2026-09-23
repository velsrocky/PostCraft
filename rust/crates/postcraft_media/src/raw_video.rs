use crate::{MediaError, MediaResult};
use std::path::Path;

/// Builds an FFmpeg argv list for packed raw frames supplied on stdin.
pub fn build_raw_video_args(
    width: u32,
    height: u32,
    fps: u32,
    pixel_format: &str,
    output: &Path,
) -> MediaResult<Vec<String>> {
    if width == 0 || height == 0 || width > 16384 || height > 16384 {
        return Err(MediaError::new(
            "invalid_raw_video",
            "raw video dimensions are invalid",
        ));
    }
    if fps == 0 || fps > 240 {
        return Err(MediaError::new(
            "invalid_raw_video",
            "raw video FPS must be within 1..=240",
        ));
    }
    if !matches!(pixel_format, "bgra" | "rgba" | "rgb24" | "bgr0") {
        return Err(MediaError::new(
            "invalid_raw_video",
            "unsupported raw pixel format",
        ));
    }
    if output.extension().and_then(|value| value.to_str()) != Some("mp4") {
        return Err(MediaError::new(
            "container_mismatch",
            "raw video output must use .mp4",
        ));
    }
    Ok(vec![
        "-hide_banner".into(),
        "-loglevel".into(),
        "error".into(),
        "-nostdin".into(),
        "-f".into(),
        "rawvideo".into(),
        "-pix_fmt".into(),
        pixel_format.into(),
        "-video_size".into(),
        format!("{width}x{height}"),
        "-framerate".into(),
        fps.to_string(),
        "-i".into(),
        "pipe:0".into(),
        "-c:v".into(),
        "libx264".into(),
        "-pix_fmt".into(),
        "yuv420p".into(),
        "-movflags".into(),
        "+faststart".into(),
        "-y".into(),
        output.to_string_lossy().into_owned(),
    ])
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn validates_raw_video_arguments() {
        let args = build_raw_video_args(1280, 720, 30, "bgra", Path::new("/tmp/out.mp4")).unwrap();
        assert!(args.windows(2).any(|pair| pair == ["-f", "rawvideo"]));
        assert_eq!(
            build_raw_video_args(0, 720, 30, "bgra", Path::new("/tmp/out.mp4"))
                .unwrap_err()
                .code,
            "invalid_raw_video"
        );
    }
}
