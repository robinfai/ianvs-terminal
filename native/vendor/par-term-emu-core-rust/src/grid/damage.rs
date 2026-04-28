use std::collections::BTreeSet;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ScrollRegionDamage {
    pub top: usize,
    pub bottom_exclusive: usize,
    pub delta_rows: i32,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct GridDamage {
    pub full_repaint: bool,
    pub dirty_rows: BTreeSet<usize>,
    pub scroll_region: Option<ScrollRegionDamage>,
    pub snapshot_fallback_reason: Option<String>,
}

impl GridDamage {
    pub fn mark_row_dirty(&mut self, row: usize) {
        if self.full_repaint {
            return;
        }
        self.dirty_rows.insert(row);
    }

    pub fn mark_rows_dirty(&mut self, start: usize, end_exclusive: usize) {
        if self.full_repaint || start >= end_exclusive {
            return;
        }
        for row in start..end_exclusive {
            self.dirty_rows.insert(row);
        }
    }

    pub fn record_scroll(&mut self, top: usize, bottom_exclusive: usize, delta_rows: i32) {
        if self.full_repaint || top >= bottom_exclusive || delta_rows == 0 {
            return;
        }

        let next = ScrollRegionDamage {
            top,
            bottom_exclusive,
            delta_rows,
        };

        match self.scroll_region.as_mut() {
            None => {
                self.scroll_region = Some(next);
            }
            Some(existing)
                if existing.top == next.top
                    && existing.bottom_exclusive == next.bottom_exclusive
                    && existing.delta_rows.signum() == next.delta_rows.signum() =>
            {
                existing.delta_rows = existing.delta_rows.saturating_add(next.delta_rows);
            }
            Some(_) => self.mark_full_repaint("conflicting_scroll_regions"),
        }
    }

    pub fn mark_full_repaint(&mut self, reason: &str) {
        self.full_repaint = true;
        self.dirty_rows.clear();
        self.scroll_region = None;
        if self.snapshot_fallback_reason.is_none() {
            self.snapshot_fallback_reason = Some(reason.to_string());
        }
    }
}
