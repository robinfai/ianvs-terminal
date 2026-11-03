use super::{RecordingError, ScreenState, VisualSample};
use crate::proto::frame_diff::{TerminalFrameDiff, TerminalFrameKind};

/// Side-effect-free structured playback. It never feeds bytes to a PTY/parser.
#[derive(Default)]
pub struct ScreenReplay {
    screen: ScreenState,
    last_sequence: Option<u64>,
    last_offset_micros: u64,
}

impl ScreenReplay {
    pub fn screen(&self) -> Option<&TerminalFrameDiff> {
        self.screen.snapshot()
    }

    /// Apply an ordered sample. Missing/reordered data cannot silently produce
    /// a plausible but incorrect picture.
    pub fn apply(&mut self, sample: VisualSample) -> Result<(), RecordingError> {
        let expected = match self.last_sequence {
            Some(sequence) => sequence
                .checked_add(1)
                .ok_or(RecordingError::SequenceExhausted)?,
            None => 0,
        };
        if sample.sequence != expected {
            return Err(RecordingError::InvalidSequence);
        }
        if sample.offset_micros < self.last_offset_micros {
            return Err(RecordingError::NonMonotonicTime);
        }
        let is_keyframe = sample.frame.frame_kind == TerminalFrameKind::Snapshot as i32;
        if (is_keyframe && sample.base_sequence.is_some())
            || (!is_keyframe
                && (self.last_sequence.is_none() || sample.base_sequence != self.last_sequence))
        {
            return Err(RecordingError::InvalidSequence);
        }
        self.screen.apply(sample.frame)?;
        self.last_sequence = Some(sample.sequence);
        self.last_offset_micros = sample.offset_micros;
        Ok(())
    }

    /// Cold seek begins at an independently indexed and validated keyframe.
    /// A malformed candidate leaves the previous playback state intact.
    pub fn seek_keyframe(&mut self, sample: VisualSample) -> Result<(), RecordingError> {
        if sample.base_sequence.is_some()
            || sample.frame.frame_kind != TerminalFrameKind::Snapshot as i32
        {
            return Err(RecordingError::MissingSnapshot);
        }
        let mut screen = ScreenState::default();
        screen.apply(sample.frame)?;
        self.screen = screen;
        self.last_sequence = Some(sample.sequence);
        self.last_offset_micros = sample.offset_micros;
        Ok(())
    }
}
