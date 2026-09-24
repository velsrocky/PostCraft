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

/// Candidate file names for a sidecar search: the bare name plus the Windows
/// `.exe` spelling so a bundled `ffmpeg.exe` is found from any host and a
/// bundled `ffmpeg` is found on Unix. `name` may already include `.exe`.
fn sidecar_names(name: &str) -> Vec<String> {
    let mut names = vec![name.to_owned()];
    if !name.ends_with(".exe") {
        names.push(format!("{name}.exe"));
    }
    names
}

/// Directories searched for a bundled engine next to the running executable.
fn sidecar_dirs(dir: &Path) -> [PathBuf; 3] {
    [dir.to_path_buf(), dir.join("lib"), dir.join("resources")]
}

/// Pure resolver: explicit `env_value` → bundled sidecar next to `exe_dir` →
/// bare PATH command name. Split out so it is testable without mutating the
/// process environment (whose setters are `unsafe` in edition 2024).
fn resolve_one(env_value: Option<OsString>, exe_dir: Option<&Path>, name: &str) -> Option<PathBuf> {
    if let Some(explicit) = env_value {
        for candidate_name in sidecar_names(&explicit.to_string_lossy()) {
            let path = PathBuf::from(&candidate_name);
            if is_executable(&path) {
                return Some(path);
            }
        }
    }
    if let Some(dir) = exe_dir {
        for base in sidecar_dirs(dir) {
            for candidate_name in sidecar_names(name) {
                let candidate = base.join(&candidate_name);
                if is_executable(&candidate) {
                    return Some(candidate);
                }
            }
        }
    }
    // Defer to PATH resolution; a launch failure surfaces as a capability error.
    // CreateProcess on Windows will append `.exe` itself, so the bare name wins.
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

    fn scratch_dir(label: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "postcraft-discovery-{label}-{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[cfg(unix)]
    fn make_executable(path: &Path) {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o755)).unwrap();
    }

    #[cfg(not(unix))]
    fn make_executable(path: &Path) {
        let _ = path;
    }

    #[test]
    fn falls_back_to_path_command_name() {
        let resolved = resolve_one(None, None, "ffmpeg");
        assert_eq!(resolved, Some(PathBuf::from("ffmpeg")));
    }

    #[test]
    fn path_fallback_preserves_windows_style_names() {
        let resolved = resolve_one(None, None, "ffmpeg.exe");
        assert_eq!(resolved, Some(PathBuf::from("ffmpeg.exe")));
        let resolved = resolve_one(None, None, "ffprobe.exe");
        assert_eq!(resolved, Some(PathBuf::from("ffprobe.exe")));
    }

    #[test]
    fn sidecar_search_finds_exe_named_candidate() {
        let dir = scratch_dir("exe-named");
        let binary = dir.join("ffmpeg.exe");
        std::fs::write(&binary, b"").unwrap();
        make_executable(&binary);
        let resolved = resolve_one(None, Some(&dir), "ffmpeg.exe");
        assert_eq!(resolved, Some(binary));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn sidecar_search_appends_exe_suffix_for_bare_name() {
        let dir = scratch_dir("exe-suffix");
        let binary = dir.join("ffprobe.exe");
        std::fs::write(&binary, b"").unwrap();
        make_executable(&binary);
        let resolved = resolve_one(None, Some(&dir), "ffprobe");
        assert_eq!(resolved, Some(binary));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn sidecar_search_covers_lib_and_resources_directories() {
        let dir = scratch_dir("sidecar-dirs");
        let lib_dir = dir.join("lib");
        std::fs::create_dir_all(&lib_dir).unwrap();
        let binary = lib_dir.join("ffmpeg.exe");
        std::fs::write(&binary, b"").unwrap();
        make_executable(&binary);
        let resolved = resolve_one(None, Some(&dir), "ffmpeg");
        assert_eq!(resolved, Some(binary));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn uses_explicit_override_when_executable() {
        let file = std::env::temp_dir().join("postcraft-discovery-override");
        std::fs::write(&file, b"").unwrap();
        make_executable(&file);
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
