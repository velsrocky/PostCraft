use crate::{CaptureResult, CaptureTarget, CaptureTargetReport, NativeError};

use core_foundation::array::CFArray;
use core_foundation::base::{CFGetTypeID, TCFType};
use core_foundation::dictionary::{CFDictionary, CFDictionaryGetTypeID, CFDictionaryRef};
use core_foundation::number::{CFNumber, CFNumberGetTypeID, CFNumberRef};
use core_foundation::string::{CFString, CFStringGetTypeID, CFStringRef};
use core_graphics::display::{CGDirectDisplayID, CGDisplay, CGRectNull};
use core_graphics::image::CGImage;
use core_graphics::window::{
    self, CGWindowID, kCGNullWindowID, kCGWindowBounds, kCGWindowImageDefault, kCGWindowLayer,
    kCGWindowListExcludeDesktopElements, kCGWindowListOptionIncludingWindow,
    kCGWindowListOptionOnScreenOnly, kCGWindowName, kCGWindowNumber, kCGWindowOwnerName,
};
use foreign_types::ForeignType;
use std::ffi::c_void;

unsafe extern "C" {
    fn CGImageGetBitmapInfo(image: *const c_void) -> u32;
}

const ALPHA_INFO_MASK: u32 = 0x1F;
const BYTE_ORDER_MASK: u32 = 0x7000;
const BYTE_ORDER_32_LITTLE: u32 = 2 << 12;
const ALPHA_NONE: u32 = 0;
const ALPHA_PREMULTIPLIED_FIRST: u32 = 2;
const ALPHA_FIRST: u32 = 4;
const ALPHA_NONE_SKIP_LAST: u32 = 5;
const ALPHA_NONE_SKIP_FIRST: u32 = 6;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum SourceLayout {
    Rgba,
    Bgra,
    Argb,
    Abgr,
}

struct MacWindow {
    id: CGWindowID,
    title: String,
    width: u32,
    height: u32,
}

fn raw_find(dict: &CFDictionary, key: CFStringRef) -> *const c_void {
    dict.find(key as *const c_void)
        .map(|value| *value)
        .unwrap_or(std::ptr::null())
}

fn dict_string(dict: &CFDictionary, key: CFStringRef) -> Option<String> {
    let value = raw_find(dict, key);
    if value.is_null() || unsafe { CFGetTypeID(value) } != unsafe { CFStringGetTypeID() } {
        return None;
    }
    Some(unsafe { CFString::wrap_under_get_rule(value as CFStringRef) }.to_string())
}

fn dict_number(dict: &CFDictionary, key: CFStringRef) -> Option<i64> {
    let value = raw_find(dict, key);
    if value.is_null() || unsafe { CFGetTypeID(value) } != unsafe { CFNumberGetTypeID() } {
        return None;
    }
    unsafe { CFNumber::wrap_under_get_rule(value as CFNumberRef) }.to_i64()
}

fn as_dictionary(pointer: *const c_void) -> Option<CFDictionary> {
    if pointer.is_null() || unsafe { CFGetTypeID(pointer) } != unsafe { CFDictionaryGetTypeID() } {
        return None;
    }
    Some(unsafe { CFDictionary::wrap_under_get_rule(pointer as CFDictionaryRef) })
}

fn discover_windows() -> Vec<MacWindow> {
    let options = kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements;
    let Some(array) = window::copy_window_info(options, kCGNullWindowID) else {
        return Vec::new();
    };
    collect_windows(&array)
}

fn collect_windows(array: &CFArray) -> Vec<MacWindow> {
    let mut windows = Vec::new();
    for entry in array.iter() {
        let Some(dict) = as_dictionary(*entry) else {
            continue;
        };
        let layer = dict_number(&dict, unsafe { kCGWindowLayer }).unwrap_or(1);
        if layer != 0 {
            continue;
        }
        let Some(id) = dict_number(&dict, unsafe { kCGWindowNumber }) else {
            continue;
        };
        let title = dict_string(&dict, unsafe { kCGWindowName })
            .or_else(|| dict_string(&dict, unsafe { kCGWindowOwnerName }))
            .unwrap_or_else(|| format!("Window {id}"));
        let bounds = raw_find(&dict, unsafe { kCGWindowBounds });
        let (width, height) = as_dictionary(bounds)
            .and_then(|bounds_dict| {
                let width_key = CFString::new("Width");
                let height_key = CFString::new("Height");
                let width = dict_number(&bounds_dict, width_key.as_concrete_TypeRef())?;
                let height = dict_number(&bounds_dict, height_key.as_concrete_TypeRef())?;
                Some((width.max(0) as u32, height.max(0) as u32))
            })
            .unwrap_or((0, 0));
        windows.push(MacWindow {
            id: id as CGWindowID,
            title,
            width,
            height,
        });
    }
    windows
}

