//! Portal-based global shortcuts via `org.freedesktop.portal.GlobalShortcuts`.
//!
//! Registration is intentionally non-blocking: `CreateSession` and
//! `BindShortcuts` return object paths synchronously, and the desktop handles
//! any user-approval prompt. Activations are collected on a background D-Bus
//! listener thread into a queue the UI drains with [`poll`]. This never hangs
//! waiting on a modal consent dialog.

use crate::{GlobalShortcutStatus, NativeError, ShortcutBinding};

#[cfg(target_os = "linux")]
mod backend {
    use super::*;
    use std::collections::{HashMap, VecDeque};
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::{Arc, Mutex, OnceLock};
    use std::thread::JoinHandle;
    use zbus::blocking::{Connection, Proxy};
    use zbus::zvariant::{OwnedObjectPath, OwnedValue, Value};

    const PORTAL_NAME: &str = "org.freedesktop.portal.Desktop";
    const PORTAL_PATH: &str = "/org/freedesktop/portal/desktop";
    const GS_IFACE: &str = "org.freedesktop.portal.GlobalShortcuts";

    struct ActiveListener {
        running: Arc<AtomicBool>,
        #[allow(dead_code)]
        events: Arc<Mutex<VecDeque<String>>>,
        // Kept so the worker detaches rather than aborts on drop of the guard.
        #[allow(dead_code)]
        worker: Option<JoinHandle<()>>,
    }

    fn state() -> &'static Mutex<Option<ActiveListener>> {
        static STATE: OnceLock<Mutex<Option<ActiveListener>>> = OnceLock::new();
        STATE.get_or_init(|| Mutex::new(None))
    }

    fn connect() -> Result<Connection, NativeError> {
        Connection::session().map_err(|error| NativeError {
            code: "shortcuts_backend_failed".to_owned(),
            message: format!("Unable to reach the session bus: {error}"),
        })
    }

    pub fn portal_supported() -> bool {
        match connect() {
            Ok(connection) => Proxy::new(&connection, PORTAL_NAME, PORTAL_PATH, GS_IFACE)
                .ok()
                .and_then(|proxy| proxy.get_property::<u32>("version").ok())
                .is_some(),
            Err(_) => false,
        }
    }

    pub fn start(bindings: Vec<ShortcutBinding>) -> Result<GlobalShortcutStatus, NativeError> {
        validate(&bindings)?;
        let connection = connect()?;
        let portal =
            Proxy::new(&connection, PORTAL_NAME, PORTAL_PATH, GS_IFACE).map_err(|error| {
                NativeError {
                    code: "shortcuts_unsupported".to_owned(),
                    message: format!("GlobalShortcuts portal is unavailable: {error}"),
                }
            })?;

        let no_options: HashMap<&str, Value<'_>> = HashMap::new();
        let session: OwnedObjectPath =
            portal
                .call("CreateSession", &(no_options,))
                .map_err(|error| NativeError {
                    code: "shortcuts_unsupported".to_owned(),
                    message: format!("CreateSession failed: {error}"),
                })?;

        let shortcuts: Vec<(String, HashMap<String, Value<'_>>)> = bindings
            .iter()
            .map(|binding| {
                let mut options: HashMap<String, Value<'_>> = HashMap::new();
                options.insert(
                    "description".to_owned(),
                    Value::from(binding.description.clone()),
                );
                options.insert(
                    "preferredTrigger".to_owned(),
                    Value::from(binding.preferred_trigger.clone()),
                );
                options.insert("reproducible".to_owned(), Value::from(false));
                (binding.id.clone(), options)
            })
            .collect();

        let bind_options: HashMap<&str, Value<'_>> = HashMap::new();
        let _request: OwnedObjectPath = portal
            .call(
                "BindShortcuts",
                &(&session, shortcuts.clone(), "", bind_options),
            )
            .map_err(|error| NativeError {
                code: "shortcuts_failed".to_owned(),
                message: format!("BindShortcuts failed: {error}"),
            })?;

        // Stop any previous listener before installing a new one.
        stop_locked();

        let running = Arc::new(AtomicBool::new(true));
        let events: Arc<Mutex<VecDeque<String>>> = Arc::new(Mutex::new(VecDeque::new()));
        let worker = {
            let running = Arc::clone(&running);
            let events = Arc::clone(&events);
            let session_path = session.to_string();
            std::thread::spawn(move || listen(running, events, session_path))
        };

        *state().lock().unwrap() = Some(ActiveListener {
            running,
            events,
            worker: Some(worker),
        });

        Ok(GlobalShortcutStatus {
            supported: true,
            requested_ids: shortcuts.into_iter().map(|(id, _)| id).collect(),
            message: "Registered; grant the desktop prompt if one appears.".to_owned(),
        })
    }

    fn listen(
        running: Arc<AtomicBool>,
        events: Arc<Mutex<VecDeque<String>>>,
        session_path: String,
    ) {
        let Ok(connection) = Connection::session() else {
            return;
        };
        let Ok(proxy) = Proxy::new(&connection, PORTAL_NAME, session_path.as_str(), GS_IFACE)
        else {
            return;
        };
        let Ok(mut iterator) = proxy.receive_signal("Activated") else {
            return;
        };
        while running.load(Ordering::Relaxed) {
            let Some(message) = iterator.next() else {
                break;
            };
            let Ok((_handle, shortcut_id, _timestamp, _options)) =
                message
                    .body()
                    .deserialize::<(OwnedObjectPath, String, u64, HashMap<String, OwnedValue>)>()
            else {
                continue;
            };
            if let Ok(mut queue) = events.lock() {
                queue.push_back(shortcut_id);
            }
        }
    }

    pub fn poll() -> Option<String> {
        let guard = state().lock().ok()?;
        let active = guard.as_ref()?;
        let mut queue = active.events.lock().ok()?;
        queue.pop_front()
    }

    pub fn stop() {
        if let Ok(mut guard) = state().lock() {
            stop_locked_with(&mut guard);
        }
    }

    fn stop_locked() {
        if let Ok(mut guard) = state().lock() {
            stop_locked_with(&mut guard);
        }
    }

    fn stop_locked_with(guard: &mut Option<ActiveListener>) {
        if let Some(active) = guard.as_ref() {
            active.running.store(false, Ordering::Relaxed);
        }
        *guard = None;
    }
}

