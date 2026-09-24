use crate::{CaptureResult, CaptureTarget, CaptureTargetReport, NativeError};

use std::ffi::c_void;
use windows_sys::Win32::Foundation::{BOOL, HWND, LPARAM, RECT};
use windows_sys::Win32::Graphics::Gdi::{
    BI_RGB, BITMAPINFO, BITMAPINFOHEADER, BitBlt, CreateCompatibleBitmap, CreateCompatibleDC,
    DIB_RGB_COLORS, DeleteDC, DeleteObject, EnumDisplayMonitors, GetDC, GetDIBits, GetMonitorInfoW,
    HDC, HGDIOBJ, MONITORINFOEXW, ReleaseDC, SRCCOPY, SelectObject,
};
use windows_sys::Win32::Storage::Xps::PrintWindow;
use windows_sys::Win32::UI::WindowsAndMessaging::{
    EnumWindows, GetShellWindow, GetSystemMetrics, GetWindowRect, GetWindowTextLengthW,
    GetWindowTextW, IsWindowVisible, MONITORINFOF_PRIMARY, PW_RENDERFULLCONTENT, SM_CXSCREEN,
    SM_CXVIRTUALSCREEN, SM_CYSCREEN, SM_CYVIRTUALSCREEN, SM_XVIRTUALSCREEN, SM_YVIRTUALSCREEN,
};

struct MonitorEntry {
    device: String,
    rect: RECT,
    primary: bool,
}

struct WindowEntry {
    hwnd: HWND,
    title: String,
    rect: RECT,
}

fn utf16_to_string(buffer: &[u16]) -> String {
    let end = buffer
        .iter()
        .position(|value| *value == 0)
        .unwrap_or(buffer.len());
    String::from_utf16_lossy(&buffer[..end])
}

fn rect_width(rect: &RECT) -> i32 {
    rect.right - rect.left
}

fn rect_height(rect: &RECT) -> i32 {
    rect.bottom - rect.top
}

unsafe extern "system" fn monitor_proc(
    hmonitor: windows_sys::Win32::Graphics::Gdi::HMONITOR,
    _hdc: HDC,
    _clip: *mut RECT,
    lparam: LPARAM,
) -> BOOL {
    unsafe {
        let monitors = &mut *(lparam as *mut Vec<MonitorEntry>);
        let mut info: MONITORINFOEXW = std::mem::zeroed();
        info.monitorInfo.cbSize = std::mem::size_of::<MONITORINFOEXW>() as u32;
        if GetMonitorInfoW(hmonitor, &mut info.monitorInfo) == 0 {
            return 1;
        }
        monitors.push(MonitorEntry {
            device: utf16_to_string(&info.szDevice),
            rect: info.monitorInfo.rcMonitor,
            primary: info.monitorInfo.dwFlags & MONITORINFOF_PRIMARY != 0,
        });
        1
    }
}

fn enumerate_monitors() -> Vec<MonitorEntry> {
    let mut monitors = Vec::new();
    unsafe {
        EnumDisplayMonitors(
            std::ptr::null_mut(),
            std::ptr::null(),
            Some(monitor_proc),
            &mut monitors as *mut Vec<MonitorEntry> as LPARAM,
        );
    }
    monitors
}

unsafe extern "system" fn window_proc(hwnd: HWND, lparam: LPARAM) -> BOOL {
    unsafe {
        let windows = &mut *(lparam as *mut Vec<WindowEntry>);
        if IsWindowVisible(hwnd) == 0 || hwnd == GetShellWindow() {
            return 1;
        }
        let title_length = GetWindowTextLengthW(hwnd);
        if title_length <= 0 {
            return 1;
        }
        let mut buffer = vec![0_u16; title_length as usize + 1];
        if GetWindowTextW(hwnd, buffer.as_mut_ptr(), buffer.len() as i32) <= 0 {
            return 1;
        }
        let mut rect: RECT = std::mem::zeroed();
        if GetWindowRect(hwnd, &mut rect) == 0 || rect_width(&rect) <= 0 || rect_height(&rect) <= 0
        {
            return 1;
        }
        windows.push(WindowEntry {
            hwnd,
            title: utf16_to_string(&buffer),
            rect,
        });
        1
    }
}

fn enumerate_windows() -> Vec<WindowEntry> {
    let mut windows = Vec::new();
    unsafe {
        EnumWindows(
            Some(window_proc),
            &mut windows as *mut Vec<WindowEntry> as LPARAM,
        );
    }
    windows
}

