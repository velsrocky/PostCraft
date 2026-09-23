use crate::NativeError;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ScreenCastSessionState {
    pub supported: bool,
    pub session_handle: Option<String>,
    pub selected_sources: Vec<String>,
    pub pipewire_node_ids: Vec<u32>,
    pub started: bool,
    pub reason: String,
    pub pipewire_runtime: bool,
    pub pipewire_development: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ScreenCastStartState {
    pub started: bool,
    pub session_handle: String,
    pub streams: Vec<ScreenCastStream>,
    pub reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ScreenCastStream {
    pub node_id: u32,
    pub source_type: Option<u32>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub scale_milli: Option<u32>,
}

#[cfg(target_os = "linux")]
pub fn prepare_session(
    include_microphone: bool,
    include_system_audio: bool,
) -> Result<ScreenCastSessionState, NativeError> {
    if !std::env::var("XDG_SESSION_TYPE")
        .unwrap_or_default()
        .eq_ignore_ascii_case("wayland")
    {
        return Ok(unsupported(
            "ScreenCast portal sessions are only used on Wayland.",
        ));
    }
    let connection =
        zbus::blocking::Connection::session().map_err(|error| backend(error.to_string()))?;
    let portal = zbus::blocking::Proxy::new(
        &connection,
        "org.freedesktop.portal.Desktop",
        "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.ScreenCast",
    )
    .map_err(|error| backend(error.to_string()))?;
    let token = format!("postcraft_sc_{}_{}", std::process::id(), unique_token());
    let mut create_options = HashMap::new();
    create_options.insert("handle_token", zbus::zvariant::Value::from(token.as_str()));
    let request_path: zbus::zvariant::OwnedObjectPath = portal
        .call("CreateSession", &create_options)
        .map_err(|error| backend(format!("CreateSession rejected: {error}")))?;
    let response = wait_response(&connection, request_path.as_str())?;
    if response.0 != 0 {
        return Err(cancelled_or_failed(
            response.0,
            "ScreenCast session creation",
        ));
    }
    let session = response
        .1
        .get("session_handle")
        .and_then(|value| <String>::try_from(value.clone()).ok())
        .ok_or_else(|| backend("ScreenCast response did not include a session handle"))?;

    let select_token = format!("postcraft_select_{}", unique_token());
    let mut select_options = HashMap::new();
    select_options.insert(
        "handle_token",
        zbus::zvariant::Value::from(select_token.as_str()),
    );
    select_options.insert("types", zbus::zvariant::Value::from(1_u32));
    if include_microphone || include_system_audio {
        return Err(NativeError {
            code: "audio_unsupported".into(),
            message: "Audio sources require a PipeWire node selector and permission flow.".into(),
        });
    }
    let select_request: zbus::zvariant::OwnedObjectPath = portal
        .call("SelectSources", &(session.as_str(), select_options))
        .map_err(|error| backend(format!("SelectSources rejected: {error}")))?;
    let select_response = wait_response(&connection, select_request.as_str())?;
    if select_response.0 != 0 {
        return Err(cancelled_or_failed(
            select_response.0,
            "ScreenCast source selection",
        ));
    }
    Ok(ScreenCastSessionState {
        supported: true,
        session_handle: Some(session),
        selected_sources: vec!["monitor".into()],
        pipewire_node_ids: Vec::new(),
        started: false,
        reason: "Sources selected. Start requires a parent window and a PipeWire consumer.".into(),
        pipewire_runtime: pipewire_runtime_available(),
        pipewire_development: pipewire_development_available(),
    })
}

#[cfg(target_os = "linux")]
pub fn start_session(
    session_handle: String,
    parent_window: String,
) -> Result<ScreenCastStartState, NativeError> {
    if session_handle.trim().is_empty() {
        return Err(NativeError {
            code: "invalid_screencast_request".into(),
            message: "session handle is required".into(),
        });
    }
    let connection =
        zbus::blocking::Connection::session().map_err(|error| backend(error.to_string()))?;
    let portal = zbus::blocking::Proxy::new(
        &connection,
        "org.freedesktop.portal.Desktop",
        "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.ScreenCast",
    )
    .map_err(|error| backend(error.to_string()))?;
    let token = format!("postcraft_start_{}_{}", std::process::id(), unique_token());
    let mut options = HashMap::new();
    options.insert("handle_token", zbus::zvariant::Value::from(token.as_str()));
    let request: zbus::zvariant::OwnedObjectPath = portal
        .call(
            "Start",
            &(session_handle.as_str(), parent_window.as_str(), options),
        )
        .map_err(|error| backend(format!("Start rejected: {error}")))?;
    let response = wait_response(&connection, request.as_str())?;
    if response.0 != 0 {
        return Err(cancelled_or_failed(response.0, "ScreenCast start"));
    }
    let streams = response
        .1
        .get("streams")
        .ok_or_else(|| backend("ScreenCast start response has no streams"))?;
    parse_streams(streams, session_handle)
}

#[cfg(not(target_os = "linux"))]
pub fn start_session(
    _session_handle: String,
    _parent_window: String,
) -> Result<ScreenCastStartState, NativeError> {
    Err(NativeError {
        code: "screencast_unsupported".into(),
        message: "ScreenCast is only available on Linux.".into(),
    })
}

#[cfg(not(target_os = "linux"))]
pub fn prepare_session(
    _include_microphone: bool,
    _include_system_audio: bool,
) -> Result<ScreenCastSessionState, NativeError> {
    Ok(unsupported("ScreenCast portal is only available on Linux."))
}

#[cfg(target_os = "linux")]
fn wait_response(
    connection: &zbus::blocking::Connection,
    path: &str,
) -> Result<(u32, HashMap<String, zbus::zvariant::OwnedValue>), NativeError> {
    let proxy = zbus::blocking::Proxy::new(
        connection,
        "org.freedesktop.portal.Desktop",
        path,
        "org.freedesktop.portal.Request",
    )
    .map_err(|error| backend(error.to_string()))?;
    let mut stream = proxy
        .receive_signal("Response")
        .map_err(|error| backend(error.to_string()))?;
    let signal = stream
        .next()
        .ok_or_else(|| backend("ScreenCast request ended without a response"))?;
    signal
        .body()
        .deserialize()
        .map_err(|error| backend(format!("Invalid ScreenCast response: {error}")))
}

#[cfg(target_os = "linux")]
fn unique_token() -> u64 {
    use std::sync::atomic::{AtomicU64, Ordering};
    static TOKEN: AtomicU64 = AtomicU64::new(1);
    TOKEN.fetch_add(1, Ordering::Relaxed)
}

fn unsupported(reason: &str) -> ScreenCastSessionState {
    ScreenCastSessionState {
        supported: false,
        session_handle: None,
        selected_sources: Vec::new(),
        pipewire_node_ids: Vec::new(),
        started: false,
        reason: reason.into(),
        pipewire_runtime: false,
        pipewire_development: false,
    }
}

#[cfg(target_os = "linux")]
fn pipewire_runtime_available() -> bool {
    std::process::Command::new("pw-cli")
        .args(["info", "0"])
        .output()
        .is_ok_and(|output| output.status.success())
}

#[cfg(not(target_os = "linux"))]
fn pipewire_runtime_available() -> bool {
    false
}

#[cfg(target_os = "linux")]
fn pipewire_development_available() -> bool {
    std::process::Command::new("pkg-config")
        .args(["--exists", "libpipewire-0.3"])
        .status()
        .is_ok_and(|status| status.success())
}

#[cfg(not(target_os = "linux"))]
fn pipewire_development_available() -> bool {
    false
}

fn backend(message: impl Into<String>) -> NativeError {
    NativeError {
        code: "screencast_backend_failed".into(),
        message: message.into(),
    }
}

fn cancelled_or_failed(status: u32, operation: &str) -> NativeError {
    NativeError {
        code: if status == 1 {
            "screencast_cancelled"
        } else {
            "screencast_failed"
        }
        .into(),
        message: format!("{operation} ended with portal status {status}"),
    }
}

#[cfg(target_os = "linux")]
fn parse_streams(
    value: &zbus::zvariant::OwnedValue,
    session_handle: String,
) -> Result<ScreenCastStartState, NativeError> {
    let raw: Vec<(u32, HashMap<String, zbus::zvariant::OwnedValue>)> = value
        .clone()
        .try_into()
        .map_err(|error| backend(format!("Invalid ScreenCast streams metadata: {error}")))?;
    let streams = raw
        .into_iter()
        .map(|(node_id, properties)| ScreenCastStream {
            node_id,
            source_type: properties
                .get("source_type")
                .and_then(|value| u32::try_from(value.clone()).ok()),
            width: properties
                .get("size")
                .and_then(|value| parse_size(value).map(|size| size.0)),
            height: properties
                .get("size")
                .and_then(|value| parse_size(value).map(|size| size.1)),
            scale_milli: properties
                .get("scale")
                .and_then(|value| f64::try_from(value.clone()).ok())
                .map(|scale| (scale * 1000.0) as u32),
        })
        .collect::<Vec<_>>();
    if streams.is_empty() {
        return Err(backend("ScreenCast start returned no authorized streams"));
    }
    Ok(ScreenCastStartState {
        started: true,
        session_handle,
        streams,
        reason: "ScreenCast stream authorized; PipeWire node negotiation is next.".into(),
    })
}

#[cfg(target_os = "linux")]
fn parse_size(value: &zbus::zvariant::OwnedValue) -> Option<(u32, u32)> {
    let pair: (u32, u32) = value.clone().try_into().ok()?;
    Some(pair)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn unsupported_state_is_structured() {
        let state = unsupported("test");
        assert!(!state.supported);
        assert!(!state.started);
        assert!(state.session_handle.is_none());
        assert!(!state.pipewire_runtime);
        assert!(!state.pipewire_development);
    }
}
