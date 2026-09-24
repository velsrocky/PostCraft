// `PostCraft`'s native API. Keep bridge methods small, validated, and deterministic.

pub mod api;
#[cfg(target_os = "macos")]
#[allow(unsafe_code)]
mod capture_macos;
#[cfg(target_os = "windows")]
#[allow(unsafe_code)]
mod capture_windows;
#[allow(unsafe_code)]
mod frb_generated;
mod global_shortcuts;
mod pipewire_transport;
mod platform_targets;
mod screencast;

use serde::{Deserialize, Serialize};

// Media-engine types surfaced to Dart via the API layer (defined in postcraft_media).
pub use postcraft_media::{TimelineClip, TimelineRenderRequest};

const MAX_IMAGE_PIXELS: u64 = 100_000_000;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RuntimeInfo {
    pub version: String,
    pub platform: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct CaptureResult {
    pub path: String,
    pub mode: String,
}

/// A single portal global-shortcut binding request.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ShortcutBinding {
    pub id: String,
    pub preferred_trigger: String,
    pub description: String,
}

/// Outcome of a global-shortcut registration request.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct GlobalShortcutStatus {
    pub supported: bool,
    pub requested_ids: Vec<String>,
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[allow(clippy::struct_excessive_bools)]
pub struct PlatformCapabilities {
    pub desktop_capture: bool,
    pub window_capture: bool,
    pub system_audio_capture: bool,
    pub global_shortcuts: bool,
    pub clipboard_image_write: bool,
    pub wayland_screencast: bool,
    pub microphone_capture: bool,
    pub capture_reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ImageOperationResult {
    pub width: u32,
    pub height: u32,
    pub rgba: Vec<u8>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct NativeError {
    pub code: String,
    pub message: String,
}

pub use platform_targets::{CaptureTarget, CaptureTargetReport};

impl NativeError {
    fn invalid(message: impl Into<String>) -> Self {
        Self {
            code: "invalid_argument".to_owned(),
            message: message.into(),
        }
    }
}

pub fn runtime_info() -> RuntimeInfo {
    RuntimeInfo {
        version: env!("CARGO_PKG_VERSION").to_owned(),
        platform: std::env::consts::OS.to_owned(),
    }
}

/// Reports the native backend surface. Capture providers are implemented per OS as they are brought online.
pub fn platform_capabilities() -> PlatformCapabilities {
    #[cfg(target_os = "linux")]
    let (desktop_capture, global_shortcuts, window_capture) = (
        screenshot_portal_available(),
        global_shortcuts::portal_supported(),
        false,
    );
    #[cfg(any(target_os = "windows", target_os = "macos"))]
    let (desktop_capture, global_shortcuts, window_capture) = (true, false, true);
    #[cfg(not(any(target_os = "linux", target_os = "windows", target_os = "macos")))]
    let (desktop_capture, global_shortcuts, window_capture) = (false, false, false);

    let session_type = std::env::var("XDG_SESSION_TYPE").unwrap_or_default();
    let wayland_screencast =
        session_type.eq_ignore_ascii_case("wayland") && screencast_portal_available();

    #[cfg(target_os = "linux")]
    let capture_reason = if wayland_screencast {
        "Wayland ScreenCast portal is present; target selection requires a portal session."
            .to_owned()
    } else if session_type.eq_ignore_ascii_case("wayland") {
        "Wayland ScreenCast portal is unavailable in this session.".to_owned()
    } else {
        "X11 screen, display, and region capture via the Screenshot portal; window capture is not implemented (use region capture)."
            .to_owned()
    };
    #[cfg(target_os = "windows")]
    let capture_reason = "Full-desktop, per-display, and window capture via GDI; region capture returns the full desktop until interactive selection ships."
        .to_owned();
    #[cfg(target_os = "macos")]
    let capture_reason = "Display and window capture via CoreGraphics; region capture returns the full desktop until interactive selection ships, and Screen Recording permission is required."
        .to_owned();
    #[cfg(not(any(target_os = "linux", target_os = "windows", target_os = "macos")))]
    let capture_reason = "No capture adapter exists for this platform.".to_owned();

    PlatformCapabilities {
        desktop_capture,
        window_capture,
        system_audio_capture: false,
        global_shortcuts,
        clipboard_image_write: true,
        wayland_screencast,
        microphone_capture: false,
        capture_reason,
    }
}

#[cfg(target_os = "linux")]
fn screencast_portal_available() -> bool {
    zbus::blocking::Connection::session()
        .ok()
        .and_then(|connection| {
            zbus::blocking::Proxy::new(
                &connection,
                "org.freedesktop.portal.Desktop",
                "/org/freedesktop/portal/desktop",
                "org.freedesktop.portal.ScreenCast",
            )
            .ok()
        })
        .and_then(|proxy| proxy.get_property::<u32>("version").ok())
        .is_some()
}

#[cfg(not(target_os = "linux"))]
fn screencast_portal_available() -> bool {
    false
}

#[cfg(target_os = "linux")]
fn screenshot_portal_available() -> bool {
    screenshot_portal_version().is_some()
}

#[cfg(target_os = "linux")]
fn screenshot_portal_version() -> Option<u32> {
    if let Ok(connection) = zbus::blocking::Connection::session() {
        let proxy = zbus::blocking::Proxy::new(
            &connection,
            "org.freedesktop.portal.Desktop",
            "/org/freedesktop/portal/desktop",
            "org.freedesktop.portal.Screenshot",
        );
        return proxy
            .ok()
            .and_then(|proxy| proxy.get_property::<u32>("version").ok());
    }
    None
}

const CAPTURE_MODES: [&str; 4] = ["region", "screen", "display", "window"];

fn validate_capture_mode(mode: &str) -> Result<(), NativeError> {
    if CAPTURE_MODES.contains(&mode) {
        Ok(())
    } else {
        Err(NativeError::invalid(
            "capture mode must be region, screen, display, or window",
        ))
    }
}

#[cfg(not(any(target_os = "windows", target_os = "macos")))]
fn window_capture_unsupported() -> NativeError {
    NativeError {
        code: "window_capture_interactive_unsupported".to_owned(),
        message:
            "Window capture is not implemented; use region capture and select the window area."
                .to_owned(),
    }
}

#[cfg(target_os = "linux")]
pub fn capture_desktop(
    mode: String,
    target_id: Option<String>,
) -> Result<CaptureResult, NativeError> {
    validate_capture_mode(&mode)?;
    if mode == "window" {
        return Err(window_capture_unsupported());
    }
    if !screenshot_portal_available() {
        return Err(NativeError {
            code: "capture_unsupported".to_owned(),
            message: "The Freedesktop Screenshot portal is unavailable in this session.".to_owned(),
        });
    }

    let wayland_session = std::env::var("XDG_SESSION_TYPE")
        .unwrap_or_default()
        .eq_ignore_ascii_case("wayland");
    let display_geometry = if mode == "display" && !wayland_session {
        resolve_display_geometry(target_id.as_deref())
    } else {
        None
    };
    if mode == "display" && !wayland_session && target_id.is_some() && display_geometry.is_none() {
        return Err(NativeError {
            code: "display_target_unavailable".to_owned(),
            message: format!(
                "Display '{}' is not reported by xrandr.",
                target_id.as_deref().unwrap_or_default()
            ),
        });
    }

    let connection = zbus::blocking::Connection::session().map_err(|error| NativeError {
        code: "capture_backend_failed".to_owned(),
        message: format!("Unable to connect to the desktop screenshot portal: {error}"),
    })?;
    let token = format!(
        "postcraft_{}_{}",
        std::process::id(),
        unique_capture_token()
    );
    let sender = connection
        .unique_name()
        .map(ToString::to_string)
        .ok_or_else(|| NativeError {
            code: "capture_backend_failed".to_owned(),
            message: "Desktop bus did not assign a unique application name.".to_owned(),
        })?;
    let sender_path = sender.replace([':', '.'], "_");
    let request_path = format!("/org/freedesktop/portal/desktop/request/{sender_path}/{token}");
    let response_proxy = zbus::blocking::Proxy::new(
        &connection,
        "org.freedesktop.portal.Desktop",
        request_path.as_str(),
        "org.freedesktop.portal.Request",
    )
    .map_err(|error| NativeError {
        code: "capture_backend_failed".to_owned(),
        message: format!("Unable to prepare desktop capture response: {error}"),
    })?;
    let mut response_stream =
        response_proxy
            .receive_signal("Response")
            .map_err(|error| NativeError {
                code: "capture_backend_failed".to_owned(),
                message: format!("Unable to subscribe to desktop capture response: {error}"),
            })?;
    let mut options: std::collections::HashMap<&str, zbus::zvariant::Value<'_>> =
        std::collections::HashMap::new();
    options.insert("handle_token", zbus::zvariant::Value::from(token.as_str()));
    options.insert("interactive", zbus::zvariant::Value::from(mode == "region"));
    options.insert("modal", zbus::zvariant::Value::from(true));
    if screenshot_portal_version().is_some_and(|version| version >= 3) {
        options.insert(
            "target",
            zbus::zvariant::Value::from(if mode == "region" { 4_u32 } else { 1_u32 }),
        );
    }
    let portal = zbus::blocking::Proxy::new(
        &connection,
        "org.freedesktop.portal.Desktop",
        "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.Screenshot",
    )
    .map_err(|error| NativeError {
        code: "capture_unsupported".to_owned(),
        message: format!("Screenshot portal is unavailable: {error}"),
    })?;
    let handle: zbus::zvariant::OwnedObjectPath =
        portal.call("Screenshot", &("", options)).map_err(|error| {
            let message = error.to_string();
            NativeError {
                code: if message.contains("NotAllowed") || message.contains("Not supported") {
                    "capture_unsupported"
                } else {
                    "capture_failed"
                }
                .to_owned(),
                message: format!("Desktop rejected the screenshot request: {message}"),
            }
        })?;
    if handle.as_str() != request_path {
        let response_proxy = zbus::blocking::Proxy::new(
            &connection,
            "org.freedesktop.portal.Desktop",
            handle,
            "org.freedesktop.portal.Request",
        )
        .map_err(|error| NativeError {
            code: "capture_backend_failed".to_owned(),
            message: format!("Unable to subscribe to portal request: {error}"),
        })?;
        response_stream =
            response_proxy
                .receive_signal("Response")
                .map_err(|error| NativeError {
                    code: "capture_backend_failed".to_owned(),
                    message: format!("Unable to subscribe to portal response: {error}"),
                })?;
    }
    let response = response_stream.next().ok_or_else(|| NativeError {
        code: "capture_failed".to_owned(),
        message: "Desktop screenshot request ended without a response.".to_owned(),
    })?;
    let (status, mut results): (
        u32,
        std::collections::HashMap<String, zbus::zvariant::OwnedValue>,
    ) = response.body().deserialize().map_err(|error| NativeError {
        code: "capture_failed".to_owned(),
        message: format!("Invalid desktop screenshot response: {error}"),
    })?;
    if status == 1 {
        return Err(NativeError {
            code: "capture_cancelled".to_owned(),
            message: "Screenshot was cancelled.".to_owned(),
        });
    }
    if status != 0 {
        return Err(NativeError {
            code: "capture_failed".to_owned(),
            message: "Desktop screenshot request failed.".to_owned(),
        });
    }
    let uri = results
        .remove("uri")
        .and_then(|value| <String>::try_from(value).ok())
        .ok_or_else(|| NativeError {
            code: "capture_failed".to_owned(),
            message: "Desktop screenshot response has no image URI.".to_owned(),
        })?;
    let mut captured_path = file_uri_to_path(&uri).ok_or_else(|| NativeError {
        code: "capture_failed".to_owned(),
        message: "Desktop returned an unsupported screenshot URI.".to_owned(),
    })?;
    let metadata = std::fs::metadata(&captured_path).map_err(|error| NativeError {
        code: "capture_failed".to_owned(),
        message: format!("Screenshot file is not readable: {error}"),
    })?;
    if !metadata.is_file() || metadata.len() == 0 || metadata.len() > 512 * 1024 * 1024 {
        return Err(NativeError {
            code: "capture_failed".to_owned(),
            message: "Screenshot file is empty or exceeds the supported size.".to_owned(),
        });
    }
    if let Some(geometry) = display_geometry {
        captured_path = crop_capture_to_geometry(&captured_path, &geometry)?;
    }
    Ok(CaptureResult {
        path: captured_path.to_string_lossy().into_owned(),
        mode,
    })
}

fn unique_capture_token() -> u64 {
    use std::sync::atomic::{AtomicU64, Ordering};
    static NEXT_TOKEN: AtomicU64 = AtomicU64::new(1);
    NEXT_TOKEN.fetch_add(1, Ordering::Relaxed)
}

fn capture_output_path(suffix: &str) -> std::path::PathBuf {
    std::env::temp_dir().join(format!(
        "postcraft-capture-{}-{}{suffix}",
        std::process::id(),
        unique_capture_token()
    ))
}

/// Encodes tightly packed RGBA8 pixels as a PNG byte stream.
fn encode_png_rgba(width: u32, height: u32, rgba: &[u8]) -> Result<Vec<u8>, String> {
    let expected = usize::try_from(u64::from(width) * u64::from(height) * 4)
        .map_err(|_| "image buffer size overflows this platform".to_owned())?;
    if rgba.len() != expected {
        return Err(format!(
            "RGBA buffer length mismatch: expected {expected}, received {}",
            rgba.len()
        ));
    }
    let mut encoded = Vec::new();
    {
        let mut encoder = png::Encoder::new(&mut encoded, width, height);
        encoder.set_color(png::ColorType::Rgba);
        encoder.set_depth(png::BitDepth::Eight);
        let mut writer = encoder.write_header().map_err(|error| error.to_string())?;
        writer
            .write_image_data(rgba)
            .map_err(|error| error.to_string())?;
    }
    Ok(encoded)
}

/// Decodes a PNG into tightly packed RGBA8 pixels.
#[cfg(target_os = "linux")]
fn decode_png_rgba(path: &std::path::Path) -> Result<(u32, u32, Vec<u8>), String> {
    use std::io::BufReader;
    let file = std::fs::File::open(path).map_err(|error| error.to_string())?;
    let mut decoder = png::Decoder::new(BufReader::new(file));
    decoder.set_transformations(png::Transformations::EXPAND | png::Transformations::STRIP_16);
    let mut reader = decoder.read_info().map_err(|error| error.to_string())?;
    let mut buffer = vec![0_u8; reader.output_buffer_size()];
    let info = reader
        .next_frame(&mut buffer)
        .map_err(|error| error.to_string())?;
    let width = info.width;
    let height = info.height;
    let bytes = &buffer[..info.buffer_size()];
    let rgba = match info.color_type {
        png::ColorType::Rgba => bytes.to_vec(),
        png::ColorType::Rgb => {
            let mut rgba = Vec::with_capacity(bytes.len() / 3 * 4);
            for pixel in bytes.chunks_exact(3) {
                rgba.extend_from_slice(pixel);
                rgba.push(255);
            }
            rgba
        }
        png::ColorType::Grayscale => {
            let mut rgba = Vec::with_capacity(bytes.len() * 4);
            for value in bytes {
                rgba.extend_from_slice(&[*value, *value, *value, 255]);
            }
            rgba
        }
        png::ColorType::GrayscaleAlpha => {
            let mut rgba = Vec::with_capacity(bytes.len() * 2);
            for pixel in bytes.chunks_exact(2) {
                rgba.extend_from_slice(&[pixel[0], pixel[0], pixel[0], pixel[1]]);
            }
            rgba
        }
        png::ColorType::Indexed => {
            return Err("indexed screenshots are not supported after EXPAND".to_owned());
        }
    };
    Ok((width, height, rgba))
}

pub fn install_panic_hook(log_path: String) {
    let mut paths: Vec<std::path::PathBuf> = Vec::new();
    if !log_path.trim().is_empty() {
        paths.push(std::path::PathBuf::from(&log_path));
    }
    let fallback = std::env::temp_dir().join("postcraft-panic.log");
    if !paths.contains(&fallback) {
        paths.push(fallback);
    }
    std::panic::set_hook(Box::new(move |info| {
        let payload = info.payload();
        let message = if let Some(text) = payload.downcast_ref::<&str>() {
            (*text).to_owned()
        } else if let Some(text) = payload.downcast_ref::<String>() {
            text.clone()
        } else {
            "panic payload was not a string".to_owned()
        };
        let location = info
            .location()
            .map(|location| format!(" at {location}"))
            .unwrap_or_default();
        let entry = format!("postcraft panic{location}: {message}\n");
        use std::io::Write;
        for path in &paths {
            if let Ok(mut file) = std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(path)
            {
                let _ = file.write_all(entry.as_bytes());
            }
        }
    }));
}

#[cfg(target_os = "linux")]
fn file_uri_to_path(uri: &str) -> Option<std::path::PathBuf> {
    let encoded_path = uri.strip_prefix("file://")?;
    if !encoded_path.starts_with('/') {
        return None;
    }
    let mut decoded = Vec::with_capacity(encoded_path.len());
    let bytes = encoded_path.as_bytes();
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'%' {
            if index + 2 >= bytes.len() {
                return None;
            }
            let hex = std::str::from_utf8(&bytes[index + 1..index + 3]).ok()?;
            decoded.push(u8::from_str_radix(hex, 16).ok()?);
            index += 3;
        } else {
            decoded.push(bytes[index]);
            index += 1;
        }
    }
    Some(std::path::PathBuf::from(String::from_utf8(decoded).ok()?))
}

#[cfg(target_os = "linux")]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct DisplayGeometry {
    x: i32,
    y: i32,
    width: u32,
    height: u32,
}

