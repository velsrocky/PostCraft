use crate::discovery::resolve_engines;
use crate::job::{start_args_job, temp_path};
use crate::timeline::{TimelineClip, TimelineRenderRequest, build_timeline_args};
use crate::{MediaError, MediaResult};

pub fn start_timeline_render(
    clips: Vec<TimelineClip>,
    output: String,
    container: String,
    crf: Option<i32>,
) -> MediaResult<u32> {
    if resolve_engines().ffmpeg.is_none() {
        return Err(MediaError::new("ffmpeg_missing", "FFmpeg was not found."));
    }
    let request = TimelineRenderRequest {
        clips,
        output: output.clone(),
        container,
        crf,
    };
    let temp = temp_path(&output);
    let args = build_timeline_args(&request, &temp)?;
    start_args_job(resolve_engines().ffmpeg.unwrap(), args, temp, output)
}
