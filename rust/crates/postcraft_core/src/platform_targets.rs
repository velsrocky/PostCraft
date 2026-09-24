use serde::{Deserialize, Serialize};
#[cfg(target_os = "linux")]
use std::process::Command;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct CaptureTarget {
    pub id: String,
    pub kind: String,
    pub name: String,
    pub width: u32,
    pub height: u32,
    pub scale_milli: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct CaptureTargetReport {
    pub targets: Vec<CaptureTarget>,
    pub window_capture: bool,
    pub multi_display: bool,
    pub microphone: bool,
    pub system_audio: bool,
    pub reason: String,
}

pub fn discover() -> CaptureTargetReport {
    #[cfg(target_os = "linux")]
    return discover_linux();
    #[cfg(target_os = "windows")]
    return crate::capture_windows::discover_targets();
    #[cfg(target_os = "macos")]
    return crate::capture_macos::discover_targets();
    #[cfg(not(any(target_os = "linux", target_os = "windows", target_os = "macos")))]
    CaptureTargetReport {
        targets: Vec::new(),
        window_capture: false,
        multi_display: false,
        microphone: false,
        system_audio: false,
        reason: "No capture adapter exists for this platform.".to_owned(),
    }
}

#[cfg(target_os = "linux")]
fn discover_linux() -> CaptureTargetReport {
    let session = std::env::var("XDG_SESSION_TYPE").unwrap_or_default();
    if session.eq_ignore_ascii_case("wayland") {
        return CaptureTargetReport {
            targets: Vec::new(),
            window_capture: false,
            multi_display: false,
            microphone: false,
            system_audio: false,
            reason:
                "Wayland targets are selected through an interactive ScreenCast portal session."
                    .to_owned(),
        };
    }
    let output = Command::new("xrandr").arg("--query").output();
    let text = output
        .ok()
        .filter(|result| result.status.success())
        .map(|result| String::from_utf8_lossy(&result.stdout).into_owned())
        .unwrap_or_default();
    let mut targets = Vec::new();
    for line in text.lines() {
        let parts = line.split_whitespace().collect::<Vec<_>>();
        if parts.len() < 3 || parts[1] != "connected" {
            continue;
        }
        let Some(size) = parts
            .iter()
            .find_map(|part| part.split_once('+').map(|(value, _)| value))
        else {
            continue;
        };
        let Some((width, height)) = size.split_once('x') else {
            continue;
        };
        let (Ok(width), Ok(height)) = (width.parse::<u32>(), height.parse::<u32>()) else {
            continue;
        };
        targets.push(CaptureTarget {
            id: parts[0].to_owned(),
            kind: "display".to_owned(),
            name: parts[0].to_owned(),
            width,
            height,
            scale_milli: 1000,
        });
    }
    CaptureTargetReport {
        multi_display: targets.len() > 1,
        targets,
        window_capture: false,
        microphone: false,
        system_audio: false,
        reason: "X11 display targets are read from xrandr; window/audio adapters are unavailable."
            .to_owned(),
    }
}