fn source_layout(bitmap_info: u32) -> (SourceLayout, bool) {
    let alpha = bitmap_info & ALPHA_INFO_MASK;
    let byte_order = bitmap_info & BYTE_ORDER_MASK;
    let little_endian = byte_order == 0 || byte_order == BYTE_ORDER_32_LITTLE;
    let alpha_is_first = matches!(
        alpha,
        ALPHA_NONE | ALPHA_PREMULTIPLIED_FIRST | ALPHA_FIRST | ALPHA_NONE_SKIP_FIRST
    );
    let layout = match (alpha_is_first, little_endian) {
        (true, true) => SourceLayout::Bgra,
        (true, false) => SourceLayout::Argb,
        (false, true) => SourceLayout::Abgr,
        (false, false) => SourceLayout::Rgba,
    };
    let force_opaque = matches!(
        alpha,
        ALPHA_NONE | ALPHA_NONE_SKIP_LAST | ALPHA_NONE_SKIP_FIRST
    );
    (layout, force_opaque)
}

fn image_to_rgba(image: &CGImage) -> Result<(u32, u32, Vec<u8>), NativeError> {
    let width = image.width();
    let height = image.height();
    if width == 0 || height == 0 {
        return Err(NativeError {
            code: "capture_failed".to_owned(),
            message: "Captured image has an empty pixel area.".to_owned(),
        });
    }
    if image.bits_per_pixel() != 32 || image.bits_per_component() != 8 {
        return Err(NativeError {
            code: "capture_failed".to_owned(),
            message: "Captured image is not a 32-bit 8-bit-per-component bitmap.".to_owned(),
        });
    }
    let bitmap_info = unsafe { CGImageGetBitmapInfo(image.as_ptr() as *const c_void) };
    let (layout, force_opaque) = source_layout(bitmap_info);
    let bytes_per_row = image.bytes_per_row();
    let data = image.data();
    let bytes = data.bytes();
    let required = bytes_per_row
        .checked_mul(height)
        .ok_or_else(|| NativeError {
            code: "capture_failed".to_owned(),
            message: "Captured image dimensions overflow this platform.".to_owned(),
        })?;
    if bytes.len() < required {
        return Err(NativeError {
            code: "capture_failed".to_owned(),
            message: "Captured image pixel buffer is truncated.".to_owned(),
        });
    }
    let mut rgba = Vec::with_capacity(width * height * 4);
    for row in 0..height {
        let start = row * bytes_per_row;
        for pixel in bytes[start..start + width * 4].chunks_exact(4) {
            let converted = match layout {
                SourceLayout::Rgba => [pixel[0], pixel[1], pixel[2], pixel[3]],
                SourceLayout::Bgra => [pixel[2], pixel[1], pixel[0], pixel[3]],
                SourceLayout::Argb => [pixel[1], pixel[2], pixel[3], pixel[0]],
                SourceLayout::Abgr => [pixel[3], pixel[2], pixel[1], pixel[0]],
            };
            rgba.extend_from_slice(&converted);
        }
    }
    if force_opaque {
        for pixel in rgba.chunks_exact_mut(4) {
            pixel[3] = 255;
        }
    }
    Ok((width as u32, height as u32, rgba))
}

fn permission_error() -> NativeError {
    NativeError {
        code: "capture_permission_denied".to_owned(),
        message: "Screen capture returned no image; grant Screen Recording permission to PostCraft in System Settings > Privacy & Security."
            .to_owned(),
    }
}

