use super::{RecordingError, ScreenState};
use crate::proto::frame_diff::{TerminalFrameDiff, TerminalFrameKind};
use prost::Message;
use serde::{Deserialize, Serialize};

/// Initial tunable values for measurement, not published performance promises.
#[derive(Clone, Copy, Debug)]
pub struct SamplingPolicy {
    pub minimum_interval_micros: u64,
    pub maximum_interval_micros: u64,
    pub keyframe_interval_micros: u64,
}

impl Default for SamplingPolicy {
    fn default() -> Self {
        Self {
            minimum_interval_micros: 100_000,
            maximum_interval_micros: 1_000_000,
            keyframe_interval_micros: 5_000_000,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SemanticKind {
    CommandStarted,
    CommandFinished,
    ContextChanged,
    HookUnavailable,
    HookAvailable,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SemanticEvent {
    pub offset_micros: u64,
    pub kind: SemanticKind,
    pub context_id: String,
    pub command_id: Option<String>,
    pub command: Option<String>,
    pub cwd: Option<String>,
    pub hostname: Option<String>,
    pub exit_code: Option<i32>,
}

impl SemanticEvent {
    pub(super) fn validate(&self) -> Result<(), RecordingError> {
        let strings = [
            Some(self.context_id.as_str()),
            self.command_id.as_deref(),
            self.command.as_deref(),
            self.cwd.as_deref(),
            self.hostname.as_deref(),
        ];
        if self.context_id.is_empty()
            || strings
                .into_iter()
                .flatten()
                .any(|value| value.len() > 64 * 1024 || value.contains('\0'))
        {
            return Err(RecordingError::InvalidSemanticEvent);
        }
        if matches!(
            self.kind,
            SemanticKind::CommandStarted | SemanticKind::CommandFinished
        ) && self.command_id.as_deref().is_none_or(str::is_empty)
        {
            return Err(RecordingError::InvalidSemanticEvent);
        }
        if self.kind == SemanticKind::CommandStarted
            && self.command.as_deref().is_none_or(str::is_empty)
        {
            return Err(RecordingError::InvalidSemanticEvent);
        }
        Ok(())
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct VisualSample {
    pub sequence: u64,
    pub offset_micros: u64,
    /// None for self-contained keyframes; otherwise the preceding stored frame.
    pub base_sequence: Option<u64>,
    pub frame: TerminalFrameDiff,
}

#[derive(Clone, Debug, PartialEq)]
pub enum SampleRecord {
    Visual(Box<VisualSample>),
    Semantic(SemanticEvent),
}

/// Owns only current state plus the previous stored state. The caller must
/// stream returned records to a bounded writer rather than accumulating them.
pub struct AdaptiveSampler {
    policy: SamplingPolicy,
    screen: ScreenState,
    stored: Option<TerminalFrameDiff>,
    next_sequence: u64,
    last_observed: u64,
    last_frame_offset: Option<u64>,
    last_sample: u64,
    last_keyframe: u64,
    activity_per_mille: u64,
    pressure_percent: u8,
}

impl AdaptiveSampler {
    pub fn new(policy: SamplingPolicy) -> Result<Self, RecordingError> {
        if policy.minimum_interval_micros == 0
            || policy.minimum_interval_micros > policy.maximum_interval_micros
            || policy.maximum_interval_micros > policy.keyframe_interval_micros
        {
            return Err(RecordingError::InvalidPolicy);
        }
        Ok(Self {
            policy,
            screen: ScreenState::default(),
            stored: None,
            next_sequence: 0,
            last_observed: 0,
            last_frame_offset: None,
            last_sample: 0,
            last_keyframe: 0,
            activity_per_mille: 0,
            pressure_percent: 0,
        })
    }

    pub fn set_writer_pressure(&mut self, percent: u8) {
        self.pressure_percent = percent.min(100);
    }

    pub fn current_screen(&self) -> Option<&TerminalFrameDiff> {
        self.screen.snapshot()
    }

    /// Diagnostic encoded size of both retained screen models; not heap/RSS.
    pub fn retained_screen_protobuf_bytes(&self) -> usize {
        self.screen.snapshot().map_or(0, Message::encoded_len)
            + self.stored.as_ref().map_or(0, Message::encoded_len)
    }

    pub fn current_interval_micros(&self) -> u64 {
        let span = self.policy.maximum_interval_micros - self.policy.minimum_interval_micros;
        let activity = self.activity_per_mille.min(1000);
        let adjustment = (u128::from(span) * u128::from(activity) / 1000) as u64;
        let interval = self.policy.maximum_interval_micros - adjustment;
        ((u128::from(interval) * (100 + u128::from(self.pressure_percent) * 3) / 100)
            .min(u128::from(self.policy.maximum_interval_micros))) as u64
    }

    pub fn observe_frame(
        &mut self,
        offset_micros: u64,
        frame: TerminalFrameDiff,
    ) -> Result<Option<VisualSample>, RecordingError> {
        self.validate_time(offset_micros)?;
        let structural_change = self.screen.snapshot().is_none_or(|previous| {
            previous.viewport_rows != frame.viewport_rows
                || previous.viewport_cols != frame.viewport_cols
                || previous.modes.as_ref().map(|modes| modes.alternate_screen)
                    != frame.modes.as_ref().map(|modes| modes.alternate_screen)
        });
        let changed_rows =
            if frame.frame_kind == TerminalFrameKind::Snapshot as i32 && !structural_change {
                let previous = self
                    .screen
                    .snapshot()
                    .expect("structural check confirmed a screen");
                frame
                    .rows
                    .iter()
                    .filter(|row| previous.rows.get(row.index as usize) != Some(row))
                    .count()
            } else {
                frame.rows.len()
            };
        let area = if self
            .screen
            .snapshot()
            .is_some_and(|previous| previous.graphics != frame.graphics)
        {
            1000
        } else {
            ((changed_rows as u64 * 1000) / u64::from(frame.viewport_rows.max(1))).min(1000)
        };
        // Damage per minimum capture interval distinguishes sustained scrolling
        // from the same small change arriving only once a second. Hook/timer
        // observations must not distort the inter-frame interval.
        let elapsed = self
            .last_frame_offset
            .map_or(self.policy.minimum_interval_micros, |previous| {
                offset_micros.saturating_sub(previous).max(1)
            });
        let damage = (u128::from(area) * u128::from(self.policy.minimum_interval_micros)
            / u128::from(elapsed))
        .min(1000) as u64;
        self.screen.apply(frame)?;
        self.last_frame_offset = Some(offset_micros);
        self.activity_per_mille = (self.activity_per_mille * 3 + damage) / 4;
        self.last_observed = offset_micros;
        self.sample(offset_micros, structural_change)
    }

    /// Timer ticks also flush a final changed screen after output becomes idle.
    pub fn tick(&mut self, offset_micros: u64) -> Result<Option<VisualSample>, RecordingError> {
        self.validate_time(offset_micros)?;
        self.last_observed = offset_micros;
        let sample = self.sample(offset_micros, false)?;
        self.activity_per_mille = self.activity_per_mille * 3 / 4;
        Ok(sample)
    }

    /// Hook events bypass visual sampling/pressure. The boundary captures the
    /// current screen, even when unchanged. Caller preserves frame/event order.
    pub fn observe_semantic(
        &mut self,
        event: SemanticEvent,
    ) -> Result<Vec<SampleRecord>, RecordingError> {
        self.validate_time(event.offset_micros)?;
        event.validate()?;
        self.last_observed = event.offset_micros;
        let mut records = Vec::with_capacity(2);
        if let Some(frame) = self.sample(event.offset_micros, true)? {
            records.push(SampleRecord::Visual(Box::new(frame)));
        }
        records.push(SampleRecord::Semantic(event));
        Ok(records)
    }

    pub fn finish(&mut self, offset_micros: u64) -> Result<Option<VisualSample>, RecordingError> {
        self.validate_time(offset_micros)?;
        self.last_observed = offset_micros;
        self.sample(offset_micros, true)
    }

    fn validate_time(&self, time: u64) -> Result<(), RecordingError> {
        if time < self.last_observed {
            Err(RecordingError::NonMonotonicTime)
        } else {
            Ok(())
        }
    }

    fn sample(&mut self, time: u64, force: bool) -> Result<Option<VisualSample>, RecordingError> {
        let Some(current) = self.screen.snapshot() else {
            return Ok(None);
        };
        // Bound replay work even when many hook boundaries share a timestamp.
        let is_keyframe = self.next_sequence.is_multiple_of(128)
            || self.stored.as_ref().is_none_or(|previous| {
                previous.viewport_rows != current.viewport_rows
                    || previous.viewport_cols != current.viewport_cols
                    || previous.modes.as_ref().map(|modes| modes.alternate_screen)
                        != current.modes.as_ref().map(|modes| modes.alternate_screen)
            })
            || time.saturating_sub(self.last_keyframe) >= self.policy.keyframe_interval_micros;
        if !force
            && self.stored.is_some()
            && (self.stored.as_ref() == Some(current)
                || time.saturating_sub(self.last_sample) < self.current_interval_micros())
        {
            return Ok(None);
        }
        let next_sequence = self
            .next_sequence
            .checked_add(1)
            .ok_or(RecordingError::SequenceExhausted)?;
        let mut frame = current.clone();
        let mut base_sequence = if is_keyframe {
            self.last_keyframe = time;
            None
        } else {
            let previous = self
                .stored
                .as_ref()
                .ok_or(RecordingError::MissingSnapshot)?;
            frame.frame_kind = TerminalFrameKind::Delta as i32;
            frame.rows.retain(|row| {
                previous.rows.get(row.index as usize) != Some(row)
                    || previous
                        .hyperlinks
                        .iter()
                        .filter(|link| link.row == row.index)
                        .ne(current
                            .hyperlinks
                            .iter()
                            .filter(|link| link.row == row.index))
            });
            frame
                .hyperlinks
                .retain(|link| frame.rows.iter().any(|row| row.index == link.row));
            // Rebuilt from complete states, never from the last live delta.
            Some(self.next_sequence - 1)
        };
        // A full repaint has no smaller delta. Store an independent keyframe
        // at the same payload cost to improve later seek/recovery.
        if base_sequence.is_some() && frame.encoded_len() >= current.encoded_len() {
            frame = current.clone();
            base_sequence = None;
            self.last_keyframe = time;
        }
        let result = VisualSample {
            sequence: self.next_sequence,
            offset_micros: time,
            base_sequence,
            frame,
        };
        self.next_sequence = next_sequence;
        self.last_sample = time;
        self.stored = Some(current.clone());
        Ok(Some(result))
    }
}