#[cfg(target_os = "linux")]
fn parse_display_offsets(offsets: &str) -> Option<(i32, i32)> {
    let mut values = Vec::with_capacity(2);
    let bytes = offsets.as_bytes();
    let mut index = 0;
    while index < bytes.len() && values.len() < 2 {
        let mut sign = 1_i32;
        if bytes[index] == b'+' {
            index += 1;
            continue;
        }
        if bytes[index] == b'-' {
            sign = -1;
            index += 1;
        }
        let start = index;
        while index < bytes.len() && bytes[index].is_ascii_digit() {
            index += 1;
        }
        if start == index {
            return None;
        }
        let digits: i32 = offsets[start..index].parse().ok()?;
        values.push(sign * digits);
    }
    match values.as_slice() {
        [x, y] => Some((*x, *y)),
        _ => None,
    }
}

#[cfg(target_os = "linux")]
fn parse_display_geometry(token: &str) -> Option<(u32, u32, i32, i32)> {
    let (width, rest) = token.split_once('x')?;
    let width: u32 = width.parse().ok()?;
    let offset_start = rest.find(['+', '-'])?;
    let height: u32 = rest[..offset_start].parse().ok()?;
    let (x, y) = parse_display_offsets(&rest[offset_start..])?;
    Some((width, height, x, y))
}

