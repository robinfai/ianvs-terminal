//! Terminal grid implementation
//!
//! Provides a 2D grid of cells with scrollback support, reflow capability,
//! and semantic zone tracking.

use crate::cell::Cell;
use crate::color::Color;
use crate::zone::Zone;
use std::ops::Range;

pub mod damage;
mod edit;
mod erase;
mod export;
mod rect;
mod scroll;
mod zone;

pub use damage::{GridDamage, ScrollRegionDamage};

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct GridScrollDebugStats {
    pub scroll_up_calls: u64,
    pub scroll_down_calls: u64,
    pub scroll_region_up_calls: u64,
    pub scroll_region_down_calls: u64,
    pub scroll_rows: u64,
    pub scrollback_push_lines: u64,
    pub scroll_micros: u64,
    pub scrollback_push_micros: u64,
}

/// A 2D grid of terminal cells
#[derive(Debug, Clone)]
pub struct Grid {
    /// Number of columns
    pub(crate) cols: usize,
    /// Number of rows
    pub(crate) rows: usize,
    /// The actual grid data (row-major order)
    pub(crate) cells: Vec<Cell>,
    /// Cell template used for implementation-created blank cells.
    pub(crate) blank_cell: Cell,
    /// Physical row backing logical row 0 in `cells`.
    pub(crate) screen_row_start: usize,
    /// Scrollback buffer (flat Vec, row-major order like main grid)
    pub(crate) scrollback_cells: Vec<Cell>,
    /// Index of oldest line in circular scrollback buffer
    pub(crate) scrollback_start: usize,
    /// Number of lines currently in scrollback
    pub(crate) scrollback_lines: usize,
    /// Maximum scrollback lines
    pub(crate) max_scrollback: usize,
    /// Track which lines are wrapped
    pub(crate) wrapped: Vec<bool>,
    /// Track wrapped state for scrollback lines
    pub(crate) scrollback_wrapped: Vec<bool>,
    /// Semantic zones tracking logical blocks (Prompt, Command, Output)
    pub(crate) zones: Vec<Zone>,
    /// Zones that were evicted from scrollback
    pub(crate) evicted_zones: Vec<Zone>,
    /// Total number of lines that have ever been scrolled into scrollback.
    pub(crate) total_lines_scrolled: usize,
    /// Incremental damage accumulated since the last drain.
    pub(crate) damage: GridDamage,
    /// Low-cost counters for scroll hot paths.
    pub(crate) scroll_debug_stats: GridScrollDebugStats,
}

impl Grid {
    /// Create a new grid with the specified dimensions
    pub fn new(cols: usize, rows: usize, max_scrollback: usize) -> Self {
        let blank_cell = Cell::default();
        let cells = vec![blank_cell.clone(); cols * rows];
        Self {
            cols,
            rows,
            cells,
            blank_cell,
            screen_row_start: 0,
            scrollback_cells: Vec::new(),
            scrollback_start: 0,
            scrollback_lines: 0,
            max_scrollback,
            wrapped: vec![false; rows],
            scrollback_wrapped: Vec::new(),
            zones: Vec::new(),
            evicted_zones: Vec::new(),
            total_lines_scrolled: 0,
            damage: GridDamage::default(),
            scroll_debug_stats: GridScrollDebugStats::default(),
        }
    }

    pub fn set_blank_style(&mut self, fg: Color, bg: Color) {
        self.blank_cell = Cell::with_colors(' ', fg, bg);
    }

    pub(crate) fn blank_cell(&self) -> Cell {
        self.blank_cell.clone()
    }

    /// Get the number of columns
    pub fn cols(&self) -> usize {
        self.cols
    }

    /// Get the number of rows
    pub fn rows(&self) -> usize {
        self.rows
    }

    pub(crate) fn physical_row(&self, row: usize) -> Option<usize> {
        if row < self.rows && self.rows > 0 {
            Some((self.screen_row_start + row) % self.rows)
        } else {
            None
        }
    }

    pub(crate) fn physical_row_range(&self, row: usize) -> Option<Range<usize>> {
        let physical_row = self.physical_row(row)?;
        let start = physical_row * self.cols;
        Some(start..start + self.cols)
    }

