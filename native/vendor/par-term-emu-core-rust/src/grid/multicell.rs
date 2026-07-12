//! Kitty OSC 66 multicell block helpers.

use crate::cell::{Cell, MultiCell};
use crate::grid::Grid;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct MultiCellRect {
    pub anchor_col: usize,
    /// Screen-relative row. Negative rows address the newest scrollback lines.
    pub anchor_row: isize,
    pub width: usize,
    pub height: usize,
    pub metadata: MultiCell,
}

impl Grid {
    pub(crate) fn has_multicells(&self) -> bool {
        self.screen_has_multicells
    }

    fn scrollback_physical_row(&self, logical_row: usize) -> Option<usize> {
        if logical_row >= self.scrollback_lines || self.max_scrollback == 0 {
            return None;
        }
        Some((self.scrollback_start + logical_row) % self.max_scrollback)
    }

    pub(crate) fn relative_row(&self, row: isize) -> Option<&[Cell]> {
        if row >= 0 {
            return self.row(row as usize);
        }
        let distance = row.unsigned_abs();
        if distance == 0 || distance > self.scrollback_lines {
            return None;
        }
        let logical_row = self.scrollback_lines - distance;
        let physical_row = self.scrollback_physical_row(logical_row)?;
        let start = physical_row.checked_mul(self.cols)?;
        self.scrollback_cells.get(start..start + self.cols)
    }

    fn relative_row_mut(&mut self, row: isize) -> Option<&mut [Cell]> {
        if row >= 0 {
            return self.row_mut(row as usize);
        }
        let distance = row.unsigned_abs();
        if distance == 0 || distance > self.scrollback_lines {
            return None;
        }
        let logical_row = self.scrollback_lines - distance;
        let physical_row = self.scrollback_physical_row(logical_row)?;
        let start = physical_row.checked_mul(self.cols)?;
        self.damage
            .mark_full_repaint("multicell_scrollback_changed");
        self.scrollback_cells.get_mut(start..start + self.cols)
    }

    pub(crate) fn multicell_rect_at(&self, col: usize, row: isize) -> Option<MultiCellRect> {
        let metadata = self.relative_row(row)?.get(col)?.multicell?;
        let anchor_col = col.checked_sub(metadata.x as usize)?;
        let anchor_row = row.checked_sub(metadata.y as isize)?;
        let width = metadata.block_width();
        let height = metadata.block_height();
        if width == 0 || height == 0 || anchor_col >= self.cols {
            return None;
        }
        Some(MultiCellRect {
            anchor_col,
            anchor_row,
            width,
            height,
            metadata,
        })
    }

    pub(crate) fn clear_multicell_at(&mut self, col: usize, row: isize) -> bool {
        let Some(rect) = self.multicell_rect_at(col, row) else {
            return false;
        };
        let blank = self.blank_cell();
        let mut changed = false;
        for block_y in 0..rect.height {
            let target_row = rect.anchor_row.saturating_add(block_y as isize);
            if let Some(row_cells) = self.relative_row_mut(target_row) {
                let end = rect
                    .anchor_col
                    .saturating_add(rect.width)
                    .min(row_cells.len());
                for cell in &mut row_cells[rect.anchor_col..end] {
                    if cell.multicell.is_some() {
                        *cell = blank.clone();
                        changed = true;
                    }
                }
            }
        }
        changed
    }

    pub(crate) fn clear_multicells_intersecting(
        &mut self,
        start_col: usize,
        end_col: usize,
        start_row: usize,
        end_row: usize,
    ) -> bool {
        let end_col = end_col.min(self.cols);
        let end_row = end_row.min(self.rows);
        if start_col >= end_col || start_row >= end_row {
            return false;
        }
        let mut anchors = Vec::new();
        for row in start_row..end_row {
            let Some(row_cells) = self.row(row) else {
                continue;
            };
            for (col, cell) in row_cells.iter().enumerate().take(end_col).skip(start_col) {
                if cell.multicell.is_none() {
                    continue;
                }
                if let Some(rect) = self.multicell_rect_at(col, row as isize) {
                    let anchor = (rect.anchor_col, rect.anchor_row);
                    if !anchors.contains(&anchor) {
                        anchors.push(anchor);
                    }
                }
            }
        }
        let mut changed = false;
        for (anchor_col, anchor_row) in anchors {
            changed |= self.clear_multicell_at(anchor_col, anchor_row);
        }
        changed
    }

    pub(crate) fn clear_multiline_multicells_from(&mut self, col: usize, row: usize) -> bool {
        if col >= self.cols || row >= self.rows {
            return false;
        }
        let anchors = self
            .row(row)
            .into_iter()
            .flat_map(|row_cells| row_cells.iter().enumerate().skip(col))
            .filter_map(|(cell_col, cell)| {
                let metadata = cell.multicell?;
                (metadata.scale > 1).then(|| {
                    (
                        cell_col.saturating_sub(metadata.x as usize),
                        row as isize - metadata.y as isize,
                    )
                })
            })
            .fold(Vec::new(), |mut anchors, anchor| {
                if !anchors.contains(&anchor) {
                    anchors.push(anchor);
                }
                anchors
            });
        let mut changed = false;
        for (anchor_col, anchor_row) in anchors {
            changed |= self.clear_multicell_at(anchor_col, anchor_row);
        }
        changed
    }