#[cfg(target_os = "linux")]
fn parse_connected_displays(text: &str) -> Vec<(String, bool, DisplayGeometry)> {
    let mut displays = Vec::new();
    for line in text.lines() {
        let parts = line.split_whitespace().collect::<Vec<_>>();
        if parts.len() < 3 || parts[1] != "connected" {
            continue;
        }
        let primary = parts[2] == "primary";
        let Some((width, height, x, y)) = parts
            .iter()
            .skip(2)
            .find_map(|part| parse_display_geometry(part))
        else {
            continue;
        };
        displays.push((
            parts[0].to_owned(),
            primary,
            DisplayGeometry {
                x,
                y,
                width,
                height,
            },
        ));
    }
    displays
}

#[cfg(target_os = "linux")]
fn resolve_display_geometry(target_id: Option<&str>) -> Option<DisplayGeometry> {
    let output = std::process::Command::new("xrandr")
        .arg("--query")
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&output.stdout);
    let displays = parse_connected_displays(&text);
    if let Some(target_id) = target_id {
        return displays
            .into_iter()
            .find(|(name, _, _)| name == target_id)
            .map(|(_, _, geometry)| geometry);
    }
    displays
        .iter()
        .find(|(_, primary, _)| *primary)
        .or_else(|| displays.first())
        .map(|(_, _, geometry)| *geometry)
}

