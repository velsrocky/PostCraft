// `PostCraft`'s native API. Keep bridge methods small, validated, and deterministic.

pub mod api;
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
    let desktop_capture = screenshot_portal_available();
    #[cfg(target_os = "linux")]
    let global_shortcuts = global_shortcuts::portal_supported();
    #[cfg(not(target_os = "linux"))]
    let (desktop_capture, global_shortcuts) = (false, false);

    let session_type = std::env::var("XDG_SESSION_TYPE").unwrap_or_default();
    let wayland_screencast =
        session_type.eq_ignore_ascii_case("wayland") && screencast_portal_available();
    PlatformCapabilities {
        desktop_capture,
        window_capture: false,
        system_audio_capture: false,
        global_shortcuts,
        clipboard_image_write: false,
        wayland_screencast,
        microphone_capture: false,
        capture_reason: if wayland_screencast {
            "Wayland ScreenCast portal is present; target selection requires a portal session."
                .to_owned()
        } else if session_type.eq_ignore_ascii_case("wayland") {
            "Wayland ScreenCast portal is unavailable in this session.".to_owned()
        } else {
            "Window and multi-display target enumeration is not available in the current adapter."
                .to_owned()
        },
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

#[cfg(target_os = "linux")]
pub fn capture_desktop(mode: String) -> Result<CaptureResult, NativeError> {
    if mode != "region" && mode != "screen" {
        return Err(NativeError::invalid(
            "capture mode must be region or screen",
        ));
    }
    if !screenshot_portal_available() {
        return Err(NativeError {
            code: "capture_unsupported".to_owned(),
            message: "The Freedesktop Screenshot portal is unavailable in this session.".to_owned(),
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
    let captured_path = file_uri_to_path(&uri).ok_or_else(|| NativeError {
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
    Ok(CaptureResult {
        path: captured_path.to_string_lossy().into_owned(),
        mode,
    })
}

#[cfg(target_os = "linux")]
fn unique_capture_token() -> u64 {
    use std::sync::atomic::{AtomicU64, Ordering};
    static NEXT_TOKEN: AtomicU64 = AtomicU64::new(1);
    NEXT_TOKEN.fetch_add(1, Ordering::Relaxed)
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

#[cfg(test)]
mod linux_capture_tests {
    use super::{file_uri_to_path, platform_capabilities};

    #[test]
    fn reports_definitively_unsupported_capabilities() {
        let capabilities = platform_capabilities();
        assert!(!capabilities.window_capture);
        assert!(!capabilities.system_audio_capture);
        // desktop_capture / global_shortcuts depend on the active desktop
        // portal, so they are not asserted here.
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

#[cfg(not(target_os = "linux"))]
pub fn capture_desktop(_mode: String) -> Result<CaptureResult, NativeError> {
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