    pub(crate) fn normalize_screen_rows(&mut self) {
        if self.screen_row_start == 0 || self.rows == 0 {
            return;
        }

        let mut logical_cells = Vec::with_capacity(self.cells.len());
        for row in 0..self.rows {
            if let Some(range) = self.physical_row_range(row) {
                logical_cells.extend_from_slice(&self.cells[range]);
            }
        }
        self.cells = logical_cells;
        self.screen_row_start = 0;
    }

    fn logical_screen_cells(&self) -> Vec<Cell> {
        if self.screen_row_start == 0 || self.rows == 0 {
            return self.cells.clone();
        }

        let mut logical_cells = Vec::with_capacity(self.cells.len());
        for row in 0..self.rows {
            if let Some(range) = self.physical_row_range(row) {
                logical_cells.extend_from_slice(&self.cells[range]);
            }
        }
        logical_cells
    }

    /// Get a reference to a cell at (col, row)
    pub fn get(&self, col: usize, row: usize) -> Option<&Cell> {
        let range = self.physical_row_range(row)?;
        (col < self.cols).then(|| &self.cells[range.start + col])
    }

    /// Get a mutable reference to a cell at (col, row)
    pub fn get_mut(&mut self, col: usize, row: usize) -> Option<&mut Cell> {
        let range = self.physical_row_range(row)?;
        if col >= self.cols {
            return None;
        }
        self.damage.mark_row_dirty(row);
        Some(&mut self.cells[range.start + col])
    }

    /// Set a cell at (col, row)
    pub fn set(&mut self, col: usize, row: usize, cell: Cell) {
        if let Some(c) = self.get_mut(col, row) {
            *c = cell;
        }
    }

    /// Get a row as a slice
    pub fn row(&self, row: usize) -> Option<&[Cell]> {
        let range = self.physical_row_range(row)?;
        Some(&self.cells[range])
    }

    /// Get a mutable row
    pub fn row_mut(&mut self, row: usize) -> Option<&mut [Cell]> {
        let range = self.physical_row_range(row)?;
        self.damage.mark_row_dirty(row);
        Some(&mut self.cells[range])
    }

    pub(crate) fn wide_safe_range(
        &self,
        col: usize,
        row: usize,
        width: usize,
    ) -> Option<Range<usize>> {
        if row >= self.rows || col >= self.cols || width == 0 {
            return None;
        }
        let row_cells = self.row(row)?;
        let mut start = col;
        let mut end = col.saturating_add(width).min(self.cols);
        if start >= end {
            return None;
        }

        if start > 0
            && row_cells[start].flags.wide_char_spacer()
            && row_cells[start - 1].flags.wide_char()
        {
            start -= 1;
        }
        if end < self.cols
            && row_cells[end - 1].flags.wide_char()
            && row_cells[end].flags.wide_char_spacer()
        {
            end += 1;
        }
        Some(start..end)
    }

    pub(crate) fn clear_wide_char_at_insertion_boundary(&mut self, col: usize, row: usize) {
        if row >= self.rows || col == 0 || col >= self.cols {
            return;
        }
        let blank_cell = self.blank_cell();
        if let Some(row_cells) = self.row_mut(row) {
            if row_cells[col].flags.wide_char_spacer() && row_cells[col - 1].flags.wide_char() {
                row_cells[col - 1] = blank_cell.clone();
                row_cells[col] = blank_cell;
            }
        }
    }

    pub(crate) fn sanitize_wide_char_fragments(&mut self, row: usize) {
        if row >= self.rows {
            return;
        }
        let blank_cell = self.blank_cell();
        let cols = self.cols;
        if let Some(row_cells) = self.row_mut(row) {
            let mut clear_cols = Vec::new();
            for col in 0..cols {
                if row_cells[col].flags.wide_char_spacer() {
                    let paired_with_lead = col > 0 && row_cells[col - 1].flags.wide_char();
                    if !paired_with_lead {
                        clear_cols.push(col);
                    }
                } else if row_cells[col].flags.wide_char() {
                    let paired_with_spacer =
                        col + 1 < cols && row_cells[col + 1].flags.wide_char_spacer();
                    if !paired_with_spacer {
                        clear_cols.push(col);
                    }
                }
            }
            for col in clear_cols {
                row_cells[col] = blank_cell.clone();
            }
        }
    }