#[cfg(target_os = "linux")]
fn crop_capture_to_geometry(
    input: &std::path::Path,
    geometry: &DisplayGeometry,
) -> Result<std::path::PathBuf, NativeError> {
    let (image_width, image_height, rgba) =
        decode_png_rgba(input).map_err(|error| NativeError {
            code: "display_crop_failed".to_owned(),
            message: format!("Screenshot could not be decoded for display cropping: {error}"),
        })?;
    let left = geometry.x.max(0).min(image_width as i32) as u32;
    let top = geometry.y.max(0).min(image_height as i32) as u32;
    let right = geometry
        .x
        .saturating_add(geometry.width as i32)
        .clamp(0, image_width as i32) as u32;
    let bottom = geometry
        .y
        .saturating_add(geometry.height as i32)
        .clamp(0, image_height as i32) as u32;
    if right <= left || bottom <= top {
        return Err(NativeError {
            code: "display_target_unavailable".to_owned(),
            message: "The selected display lies outside the captured screenshot.".to_owned(),
        });
    }
    if left == 0 && top == 0 && right == image_width && bottom == image_height {
        return Ok(input.to_path_buf());
    }
    let crop_width = right - left;
    let crop_height = bottom - top;
    let mut cropped = vec![0_u8; (crop_width * crop_height * 4) as usize];
    let source_stride = image_width as usize * 4;
    for row in 0..crop_height as usize {
        let source_start = (top as usize + row) * source_stride + left as usize * 4;
        let target_start = row * crop_width as usize * 4;
        cropped[target_start..target_start + crop_width as usize * 4]
            .copy_from_slice(&rgba[source_start..source_start + crop_width as usize * 4]);
    }
    let encoded =
        encode_png_rgba(crop_width, crop_height, &cropped).map_err(|error| NativeError {
            code: "display_crop_failed".to_owned(),
            message: format!("Cropped screenshot could not be encoded: {error}"),
        })?;
    let output = capture_output_path("-display.png");
    std::fs::write(&output, encoded).map_err(|error| NativeError {
        code: "display_crop_failed".to_owned(),
        message: format!("Cropped screenshot could not be written: {error}"),
    })?;
    Ok(output)
}

