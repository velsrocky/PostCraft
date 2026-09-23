use crate::discovery::resolve_engines;
use crate::progress::ProgressParser;
use crate::{MediaError, MediaResult};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::io::{BufRead, BufReader, Read};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

/// Request describing a single transcode (foundation: whole-file, no timeline).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscodeRequest {
    pub input: String,
    pub output: String,
    /// "mp4" or "webm".
    pub container: String,
    pub audio: bool,
    pub crf: Option<i32>,
    pub fps: Option<i32>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum JobState {
    Queued,
    Running,
    Succeeded,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscodeProgress {
    pub state: JobState,
    pub out_time_us: i64,
    pub message: String,
}

impl TranscodeProgress {
    fn terminal(&self) -> bool {
        matches!(
            self.state,
            JobState::Succeeded | JobState::Failed | JobState::Cancelled
        )
    }
}

const MP4_VIDEO: &str = "libx264";
const MP4_AUDIO: &str = "aac";
const WEBM_VIDEO: &str = "libvpx-vp9";
const WEBM_AUDIO: &str = "libopus";

/// Builds a validated ffmpeg argv list (never a shell string). [temp_output] is
/// where ffmpeg writes before the atomic rename to the final path.
pub fn build_args(request: &TranscodeRequest, temp_output: &Path) -> MediaResult<Vec<String>> {
    if request.input.trim().is_empty() || request.output.trim().is_empty() {
        return Err(MediaError::new(
            "invalid_request",
            "input and output are required",
        ));
    }
    let (video_codec, default_crf, extension) = match request.container.as_str() {
        "mp4" => (MP4_VIDEO, 23, "mp4"),
        "webm" => (WEBM_VIDEO, 33, "webm"),
        other => {
            return Err(MediaError::new(
                "invalid_container",
                format!("unsupported container '{other}' (expected mp4 or webm)"),
            ));
        }
    };
    let output_matches = Path::new(&request.output)
        .extension()
        .and_then(|ext| ext.to_str())
        .is_some_and(|ext| ext.eq_ignore_ascii_case(extension));
    if !output_matches {
        return Err(MediaError::new(
            "container_mismatch",
            format!(
                "output extension must be .{extension} for the {} container",
                request.container
            ),
        ));
    }
    if request.crf.is_some_and(|crf| !(0..=51).contains(&crf)) {
        return Err(MediaError::new("invalid_crf", "crf must be within 0..=51"));
    }
    if request.fps.is_some_and(|fps| fps <= 0 || fps > 240) {
        return Err(MediaError::new("invalid_fps", "fps must be within 1..=240"));
    }

    let mut args: Vec<String> = vec![
        "-hide_banner".into(),
        "-loglevel".into(),
        "error".into(),
        "-nostdin".into(),
        "-progress".into(),
        "pipe:1".into(),
        "-y".into(),
        "-i".into(),
        request.input.clone(),
        "-map".into(),
        "0:v:0".into(),
        "-c:v".into(),
        video_codec.into(),
        "-crf".into(),
        request.crf.unwrap_or(default_crf).to_string(),
        "-pix_fmt".into(),
        "yuv420p".into(),
    ];
    if request.container == "mp4" {
        args.extend(["-movflags".into(), "+faststart".into()]);
    }
    if request.audio {
        let audio_codec = if request.container == "mp4" {
            MP4_AUDIO
        } else {
            WEBM_AUDIO
        };
        args.extend([
            "-map".into(),
            "0:a:0?".into(),
            "-c:a".into(),
            audio_codec.into(),
        ]);
    } else {
        args.push("-an".into());
    }
    if let Some(fps) = request.fps {
        args.extend(["-r".into(), fps.to_string()]);
    }
    args.push(temp_output.to_string_lossy().into_owned());
    Ok(args)
}

struct JobRecord {
    cancel: Arc<AtomicBool>,
    progress: Arc<Mutex<TranscodeProgress>>,
}

fn job_map() -> &'static Mutex<HashMap<u32, JobRecord>> {
    static MAP: OnceLock<Mutex<HashMap<u32, JobRecord>>> = OnceLock::new();
    MAP.get_or_init(|| Mutex::new(HashMap::new()))
}

