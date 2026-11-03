use super::RecordingError;
use crate::model::TERMINAL_FRAME_SCHEMA_VERSION;
use crate::proto::frame_diff::{TerminalFrameDiff, TerminalFrameKind, TerminalRow};
use prost::Message;

// These are decoded-state admission bounds, not whole-recording limits.
const MAX_SCREEN_CELLS: u64 = 1_048_576;
const MAX_SCREEN_DIMENSION: u32 = 4096;
const MAX_SCREEN_BYTES: usize = 16 * 1024 * 1024;

/// Materializes every live delta, including those between stored samples.
/// Only a current screen is retained: memory does not grow with duration.
#[derive(Default)]
pub struct ScreenState {
    screen: Option<TerminalFrameDiff>,
}

impl ScreenState {
    pub fn snapshot(&self) -> Option<&TerminalFrameDiff> {
        self.screen.as_ref()
    }

    /// Validates before committing. A rejected update leaves the base intact.
    pub fn apply(&mut self, frame: TerminalFrameDiff) -> Result<(), RecordingError> {
        validate(&frame)?;
        let is_snapshot = frame.frame_kind == TerminalFrameKind::Snapshot as i32;
        let height = frame.viewport_rows as usize;
        let mut next = frame.clone();
        if is_snapshot {
            if frame.rows.len() != height {
                return Err(RecordingError::InvalidFrame("incomplete snapshot"));
            }
            next.rows.sort_by_key(|row| row.index);
        } else {
            let previous = self
                .screen
                .as_ref()
                .ok_or(RecordingError::MissingSnapshot)?;
            if frame.viewport_rows != previous.viewport_rows
                || frame.viewport_cols != previous.viewport_cols
                || frame.modes.as_ref().map(|modes| modes.alternate_screen)
                    != previous.modes.as_ref().map(|modes| modes.alternate_screen)
            {
                return Err(RecordingError::InvalidFrame(
                    "geometry or screen changed without snapshot",
                ));
            }
            let mut rows: Vec<Option<TerminalRow>> = vec![None; height];
            for row in &previous.rows {
                if let Some(index) =
                    shifted_index(row.index, frame.viewport_row_shift, frame.viewport_rows)
                {
                    let mut shifted = row.clone();
                    shifted.index = index;
                    rows[index as usize] = Some(shifted);
                }
            }
            let mut links = previous
                .hyperlinks
                .iter()
                .filter_map(|link| {
                    let row =
                        shifted_index(link.row, frame.viewport_row_shift, frame.viewport_rows)?;
                    if frame.rows.iter().any(|updated| updated.index == row) {
                        return None;
                    }
                    let mut shifted = link.clone();
                    shifted.row = row;
                    Some(shifted)
                })
                .collect::<Vec<_>>();
            for row in &frame.rows {
                rows[row.index as usize] = Some(row.clone());
            }
            next.rows = rows
                .into_iter()
                .collect::<Option<Vec<_>>>()
                .ok_or(RecordingError::InvalidFrame("unpopulated row after shift"))?;
            links.extend(frame.hyperlinks.clone());
            next.hyperlinks = links;
        }
        next.hyperlinks.sort_by(|a, b| {
            (a.row, a.start_col, a.end_col, &a.uri, &a.protocol_id).cmp(&(
                b.row,
                b.start_col,
                b.end_col,
                &b.uri,
                &b.protocol_id,
            ))
        });
        next.frame_kind = TerminalFrameKind::Snapshot as i32;
        next.viewport_row_shift = 0;
        next.dirty_ranges.clear();
        if next.encoded_len() > MAX_SCREEN_BYTES {
            return Err(RecordingError::InvalidFrame(
                "materialized screen exceeds byte limit",
            ));
        }
        self.screen = Some(next);
        Ok(())
    }
}

fn shifted_index(index: u32, shift: i32, height: u32) -> Option<u32> {
    let next = i64::from(index) + i64::from(shift);
    (next >= 0 && next < i64::from(height)).then_some(next as u32)
}

fn validate(frame: &TerminalFrameDiff) -> Result<(), RecordingError> {
    let reject = |reason| Err(RecordingError::InvalidFrame(reason));
    if frame.frame_schema_version != TERMINAL_FRAME_SCHEMA_VERSION {
        return reject("unsupported frame schema");
    }
    if !matches!(
        TerminalFrameKind::try_from(frame.frame_kind),
        Ok(TerminalFrameKind::Snapshot | TerminalFrameKind::Delta)
    ) {
        return reject("unknown frame kind");
    }
    if frame.viewport_rows == 0
        || frame.viewport_cols == 0
        || frame.viewport_rows > MAX_SCREEN_DIMENSION
        || frame.viewport_cols > MAX_SCREEN_DIMENSION
        || u64::from(frame.viewport_rows) * u64::from(frame.viewport_cols) > MAX_SCREEN_CELLS
        || frame.encoded_len() > MAX_SCREEN_BYTES
    {
        return reject("screen exceeds size limit");
    }
    if frame.cursor.is_none() || frame.modes.is_none() {
        return reject("missing cursor or modes");
    }
    let mut seen = vec![false; frame.viewport_rows as usize];
    for row in &frame.rows {
        if row.index >= frame.viewport_rows || seen[row.index as usize] {
            return reject("duplicate or out-of-range row");
        }
        seen[row.index as usize] = true;
        if row
            .style_runs
            .iter()
            .any(|style| style.end < style.start || style.end > frame.viewport_cols)
        {
            return reject("invalid style span");
        }
    }
    for link in &frame.hyperlinks {
        if link.row >= frame.viewport_rows
            || !seen[link.row as usize]
            || link.start_col > link.end_col
            || link.end_col > frame.viewport_cols
        {
            return reject("invalid hyperlink span");
        }
    }
    Ok(())
}
