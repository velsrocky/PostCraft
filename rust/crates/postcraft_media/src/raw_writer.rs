use crate::{MediaError, MediaResult};
use std::io::Write;
use std::process::ChildStdin;

/// Writes a PipeWire packed-memory frame into an FFmpeg raw-video stdin.
/// DMABUF, planar, and multi-plane frames are rejected until an explicit
/// conversion path is available.
pub fn write_packed_frame(
    input: &mut ChildStdin,
    planes: &mut [(&str, Option<&mut [u8]>, u32, u32)],
) -> MediaResult<usize> {
    if planes.len() != 1 {
        return Err(MediaError::new(
            "raw_frame_unsupported",
            "only one packed video plane is supported",
        ));
    }
    let (_, data, offset, size) = &mut planes[0];
    let bytes = data.as_deref_mut().ok_or_else(|| {
        MediaError::new("raw_frame_unmapped", "PipeWire frame memory is not mapped")
    })?;
    let start = *offset as usize;
    let end = start
        .checked_add(*size as usize)
        .ok_or_else(|| MediaError::new("raw_frame_invalid", "frame bounds overflow"))?;
    if end > bytes.len() {
        return Err(MediaError::new(
            "raw_frame_invalid",
            "PipeWire frame bounds exceed mapped memory",
        ));
    }
    input
        .write_all(&bytes[start..end])
        .map_err(|error| MediaError::new("raw_frame_write", error.to_string()))?;
    Ok(end - start)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::process::{Command, Stdio};

    #[test]
    fn rejects_multiple_planes() {
        let mut child = Command::new("cat").stdin(Stdio::piped()).spawn().unwrap();
        let mut input = child.stdin.take().unwrap();
        let mut planes = [("bgra", None, 0, 4), ("extra", None, 0, 4)];
        assert_eq!(
            write_packed_frame(&mut input, &mut planes)
                .unwrap_err()
                .code,
            "raw_frame_unsupported"
        );
        drop(input);
        let _ = child.kill();
        let _ = child.wait();
    }
}
