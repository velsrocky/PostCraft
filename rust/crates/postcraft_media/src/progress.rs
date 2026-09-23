/// Accumulates FFmpeg `-progress pipe:1` key/value lines into a snapshot.
#[derive(Debug, Default, Clone)]
pub struct ProgressParser {
    pub out_time_us: i64,
    pub finished: bool,
}

impl ProgressParser {
    pub fn new() -> Self {
        Self::default()
    }

    /// Feeds one `key=value` line. Unknown keys are ignored.
    pub fn apply_line(&mut self, line: &str) {
        let Some((key, value)) = line.trim().split_once('=') else {
            return;
        };
        match key {
            "out_time_us" | "out_time_ms" => {
                if let Ok(parsed) = value.trim().parse::<i64>() {
                    self.out_time_us = parsed;
                }
            }
            "progress" => {
                self.finished = value.trim() == "end";
            }
            _ => {}
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tracks_time_and_completion() {
        let mut parser = ProgressParser::new();
        for line in [
            "frame=120",
            "out_time_us=4000000",
            "bitrate=1024.0kbits/s",
            "progress=continue",
            "out_time_us=8000000",
            "progress=end",
        ] {
            parser.apply_line(line);
        }
        assert_eq!(parser.out_time_us, 8_000_000);
        assert!(parser.finished);
    }

    #[test]
    fn ignores_garbage_and_unrelated_keys() {
        let mut parser = ProgressParser::new();
        parser.apply_line("garbage without equals");
        parser.apply_line("out_time_us=not_a_number");
        parser.apply_line("progress=continue");
        assert_eq!(parser.out_time_us, 0);
        assert!(!parser.finished);
    }
}
