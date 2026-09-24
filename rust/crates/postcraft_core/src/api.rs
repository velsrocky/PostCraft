use crate::global_shortcuts;
pub use crate::{
    CaptureResult, GlobalShortcutStatus, ImageOperationResult, NativeError, PlatformCapabilities,
    RuntimeInfo, ShortcutBinding, blur_region_rgba as blur_region_rgba_impl,
    capture_desktop as capture_desktop_impl, pixelate_region_rgba as pixelate_region_rgba_impl,
    pixelate_rgba as pixelate_rgba_impl, platform_capabilities as platform_capabilities_impl,
    runtime_info as runtime_info_impl,
};

#[flutter_rust_bridge::frb]
pub fn runtime_info() -> RuntimeInfo {
    runtime_info_impl()
}

#[flutter_rust_bridge::frb]
pub fn platform_capabilities() -> PlatformCapabilities {
    platform_capabilities_impl()
}

#[flutter_rust_bridge::frb]
pub fn capture_target_report() -> String {
    serde_json::to_string(&crate::platform_targets::discover()).unwrap_or_else(|_| {
        "{\"targets\":[],\"reason\":\"capability serialization failed\"}".to_owned()
    })
}

#[flutter_rust_bridge::frb]
pub fn prepare_wayland_screencast(include_microphone: bool, include_system_audio: bool) -> String {
    match crate::screencast::prepare_session(include_microphone, include_system_audio) {
        Ok(state) => serde_json::to_string(&state).unwrap_or_else(|_| "{}".into()),
        Err(error) => serde_json::json!({"supported": false, "started": false, "reason": error.message, "code": error.code}).to_string(),
    }
}

#[flutter_rust_bridge::frb]
pub fn start_wayland_screencast(session_handle: String, parent_window: String) -> String {
    match crate::screencast::start_session(session_handle, parent_window) {
        Ok(state) => serde_json::to_string(&state).unwrap_or_else(|_| "{}".into()),
        Err(error) => {
            serde_json::json!({"started": false, "reason": error.message, "code": error.code})
                .to_string()
        }
    }
}

#[flutter_rust_bridge::frb]
pub fn inspect_pipewire_transport() -> String {
    serde_json::to_string(&crate::pipewire_transport::inspect())
        .unwrap_or_else(|_| "{\"connected\":false,\"reason\":\"serialization failed\"}".into())
}

#[flutter_rust_bridge::frb]
pub fn probe_authorized_pipewire_stream(node_id: u32) -> String {
    serde_json::to_string(&crate::pipewire_transport::probe_authorized_stream(node_id))
        .unwrap_or_else(|_| "{\"connected\":false,\"reason\":\"serialization failed\"}".into())
}

#[flutter_rust_bridge::frb]
pub fn record_authorized_pipewire_stream(
    node_id: u32,
    width: u32,
    height: u32,
    fps: u32,
    pixel_format: String,
    output: String,
    duration_ms: u64,
) -> Result<u64, NativeError> {
    crate::pipewire_transport::record_authorized_stream(
        node_id,
        width,
        height,
        fps,
        &pixel_format,
        &output,
        duration_ms,
    )
    .map_err(|message| NativeError {
        code: "pipewire_recording_failed".into(),
        message,
    })
}

#[flutter_rust_bridge::frb]
pub fn global_shortcuts_supported() -> bool {
    global_shortcuts::portal_supported()
}

#[flutter_rust_bridge::frb]
pub fn start_global_shortcuts(
    bindings: Vec<ShortcutBinding>,
) -> Result<GlobalShortcutStatus, NativeError> {
    global_shortcuts::start(bindings)
}

#[flutter_rust_bridge::frb]
pub fn poll_global_shortcut() -> Option<String> {
    global_shortcuts::poll()
}

#[flutter_rust_bridge::frb]
pub fn stop_global_shortcuts() {
    global_shortcuts::stop();
}

fn map_media_error(error: postcraft_media::MediaError) -> NativeError {
    NativeError {
        code: error.code,
        message: error.message,
    }
}

#[flutter_rust_bridge::frb]
pub fn recording_capabilities() -> String {
    let capabilities = postcraft_media::recording_capabilities();
    format!(
        "{}|{}|{}|{}",
        capabilities.supported,
        capabilities.microphone,
        capabilities.system_audio,
        capabilities.reason
    )
}

#[flutter_rust_bridge::frb]
pub fn start_recording_session(
    output: String,
    width: u32,
    height: u32,
    fps: u32,
    include_microphone: bool,
    include_system_audio: bool,
) -> Result<String, NativeError> {
    let request = postcraft_media::RecordingRequest {
        output,
        width,
        height,
        fps,
        include_microphone,
        include_system_audio,
    };
    postcraft_media::start_recording(request)
        .map(|session| format!("{}|{}", session.id, session.output))
        .map_err(map_media_error)
}

