//! Zone management for the terminal grid

use crate::grid::Grid;
use crate::zone::Zone;

/// Maximum number of retained semantic zones per grid.
///
/// This is independent of scrollback size because a process can emit complete
/// shell-integration cycles repeatedly without advancing a single row.
pub const MAX_SEMANTIC_ZONES: usize = 4096;
const ZONE_CAP_EVICTION_BATCH: usize = 256;

impl Grid {
    /// Cell moves cannot preserve the column ownership of a parent/child
    /// boundary. Discard affected portions instead of attributing moved child
    /// text to the parent. Ordinary full-screen upward scrolling preserves
    /// absolute row identity and does not call this invalidation path.
    pub(crate) fn invalidate_segmented_output_rows(&mut self, top: usize, bottom: usize) {
        if top > bottom || top >= self.rows {
            return;
        }
        let top = self.total_lines_scrolled.saturating_add(top);
        let bottom = self
            .total_lines_scrolled
            .saturating_add(bottom.min(self.rows - 1));
        let screen_end = self.total_lines_scrolled.saturating_add(self.rows);
        for zone in &mut self.zones {
            if zone.output_start.is_none() && !zone.suspended && zone.pending_child.is_none() {
                continue;
            }
            let previous = zone.output_slices.len();
            zone.output_slices.retain(|slice| {
                slice.end_row < top
                    || (slice.end_row == top && slice.end_col == 0)
                    || slice.start_row > bottom
            });
            zone.output_truncated |= previous != zone.output_slices.len();
            for (_, owned) in zone.output_boundary_rows.range_mut(top..=bottom) {
                zone.output_truncated |= owned.iter().any(|owned| *owned);
                owned.fill(false);
            }
            if let Some(pending) = &mut zone.pending_child {
                if (top..=bottom).contains(&pending.row) {
                    pending.overwritten = true;
                    pending.owned.fill(false);
                }
            }
            let active_start = zone
                .output_start
                .map_or(zone.abs_row_start, |start| start.0);
            let active_end = if zone.is_open() {
                zone.pending_child
                    .as_ref()
                    .map_or(screen_end, |pending| pending.row)
            } else {
                zone.abs_row_end
            };
            if !zone.suspended && active_start <= bottom && active_end >= top {
                zone.output_start = Some((bottom.saturating_add(1), 0));
                zone.output_truncated = true;
            }
        }
    }

    /// Get all semantic zones
    pub fn zones(&self) -> &[Zone] {
        &self.zones
    }

    /// Get all semantic zones mutably
    pub fn zones_mut(&mut self) -> &mut Vec<Zone> {
        &mut self.zones
    }

    /// Push a new zone
    pub fn push_zone(&mut self, zone: Zone) {
        self.make_room_for_zone();
        self.zones.push(zone);
    }

    /// Close the current zone at the given row
    pub fn close_current_zone(&mut self, abs_row: usize) {
        if let Some(zone) = self.zones.iter_mut().rfind(|zone| zone.is_open()) {
            zone.close(abs_row);
        }
    }

    /// Close a specific open zone by identifier.
    pub(crate) fn close_zone(&mut self, zone_id: usize, abs_row: usize) -> bool {
        let Some(zone) = self
            .zones
            .iter_mut()
            .rfind(|zone| zone.id == zone_id && zone.is_open())
        else {
            return false;
        };
        zone.close(abs_row);
        true
    }

    /// Get the zone containing the given global absolute row.
    pub fn zone_at(&self, abs_row: usize) -> Option<&Zone> {
        self.zones.iter().find(|z| z.contains_row(abs_row))
    }

    /// Evict closed zones whose entire range is before the retained floor.
    ///
    /// Open zones are retained and extended to the retained floor instead of
    /// being removed; their final end row is not known until `D` arrives.
    pub fn evict_zones(&mut self, floor: usize) {
        let (evicted, mut remaining): (Vec<_>, Vec<_>) = self
            .zones
            .drain(..)
            .partition(|zone| zone.is_closed() && zone.abs_row_end < floor);
        self.evicted_zones.extend(evicted);

        // Preserve global start coordinates so ZoneOpened and ZoneClosed use
        // the same immutable boundary. Text extraction maps that boundary to
        // the retained floor; only an open end is advanced to show that the
        // zone still spans retained output.
        for zone in &mut remaining {
            if zone.is_open() {
                zone.extend_to(floor);
            }
        }

        self.zones = remaining;
    }

    /// Invalidate all zones whose physical row mapping is no longer valid.
    pub(crate) fn invalidate_zones(&mut self) {
        self.evicted_zones.append(&mut self.zones);
    }

    /// Clear all zones
    pub fn clear_zones(&mut self) {
        self.zones.clear();
    }

    /// Drain evicted zones
    pub fn drain_evicted_zones(&mut self) -> Vec<Zone> {
        std::mem::take(&mut self.evicted_zones)
    }

    pub(crate) fn enforce_zone_capacity(&mut self) {
        while self.zones.len() > MAX_SEMANTIC_ZONES {
            self.make_room_for_zone();
        }
    }

    fn make_room_for_zone(&mut self) {
        if self.zones.len() < MAX_SEMANTIC_ZONES {
            return;
        }

        // Normal parser operation leaves a prefix of completed zones followed
        // by at most one active zone. Evict a small batch to avoid shifting the
        // Vec for every new marker once the cap is reached.
        let completed_prefix = self
            .zones
            .iter()
            .take_while(|zone| zone.is_closed())
            .count();
        if completed_prefix > 0 {
            let count = completed_prefix.min(ZONE_CAP_EVICTION_BATCH);
            self.evicted_zones.extend(self.zones.drain(..count));
            return;
        }

        // Malformed external snapshots may contain stale open zones. Prefer a
        // completed entry anywhere in the list, otherwise discard the oldest
        // stale open zone while always protecting the newest active zone.
        if let Some(index) = self.zones.iter().position(Zone::is_closed) {
            self.evicted_zones.push(self.zones.remove(index));
        } else if self.zones.len() > 1 {
            self.evicted_zones.push(self.zones.remove(0));
        }
    }
}
