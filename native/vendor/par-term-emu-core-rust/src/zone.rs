//! Semantic buffer zones for tracking logical blocks in terminal output
//!
//! Zones segment the scrollback buffer into Prompt, Command, and Output
//! blocks using FinalTerm/OSC 133 shell integration markers.

/// Type of semantic zone in the terminal buffer
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ZoneType {
    /// Shell prompt text (between OSC 133;A and OSC 133;B)
    Prompt,
    /// Command input text (between OSC 133;B and OSC 133;C)
    Command,
    /// Command output text (between OSC 133;C and OSC 133;D)
    Output,
}

impl std::fmt::Display for ZoneType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ZoneType::Prompt => write!(f, "prompt"),
            ZoneType::Command => write!(f, "command"),
            ZoneType::Output => write!(f, "output"),
        }
    }
}

/// One continuous portion of command output, ending before a child shell.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ZoneOutputSlice {
    pub start_row: usize,
    pub start_col: usize,
    pub end_row: usize,
    pub end_col: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct PendingChildBoundary {
    pub row: usize,
    pub col: usize,
    pub owned: Vec<bool>,
    pub overwritten: bool,
    pub temporary_row: bool,
}

/// A semantic zone in the terminal buffer.
///
/// Zones use global absolute row numbers and are stored in start order on the
/// grid. A parent command can contain disjoint output portions around a child.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Zone {
    /// Unique zone identifier (monotonically increasing per terminal)
    pub id: usize,
    /// Type of this zone
    pub zone_type: ZoneType,
    /// Global absolute row where this zone starts.
    ///
    /// This is `total_lines_scrolled + cursor.row` at creation, so the value
    /// remains monotonic even after the bounded scrollback ring evicts rows.
    pub abs_row_start: usize,
    /// Absolute row where this zone ends (inclusive). Updated as zone grows.
    /// Equal to abs_row_start when zone is first created; updated when zone is closed.
    pub abs_row_end: usize,
    /// Whether the zone has received its closing shell-integration marker.
    ///
    /// Open zones are retained while scrollback advances so a long-running
    /// command cannot lose its output zone before the final `D` marker.
    pub closed: bool,
    /// Command text (from OSC 133;B parameter), set on Command and Output zones
    pub command: Option<String>,
    /// Exit code (from OSC 133;D parameter), set on Output zones when command finishes
    pub exit_code: Option<i32>,
    /// Timestamp in Unix milliseconds when this zone was created
    pub timestamp: Option<u64>,
    /// Cell boundaries used by command-block copy. The end column is exclusive.
    pub start_col: usize,
    pub end_col: Option<usize>,
    /// Execution context captured at the boundary, rather than the current cwd.
    pub cwd: Option<String>,
    pub finished_at: Option<u64>,
    /// Shell-provided provenance; never grants input permission by itself.
    pub submission_id: Option<String>,
    pub context_id: Option<String>,
    /// Completed portions of a command interrupted by an interactive child.
    /// Child prompts/output are not part of its parent's output.
    pub output_slices: Vec<ZoneOutputSlice>,
    pub output_start: Option<(usize, usize)>,
    pub suspended: bool,
    pub output_truncated: bool,
    /// Ownership on rows shared with a child. A CR may leave child cells to
    /// the right of the parent's new cursor; range endpoints alone are not
    /// sufficient to distinguish those cells from the parent's own output.
    pub output_boundary_rows: std::collections::BTreeMap<usize, Vec<bool>>,
    pub(crate) pending_child: Option<PendingChildBoundary>,
}

impl Zone {
    /// Create a new zone starting at the given absolute row
    pub fn new(id: usize, zone_type: ZoneType, abs_row: usize, timestamp: Option<u64>) -> Self {
        Self {
            id,
            zone_type,
            abs_row_start: abs_row,
            abs_row_end: abs_row,
            closed: false,
            command: None,
            exit_code: None,
            timestamp,
            start_col: 0,
            end_col: None,
            cwd: None,
            finished_at: None,
            submission_id: None,
            context_id: None,
            output_slices: Vec::new(),
            output_start: None,
            suspended: false,
            output_truncated: false,
            output_boundary_rows: std::collections::BTreeMap::new(),
            pending_child: None,
        }
    }

    /// Close this zone at the given absolute row
    pub fn close(&mut self, abs_row: usize) {
        self.abs_row_end = abs_row.max(self.abs_row_start);
        self.closed = true;
    }

    /// Extend the retained range of an open zone without closing it.
    pub(crate) fn extend_to(&mut self, abs_row: usize) {
        self.abs_row_end = self.abs_row_end.max(abs_row).max(self.abs_row_start);
    }

    /// Whether this zone is still awaiting its closing marker.
    pub fn is_open(&self) -> bool {
        !self.closed
    }

    /// Whether this zone has received its closing marker.
    pub fn is_closed(&self) -> bool {
        self.closed
    }

    /// Check if a given absolute row falls within this zone
    pub fn contains_row(&self, abs_row: usize) -> bool {
        if self.suspended || self.output_start.is_some() {
            return self.output_slices.iter().any(|slice| {
                abs_row >= slice.start_row
                    && (abs_row < slice.end_row || abs_row == slice.end_row && slice.end_col > 0)
            }) || (!self.suspended
                && abs_row
                    >= self
                        .output_start
                        .unwrap_or((self.abs_row_start, self.start_col))
                        .0
                && (self.is_open() || abs_row <= self.abs_row_end));
        }
        abs_row >= self.abs_row_start && (self.is_open() || abs_row <= self.abs_row_end)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_zone_new() {
        let zone = Zone::new(0, ZoneType::Prompt, 10, Some(1000));
        assert_eq!(zone.id, 0);
        assert_eq!(zone.zone_type, ZoneType::Prompt);
        assert_eq!(zone.abs_row_start, 10);
        assert_eq!(zone.abs_row_end, 10);
        assert!(zone.is_open());
        assert!(zone.command.is_none());
        assert!(zone.exit_code.is_none());
        assert_eq!(zone.timestamp, Some(1000));
    }

    #[test]
    fn test_zone_close() {
        let mut zone = Zone::new(1, ZoneType::Output, 5, None);
        zone.close(15);
        assert_eq!(zone.abs_row_end, 15);
        assert!(zone.is_closed());
    }

    #[test]
    fn test_zone_close_same_row() {
        let mut zone = Zone::new(2, ZoneType::Prompt, 5, None);
        zone.close(5);
        assert_eq!(zone.abs_row_end, 5);
    }

    #[test]
    fn test_zone_close_clamps_to_start() {
        let mut zone = Zone::new(3, ZoneType::Command, 10, None);
        zone.close(3);
        assert_eq!(zone.abs_row_end, 10);
    }

    #[test]
    fn test_zone_contains_row() {
        let mut zone = Zone::new(4, ZoneType::Output, 5, None);
        assert!(zone.contains_row(50));
        zone.close(15);
        assert!(!zone.contains_row(4));
        assert!(zone.contains_row(5));
        assert!(zone.contains_row(10));
        assert!(zone.contains_row(15));
        assert!(!zone.contains_row(16));
    }

    #[test]
    fn test_zone_type_display() {
        assert_eq!(ZoneType::Prompt.to_string(), "prompt");
        assert_eq!(ZoneType::Command.to_string(), "command");
        assert_eq!(ZoneType::Output.to_string(), "output");
    }
}