#[cfg(all(test, target_os = "linux"))]
mod linux_capture_tests {
    use super::{file_uri_to_path, parse_connected_displays, platform_capabilities};

    #[test]
    fn reports_definitively_unsupported_capabilities() {
        let capabilities = platform_capabilities();
        assert!(!capabilities.window_capture);
        assert!(!capabilities.system_audio_capture);
        assert!(!capabilities.microphone_capture);
        assert!(capabilities.clipboard_image_write);
        // desktop_capture / global_shortcuts depend on the active desktop
        // portal, so they are not asserted here.
    }

    #[test]
    fn parses_xrandr_display_geometry() {
        let text = "\
eDP-1 connected primary 1920x1080+0+0 (normal left inverted right) 344mm x 194mm
HDMI-1 connected 2560x1440+1920+0 (normal left inverted right) 597mm x 336mm
DP-2 connected 1920x1080-1920+0 (normal left inverted right) 509mm x 286mm
DP-4 connected 1920x1080+-1920+-100 (normal left inverted right) 509mm x 286mm
DP-3 disconnected (normal left inverted right x axis y axis)
";
        let displays = parse_connected_displays(text);
        assert_eq!(displays.len(), 4);
        assert_eq!(displays[0].0, "eDP-1");
        assert!(displays[0].1);
        assert_eq!(displays[0].2.width, 1920);
        assert_eq!(displays[0].2.x, 0);
        assert_eq!(displays[1].2.x, 1920);
        assert_eq!(displays[1].2.height, 1440);
        assert!(!displays[1].1);
        assert_eq!(displays[2].2.x, -1920);
        assert_eq!(displays[3].2.x, -1920);
        assert_eq!(displays[3].2.y, -100);
    }

