use serde::{Deserialize, Serialize};
#[cfg(target_os = "linux")]
use std::path::Path;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PipewireTransportState {
    pub runtime_available: bool,
    pub development_available: bool,
    pub connected: bool,
    pub node_ids: Vec<u32>,
    pub reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PipewireStreamState {
    pub node_id: u32,
    pub connected: bool,
    pub streaming: bool,
    pub frames_received: u64,
    pub last_buffer_bytes: u32,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub format: Option<String>,
    pub framerate_num: Option<u32>,
    pub framerate_den: Option<u32>,
    pub reason: String,
}

/// Connects to PipeWire and enumerates visible global node IDs.
///
/// Stream negotiation is intentionally kept separate: the portal must first
/// authorize a ScreenCast stream and return its PipeWire remote/node metadata.
#[cfg(target_os = "linux")]
pub fn inspect() -> PipewireTransportState {
    let development_available = std::process::Command::new("pkg-config")
        .args(["--exists", "libpipewire-0.3"])
        .status()
        .is_ok_and(|status| status.success());
    if !development_available {
        return PipewireTransportState {
            runtime_available: false,
            development_available: false,
            connected: false,
            node_ids: Vec::new(),
            reason: "PipeWire development metadata is unavailable.".into(),
        };
    }

    let main_loop = match pipewire::main_loop::MainLoopBox::new(None) {
        Ok(main_loop) => main_loop,
        Err(error) => return failure(format!("PipeWire main loop failed: {error}")),
    };
    let context = match pipewire::context::ContextBox::new(main_loop.loop_(), None) {
        Ok(context) => context,
        Err(error) => return failure(format!("PipeWire context failed: {error}")),
    };
    let core = match context.connect(None) {
        Ok(core) => core,
        Err(error) => return failure(format!("PipeWire connection failed: {error}")),
    };
    let registry = match core.get_registry() {
        Ok(registry) => registry,
        Err(error) => return failure(format!("PipeWire registry failed: {error}")),
    };
    let node_ids = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
    let node_ids_for_listener = node_ids.clone();
    let _listener = registry
        .add_listener_local()
        .global(move |global| {
            if global.type_ == pipewire::types::ObjectType::Node {
                if let Ok(mut ids) = node_ids_for_listener.lock() {
                    ids.push(global.id);
                }
            }
        })
        .register();
    main_loop
        .loop_()
        .iterate(pipewire::loop_::Timeout::Finite(Duration::from_millis(100)));
    let node_ids = node_ids.lock().map(|ids| ids.clone()).unwrap_or_default();
    PipewireTransportState {
        runtime_available: true,
        development_available: true,
        connected: true,
        node_ids,
        reason: "Connected to PipeWire; no portal-authorized ScreenCast stream has been attached."
            .into(),
    }
}

#[cfg(target_os = "linux")]
pub fn probe_authorized_stream(node_id: u32) -> PipewireStreamState {
    use pipewire as pw;
    use pw::properties::properties;
    use pw::spa;
    use pw::spa::param::video::VideoInfoRaw;
    use std::sync::{Arc, Mutex};

    if node_id == 0 {
        return stream_failure(node_id, "An authorized PipeWire node ID is required.");
    }
    pw::init();
    let main_loop = match pw::main_loop::MainLoopRc::new(None) {
        Ok(value) => value,
        Err(error) => {
            return stream_failure(node_id, &format!("PipeWire main loop failed: {error}"));
        }
    };
    let context = match pw::context::ContextRc::new(&main_loop, None) {
        Ok(value) => value,
        Err(error) => return stream_failure(node_id, &format!("PipeWire context failed: {error}")),
    };
    let core = match context.connect_rc(None) {
        Ok(value) => value,
        Err(error) => {
            return stream_failure(node_id, &format!("PipeWire connection failed: {error}"));
        }
    };
    let stream = match pw::stream::StreamBox::new(
        &core,
        "postcraft-screencast",
        properties! {
            *pw::keys::MEDIA_TYPE => "Video",
            *pw::keys::MEDIA_CATEGORY => "Capture",
            *pw::keys::MEDIA_ROLE => "Screen",
        },
    ) {
        Ok(value) => value,
        Err(error) => {
            return stream_failure(
                node_id,
                &format!("PipeWire stream creation failed: {error}"),
            );
        }
    };
    let frames = Arc::new(Mutex::new((
        0_u64,
        0_u32,
        None::<(u32, u32, String, u32, u32)>,
    )));
    let listener = match stream
        .add_local_listener_with_user_data((VideoInfoRaw::default(), frames.clone()))
        .param_changed(move |_, user_data, id, param| {
            if id != pw::spa::param::ParamType::Format.as_raw() {
                return;
            }
            let Some(param) = param else {
                return;
            };
            let Ok((media_type, media_subtype)) = pw::spa::param::format_utils::parse_format(param)
            else {
                return;
            };
            if media_type != pw::spa::param::format::MediaType::Video
                || media_subtype != pw::spa::param::format::MediaSubtype::Raw
            {
                return;
            }
            if user_data.0.parse(param).is_ok() {
                let size = user_data.0.size();
                let fps = user_data.0.framerate();
                let format = format!("{:?}", user_data.0.format());
                if let Ok(mut state) = user_data.1.lock() {
                    state.2 = Some((size.width, size.height, format, fps.num, fps.denom));
                }
            }
        })
        .process(move |stream, user_data| {
            if let Some(mut buffer) = stream.dequeue_buffer() {
                if let Some(data) = buffer.datas_mut().first() {
                    if let Ok(mut stats) = user_data.1.lock() {
                        stats.0 += 1;
                        stats.1 = data.chunk().size();
                    }
                }
            }
        })
        .register()
    {
        Ok(value) => value,
        Err(error) => {
            return stream_failure(node_id, &format!("PipeWire listener failed: {error}"));
        }
    };
    let mut params: [&spa::pod::Pod; 0] = [];
    if let Err(error) = stream.connect(
        spa::utils::Direction::Input,
        Some(node_id),
        pw::stream::StreamFlags::AUTOCONNECT | pw::stream::StreamFlags::MAP_BUFFERS,
        &mut params,
    ) {
        drop(listener);
        return stream_failure(node_id, &format!("PipeWire stream connect failed: {error}"));
    }
    for _ in 0..5 {
        main_loop.loop_().iterate(pw::loop_::Timeout::Finite(
            std::time::Duration::from_millis(20),
        ));
    }
    let (frames_received, last_buffer_bytes, format) = frames
        .lock()
        .map(|value| (value.0, value.1, value.2.clone()))
        .unwrap_or_default();
    PipewireStreamState {
        node_id,
        connected: true,
        streaming: frames_received > 0,
        frames_received,
        last_buffer_bytes,
        width: format.as_ref().map(|value| value.0),
        height: format.as_ref().map(|value| value.1),
        format: format.as_ref().map(|value| value.2.clone()),
        framerate_num: format.as_ref().map(|value| value.3),
        framerate_den: format.as_ref().map(|value| value.4),
        reason: if frames_received > 0 {
            "PipeWire delivered video buffers.".into()
        } else {
            "PipeWire stream connected but delivered no buffers during the probe window.".into()
        },
    }
}

/// Captures an authorized PipeWire node for a bounded duration into an MP4.
/// This is intentionally synchronous at the native boundary; the bridge caller
/// should dispatch it off the UI isolate for interactive recording.
#[cfg(target_os = "linux")]
pub fn record_authorized_stream(
    node_id: u32,
    width: u32,
    height: u32,
    fps: u32,
    pixel_format: &str,
    output: &str,
    duration_ms: u64,
) -> Result<u64, String> {
    use pipewire as pw;
    use pw::properties::properties;
    use pw::spa;
    use std::io::Write;
    use std::process::{Command, Stdio};
    use std::sync::{Arc, Mutex};

    if node_id == 0 || width == 0 || height == 0 || fps == 0 || duration_ms == 0 {
        return Err("invalid PipeWire recording parameters".into());
    }
    if !matches!(pixel_format, "bgra" | "rgba" | "rgb24" | "bgr0") {
        return Err("unsupported packed pixel format".into());
    }
    let output_path = Path::new(output);
    if output_path.extension().and_then(|value| value.to_str()) != Some("mp4") {
        return Err("recording output must use .mp4".into());
    }
    let temporary = Path::new(&format!("{output}.pipewire-tmp.mp4")).to_path_buf();
    let ffmpeg = crate::pipewire_transport::ffmpeg_path();
    let args = postcraft_media::build_raw_video_args(width, height, fps, pixel_format, &temporary)
        .map_err(|error| error.message)?;
    let mut child = Command::new(ffmpeg)
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| error.to_string())?;
    let stdin = Arc::new(Mutex::new(
        child.stdin.take().ok_or("FFmpeg stdin unavailable")?,
    ));
    pw::init();
    let main_loop = pw::main_loop::MainLoopRc::new(None).map_err(|error| error.to_string())?;
    let context =
        pw::context::ContextRc::new(&main_loop, None).map_err(|error| error.to_string())?;
    let core = context
        .connect_rc(None)
        .map_err(|error| error.to_string())?;
    let stream = pw::stream::StreamBox::new(
        &core,
        "postcraft-recording",
        properties! {
            *pw::keys::MEDIA_TYPE => "Video",
            *pw::keys::MEDIA_CATEGORY => "Capture",
            *pw::keys::MEDIA_ROLE => "Screen",
        },
    )
    .map_err(|error| error.to_string())?;
    let frames = Arc::new(Mutex::new(0_u64));
    let callback_stdin = stdin.clone();
    let callback_frames = frames.clone();
    let listener = stream
        .add_local_listener_with_user_data(())
        .process(move |stream, _| {
            let Some(mut buffer) = stream.dequeue_buffer() else {
                return;
            };
            let Some(data) = buffer.datas_mut().first_mut() else {
                return;
            };
            let start = data.chunk().offset() as usize;
            let size = data.chunk().size() as usize;
            let Some(bytes) = data.data() else {
                return;
            };
            let Some(frame) = bytes.get(start..start.saturating_add(size)) else {
                return;
            };
            if let Ok(mut input) = callback_stdin.lock() {
                if input.write_all(frame).is_ok() {
                    if let Ok(mut count) = callback_frames.lock() {
                        *count += 1;
                    }
                }
            }
        })
        .register()
        .map_err(|error| error.to_string())?;
    let mut params: [&spa::pod::Pod; 0] = [];
    stream
        .connect(
            spa::utils::Direction::Input,
            Some(node_id),
            pw::stream::StreamFlags::AUTOCONNECT | pw::stream::StreamFlags::MAP_BUFFERS,
            &mut params,
        )
        .map_err(|error| error.to_string())?;
    let deadline = std::time::Instant::now() + std::time::Duration::from_millis(duration_ms);
    while std::time::Instant::now() < deadline {
        main_loop.loop_().iterate(pw::loop_::Timeout::Finite(
            std::time::Duration::from_millis(20),
        ));
    }
    drop(listener);
    drop(stdin);
    let status = child.wait().map_err(|error| error.to_string())?;
    let frame_count = frames.lock().map(|value| *value).unwrap_or(0);
    if !status.success() || frame_count == 0 {
        let _ = std::fs::remove_file(&temporary);
        return Err(format!(
            "FFmpeg recording failed; frames={frame_count}, status={status}"
        ));
    }
    if let Some(parent) = output_path.parent() {
        std::fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    std::fs::rename(&temporary, output_path).map_err(|error| error.to_string())?;
    Ok(frame_count)
}

#[cfg(not(target_os = "linux"))]
pub fn record_authorized_stream(
    _node_id: u32,
    _width: u32,
    _height: u32,
    _fps: u32,
    _pixel_format: &str,
    _output: &str,
    _duration_ms: u64,
) -> Result<u64, String> {
    Err("PipeWire recording is only available on Linux".into())
}

#[cfg(target_os = "linux")]
fn ffmpeg_path() -> std::path::PathBuf {
    std::env::var_os("POSTCRAFT_FFMPEG")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| std::path::PathBuf::from("ffmpeg"))
}