fn lock_or_recover<T>(mutex: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    mutex
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

static NEXT_JOB_ID: AtomicU32 = AtomicU32::new(1);

pub(crate) fn temp_path(output: &str) -> PathBuf {
    let output_path = Path::new(output);
    let extension = output_path
        .extension()
        .and_then(|extension| extension.to_str())
        .unwrap_or("tmp");
    PathBuf::from(format!("{output}.postcraft-tmp.{extension}"))
}

/// Launches a supervised transcode and returns a job id for polling/cancel.
pub fn start_transcode(request: TranscodeRequest) -> MediaResult<u32> {
    let ffmpeg = resolve_engines()
        .ffmpeg
        .ok_or_else(|| MediaError::new("ffmpeg_missing", "FFmpeg was not found."))?;
    let temp = temp_path(&request.output);
    let args = build_args(&request, &temp)?;
    start_args_job(ffmpeg, args, temp, request.output)
}

pub(crate) fn start_args_job(
    ffmpeg: PathBuf,
    args: Vec<String>,
    temp: PathBuf,
    final_output: String,
) -> MediaResult<u32> {
    let id = NEXT_JOB_ID.fetch_add(1, Ordering::Relaxed);
    let cancel = Arc::new(AtomicBool::new(false));
    let progress = Arc::new(Mutex::new(TranscodeProgress {
        state: JobState::Queued,
        out_time_us: 0,
        message: String::new(),
    }));

    let thread_cancel = Arc::clone(&cancel);
    let thread_progress = Arc::clone(&progress);
    std::thread::spawn(move || {
        let _ = run_supervised(
            &ffmpeg,
            &args,
            &temp,
            &final_output,
            &thread_cancel,
            &thread_progress,
        );
        let mut current = lock_or_recover(&thread_progress);
        if !current.terminal() {
            current.state = JobState::Failed;
            if current.message.is_empty() {
                current.message = "transcode ended without a final state".into();
            }
        }
    });

    lock_or_recover(job_map()).insert(id, JobRecord { cancel, progress });
    Ok(id)
}

fn run_supervised(
    ffmpeg: &Path,
    args: &[String],
    temp: &Path,
    final_output: &str,
    cancel: &Arc<AtomicBool>,
    progress: &Arc<Mutex<TranscodeProgress>>,
) -> MediaResult<()> {
    update(progress, |snapshot| snapshot.state = JobState::Running);
    let mut child = match Command::new(ffmpeg)
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
    {
        Ok(child) => child,
        Err(error) => {
            set_failed(progress, &format!("failed to launch ffmpeg: {error}"));
            return Err(MediaError::new("ffmpeg_launch_failed", error.to_string()));
        }
    };

    match supervise(&mut child, cancel, progress) {
        Ok(true) => finalize_success(temp, final_output, progress),
        Ok(false) => {
            let _ = fs::remove_file(temp);
            update(progress, |snapshot| snapshot.state = JobState::Cancelled);
            Ok(())
        }
        Err(error) => {
            let _ = child.wait();
            let _ = fs::remove_file(temp);
            set_failed(progress, &error.message);
            Err(error)
        }
    }
}

/// Reads ffmpeg's stdout tracking progress. Ok(true) = completed, Ok(false) =
/// cancelled, Err = failure.
fn supervise(
    child: &mut Child,
    cancel: &AtomicBool,
    progress: &Arc<Mutex<TranscodeProgress>>,
) -> MediaResult<bool> {
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| MediaError::new("ffmpeg_pipe", "no stdout pipe"))?;
    let mut reader = BufReader::new(stdout);
    let mut parser = ProgressParser::new();
    let mut line = String::new();
    loop {
        if cancel.load(Ordering::Relaxed) {
            let _ = child.kill();
            return Ok(false);
        }
        line.clear();
        match reader.read_line(&mut line) {
            Ok(0) => break,
            Ok(_) => {
                parser.apply_line(&line);
                let snapshot = TranscodeProgress {
                    state: JobState::Running,
                    out_time_us: parser.out_time_us,
                    message: String::new(),
                };
                update(progress, |current| *current = snapshot);
            }
            Err(error) => return Err(MediaError::new("ffmpeg_read", error.to_string())),
        }
    }
    let status = child
        .wait()
        .map_err(|error| MediaError::new("ffmpeg_wait", error.to_string()))?;
    if !status.success() {
        let mut stderr = String::new();
        if let Some(pipe) = child.stderr.as_mut() {
            let _ = pipe.read_to_string(&mut stderr);
        }
        return Err(MediaError::new(
            "ffmpeg_exit",
            stderr
                .trim()
                .lines()
                .next_back()
                .unwrap_or("ffmpeg failed")
                .to_owned(),
        ));
    }
    Ok(true)
}

