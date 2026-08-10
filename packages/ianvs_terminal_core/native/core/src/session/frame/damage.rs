use crate::model::{TerminalCursor, TerminalDirtyRange, TerminalFrameModes};
use par_term_emu_core_rust::color::Color;
use par_term_emu_core_rust::grid::ScrollRegionDamage;
use par_term_emu_core_rust::terminal::TerminalDamage;
use std::collections::BTreeSet;

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub(in crate::session) struct CachedRowState {
    pub(in crate::session) text: String,
    pub(in crate::session) wrapped: bool,
    pub(in crate::session) continues_from_previous: bool,
    pub(in crate::session) style_signature: u64,
    pub(in crate::session) hyperlink_signature: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(in crate::session) struct CachedFrameMeta {
    pub(in crate::session) viewport_rows: usize,
    pub(in crate::session) viewport_cols: usize,
    pub(in crate::session) scrollback_offset: usize,
    pub(in crate::session) viewport_start_row: usize,
    pub(in crate::session) alt_screen_active: bool,
    pub(in crate::session) default_foreground_rgb: (u8, u8, u8),
    pub(in crate::session) default_background_rgb: (u8, u8, u8),
    pub(in crate::session) cursor_color_rgb: (u8, u8, u8),
    pub(in crate::session) cursor_guide_color_rgb: (u8, u8, u8),
    pub(in crate::session) selection_background_rgb: (u8, u8, u8),
    pub(in crate::session) selection_foreground_rgb: Option<(u8, u8, u8)>,
    pub(in crate::session) link_color_rgb: Option<(u8, u8, u8)>,
    pub(in crate::session) cursor_text_color_rgb: Option<(u8, u8, u8)>,
    pub(in crate::session) tab_color_rgb: Option<(u8, u8, u8)>,
    pub(in crate::session) pointer_shape: Option<String>,
    pub(in crate::session) ansi_palette: [Color; 256],
    pub(in crate::session) modes: TerminalFrameModes,
    pub(in crate::session) window_title: Option<String>,
    pub(in crate::session) window_icon_name: Option<String>,
    pub(in crate::session) font_family: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(in crate::session) struct PendingScrollRegion {
    pub(in crate::session) top: usize,
    pub(in crate::session) bottom_exclusive: usize,
    pub(in crate::session) delta_rows: i32,
}

impl From<ScrollRegionDamage> for PendingScrollRegion {
    fn from(value: ScrollRegionDamage) -> Self {
        Self {
            top: value.top,
            bottom_exclusive: value.bottom_exclusive,
            delta_rows: value.delta_rows,
        }
    }
}

#[derive(Clone, Debug, Default)]
pub(in crate::session) struct PendingFrameWork {
    pub(in crate::session) full_repaint: bool,
    pub(in crate::session) snapshot_fallback_reason: Option<String>,
    pub(in crate::session) dirty_rows: BTreeSet<usize>,
    pub(in crate::session) scroll_region: Option<PendingScrollRegion>,
    pub(in crate::session) cursor_before: Option<TerminalCursor>,
    pub(in crate::session) cursor_after: Option<TerminalCursor>,
    pub(in crate::session) damage_generation: u64,
}

impl PendingFrameWork {
    pub(in crate::session) fn is_empty(&self) -> bool {
        !self.full_repaint
            && self.snapshot_fallback_reason.is_none()
            && self.dirty_rows.is_empty()
            && self.scroll_region.is_none()
            && self.cursor_before.is_none()
            && self.cursor_after.is_none()
            && self.damage_generation == 0
    }

    pub(in crate::session) fn mark_full_repaint(&mut self, reason: &str) {
        self.full_repaint = true;
        self.dirty_rows.clear();
        self.scroll_region = None;
        self.bump_generation();
        if self.snapshot_fallback_reason.is_none() {
            self.snapshot_fallback_reason = Some(reason.to_string());
        }
    }

    pub(in crate::session) fn merge_terminal_damage(
        &mut self,
        damage: TerminalDamage,
        cursor_before: TerminalCursor,
        cursor_after: TerminalCursor,
    ) {
        self.bump_generation();
        if self.cursor_before.is_none() {
            self.cursor_before = Some(cursor_before);
        }
        self.cursor_after = Some(cursor_after);

        if damage.full_repaint {
            self.full_repaint = true;
            self.dirty_rows.clear();
            self.scroll_region = None;
            if self.snapshot_fallback_reason.is_none() {
                self.snapshot_fallback_reason = damage.snapshot_fallback_reason;
            }
            return;
        }

        self.dirty_rows.extend(damage.dirty_rows);
        if let Some(scroll_region) = damage.scroll_region {
            self.merge_scroll_region(scroll_region.into());
        }
    }

    fn merge_scroll_region(&mut self, scroll_region: PendingScrollRegion) {
        match self.scroll_region.as_mut() {
            None => {
                self.scroll_region = Some(scroll_region);
            }
            Some(existing)
                if existing.top == scroll_region.top
                    && existing.bottom_exclusive == scroll_region.bottom_exclusive
                    && existing.delta_rows.signum() == scroll_region.delta_rows.signum() =>
            {
                existing.delta_rows = existing.delta_rows.saturating_add(scroll_region.delta_rows);
            }
            Some(_) => self.mark_full_repaint("conflicting_scroll_regions"),
        }
    }

    fn bump_generation(&mut self) {
        self.damage_generation = self.damage_generation.saturating_add(1);
    }
}

pub(in crate::session) fn shift_cached_rows(
    previous_rows: &[CachedRowState],
    viewport_rows: usize,
    viewport_row_shift: i32,
) -> Vec<CachedRowState> {
    let mut shifted = vec![CachedRowState::default(); viewport_rows];
    for (row, shifted_row) in shifted.iter_mut().enumerate() {
        let previous_index = row as isize - viewport_row_shift as isize;
        let Some(previous_index) = usize::try_from(previous_index).ok() else {
            continue;
        };
        if let Some(previous_row) = previous_rows.get(previous_index) {
            *shifted_row = previous_row.clone();
        }
    }
    shifted
}

pub(in crate::session) fn delta_candidate_row_indexes(
    pending_frame_work: &PendingFrameWork,
    viewport_rows: usize,
    viewport_start_row: usize,
    scrollback_len: usize,
    alt_screen_active: bool,
    viewport_row_shift: i32,
) -> Vec<usize> {
    let mut candidates = BTreeSet::new();
    let uses_viewport_shift =
        pending_frame_work
            .scroll_region
            .as_ref()
            .is_some_and(|scroll_region| {
                viewport_row_shift != 0
                    && scroll_region_covers_full_active_screen(scroll_region, viewport_rows)
            });

    add_shift_exposed_rows(&mut candidates, viewport_rows, viewport_row_shift);
    for row in &pending_frame_work.dirty_rows {
        if let Some(visible_row) = visible_row_for_screen_row(
            *row,
            viewport_start_row,
            viewport_rows,
            scrollback_len,
            alt_screen_active,
        ) {
            candidates.insert(visible_row);
        }
        if uses_viewport_shift {
            let shifted_row = *row as isize + viewport_row_shift as isize;
            let Some(shifted_row) = usize::try_from(shifted_row).ok() else {
                continue;
            };
            if let Some(visible_row) = visible_row_for_screen_row(
                shifted_row,
                viewport_start_row,
                viewport_rows,
                scrollback_len,
                alt_screen_active,
            ) {
                candidates.insert(visible_row);
            }
        }
    }

    if let Some(scroll_region) = pending_frame_work.scroll_region.as_ref()
        && !uses_viewport_shift
    {
        add_visible_rows_for_scroll_region(
            &mut candidates,
            scroll_region,
            viewport_start_row,
            viewport_rows,
            scrollback_len,
            alt_screen_active,
        );
    }

    add_visible_cursor_row(
        &mut candidates,
        pending_frame_work.cursor_before.as_ref(),
        viewport_start_row,
        viewport_rows,
        scrollback_len,
        alt_screen_active,
    );
    add_visible_cursor_row(
        &mut candidates,
        pending_frame_work.cursor_after.as_ref(),
        viewport_start_row,
        viewport_rows,
        scrollback_len,
        alt_screen_active,
    );

    candidates.into_iter().collect()
}

fn add_shift_exposed_rows(
    candidates: &mut BTreeSet<usize>,
    viewport_rows: usize,
    viewport_row_shift: i32,
) {
    if viewport_row_shift == 0 || viewport_rows == 0 {
        return;
    }

    let shift = viewport_row_shift.unsigned_abs() as usize;
    if viewport_row_shift < 0 {
        let start = viewport_rows.saturating_sub(shift);
        for row in start..viewport_rows {
            candidates.insert(row);
        }
        return;
    }

    for row in 0..shift.min(viewport_rows) {
        candidates.insert(row);
    }
}

fn add_visible_rows_for_scroll_region(
    candidates: &mut BTreeSet<usize>,
    scroll_region: &PendingScrollRegion,
    viewport_start_row: usize,
    viewport_rows: usize,
    scrollback_len: usize,
    alt_screen_active: bool,
) {
    if viewport_rows == 0 || scroll_region.top >= scroll_region.bottom_exclusive {
        return;
    }

    if alt_screen_active {
        let start = scroll_region.top.min(viewport_rows);
        let end = scroll_region.bottom_exclusive.min(viewport_rows);
        for row in start..end {
            candidates.insert(row);
        }
        return;
    }

    let region_start = scrollback_len.saturating_add(scroll_region.top);
    let region_end = scrollback_len.saturating_add(scroll_region.bottom_exclusive);
    let viewport_end = viewport_start_row.saturating_add(viewport_rows);
    let visible_start = region_start.max(viewport_start_row);
    let visible_end = region_end.min(viewport_end);
    for absolute_row in visible_start..visible_end {
        candidates.insert(absolute_row.saturating_sub(viewport_start_row));
    }
}

fn add_visible_cursor_row(
    candidates: &mut BTreeSet<usize>,
    cursor: Option<&TerminalCursor>,
    viewport_start_row: usize,
    viewport_rows: usize,
    scrollback_len: usize,
    alt_screen_active: bool,
) {
    let Some(cursor) = cursor else {
        return;
    };

    if let Some(visible_row) = visible_row_for_screen_row(
        cursor.row,
        viewport_start_row,
        viewport_rows,
        scrollback_len,
        alt_screen_active,
    ) {
        candidates.insert(visible_row);
    }
}

fn visible_row_for_screen_row(
    screen_row: usize,
    viewport_start_row: usize,
    viewport_rows: usize,
    scrollback_len: usize,
    alt_screen_active: bool,
) -> Option<usize> {
    if alt_screen_active {
        return (screen_row < viewport_rows).then_some(screen_row);
    }

    let absolute_row = scrollback_len.saturating_add(screen_row);
    let viewport_end = viewport_start_row.saturating_add(viewport_rows);
    if absolute_row < viewport_start_row || absolute_row >= viewport_end {
        return None;
    }
    Some(absolute_row.saturating_sub(viewport_start_row))
}

fn scroll_region_covers_full_active_screen(
    scroll_region: &PendingScrollRegion,
    viewport_rows: usize,
) -> bool {
    scroll_region.top == 0 && scroll_region.bottom_exclusive >= viewport_rows
}

fn viewport_row_shift_for(
    previous_frame_meta: Option<&CachedFrameMeta>,
    viewport_start_row: usize,
    frame_meta: &CachedFrameMeta,
) -> i32 {
    let Some(previous_frame_meta) = previous_frame_meta else {
        return 0;
    };
    if !frame_meta_is_delta_compatible(Some(previous_frame_meta), frame_meta) {
        return 0;
    }
    let row_shift = previous_frame_meta.viewport_start_row as i64 - viewport_start_row as i64;
    row_shift.clamp(i32::MIN as i64, i32::MAX as i64) as i32
}

pub(in crate::session) fn resolve_viewport_row_shift(
    previous_frame_meta: Option<&CachedFrameMeta>,
    viewport_start_row: usize,
    frame_meta: &CachedFrameMeta,
    scroll_region: Option<&PendingScrollRegion>,
) -> i32 {
    let frame_meta_shift =
        viewport_row_shift_for(previous_frame_meta, viewport_start_row, frame_meta);
    if frame_meta_shift != 0 {
        return frame_meta_shift;
    }

    let Some(scroll_region) = scroll_region else {
        return 0;
    };
    if !scroll_region_covers_full_active_screen(scroll_region, frame_meta.viewport_rows) {
        return 0;
    }
    scroll_region.delta_rows.clamp(
        -(frame_meta.viewport_rows as i32),
        frame_meta.viewport_rows as i32,
    )
}

pub(in crate::session) fn snapshot_fallback_reason(
    pending_frame_work: &PendingFrameWork,
    previous_rows: &[CachedRowState],
    previous_frame_meta: Option<&CachedFrameMeta>,
    frame_meta: &CachedFrameMeta,
) -> Option<String> {
    if pending_frame_work.full_repaint {
        return Some(
            pending_frame_work
                .snapshot_fallback_reason
                .clone()
                .unwrap_or_else(|| "pending_full_repaint".to_string()),
        );
    }
    if previous_rows.is_empty() {
        return Some("no_previous_frame".to_string());
    }
    if previous_rows.len() != frame_meta.viewport_rows {
        return Some("viewport_row_count_changed".to_string());
    }
    frame_meta_delta_break_reason(previous_frame_meta, frame_meta).map(str::to_string)
}

fn frame_meta_delta_break_reason(
    previous_frame_meta: Option<&CachedFrameMeta>,
    frame_meta: &CachedFrameMeta,
) -> Option<&'static str> {
    let previous_frame_meta = previous_frame_meta?;
    if previous_frame_meta.viewport_rows != frame_meta.viewport_rows
        || previous_frame_meta.viewport_cols != frame_meta.viewport_cols
    {
        return Some("viewport_metrics_changed");
    }
    if previous_frame_meta.scrollback_offset != frame_meta.scrollback_offset {
        return Some("scrollback_offset_changed");
    }
    if previous_frame_meta.alt_screen_active != frame_meta.alt_screen_active {
        return Some("alternate_screen_changed");
    }
    if previous_frame_meta.default_foreground_rgb != frame_meta.default_foreground_rgb
        || previous_frame_meta.default_background_rgb != frame_meta.default_background_rgb
    {
        return Some("terminal_default_colors_changed");
    }
    if previous_frame_meta.cursor_color_rgb != frame_meta.cursor_color_rgb {
        return Some("terminal_cursor_color_changed");
    }
    if previous_frame_meta.selection_background_rgb != frame_meta.selection_background_rgb
        || previous_frame_meta.selection_foreground_rgb != frame_meta.selection_foreground_rgb
    {
        return Some("terminal_selection_colors_changed");
    }
    if previous_frame_meta.link_color_rgb != frame_meta.link_color_rgb
        || previous_frame_meta.cursor_text_color_rgb != frame_meta.cursor_text_color_rgb
        || previous_frame_meta.tab_color_rgb != frame_meta.tab_color_rgb
    {
        return Some("terminal_iterm_colors_changed");
    }
    if previous_frame_meta.pointer_shape != frame_meta.pointer_shape {
        return Some("terminal_pointer_shape_changed");
    }
    if previous_frame_meta.ansi_palette != frame_meta.ansi_palette {
        return Some("terminal_palette_changed");
    }
    if previous_frame_meta.modes != frame_meta.modes {
        return Some("terminal_modes_changed");
    }
    if previous_frame_meta.window_title != frame_meta.window_title {
        return Some("window_title_changed");
    }
    if previous_frame_meta.window_icon_name != frame_meta.window_icon_name {
        return Some("window_icon_name_changed");
    }
    if previous_frame_meta.font_family != frame_meta.font_family {
        return Some("terminal_font_changed");
    }
    None
}

fn frame_meta_is_delta_compatible(
    previous_frame_meta: Option<&CachedFrameMeta>,
    frame_meta: &CachedFrameMeta,
) -> bool {
    frame_meta_delta_break_reason(previous_frame_meta, frame_meta).is_none()
}

pub(in crate::session) fn merge_dirty_ranges(
    dirty_row_indexes: &[usize],
) -> Vec<TerminalDirtyRange> {
    let mut ranges = Vec::new();
    let Some((&first, rest)) = dirty_row_indexes.split_first() else {
        return ranges;
    };
    let mut start = first;
    let mut end = first + 1;
    for index in rest {
        if *index == end {
            end += 1;
            continue;
        }
        ranges.push(TerminalDirtyRange { start, end });
        start = *index;
        end = *index + 1;
    }
    ranges.push(TerminalDirtyRange { start, end });
    ranges
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frame_meta(viewport_start_row: usize) -> CachedFrameMeta {
        CachedFrameMeta {
            viewport_rows: 5,
            viewport_cols: 80,
            scrollback_offset: 0,
            viewport_start_row,
            alt_screen_active: false,
            default_foreground_rgb: (255, 255, 255),
            default_background_rgb: (0, 0, 0),
            cursor_color_rgb: (255, 255, 255),
            cursor_guide_color_rgb: (255, 255, 255),
            selection_background_rgb: (64, 64, 64),
            selection_foreground_rgb: None,
            link_color_rgb: None,
            cursor_text_color_rgb: None,
            tab_color_rgb: None,
            pointer_shape: None,
            ansi_palette: [Color::Rgb(0, 0, 0); 256],
            modes: TerminalFrameModes::default(),
            window_title: None,
            window_icon_name: None,
            font_family: Some("monospace".to_string()),
        }
    }

    #[test]
    fn snapshot_fallback_preserves_the_first_full_repaint_reason() {
        let mut pending = PendingFrameWork::default();
        pending.mark_full_repaint("clear_screen");
        pending.mark_full_repaint("later_damage");

        assert_eq!(
            snapshot_fallback_reason(&pending, &[], None, &frame_meta(0)).as_deref(),
            Some("clear_screen")
        );
    }

    #[test]
    fn compatible_frame_metadata_preserves_viewport_row_shift() {
        let previous = frame_meta(12);
        let current = frame_meta(10);

        assert_eq!(
            resolve_viewport_row_shift(Some(&previous), 10, &current, None),
            2
        );
    }

    #[test]
    fn incompatible_frame_metadata_forces_snapshot_and_zero_shift() {
        let previous = frame_meta(12);
        let mut current = frame_meta(10);
        current.viewport_cols = 100;

        assert_eq!(
            snapshot_fallback_reason(
                &PendingFrameWork::default(),
                &vec![CachedRowState::default(); 5],
                Some(&previous),
                &current,
            )
            .as_deref(),
            Some("viewport_metrics_changed")
        );
        assert_eq!(
            resolve_viewport_row_shift(Some(&previous), 10, &current, None),
            0
        );
    }

    #[test]
    fn dirty_rows_merge_into_stable_half_open_ranges() {
        assert_eq!(
            merge_dirty_ranges(&[0, 1, 3, 4, 7])
                .into_iter()
                .map(|range| (range.start, range.end))
                .collect::<Vec<_>>(),
            vec![(0, 2), (3, 5), (7, 8)]
        );
    }
}