    #[test]
    fn decodes_escaped_file_uri() {
        let uri = "file:///tmp/PostCraft%20Capture.png";
        assert_eq!(
            file_uri_to_path(uri).expect("valid local URI"),
            std::path::PathBuf::from("/tmp/PostCraft Capture.png")
        );
    }

    #[test]
    fn rejects_non_local_and_malformed_file_uris() {
        assert!(file_uri_to_path("https://example.test/capture.png").is_none());
        assert!(file_uri_to_path("file:///tmp/%ZZ.png").is_none());
        assert!(file_uri_to_path("file:///tmp/%2").is_none());
    }
}

#[cfg(target_os = "windows")]
pub fn capture_desktop(
    mode: String,
    target_id: Option<String>,
) -> Result<CaptureResult, NativeError> {
    validate_capture_mode(&mode)?;
    capture_windows::capture(&mode, target_id.as_deref())
}

#[cfg(target_os = "macos")]
pub fn capture_desktop(
    mode: String,
    target_id: Option<String>,
) -> Result<CaptureResult, NativeError> {
    validate_capture_mode(&mode)?;
    capture_macos::capture(&mode, target_id.as_deref())
}

#[cfg(not(any(target_os = "linux", target_os = "windows", target_os = "macos")))]
pub fn capture_desktop(
    mode: String,
    _target_id: Option<String>,
) -> Result<CaptureResult, NativeError> {
    validate_capture_mode(&mode)?;
    if mode == "window" {
        return Err(window_capture_unsupported());
    }
    Err(NativeError {
        code: "capture_unsupported".to_owned(),
        message: "Desktop capture is not available on this platform yet.".to_owned(),
    })
}

/// Applies source-backed pixelation to a tightly packed RGBA image.
///
/// This function is useful for final redaction/export, while the Flutter editor
/// uses a cached preview. Input dimensions and byte length are bounded before
/// indexing so malformed bridge payloads cannot cause out-of-range access.
pub fn pixelate_rgba(
    width: u32,
    height: u32,
    rgba: Vec<u8>,
    block_size: u32,
) -> Result<ImageOperationResult, NativeError> {
    let expected_len = validate_rgba(width, height, &rgba)?;
    if block_size == 0 || block_size > 512 {
        return Err(NativeError::invalid("block_size must be between 1 and 512"));
    }

    let mut output = rgba;
    let step = block_size as usize;
    let row_stride = width as usize * 4;
    for block_y in (0..height as usize).step_by(step) {
        for block_x in (0..width as usize).step_by(step) {
            let end_y = (block_y + step).min(height as usize);
            let end_x = (block_x + step).min(width as usize);
            let mut sums = [0_u64; 4];
            let mut count = 0_u64;

            for y in block_y..end_y {
                for x in block_x..end_x {
                    let offset = y * row_stride + x * 4;
                    for channel in 0..4 {
                        sums[channel] += u64::from(output[offset + channel]);
                    }
                    count += 1;
                }
            }

            let average: [u8; 4] = std::array::from_fn(|channel| (sums[channel] / count) as u8);
            for y in block_y..end_y {
                for x in block_x..end_x {
                    let offset = y * row_stride + x * 4;
                    output[offset..offset + 4].copy_from_slice(&average);
                }
            }
        }
    }

    debug_assert_eq!(output.len(), expected_len);
    Ok(ImageOperationResult {
        width,
        height,
        rgba: output,
    })
}