fn virtual_screen_rect() -> RECT {
    unsafe {
        let mut rect = RECT {
            left: GetSystemMetrics(SM_XVIRTUALSCREEN),
            top: GetSystemMetrics(SM_YVIRTUALSCREEN),
            right: 0,
            bottom: 0,
        };
        let width = GetSystemMetrics(SM_CXVIRTUALSCREEN);
        let height = GetSystemMetrics(SM_CYVIRTUALSCREEN);
        if width > 0 && height > 0 {
            rect.right = rect.left + width;
            rect.bottom = rect.top + height;
            return rect;
        }
        RECT {
            left: 0,
            top: 0,
            right: GetSystemMetrics(SM_CXSCREEN),
            bottom: GetSystemMetrics(SM_CYSCREEN),
        }
    }
}

fn read_bitmap_rgba(
    hdc: HDC,
    bitmap: windows_sys::Win32::Graphics::Gdi::HBITMAP,
    width: i32,
    height: i32,
) -> Result<Vec<u8>, NativeError> {
    unsafe {
        let mut info: BITMAPINFO = std::mem::zeroed();
        info.bmiHeader = BITMAPINFOHEADER {
            biSize: std::mem::size_of::<BITMAPINFOHEADER>() as u32,
            biWidth: width,
            biHeight: -height,
            biPlanes: 1,
            biBitCount: 32,
            biCompression: BI_RGB,
            biSizeImage: 0,
            biXPelsPerMeter: 0,
            biYPelsPerMeter: 0,
            biClrUsed: 0,
            biClrImportant: 0,
        };
        let mut pixels = vec![0_u8; (width * height * 4) as usize];
        let scanned = GetDIBits(
            hdc,
            bitmap,
            0,
            height as u32,
            pixels.as_mut_ptr() as *mut c_void,
            &mut info,
            DIB_RGB_COLORS,
        );
        if scanned == 0 {
            return Err(NativeError {
                code: "capture_failed".to_owned(),
                message: "GDI could not read the captured bitmap pixels.".to_owned(),
            });
        }
        for pixel in pixels.chunks_exact_mut(4) {
            pixel.swap(0, 2);
        }
        Ok(pixels)
    }
}

fn with_memory_bitmap<F>(width: i32, height: i32, draw: F) -> Result<Vec<u8>, NativeError>
where
    F: FnOnce(HDC) -> bool,
{
    if width <= 0 || height <= 0 {
        return Err(NativeError {
            code: "capture_failed".to_owned(),
            message: "Capture target has an empty pixel area.".to_owned(),
        });
    }
    unsafe {
        let screen_dc = GetDC(std::ptr::null_mut());
        if screen_dc.is_null() {
            return Err(NativeError {
                code: "capture_failed".to_owned(),
                message: "GDI could not acquire the screen device context.".to_owned(),
            });
        }
        let memory_dc = CreateCompatibleDC(screen_dc);
        if memory_dc.is_null() {
            ReleaseDC(std::ptr::null_mut(), screen_dc);
            return Err(NativeError {
                code: "capture_failed".to_owned(),
                message: "GDI could not create a compatible device context.".to_owned(),
            });
        }
        let bitmap = CreateCompatibleBitmap(screen_dc, width, height);
        if bitmap.is_null() {
            DeleteDC(memory_dc);
            ReleaseDC(std::ptr::null_mut(), screen_dc);
            return Err(NativeError {
                code: "capture_failed".to_owned(),
                message: "GDI could not create a compatible bitmap.".to_owned(),
            });
        }
        let previous = SelectObject(memory_dc, bitmap as HGDIOBJ);
        let drawn = draw(memory_dc);
        SelectObject(memory_dc, previous);
        let result = if drawn {
            read_bitmap_rgba(memory_dc, bitmap, width, height)
        } else {
            Err(NativeError {
                code: "capture_failed".to_owned(),
                message: "GDI could not draw into the capture bitmap.".to_owned(),
            })
        };
        DeleteObject(bitmap);
        DeleteDC(memory_dc);
        ReleaseDC(std::ptr::null_mut(), screen_dc);
        result
    }
}

