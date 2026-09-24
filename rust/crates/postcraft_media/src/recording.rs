use crate::discovery::resolve_engines;
use crate::{MediaError, MediaResult};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
#[cfg(not(any(target_os = "windows", target_os = "macos")))]
use std::env;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{Mutex, OnceLock};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RecordingCapabilities {
    pub supported: bool,
    pub microphone: bool,
    pub system_audio: bool,
    pub reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RecordingRequest {
    pub output: String,
    pub width: u32,
    pub height: u32,
    pub fps: u32,
    pub include_microphone: bool,
    pub include_system_audio: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RecordingSession {
    pub id: u32,
    pub output: String,
}

struct RecordingProcess {
    child: Child,
    output: PathBuf,
}

fn sessions() -> &'static Mutex<HashMap<u32, RecordingProcess>> {
    static SESSIONS: OnceLock<Mutex<HashMap<u32, RecordingProcess>>> = OnceLock::new();
    SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

static NEXT_SESSION_ID: AtomicU32 = AtomicU32::new(1);

#[cfg(target_os = "windows")]
fn platform_recording_capabilities() -> RecordingCapabilities {
    let supported = resolve_engines().ffmpeg.is_some();
    RecordingCapabilities {
        supported,
        microphone: false,
        system_audio: false,
        reason: if supported {
            "Windows screen recording via FFmpeg gdigrab.".to_owned()
        } else {
            "FFmpeg was not found for gdigrab recording.".to_owned()
        },
    }
}

#[cfg(target_os = "macos")]
fn platform_recording_capabilities() -> RecordingCapabilities {
    let supported = resolve_engines().ffmpeg.is_some();
    RecordingCapabilities {
        supported,
        microphone: false,
        system_audio: false,
        reason: if supported {
            "macOS screen recording via FFmpeg avfoundation; grant Screen Recording permission in System Settings."
                .to_owned()
        } else {
            "FFmpeg was not found for avfoundation recording.".to_owned()
        },
    }
}

#[cfg(not(any(target_os = "windows", target_os = "macos")))]
fn platform_recording_capabilities() -> RecordingCapabilities {
    let session = env::var("XDG_SESSION_TYPE")
        .unwrap_or_default()
        .to_lowercase();
    let supported =
        session == "x11" && env::var_os("DISPLAY").is_some() && resolve_engines().ffmpeg.is_some();
    let reason = if supported {
        "X11 screen recording is available through FFmpeg x11grab.".to_owned()
    } else if session == "wayland" {
        "Wayland recording requires a PipeWire portal backend; the X11 recorder is not used on Wayland.".to_owned()
    } else if env::var_os("DISPLAY").is_none() {
        "No X11 DISPLAY is available for recording.".to_owned()
    } else {
        "FFmpeg was not found for recording.".to_owned()
    };
    RecordingCapabilities {
        supported,
        microphone: false,
        system_audio: false,
        reason,
    }
}

pub fn recording_capabilities() -> RecordingCapabilities {
    platform_recording_capabilities()
}

/// FFmpeg input arguments for the platform screen source.
#[cfg(target_os = "windows")]
fn recording_input_args(request: &RecordingRequest) -> MediaResult<Vec<String>> {
    Ok(vec![
        "-f".to_owned(),
        "gdigrab".to_owned(),
        "-framerate".to_owned(),
        request.fps.to_string(),
        "-i".to_owned(),
        "desktop".to_owned(),
    ])
}

#[cfg(target_os = "macos")]
fn recording_input_args(request: &RecordingRequest) -> MediaResult<Vec<String>> {
    Ok(vec![
        "-f".to_owned(),
        "avfoundation".to_owned(),
        "-framerate".to_owned(),
        request.fps.to_string(),
        "-i".to_owned(),
        "1:none".to_owned(),
    ])
}

#[cfg(not(any(target_os = "windows", target_os = "macos")))]
fn recording_input_args(request: &RecordingRequest) -> MediaResult<Vec<String>> {
    let display = env::var("DISPLAY")
        .map_err(|_| MediaError::new("recording_unsupported", "DISPLAY is unavailable"))?;
    Ok(vec![
        "-f".to_owned(),
        "x11grab".to_owned(),
        "-video_size".to_owned(),
        format!("{}x{}", request.width, request.height),
        "-framerate".to_owned(),
        request.fps.to_string(),
        "-i".to_owned(),
        format!("{display}+0,0"),
    ])
}

pub fn start_recording(request: RecordingRequest) -> MediaResult<RecordingSession> {
    let capabilities = recording_capabilities();
    if !capabilities.supported {
        return Err(MediaError::new(
            "recording_unsupported",
            capabilities.reason,
        ));
    }
    if request.width == 0 || request.height == 0 || request.width > 16384 || request.height > 16384
    {
        return Err(MediaError::new(
            "invalid_recording",
            "recording dimensions are invalid",
        ));
    }
    if request.fps == 0 || request.fps > 240 {
        return Err(MediaError::new(
            "invalid_recording",
            "recording FPS must be within 1..=240",
        ));
    }
    if request.include_microphone || request.include_system_audio {
        return Err(MediaError::new(
            "audio_unsupported",
            "Microphone and system audio capture is not configured for this recorder",
        ));
    }
    let ffmpeg = resolve_engines()
        .ffmpeg
        .ok_or_else(|| MediaError::new("ffmpeg_missing", "FFmpeg was not found."))?;
    let input_args = recording_input_args(&request)?;
    let output = PathBuf::from(&request.output);
    if output.extension().and_then(|value| value.to_str()) != Some("mp4") {
        return Err(MediaError::new(
            "invalid_recording",
            "recording output must use the .mp4 extension",
        ));
    }
    if let Some(parent) = output.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|error| MediaError::new("recording_output", error.to_string()))?;
    }
    let child = Command::new(ffmpeg)
        .args(["-hide_banner", "-loglevel", "error", "-nostdin", "-y"])
        .args(&input_args)
        .args([
            "-c:v",
            "libx264",
            "-preset",
            "veryfast",
            "-pix_fmt",
            "yuv420p",
            "-movflags",
            "+faststart",
        ])
        .arg(&output)
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| MediaError::new("recording_launch_failed", error.to_string()))?;
    let id = NEXT_SESSION_ID.fetch_add(1, Ordering::Relaxed);
    sessions()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .insert(
            id,
            RecordingProcess {
                child,
                output: output.clone(),
            },
        );
    Ok(RecordingSession {
        id,
        output: output.to_string_lossy().into_owned(),
    })
}

pub fn stop_recording(id: u32) -> MediaResult<String> {
    let process = sessions()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .remove(&id)
        .ok_or_else(|| MediaError::new("recording_unknown", "recording session was not found"))?;
    let mut child = process.child;
    let _ = child.kill();
    let status = child
        .wait()
        .map_err(|error| MediaError::new("recording_wait", error.to_string()))?;
    if !process.output.exists()
        || std::fs::metadata(&process.output)
            .map(|metadata| metadata.len())
            .unwrap_or(0)
            == 0
    {
        return Err(MediaError::new(
            "recording_failed",
            format!("recording exited with status {status}"),
        ));
    }
    Ok(process.output.to_string_lossy().into_owned())
}

pub fn cancel_recording(id: u32) -> bool {
    let Some(mut process) = sessions()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .remove(&id)
    else {
        return false;
    };
    let _ = process.child.kill();
    let _ = std::fs::remove_file(process.output);
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reports_audio_as_unsupported_until_a_backend_exists() {
        assert!(!recording_capabilities().microphone);
        assert!(!recording_capabilities().system_audio);
    }
}