fn store_capture(image: CGImage, mode: &str) -> Result<CaptureResult, NativeError> {
    let (width, height, rgba) = image_to_rgba(&image)?;
    let encoded = crate::encode_png_rgba(width, height, &rgba).map_err(|error| NativeError {
        code: "capture_encode_failed".to_owned(),
        message: format!("Screenshot could not be encoded as PNG: {error}"),
    })?;
    let path = crate::capture_output_path(".png");
    std::fs::write(&path, encoded).map_err(|error| NativeError {
        code: "capture_failed".to_owned(),
        message: format!("Screenshot could not be written: {error}"),
    })?;
    Ok(CaptureResult {
        path: path.to_string_lossy().into_owned(),
        mode: mode.to_owned(),
    })
}

fn resolve_display(target_id: Option<&str>) -> Result<CGDisplay, NativeError> {
    let target = match target_id {
        Some(target) => target,
        None => return Ok(CGDisplay::main()),
    };
    let id: CGDirectDisplayID = target.parse().map_err(|_| NativeError {
        code: "display_target_unavailable".to_owned(),
        message: format!("Display '{target}' is not a valid display id."),
    })?;
    let active = CGDisplay::active_displays().unwrap_or_default();
    if !active.contains(&id) {
        return Err(NativeError {
            code: "display_target_unavailable".to_owned(),
            message: format!("Display '{target}' is not an active display."),
        });
    }
    Ok(CGDisplay::new(id))
}

pub fn capture(mode: &str, target_id: Option<&str>) -> Result<CaptureResult, NativeError> {
    match mode {
        "screen" | "region" => {
            let image = CGDisplay::main().image().ok_or_else(permission_error)?;
            store_capture(image, mode)
        }
        "display" => {
            let display = resolve_display(target_id)?;
            let image = display.image().ok_or_else(permission_error)?;
            store_capture(image, mode)
        }
        "window" => {
            let target = target_id.ok_or_else(|| NativeError {
                code: "window_target_required".to_owned(),
                message: "Select a window target id before capturing a window.".to_owned(),
            })?;
            let id: CGWindowID = target.parse().map_err(|_| NativeError {
                code: "window_target_required".to_owned(),
                message: format!("Window target '{target}' is not a valid window id."),
            })?;
            let image = window::create_image(
                unsafe { CGRectNull },
                kCGWindowListOptionIncludingWindow,
                id,
                kCGWindowImageDefault,
            )
            .ok_or_else(permission_error)?;
            store_capture(image, mode)
        }
        _ => Err(NativeError::invalid(
            "capture mode must be region, screen, display, or window",
        )),
    }
}

pub fn discover_targets() -> CaptureTargetReport {
    let displays = CGDisplay::active_displays().unwrap_or_default();
    let mut targets = Vec::new();
    for id in &displays {
        let display = CGDisplay::new(*id);
        let bounds = display.bounds();
        let width = display.pixels_wide();
        let height = display.pixels_high();
        let points_width = bounds.size.width;
        let scale_milli = if points_width > 0.0 {
            ((width as f64 / points_width) * 1000.0).round() as u32
        } else {
            1000
        };
        targets.push(CaptureTarget {
            id: id.to_string(),
            kind: "display".to_owned(),
            name: format!("Display {id}"),
            width: width as u32,
            height: height as u32,
            scale_milli,
        });
    }
    for window in discover_windows() {
        targets.push(CaptureTarget {
            id: window.id.to_string(),
            kind: "window".to_owned(),
            name: window.title,
            width: window.width,
            height: window.height,
            scale_milli: 1000,
        });
    }
    CaptureTargetReport {
        window_capture: true,
        multi_display: displays.len() > 1,
        microphone: false,
        system_audio: false,
        reason: "Displays are read from CGGetActiveDisplayList; windows from CGWindowListCopyWindowInfo."
            .to_owned(),
        targets,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_common_macos_bitmap_layouts_to_rgba() {
        assert_eq!(
            source_layout(ALPHA_PREMULTIPLIED_FIRST | BYTE_ORDER_32_LITTLE),
            (SourceLayout::Bgra, false)
        );
        assert_eq!(
            source_layout(ALPHA_NONE_SKIP_LAST),
            (SourceLayout::Abgr, true)
        );
        assert_eq!(source_layout(ALPHA_FIRST), (SourceLayout::Bgra, false));
        assert_eq!(source_layout(ALPHA_NONE), (SourceLayout::Bgra, true));
    }
}
