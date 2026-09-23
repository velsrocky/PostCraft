use crate::{MediaError, MediaResult};
use serde::{Deserialize, Serialize};
use std::path::Path;

/// A validated slice of a media asset on a single sequential video track.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct TimelineClip {
    pub input: String,
    /// `video`, `image`, or `audio`.
    pub kind: String,
    pub source_in_us: i64,
    pub source_out_us: i64,
    pub start_us: i64,
    /// Volume in thousandths, where 1000 is unity gain.
    pub volume_milli: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct TimelineRenderRequest {
    pub clips: Vec<TimelineClip>,
    pub output: String,
    pub container: String,
    pub crf: Option<i32>,
}

/// Compiles a sequential mixed-media timeline into an FFmpeg filter graph.
/// The compiler accepts only resolved local paths and emits argv entries.
pub fn build_timeline_args(
    request: &TimelineRenderRequest,
    temp_output: &Path,
) -> MediaResult<Vec<String>> {
    if request.clips.is_empty() {
        return Err(MediaError::new(
            "invalid_timeline",
            "at least one clip is required",
        ));
    }
    let (codec, default_crf, extension) = match request.container.as_str() {
        "mp4" => ("libx264", 23, "mp4"),
        "webm" => ("libvpx-vp9", 33, "webm"),
        other => {
            return Err(MediaError::new(
                "invalid_container",
                format!("unsupported container '{other}' (expected mp4 or webm)"),
            ));
        }
    };
    if !Path::new(&request.output)
        .extension()
        .and_then(|extension| extension.to_str())
        .is_some_and(|output_extension| output_extension.eq_ignore_ascii_case(extension))
    {
        return Err(MediaError::new(
            "container_mismatch",
            format!("output extension must be .{extension}"),
        ));
    }
    if request.crf.is_some_and(|crf| !(0..=51).contains(&crf)) {
        return Err(MediaError::new("invalid_crf", "crf must be within 0..=51"));
    }

    let mut args = vec![
        "-hide_banner".into(),
        "-loglevel".into(),
        "error".into(),
        "-nostdin".into(),
        "-progress".into(),
        "pipe:1".into(),
        "-y".into(),
    ];
    for clip in &request.clips {
        if clip.input.trim().is_empty()
            || clip.source_in_us < 0
            || clip.source_out_us <= clip.source_in_us
        {
            return Err(MediaError::new(
                "invalid_clip",
                "clip range or input is invalid",
            ));
        }
        match clip.kind.as_str() {
            "image" => args.extend([
                "-loop".into(),
                "1".into(),
                "-t".into(),
                format_seconds(clip.source_out_us - clip.source_in_us),
                "-i".into(),
                clip.input.clone(),
            ]),
            "video" | "audio" => args.extend([
                "-ss".into(),
                format_seconds(clip.source_in_us),
                "-t".into(),
                format_seconds(clip.source_out_us - clip.source_in_us),
                "-i".into(),
                clip.input.clone(),
            ]),
            other => {
                return Err(MediaError::new(
                    "invalid_clip",
                    format!("unsupported clip kind '{other}'"),
                ));
            }
        }
    }

    let video_clips = request
        .clips
        .iter()
        .filter(|clip| clip.kind == "video" || clip.kind == "image")
        .collect::<Vec<_>>();
    if video_clips.is_empty() {
        return Err(MediaError::new(
            "invalid_timeline",
            "timeline needs a video or image clip",
        ));
    }
    let filters = request
        .clips
        .iter()
        .enumerate()
        .filter(|(_, clip)| clip.kind == "video" || clip.kind == "image")
        .map(|(index, _)| format!("[{index}:v]setpts=PTS-STARTPTS[v{index}]"))
        .collect::<Vec<_>>();
    let inputs = request
        .clips
        .iter()
        .enumerate()
        .filter(|(_, clip)| clip.kind == "video" || clip.kind == "image")
        .map(|(index, _)| format!("[v{index}]"))
        .collect::<String>();
    let video_concat = format!("{inputs}concat=n={}:v=1:a=0[vout]", video_clips.len());
    let audio_clips = request
        .clips
        .iter()
        .enumerate()
        .filter(|(_, clip)| clip.kind == "audio")
        .collect::<Vec<_>>();
    let audio_filters = audio_clips
        .iter()
        .map(|(index, clip)| {
            format!(
                "[{index}:a]volume={:.3},asetpts=PTS-STARTPTS[a{index}]",
                clip.volume_milli.min(4000) as f32 / 1000.0
            )
        })
        .collect::<Vec<_>>();
    let audio_map = if audio_clips.is_empty() {
        "-an".to_owned()
    } else {
        let inputs = audio_clips
            .iter()
            .map(|(index, _)| format!("[a{index}]"))
            .collect::<String>();
        format!("{inputs}concat=n={}:v=0:a=1[aout]", audio_clips.len())
    };
    let mut filter_graph = filters;
    filter_graph.push(video_concat);
    filter_graph.extend(audio_filters);
    if !audio_clips.is_empty() {
        filter_graph.push(audio_map.clone());
    }
    let mut output_args = vec![
        "-filter_complex".into(),
        filter_graph.join(";"),
        "-map".into(),
        "[vout]".into(),
    ];
    if !audio_clips.is_empty() {
        output_args.extend([
            "-map".into(),
            "[aout]".into(),
            "-c:a".into(),
            audio_codec(&request.container).into(),
        ]);
    } else {
        output_args.push("-an".into());
    }
    output_args.extend([
        "-c:v".into(),
        codec.into(),
        "-crf".into(),
        request.crf.unwrap_or(default_crf).to_string(),
        "-pix_fmt".into(),
        "yuv420p".into(),
        "-movflags".into(),
        "+faststart".into(),
        temp_output.to_string_lossy().into_owned(),
    ]);
    args.extend(output_args);
    Ok(args)
}