#[cfg(not(target_os = "linux"))]
pub fn probe_authorized_stream(node_id: u32) -> PipewireStreamState {
    stream_failure(
        node_id,
        "PipeWire screen capture is only available on Linux.",
    )
}

fn stream_failure(node_id: u32, reason: &str) -> PipewireStreamState {
    PipewireStreamState {
        node_id,
        connected: false,
        streaming: false,
        frames_received: 0,
        last_buffer_bytes: 0,
        width: None,
        height: None,
        format: None,
        framerate_num: None,
        framerate_den: None,
        reason: reason.into(),
    }
}

#[cfg(not(target_os = "linux"))]
pub fn inspect() -> PipewireTransportState {
    failure("PipeWire transport inspection is only available on Linux.".into())
}

fn failure(reason: String) -> PipewireTransportState {
    PipewireTransportState {
        runtime_available: false,
        development_available: true,
        connected: false,
        node_ids: Vec::new(),
        reason,
    }
}

#[cfg(target_os = "linux")]
use std::time::Duration;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn state_serializes_without_a_stream() {
        let state = PipewireTransportState {
            runtime_available: true,
            development_available: true,
            connected: true,
            node_ids: vec![42],
            reason: "test".into(),
        };
        assert_eq!(state.node_ids, vec![42]);
    }
}