fn finalize_success(
    temp: &Path,
    final_output: &str,
    progress: &Arc<Mutex<TranscodeProgress>>,
) -> MediaResult<()> {
    let metadata = fs::metadata(temp).map_err(|error| {
        set_failed(progress, "output was not produced");
        MediaError::new("ffmpeg_output_missing", error.to_string())
    })?;
    if metadata.len() == 0 {
        let _ = fs::remove_file(temp);
        set_failed(progress, "output is empty");
        return Err(MediaError::new("ffmpeg_output_empty", "output is empty"));
    }
    if let Some(parent) = Path::new(final_output).parent() {
        let _ = fs::create_dir_all(parent);
    }
    fs::rename(temp, final_output).map_err(|error| {
        let _ = fs::remove_file(temp);
        MediaError::new("ffmpeg_finalize", error.to_string())
    })?;
    update(progress, |snapshot| snapshot.state = JobState::Succeeded);
    Ok(())
}

/// Polls a job's current state; returns `None` for unknown ids and removes the
/// record once it reports a terminal state.
pub fn poll_transcode(id: u32) -> Option<TranscodeProgress> {
    let snapshot = {
        let map = lock_or_recover(job_map());
        map.get(&id)?.progress.lock().ok()?.clone()
    };
    if snapshot.terminal() {
        lock_or_recover(job_map()).remove(&id);
    }
    Some(snapshot)
}

pub fn cancel_transcode(id: u32) -> bool {
    let map = lock_or_recover(job_map());
    if let Some(record) = map.get(&id) {
        record.cancel.store(true, Ordering::Relaxed);
        true
    } else {
        false
    }
}

fn update<F: FnOnce(&mut TranscodeProgress)>(progress: &Arc<Mutex<TranscodeProgress>>, f: F) {
    let mut snapshot = lock_or_recover(progress);
    f(&mut snapshot);
}

fn set_failed(progress: &Arc<Mutex<TranscodeProgress>>, message: &str) {
    update(progress, |snapshot| {
        snapshot.state = JobState::Failed;
        snapshot.message = message.to_owned();
    });
}