    pub(crate) fn clear_multicell_split_at_line(&mut self, row: usize) -> bool {
        if row >= self.rows {
            return false;
        }
        let anchors = self
            .row(row)
            .into_iter()
            .flat_map(|row_cells| row_cells.iter().enumerate())
            .filter_map(|(col, cell)| {
                let metadata = cell.multicell?;
                (metadata.y > 0).then(|| {
                    (
                        col.saturating_sub(metadata.x as usize),
                        row as isize - metadata.y as isize,
                    )
                })
            })
            .fold(Vec::new(), |mut anchors, anchor| {
                if !anchors.contains(&anchor) {
                    anchors.push(anchor);
                }
                anchors
            });
        let mut changed = false;
        for (anchor_col, anchor_row) in anchors {
            changed |= self.clear_multicell_at(anchor_col, anchor_row);
        }
        changed
    }

    pub(crate) fn append_multicell_text_at(
        &mut self,
        col: usize,
        row: isize,
        character: char,
    ) -> bool {
        let Some(rect) = self.multicell_rect_at(col, row) else {
            return false;
        };
        if rect.metadata.y > 0 {
            return false;
        }
        let Some(anchor) = self
            .relative_row_mut(rect.anchor_row)
            .and_then(|row_cells| row_cells.get_mut(rect.anchor_col))
        else {
            return false;
        };
        anchor.combining.push(character);
        for block_y in 0..rect.height {
            let target_row = rect.anchor_row + block_y as isize;
            if target_row >= 0 {
                self.damage.mark_row_dirty(target_row as usize);
            }
        }
        true
    }

    /// Remove blocks that no longer fit or whose cells were split by an edit.
    pub(crate) fn sanitize_multicell_fragments(&mut self) {
        if !self.multicells_may_exist {
            return;
        }
        let mut anchors = Vec::new();
        let mut invalid_cells = Vec::new();
        let first_row = -(self.scrollback_lines as isize);
        for row in first_row..self.rows as isize {
            let Some(row_cells) = self.relative_row(row) else {
                continue;
            };
            for (col, cell) in row_cells.iter().enumerate() {
                let Some(metadata) = cell.multicell else {
                    continue;
                };
                let Some(anchor_col) = col.checked_sub(metadata.x as usize) else {
                    invalid_cells.push((col, row));
                    continue;
                };
                let Some(anchor_row) = row.checked_sub(metadata.y as isize) else {
                    invalid_cells.push((col, row));
                    continue;
                };
                if !anchors.iter().any(|(existing_col, existing_row, _, _)| {
                    *existing_col == anchor_col && *existing_row == anchor_row
                }) {
                    anchors.push((anchor_col, anchor_row, col, row));
                }
            }
        }

        let blank = self.blank_cell.clone();
        for (col, row) in invalid_cells {
            if let Some(cell) = self
                .relative_row_mut(row)
                .and_then(|row_cells| row_cells.get_mut(col))
            {
                *cell = blank.clone();
            }
        }

        for (anchor_col, anchor_row, sample_col, sample_row) in anchors {
            let Some(rect) = self.multicell_rect_at(anchor_col, anchor_row) else {
                let _ = self.clear_multicell_at(sample_col, sample_row);
                continue;
            };
            let fits = rect.anchor_row >= -(self.scrollback_lines as isize)
                && rect.anchor_row.saturating_add(rect.height as isize) <= self.rows as isize
                && rect.anchor_col.saturating_add(rect.width) <= self.cols;
            let complete = fits
                && (0..rect.height).all(|block_y| {
                    self.relative_row(rect.anchor_row + block_y as isize)
                        .is_some_and(|row_cells| {
                            (0..rect.width).all(|block_x| {
                                row_cells
                                    .get(rect.anchor_col + block_x)
                                    .and_then(|cell| cell.multicell)
                                    .is_some_and(|metadata| {
                                        metadata.width == rect.metadata.width
                                            && metadata.scale == rect.metadata.scale
                                            && metadata.subscale_n == rect.metadata.subscale_n
                                            && metadata.subscale_d == rect.metadata.subscale_d
                                            && metadata.vertical_align
                                                == rect.metadata.vertical_align
                                            && metadata.horizontal_align
                                                == rect.metadata.horizontal_align
                                            && metadata.natural_width == rect.metadata.natural_width
                                            && metadata.x as usize == block_x
                                            && metadata.y as usize == block_y
                                    })
                            })
                        })
                });
            if !complete {
                let _ = self.clear_multicell_at(anchor_col, anchor_row);
            }
        }
        self.screen_has_multicells = self.cells.iter().any(|cell| cell.multicell.is_some());
        self.multicells_may_exist = self.screen_has_multicells
            || self
                .scrollback_cells
                .iter()
                .any(|cell| cell.multicell.is_some());
    }
}