#[flutter_rust_bridge::frb]
pub fn stop_recording(id: u32) -> Result<String, NativeError> {
    postcraft_media::stop_recording(id).map_err(map_media_error)
}

#[flutter_rust_bridge::frb]
pub fn cancel_recording(id: u32) -> bool {
    postcraft_media::cancel_recording(id)
}

#[flutter_rust_bridge::frb]
pub fn poll_render_session(id: u32) -> Option<String> {
    postcraft_media::poll_transcode(id)
        .map(|progress| format!("{:?}|{}", progress.state, progress.message))
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn start_timeline_render_session(
    inputs: Vec<String>,
    kinds: Vec<String>,
    source_in_us: Vec<String>,
    source_out_us: Vec<String>,
    volumes: Vec<String>,
    output: String,
    container: String,
    crf: Option<i32>,
) -> Result<u32, NativeError> {
    if inputs.len() != source_in_us.len()
        || inputs.len() != source_out_us.len()
        || inputs.len() != kinds.len()
        || inputs.len() != volumes.len()
    {
        return Err(NativeError::invalid(
            "timeline clip arrays must have equal lengths",
        ));
    }
    let clips = inputs
        .into_iter()
        .zip(kinds)
        .zip(source_in_us)
        .zip(source_out_us)
        .zip(volumes)
        .map(|((((input, kind), source_in_us), source_out_us), volume)| {
            let source_in_us = source_in_us
                .parse()
                .map_err(|_| NativeError::invalid("invalid clip start"))?;
            let source_out_us = source_out_us
                .parse()
                .map_err(|_| NativeError::invalid("invalid clip end"))?;
            let volume_milli = volume
                .parse()
                .map_err(|_| NativeError::invalid("invalid clip volume"))?;
            Ok(postcraft_media::TimelineClip {
                input,
                kind,
                source_in_us,
                source_out_us,
                start_us: 0,
                volume_milli,
            })
        })
        .collect::<Result<Vec<_>, NativeError>>()?;
    postcraft_media::start_timeline_render(clips, output, container, crf).map_err(map_media_error)
}

#[flutter_rust_bridge::frb]
pub fn capture_desktop(
    mode: String,
    target_id: Option<String>,
) -> Result<CaptureResult, NativeError> {
    capture_desktop_impl(mode, target_id)
}

#[flutter_rust_bridge::frb]
pub fn media_status() -> String {
    serde_json::to_string(&postcraft_media::media_status()).unwrap_or_else(|_| {
        "{\"available\":false,\"message\":\"media status serialization failed\"}".to_owned()
    })
}

#[flutter_rust_bridge::frb]
pub fn install_panic_hook(log_path: String) {
    crate::install_panic_hook(log_path);
}

#[flutter_rust_bridge::frb]
pub fn pixelate_rgba(
    width: u32,
    height: u32,
    rgba: Vec<u8>,
    block_size: u32,
) -> Result<ImageOperationResult, NativeError> {
    pixelate_rgba_impl(width, height, rgba, block_size)
}

#[flutter_rust_bridge::frb]
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
    pixelate_region_rgba_impl(
        width,
        height,
        rgba,
        left,
        top,
        region_width,
        region_height,
        block_size,
    )
}

#[flutter_rust_bridge::frb]
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
    blur_region_rgba_impl(
        width,
        height,
        rgba,
        left,
        top,
        region_width,
        region_height,
        radius,
    )
}

#[flutter_rust_bridge::frb]
pub fn generate_poster_frame(input: String, width: u32) -> Result<Vec<u8>, NativeError> {
    let output = std::env::temp_dir().join(format!("postcraft-poster-{}.png", std::process::id()));
    postcraft_media::generate_poster(&input, &output, width).map_err(map_media_error)?;
    std::fs::read(&output)
        .map_err(|error| NativeError {
            code: "poster_read_failed".to_owned(),
            message: error.to_string(),
        })
        .inspect(|_| {
            let _ = std::fs::remove_file(&output);
        })
}

#[flutter_rust_bridge::frb]
pub fn generate_waveform_data(input: String, samples: usize) -> Result<Vec<f32>, NativeError> {
    postcraft_media::generate_waveform(&input, samples).map_err(map_media_error)
}

#[flutter_rust_bridge::frb]
pub fn probe_media_file(input: String) -> Result<String, NativeError> {
    let result = postcraft_media::probe_media(&input).map_err(map_media_error)?;
    serde_json::to_string(&result).map_err(|error| NativeError {
        code: "probe_serialization_failed".to_owned(),
        message: error.to_string(),
    })
}
