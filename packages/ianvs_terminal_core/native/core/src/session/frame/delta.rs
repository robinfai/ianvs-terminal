use super::super::{cached_row_state_for, extract_viewport_row};
use super::damage::{delta_candidate_row_indexes, merge_dirty_ranges, shift_cached_rows};
use super::{BuiltFrameRows, CachedRowState, FrameBuildContext, PendingFrameWork};

pub(in crate::session) struct DeltaFrameContext<'frame, 'terminal> {
    pub(in crate::session) build: &'frame FrameBuildContext<'terminal>,
    pub(in crate::session) pending_frame_work: &'frame PendingFrameWork,
    pub(in crate::session) previous_rows: &'frame [CachedRowState],
    pub(in crate::session) viewport_row_shift: i32,
}

pub(in crate::session) fn build_delta_frame(context: DeltaFrameContext<'_, '_>) -> BuiltFrameRows {
    let DeltaFrameContext {
        build,
        pending_frame_work,
        previous_rows,
        viewport_row_shift,
    } = context;
    let candidate_row_indexes = delta_candidate_row_indexes(
        pending_frame_work,
        build.viewport_rows,
        build.viewport_start_row,
        build.scrollback_len,
        build.alt_screen_active,
        viewport_row_shift,
    );
    let mut next_rows = shift_cached_rows(previous_rows, build.viewport_rows, viewport_row_shift);
    let mut dirty_row_indexes = Vec::new();
    let mut rows = Vec::new();
    let mut hyperlinks = Vec::new();

    for row_index in &candidate_row_indexes {
        let extracted = extract_viewport_row(
            build.terminal,
            build.emulation,
            build.viewport_start_row,
            *row_index,
        );
        let row_state = cached_row_state_for(&extracted);
        if next_rows.get(*row_index) != Some(&row_state) {
            dirty_row_indexes.push(*row_index);
            hyperlinks.extend(extracted.hyperlinks.clone());
            rows.push(extracted.row);
        }
        next_rows[*row_index] = row_state;
    }

    let dirty_ranges = merge_dirty_ranges(&dirty_row_indexes);
    let rows_emitted = rows.len();

    (
        rows,
        hyperlinks,
        next_rows,
        dirty_ranges,
        candidate_row_indexes.len(),
        rows_emitted,
    )
}

#[cfg(test)]
mod tests {
    use super::super::{DisplayProjection, build_snapshot_frame, display_projection_for_terminal};
    use super::*;
    use crate::model::TerminalEmulation;
    use par_term_emu_core_rust::terminal::Terminal;
    use std::collections::BTreeSet;

    #[test]
    fn delta_emits_only_a_changed_candidate_row_and_updates_its_cache() {
        let mut terminal = Terminal::with_scrollback(12, 3, 16);
        terminal.process(b"one\r\ntwo");
        let before_projection = display_projection_for_terminal(&terminal);
        let before_context = frame_context(&terminal, &before_projection);
        let (_, _, previous_rows, _, _, _) = build_snapshot_frame(&before_context);

        terminal.process(b"\rTWO");
        let projection = display_projection_for_terminal(&terminal);
        let build = frame_context(&terminal, &projection);
        let pending_frame_work = PendingFrameWork {
            dirty_rows: BTreeSet::from([1]),
            ..PendingFrameWork::default()
        };

        let (rows, hyperlinks, next_rows, dirty_ranges, rows_scanned, rows_emitted) =
            build_delta_frame(DeltaFrameContext {
                build: &build,
                pending_frame_work: &pending_frame_work,
                previous_rows: &previous_rows,
                viewport_row_shift: 0,
            });

        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].index, 1);
        assert_eq!(rows[0].text.trim_end(), "TWO");
        assert!(hyperlinks.is_empty());
        assert_eq!(next_rows.len(), 3);
        assert_eq!(dirty_ranges.len(), 1);
        assert_eq!((dirty_ranges[0].start, dirty_ranges[0].end), (1, 2));
        assert_eq!((rows_scanned, rows_emitted), (1, 1));
    }

    #[test]
    fn unchanged_candidate_is_scanned_without_emitting_damage() {
        let mut terminal = Terminal::with_scrollback(12, 3, 16);
        terminal.process(b"one\r\ntwo");
        let projection = display_projection_for_terminal(&terminal);
        let build = frame_context(&terminal, &projection);
        let (_, _, previous_rows, _, _, _) = build_snapshot_frame(&build);
        let pending_frame_work = PendingFrameWork {
            dirty_rows: BTreeSet::from([1]),
            ..PendingFrameWork::default()
        };

        let (rows, hyperlinks, next_rows, dirty_ranges, rows_scanned, rows_emitted) =
            build_delta_frame(DeltaFrameContext {
                build: &build,
                pending_frame_work: &pending_frame_work,
                previous_rows: &previous_rows,
                viewport_row_shift: 0,
            });

        assert!(rows.is_empty());
        assert!(hyperlinks.is_empty());
        assert_eq!(next_rows, previous_rows);
        assert!(dirty_ranges.is_empty());
        assert_eq!((rows_scanned, rows_emitted), (1, 0));
    }

    fn frame_context<'a>(
        terminal: &'a Terminal,
        projection: &'a DisplayProjection,
    ) -> FrameBuildContext<'a> {
        FrameBuildContext {
            terminal,
            emulation: TerminalEmulation::Xterm256,
            display_projection: projection,
            viewport_start_row: 0,
            viewport_display_start_row: 0,
            viewport_rows: 3,
            viewport_cols: 12,
            scrollback_len: terminal.grid().scrollback_len(),
            alt_screen_active: false,
        }
    }
}