fn store_capture(
    rgba: Vec<u8>,
    width: i32,
    height: i32,
    mode: &str,
) -> Result<CaptureResult, NativeError> {
    let encoded = crate::encode_png_rgba(width as u32, height as u32, &rgba).map_err(|error| {
        NativeError {
            code: "capture_encode_failed".to_owned(),
            message: format!("Screenshot could not be encoded as PNG: {error}"),
        }
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

fn capture_rect(rect: RECT, mode: &str) -> Result<CaptureResult, NativeError> {
    let width = rect_width(&rect);
    let height = rect_height(&rect);
    let origin_x = rect.left;
    let origin_y = rect.top;
    let rgba = with_memory_bitmap(width, height, |memory_dc| unsafe {
        let screen_dc = GetDC(std::ptr::null_mut());
        if screen_dc.is_null() {
            return false;
        }
        let blitted = BitBlt(
            memory_dc, 0, 0, width, height, screen_dc, origin_x, origin_y, SRCCOPY,
        );
        ReleaseDC(std::ptr::null_mut(), screen_dc);
        blitted != 0
    })?;
    store_capture(rgba, width, height, mode)
}

fn capture_window(hwnd: HWND, mode: &str) -> Result<CaptureResult, NativeError> {
    unsafe {
        if IsWindowVisible(hwnd) == 0 {
            return Err(NativeError {
                code: "window_target_unavailable".to_owned(),
                message: "The selected window is no longer visible.".to_owned(),
            });
        }
        let mut rect: RECT = std::mem::zeroed();
        if GetWindowRect(hwnd, &mut rect) == 0 {
            return Err(NativeError {
                code: "window_target_unavailable".to_owned(),
                message: "The selected window no longer exists.".to_owned(),
            });
        }
        let width = rect_width(&rect);
        let height = rect_height(&rect);
        let origin_x = rect.left;
        let origin_y = rect.top;
        let printed = with_memory_bitmap(width, height, |memory_dc| {
            PrintWindow(hwnd, memory_dc, PW_RENDERFULLCONTENT) != 0
        });
        let rgba = match printed {
            Ok(rgba) => rgba,
            Err(_) => with_memory_bitmap(width, height, |memory_dc| {
                let screen_dc = GetDC(std::ptr::null_mut());
                if screen_dc.is_null() {
                    return false;
                }
                let blitted = BitBlt(
                    memory_dc, 0, 0, width, height, screen_dc, origin_x, origin_y, SRCCOPY,
                );
                ReleaseDC(std::ptr::null_mut(), screen_dc);
                blitted != 0
            })?,
        };
        store_capture(rgba, width, height, mode)
    }
}

pub fn capture(mode: &str, target_id: Option<&str>) -> Result<CaptureResult, NativeError> {
    match mode {
        "screen" | "region" => capture_rect(virtual_screen_rect(), mode),
        "display" => {
            let monitors = enumerate_monitors();
            let monitor = match target_id {
                Some(target) => monitors
                    .iter()
                    .find(|monitor| monitor.device == target)
                    .ok_or_else(|| NativeError {
                        code: "display_target_unavailable".to_owned(),
                        message: format!("Display '{target}' was not found on this system."),
                    })?,
                None => monitors
                    .iter()
                    .find(|monitor| monitor.primary)
                    .or_else(|| monitors.first())
                    .ok_or_else(|| NativeError {
                        code: "display_target_unavailable".to_owned(),
                        message: "No display is available for capture.".to_owned(),
                    })?,
            };
            capture_rect(monitor.rect, mode)
        }
        "window" => {
            let target = target_id.ok_or_else(|| NativeError {
                code: "window_target_required".to_owned(),
                message: "Select a window target id before capturing a window.".to_owned(),
            })?;
            let hwnd: usize = target.parse().map_err(|_| NativeError {
                code: "window_target_required".to_owned(),
                message: format!("Window target '{target}' is not a valid window id."),
            })?;
            capture_window(hwnd as HWND, mode)
        }
        _ => Err(NativeError::invalid(
            "capture mode must be region, screen, display, or window",
        )),
    }
}

pub fn discover_targets() -> CaptureTargetReport {
    let monitors = enumerate_monitors();
    let windows = enumerate_windows();
    let mut targets = Vec::with_capacity(monitors.len() + windows.len());
    for monitor in &monitors {
        targets.push(CaptureTarget {
            id: monitor.device.clone(),
            kind: "display".to_owned(),
            name: monitor.device.clone(),
            width: rect_width(&monitor.rect).max(0) as u32,
            height: rect_height(&monitor.rect).max(0) as u32,
            scale_milli: 1000,
        });
    }
    for window in &windows {
        targets.push(CaptureTarget {
            id: (window.hwnd as usize).to_string(),
            kind: "window".to_owned(),
            name: window.title.clone(),
            width: rect_width(&window.rect).max(0) as u32,
            height: rect_height(&window.rect).max(0) as u32,
            scale_milli: 1000,
        });
    }
    CaptureTargetReport {
        window_capture: true,
        multi_display: monitors.len() > 1,
        microphone: false,
        system_audio: false,
        reason: "Displays are read from EnumDisplayMonitors; visible windows from EnumWindows."
            .to_owned(),
        targets,
    }
}