#[allow(clippy::too_many_arguments)]
pub fn pixelate_region_rgba(
    width: u32,
    height: u32,
    rgba: Vec<u8>,
    left: u32,
    top: u32,
    region_width: u32,
    region_height: u32,
    block_size: u32,
) -> Result<ImageOperationResult, NativeError> {
    validate_rgba(width, height, &rgba)?;
    if block_size == 0 || block_size > 512 {
        return Err(NativeError::invalid("block_size must be between 1 and 512"));
    }
    if region_width == 0 || region_height == 0 || left >= width || top >= height {
        return Err(NativeError::invalid(
            "redaction region is empty or outside the image",
        ));
    }

    let right = left.saturating_add(region_width).min(width);
    let bottom = top.saturating_add(region_height).min(height);
    let step = block_size as usize;
    let row_stride = width as usize * 4;
    let mut output = rgba;

    for block_y in (top as usize..bottom as usize).step_by(step) {
        for block_x in (left as usize..right as usize).step_by(step) {
            let end_y = (block_y + step).min(bottom as usize);
            let end_x = (block_x + step).min(right as usize);
            let mut sums = [0_u64; 4];
            let mut count = 0_u64;
            for y in block_y..end_y {
                for x in block_x..end_x {
                    let offset = y * row_stride + x * 4;
                    for channel in 0..4 {
                        sums[channel] += u64::from(output[offset + channel]);
                    }
                    count += 1;
                }
            }
            let average: [u8; 4] = std::array::from_fn(|channel| (sums[channel] / count) as u8);
            for y in block_y..end_y {
                for x in block_x..end_x {
                    let offset = y * row_stride + x * 4;
                    output[offset..offset + 4].copy_from_slice(&average);
                }
            }
        }
    }

    Ok(ImageOperationResult {
        width,
        height,
        rgba: output,
    })
}

/// Applies a separable Gaussian blur to a bounded region of an RGBA image.
///
/// Only pixels within `[left, left+region_width) x [top, top+region_height)`
/// are blurred; all other pixels are left untouched. Uses a two-pass
/// horizontal/vertical separable kernel for O(width*height*radius) cost.
#[allow(clippy::too_many_arguments)]
pub fn blur_region_rgba(
    width: u32,
    height: u32,
    rgba: Vec<u8>,
    left: u32,
    top: u32,
    region_width: u32,
    region_height: u32,
    radius: u32,
) -> Result<ImageOperationResult, NativeError> {
    validate_rgba(width, height, &rgba)?;
    if radius == 0 || radius > 64 {
        return Err(NativeError::invalid("blur radius must be between 1 and 64"));
    }
    if region_width == 0 || region_height == 0 || left >= width || top >= height {
        return Err(NativeError::invalid(
            "blur region is empty or outside the image",
        ));
    }

    let right = (left + region_width).min(width);
    let bottom = (top + region_height).min(height);
    let row_stride = width as usize * 4;
    let mut output = rgba;

    // Horizontal pass
    let mut temp = vec![0u8; output.len()];
    let kernel = gaussian_kernel(radius as usize);
    let half = radius as i64;

    for y in top as usize..bottom as usize {
        for x in 0..width as usize {
            let px = x as i64;
            let mut sums = [0.0_f64; 4];
            let mut total_weight = 0.0_f64;
            for offset in -half..=half {
                let sx = px + offset;
                if sx < 0 || sx >= width as i64 {
                    continue;
                }
                let weight = kernel[(offset + half) as usize];
                let idx = y * row_stride + sx as usize * 4;
                for channel in 0..4 {
                    sums[channel] += output[idx + channel] as f64 * weight;
                }
                total_weight += weight;
            }
            if total_weight > 0.0 {
                let inv = 1.0 / total_weight;
                let idx = y * row_stride + x * 4;
                for channel in 0..4 {
                    temp[idx + channel] = (sums[channel] * inv).round().clamp(0.0, 255.0) as u8;
                }
            }
        }
    }

    // Vertical pass
    for y in top as usize..bottom as usize {
        let py = y as i64;
        for x in left as usize..right as usize {
            let mut sums = [0.0_f64; 4];
            let mut total_weight = 0.0_f64;
            for offset in -half..=half {
                let sy = py + offset;
                if sy < 0 || sy >= height as i64 {
                    continue;
                }
                let weight = kernel[(offset + half) as usize];
                let idx = sy as usize * row_stride + x * 4;
                for channel in 0..4 {
                    sums[channel] += temp[idx + channel] as f64 * weight;
                }
                total_weight += weight;
            }
            if total_weight > 0.0 {
                let inv = 1.0 / total_weight;
                let idx = y * row_stride + x * 4;
                for channel in 0..4 {
                    output[idx + channel] = (sums[channel] * inv).round().clamp(0.0, 255.0) as u8;
                }
            }
        }
    }

    Ok(ImageOperationResult {
        width,
        height,
        rgba: output,
    })
}