/// Blocking convenience used by tests and small jobs; runs to completion or
/// error with an atomic temp→final move.
pub fn run_transcode_to_completion(request: &TranscodeRequest) -> MediaResult<()> {
    let ffmpeg = resolve_engines()
        .ffmpeg
        .ok_or_else(|| MediaError::new("ffmpeg_missing", "FFmpeg was not found."))?;
    let temp = temp_path(&request.output);
    let args = build_args(request, &temp)?;
    let output = Command::new(&ffmpeg)
        .args(&args)
        .stderr(Stdio::piped())
        .output()
        .map_err(|error| MediaError::new("ffmpeg_launch_failed", error.to_string()))?;
    if !output.status.success() {
        let _ = fs::remove_file(&temp);
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(MediaError::new(
            "ffmpeg_exit",
            stderr
                .trim()
                .lines()
                .next_back()
                .unwrap_or("ffmpeg failed")
                .to_owned(),
        ));
    }
    let progress = Arc::new(Mutex::new(TranscodeProgress {
        state: JobState::Running,
        out_time_us: 0,
        message: String::new(),
    }));
    finalize_success(&temp, &request.output, &progress)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request(container: &str) -> TranscodeRequest {
        TranscodeRequest {
            input: "/tmp/in.mp4".into(),
            output: format!("/tmp/out.{container}"),
            container: container.into(),
            audio: true,
            crf: None,
            fps: None,
        }
    }

    #[test]
    fn builds_mp4_command() {
        let args = build_args(&request("mp4"), Path::new("/tmp/out.mp4.tmp")).unwrap();
        assert!(args.windows(2).any(|w| w == ["-c:v", MP4_VIDEO]));
        assert!(args.windows(2).any(|w| w == ["-c:a", MP4_AUDIO]));
        assert!(args.windows(2).any(|w| w == ["-movflags", "+faststart"]));
        assert!(args.windows(2).any(|w| w == ["-progress", "pipe:1"]));
        assert!(args.last().unwrap().ends_with("out.mp4.tmp"));
    }

    #[test]
    fn builds_webm_without_audio() {
        let mut req = request("webm");
        req.audio = false;
        let args = build_args(&req, Path::new("/tmp/out.webm.tmp")).unwrap();
        assert!(args.windows(2).any(|w| w == ["-c:v", WEBM_VIDEO]));
        assert!(args.iter().any(|a| a == "-an"));
        assert!(!args.iter().any(|a| a == WEBM_AUDIO));
        assert!(!args.iter().any(|a| a == "+faststart"));
    }

    #[test]
    fn rejects_bad_container_extension_and_bounds() {
        assert!(build_args(&request("avi"), Path::new("/tmp/x")).is_err());
        let mut mismatch = request("mp4");
        mismatch.output = "/tmp/out.webm".into();
        assert!(build_args(&mismatch, Path::new("/tmp/x")).is_err());
        let mut bad_crf = request("mp4");
        bad_crf.crf = Some(60);
        assert!(build_args(&bad_crf, Path::new("/tmp/x")).is_err());
        let mut bad_fps = request("mp4");
        bad_fps.fps = Some(0);
        assert!(build_args(&bad_fps, Path::new("/tmp/x")).is_err());
    }

    fn ffmpeg_present() -> bool {
        Command::new("ffmpeg").arg("-version").output().is_ok()
    }

    #[test]
    fn transcodes_a_generated_clip_end_to_end_and_probes_it() {
        if !ffmpeg_present() {
            eprintln!("ffmpeg missing; skipping live transcode test");
            return;
        }
        let dir = std::env::temp_dir();
        let source = dir.join("postcraft-live-src.mp4");
        let webm = dir.join("postcraft-live-out.webm");
        let _ = fs::remove_file(&source);
        let _ = fs::remove_file(&webm);

        let made = Command::new("ffmpeg")
            .args([
                "-hide_banner",
                "-loglevel",
                "error",
                "-y",
                "-f",
                "lavfi",
                "-i",
                "testsrc=duration=1:size=320x240:rate=15",
                "-pix_fmt",
                "yuv420p",
            ])
            .arg(&source)
            .status()
            .expect("spawn source");
        assert!(made.success(), "failed to build test source clip");

        let req = TranscodeRequest {
            input: source.to_string_lossy().into_owned(),
            output: webm.to_string_lossy().into_owned(),
            container: "webm".into(),
            audio: false,
            crf: None,
            fps: Some(15),
        };
        run_transcode_to_completion(&req).expect("transcode should succeed");
        assert!(webm.exists());

        let engines = resolve_engines();
        if let Some(ffprobe) = engines.ffprobe {
            let probe = crate::probe::probe_file(&ffprobe, &webm.to_string_lossy())
                .expect("probe should succeed");
            assert!(probe.has_video);
            assert_eq!(probe.width, 320);
            assert_eq!(probe.height, 240);
        }

        let _ = fs::remove_file(&source);
        let _ = fs::remove_file(&webm);
    }

    #[test]
    fn start_poll_cancel_reports_terminal_state() {
        if !ffmpeg_present() {
            eprintln!("ffmpeg missing; skipping async job test");
            return;
        }
        let dir = std::env::temp_dir();
        let source = dir.join("postcraft-async-src.mp4");
        let out = dir.join("postcraft-async-out.mp4");
        let _ = fs::remove_file(&source);
        let _ = fs::remove_file(&out);
        let made = Command::new("ffmpeg")
            .args([
                "-hide_banner",
                "-loglevel",
                "error",
                "-y",
                "-f",
                "lavfi",
                "-i",
                "testsrc=duration=1:size=160x120:rate=10",
                "-pix_fmt",
                "yuv420p",
            ])
            .arg(&source)
            .status()
            .expect("spawn source");
        assert!(made.success());

        let req = TranscodeRequest {
            input: source.to_string_lossy().into_owned(),
            output: out.to_string_lossy().into_owned(),
            container: "mp4".into(),
            audio: false,
            crf: None,
            fps: None,
        };
        let id = start_transcode(req).expect("start job");
        let mut final_state = None;
        for _ in 0..300 {
            if let Some(progress) = poll_transcode(id) {
                if matches!(
                    progress.state,
                    JobState::Succeeded | JobState::Failed | JobState::Cancelled
                ) {
                    final_state = Some(progress.state);
                    break;
                }
            }
            std::thread::sleep(std::time::Duration::from_millis(20));
        }
        assert!(
            matches!(final_state, Some(JobState::Succeeded)),
            "job did not succeed: {final_state:?}"
        );
        assert!(out.exists());
        let _ = fs::remove_file(&source);
        let _ = fs::remove_file(&out);
    }
}