    /// Get the text content of a row
    pub fn row_text(&self, row: usize) -> String {
        if let Some(cells) = self.row(row) {
            cells
                .iter()
                .filter(|cell| !cell.flags.wide_char_spacer())
                .map(|cell| cell.get_grapheme())
                .collect::<Vec<String>>()
                .join("")
        } else {
            String::new()
        }
    }

    /// Get total number of lines currently in scrollback
    pub fn scrollback_len(&self) -> usize {
        self.scrollback_lines
    }

    /// Get total number of lines that have ever been scrolled
    pub fn total_lines_scrolled(&self) -> usize {
        self.total_lines_scrolled
    }

    /// Get maximum scrollback capacity
    pub fn max_scrollback(&self) -> usize {
        self.max_scrollback
    }

    /// Check if a line is wrapped
    pub fn is_line_wrapped(&self, row: usize) -> bool {
        self.wrapped.get(row).copied().unwrap_or(false)
    }

    /// Set wrapped state for a line
    pub fn set_line_wrapped(&mut self, row: usize, wrapped: bool) {
        if let Some(w) = self.wrapped.get_mut(row) {
            *w = wrapped;
            self.damage.mark_row_dirty(row);
        }
    }

    pub fn drain_damage(&mut self) -> GridDamage {
        std::mem::take(&mut self.damage)
    }

    pub fn take_scroll_debug_stats(&mut self) -> GridScrollDebugStats {
        std::mem::take(&mut self.scroll_debug_stats)
    }

    /// Get a line from scrollback by index
    pub fn scrollback_line(&self, index: usize) -> Option<&[Cell]> {
        if index < self.scrollback_lines {
            let physical_index = (self.scrollback_start + index) % self.max_scrollback;
            let start = physical_index * self.cols;
            let end = start + self.cols;
            Some(&self.scrollback_cells[start..end])
        } else {
            None
        }
    }

    /// Check if a scrollback line is wrapped
    pub fn is_scrollback_wrapped(&self, index: usize) -> bool {
        if index < self.scrollback_lines {
            let physical_index = (self.scrollback_start + index) % self.max_scrollback;
            self.scrollback_wrapped
                .get(physical_index)
                .copied()
                .unwrap_or(false)
        } else {
            false
        }
    }

    /// Capture a snapshot of this grid's entire state.
    #[must_use]
    pub fn capture_snapshot(&self) -> crate::terminal::terminal_snapshot::GridSnapshot {
        crate::terminal::terminal_snapshot::GridSnapshot {
            cells: self.logical_screen_cells(),
            scrollback_cells: self.scrollback_cells.clone(),
            scrollback_start: self.scrollback_start,
            scrollback_lines: self.scrollback_lines,
            max_scrollback: self.max_scrollback,
            cols: self.cols,
            rows: self.rows,
            wrapped: self.wrapped.clone(),
            scrollback_wrapped: self.scrollback_wrapped.clone(),
            zones: self.zones.clone(),
            total_lines_scrolled: self.total_lines_scrolled,
        }
    }

    /// Restore this grid's state from a previously captured snapshot.
    pub fn restore_from_snapshot(
        &mut self,
        snap: &crate::terminal::terminal_snapshot::GridSnapshot,
    ) {
        self.cells = snap.cells.clone();
        self.screen_row_start = 0;
        self.scrollback_cells = snap.scrollback_cells.clone();
        self.scrollback_start = snap.scrollback_start;
        self.scrollback_lines = snap.scrollback_lines;
        self.max_scrollback = snap.max_scrollback;
        self.cols = snap.cols;
        self.rows = snap.rows;
        self.wrapped = snap.wrapped.clone();
        self.scrollback_wrapped = snap.scrollback_wrapped.clone();
        self.zones = snap.zones.clone();
        self.evicted_zones.clear();
        self.total_lines_scrolled = snap.total_lines_scrolled;
        self.damage = GridDamage::default();
        self.scroll_debug_stats = GridScrollDebugStats::default();
    }
}

#[cfg(test)]
mod tests;