fn gaussian_kernel(radius: usize) -> Vec<f64> {
    let sigma = radius as f64 / 3.0;
    let mut kernel = Vec::with_capacity(2 * radius + 1);
    let mut sum = 0.0_f64;
    for i in 0..=radius {
        let x = i as f64;
        let w = (-x * x / (2.0 * sigma * sigma)).exp();
        kernel.push(w);
        sum += w;
    }
    // Mirror the first half (excluding center) to the second half
    for i in (1..radius).rev() {
        let w = kernel[i];
        kernel.push(w);
        sum += w;
    }
    // Need 2*radius+1 elements total. We have radius+1 + (radius-1) = 2*radius.
    // Add the final mirrored element.
    if radius > 0 {
        let w = kernel[0];
        kernel.push(w);
        sum += w;
    }
    for w in &mut kernel {
        *w /= sum;
    }
    kernel
}

fn validate_rgba(width: u32, height: u32, rgba: &[u8]) -> Result<usize, NativeError> {
    if width == 0 || height == 0 {
        return Err(NativeError::invalid("image dimensions must be positive"));
    }
    let pixels = u64::from(width) * u64::from(height);
    if pixels > MAX_IMAGE_PIXELS {
        return Err(NativeError::invalid(
            "image exceeds the 100 megapixel limit",
        ));
    }
    let expected = usize::try_from(pixels * 4)
        .map_err(|_| NativeError::invalid("image buffer size overflows this platform"))?;
    if rgba.len() != expected {
        return Err(NativeError::invalid(format!(
            "RGBA buffer length mismatch: expected {expected}, received {}",
            rgba.len()
        )));
    }
    Ok(expected)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pixelates_each_block_without_changing_dimensions() {
        let input = vec![
            0, 0, 0, 255, 100, 100, 100, 255, 200, 200, 200, 255, 255, 255, 255, 255,
        ];

        let output = pixelate_rgba(2, 2, input, 2).expect("valid image should pixelate");

        assert_eq!(output.width, 2);
        assert_eq!(output.height, 2);
        assert_eq!(
            output.rgba,
            vec![
                138, 138, 138, 255, 138, 138, 138, 255, 138, 138, 138, 255, 138, 138, 138, 255,
            ]
        );
    }

    #[test]
    fn rejects_wrong_buffer_length() {
        let error = pixelate_rgba(2, 2, vec![0; 8], 2).expect_err("invalid buffer should fail");

        assert_eq!(error.code, "invalid_argument");
        assert!(error.message.contains("length mismatch"));
    }

    #[test]
    fn rejects_zero_block_size() {
        let error = pixelate_rgba(1, 1, vec![0; 4], 0).expect_err("zero block should fail");

        assert!(error.message.contains("block_size"));
    }

    #[test]
    fn redacts_only_requested_region() {
        let input = vec![
            10, 10, 10, 255, 20, 20, 20, 255, 30, 30, 30, 255, 40, 40, 40, 255,
        ];
        let output =
            pixelate_region_rgba(2, 2, input, 0, 0, 1, 2, 8).expect("region should be pixelated");
        assert_eq!(&output.rgba[0..8], &[20, 20, 20, 255, 20, 20, 20, 255]);
        assert_eq!(&output.rgba[8..], &[20, 20, 20, 255, 40, 40, 40, 255]);
    }

    #[test]
    fn blur_preserves_image_dimensions() {
        let input: Vec<u8> = [0u8, 0, 0, 255].repeat(16);
        let output = blur_region_rgba(4, 4, input, 0, 0, 4, 4, 3).expect("blur should succeed");
        assert_eq!(output.width, 4);
        assert_eq!(output.height, 4);
        assert_eq!(output.rgba.len(), 4 * 4 * 4);
    }

    #[test]
    fn blur_rejects_zero_radius() {
        let input: Vec<u8> = [0u8, 0, 0, 255].repeat(16);
        let error =
            blur_region_rgba(4, 4, input, 0, 0, 4, 4, 0).expect_err("zero radius should fail");
        assert!(error.message.contains("radius"));
    }

    #[test]
    fn blur_rejects_region_outside_image() {
        let input: Vec<u8> = [0u8, 0, 0, 255].repeat(16);
        let error =
            blur_region_rgba(4, 4, input, 10, 0, 1, 1, 3).expect_err("out-of-bounds should fail");
        assert!(error.message.contains("blur region"));
    }
}
