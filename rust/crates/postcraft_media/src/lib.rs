//! FFmpeg/ffprobe integration for PostCraft: discovery, capability probing,
//! validated command construction, progress parsing, and supervised render
//! jobs.
//!
//! FFmpeg is driven as a supervised child process (never in-process), with an
//! argv `Command` (never a shell string), bounded progress parsing, and
//! atomic temporary-to-final output. Cancellation is cooperative via a flag the
//! worker thread checks and by terminating the child process.

mod capabilities;
mod discovery;
mod job;
mod preview;
mod probe;
mod progress;
mod raw_video;
mod raw_writer;
mod recording;
mod timeline;
mod timeline_job;

pub use capabilities::MediaStatus;
pub use discovery::{EnginePaths, resolve_engines};
pub use job::{
    JobState, TranscodeProgress, TranscodeRequest, cancel_transcode, poll_transcode,
    run_transcode_to_completion, start_transcode,
};
pub use preview::{generate_poster, generate_waveform};
pub use probe::ProbeResult;
pub use raw_video::build_raw_video_args;
pub use raw_writer::write_packed_frame;
pub use recording::{
    RecordingCapabilities, RecordingRequest, RecordingSession, cancel_recording,
    recording_capabilities, start_recording, stop_recording,
};
pub use timeline::{TimelineClip, TimelineRenderRequest, build_timeline_args};
pub use timeline_job::start_timeline_render;

use serde::{Deserialize, Serialize};

/// Crate-local error mirroring `postcraft_core::NativeError` so this crate has
/// no dependency on the bridge types; the API layer maps it across.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct MediaError {
    pub code: String,
    pub message: String,
}

impl MediaError {
    pub fn new(code: &str, message: impl Into<String>) -> Self {
        Self {
            code: code.to_owned(),
            message: message.into(),
        }
    }
}

pub type MediaResult<T> = Result<T, MediaError>;

/// Report the resolved engine paths + codec availability.
pub fn media_status() -> MediaStatus {
    let engines = resolve_engines();
    let Some(ffmpeg) = engines.ffmpeg else {
        return MediaStatus::unavailable(
            "FFmpeg was not found. Set POSTCRAFT_FFMPEG/POSTCRAFT_FFPROBE or install it on PATH.",
        );
    };

    match capabilities::probe(&ffmpeg) {
        Ok(status) => MediaStatus {
            available: true,
            ..status
        },
        Err(error) => MediaStatus::unavailable(&error.message),
    }
}

/// Probe a media file with ffprobe.
pub fn probe_media(path: &str) -> MediaResult<ProbeResult> {
    let engines = resolve_engines();
    let ffprobe = engines
        .ffprobe
        .ok_or_else(|| MediaError::new("ffprobe_missing", "ffprobe was not found."))?;
    probe::probe_file(&ffprobe, path)
}