/// Rejects malformed bindings before any D-Bus work happens.
fn validate(bindings: &[ShortcutBinding]) -> Result<(), NativeError> {
    if bindings.is_empty() {
        return Err(NativeError::invalid(
            "at least one shortcut binding is required",
        ));
    }
    for binding in bindings {
        if binding.id.trim().is_empty() {
            return Err(NativeError::invalid("shortcut id must not be empty"));
        }
        if binding.preferred_trigger.trim().is_empty() {
            return Err(NativeError::invalid(format!(
                "shortcut '{}' must declare a preferred trigger",
                binding.id
            )));
        }
    }
    Ok(())
}

#[cfg(target_os = "linux")]
pub fn portal_supported() -> bool {
    backend::portal_supported()
}

#[cfg(target_os = "linux")]
pub fn start(bindings: Vec<ShortcutBinding>) -> Result<GlobalShortcutStatus, NativeError> {
    backend::start(bindings)
}

#[cfg(target_os = "linux")]
pub fn poll() -> Option<String> {
    backend::poll()
}

#[cfg(target_os = "linux")]
pub fn stop() {
    backend::stop();
}

#[cfg(not(target_os = "linux"))]
pub fn portal_supported() -> bool {
    false
}

#[cfg(not(target_os = "linux"))]
pub fn start(bindings: Vec<ShortcutBinding>) -> Result<GlobalShortcutStatus, NativeError> {
    validate(&bindings)?;
    Err(NativeError {
        code: "shortcuts_unsupported".to_owned(),
        message: "Global shortcuts are not available on this platform yet.".to_owned(),
    })
}

#[cfg(not(target_os = "linux"))]
pub fn poll() -> Option<String> {
    None
}

#[cfg(not(target_os = "linux"))]
pub fn stop() {}

#[cfg(test)]
mod tests {
    use super::*;

    fn binding(id: &str, trigger: &str) -> ShortcutBinding {
        ShortcutBinding {
            id: id.to_owned(),
            preferred_trigger: trigger.to_owned(),
            description: id.to_owned(),
        }
    }

    #[test]
    fn validation_rejects_empty_sets() {
        assert!(validate(&[]).is_err());
    }

    #[test]
    fn validation_rejects_blank_ids_and_triggers() {
        assert!(validate(&[binding("", "<Ctrl>A")]).is_err());
        assert!(validate(&[binding("postcraft.region", "   ")]).is_err());
    }

    #[test]
    fn validation_accepts_well_formed_bindings() {
        assert!(
            validate(&[
                binding("postcraft.region", "<Ctrl><Shift>A"),
                binding("postcraft.screen", "<Ctrl><Shift>F"),
            ])
            .is_ok()
        );
    }
}
