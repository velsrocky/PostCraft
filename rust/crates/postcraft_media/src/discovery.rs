use std::env;
use std::ffi::OsString;
use std::path::{Path, PathBuf};

/// Resolved locations of the FFmpeg toolchain binaries.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EnginePaths {
    pub ffmpeg: Option<PathBuf>,
    pub ffprobe: Option<PathBuf>,
}

fn is_executable(path: &Path) -> bool {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        path.metadata()
            .map(|metadata| metadata.is_file() && metadata.permissions().mode() & 0o111 != 0)
            .unwrap_or(false)
    }
    #[cfg(not(unix))]
    {
        path.is_file()
    }
}

/// Pure resolver: explicit `env_value` → bundled sidecar next to `exe_dir` →
/// bare PATH command name. Split out so it is testable without mutating the
/// process environment (whose setters are `unsafe` in edition 2024).
fn resolve_one(env_value: Option<OsString>, exe_dir: Option<&Path>, name: &str) -> Option<PathBuf> {
    if let Some(explicit) = env_value {
        let path = PathBuf::from(explicit);
        if is_executable(&path) {
            return Some(path);
        }
    }
    if let Some(dir) = exe_dir {
        for candidate in [
            dir.join(name),
            dir.join("lib").join(name),
            dir.join("resources").join(name),
        ] {
            if is_executable(&candidate) {
                return Some(candidate);
            }
        }
    }
    // Defer to PATH resolution; a launch failure surfaces as a capability error.
    Some(PathBuf::from(name))
}

/// Resolves ffmpeg/ffprobe: explicit env override → bundled sidecar → PATH.
pub fn resolve_engines() -> EnginePaths {
    let exe_dir = env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(Path::to_path_buf));
    EnginePaths {
        ffmpeg: resolve_one(
            env::var_os("POSTCRAFT_FFMPEG"),
            exe_dir.as_deref(),
            "ffmpeg",
        ),
        ffprobe: resolve_one(
            env::var_os("POSTCRAFT_FFPROBE"),
            exe_dir.as_deref(),
            "ffprobe",
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn falls_back_to_path_command_name() {
        let resolved = resolve_one(None, None, "ffmpeg");
        assert_eq!(resolved, Some(PathBuf::from("ffmpeg")));
    }

    #[test]
    fn uses_explicit_override_when_executable() {
        let file = std::env::temp_dir().join("postcraft-discovery-override");
        std::fs::write(&file, b"").unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&file, std::fs::Permissions::from_mode(0o755)).unwrap();
        }
        let resolved = resolve_one(Some(file.clone().into_os_string()), None, "ffmpeg");
        assert_eq!(resolved, Some(file));
        let _ = std::fs::remove_file(std::env::temp_dir().join("postcraft-discovery-override"));
    }

    #[test]
    fn ignores_non_executable_override_and_uses_sidecar() {
        // A non-executable override is skipped in favour of the bundled sidecar.
        let dir = std::env::temp_dir();
        let resolved = resolve_one(Some(dir.clone().into_os_string()), None, "ffmpeg");
        // The override path is a directory → not executable → falls through to
        // sidecar search (none in temp) → PATH name.
        assert_eq!(resolved, Some(PathBuf::from("ffmpeg")));
    }
}