fn audio_codec(container: &str) -> &'static str {
    if container == "webm" {
        "libopus"
    } else {
        "aac"
    }
}

fn format_seconds(micros: i64) -> String {
    format!("{:.6}", micros as f64 / 1_000_000.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compiles_sequential_trimmed_video_clips() {
        let request = TimelineRenderRequest {
            clips: vec![
                TimelineClip {
                    input: "/tmp/a.mp4".into(),
                    kind: "video".into(),
                    source_in_us: 0,
                    source_out_us: 1_500_000,
                    start_us: 0,
                    volume_milli: 1000,
                },
                TimelineClip {
                    input: "/tmp/b.mp4".into(),
                    kind: "video".into(),
                    source_in_us: 500_000,
                    source_out_us: 2_000_000,
                    start_us: 1_500_000,
                    volume_milli: 1000,
                },
            ],
            output: "/tmp/timeline.mp4".into(),
            container: "mp4".into(),
            crf: None,
        };
        let args =
            build_timeline_args(&request, Path::new("/tmp/timeline.postcraft-tmp.mp4")).unwrap();
        assert!(args.windows(2).any(|pair| pair == ["-filter_complex", "[0:v]setpts=PTS-STARTPTS[v0];[1:v]setpts=PTS-STARTPTS[v1];[v0][v1]concat=n=2:v=1:a=0[vout]"]));
        assert!(args.windows(2).any(|pair| pair == ["-map", "[vout]"]));
    }

    #[test]
    fn rejects_invalid_ranges() {
        let request = TimelineRenderRequest {
            clips: vec![TimelineClip {
                input: "/tmp/a.mp4".into(),
                kind: "video".into(),
                source_in_us: 2,
                source_out_us: 1,
                start_us: 0,
                volume_milli: 1000,
            }],
            output: "/tmp/timeline.mp4".into(),
            container: "mp4".into(),
            crf: None,
        };
        assert_eq!(
            build_timeline_args(&request, Path::new("/tmp/x.mp4"))
                .unwrap_err()
                .code,
            "invalid_clip"
        );
    }
}
