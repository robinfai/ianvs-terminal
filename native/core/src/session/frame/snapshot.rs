use super::super::{
    ExtractedVisibleRow, cached_row_state_for, extract_fold_summary_row, extract_source_row,
    extract_viewport_row,
};
use super::{BuiltFrameRows, DisplayProjectionRow, FrameBuildContext};
use crate::model::{TerminalDirtyRange, TerminalRow};

pub(in crate::session) fn build_snapshot_frame(context: &FrameBuildContext<'_>) -> BuiltFrameRows {
    if context.display_projection.has_folds() {
        build_projected_snapshot_frame(context)
    } else {
        build_contiguous_snapshot_frame(context)
    }
}

fn build_contiguous_snapshot_frame(context: &FrameBuildContext<'_>) -> BuiltFrameRows {
    let mut rows = Vec::with_capacity(context.viewport_rows);
    let mut hyperlinks = Vec::new();
    let mut current_rows = Vec::with_capacity(context.viewport_rows);

    for row in 0..context.viewport_rows {
        let extracted = extract_viewport_row(
            context.terminal,
            context.emulation,
            context.viewport_start_row,
            row,
        );
        current_rows.push(cached_row_state_for(&extracted));
        hyperlinks.extend(extracted.hyperlinks.clone());
        rows.push(extracted.row);
    }

    let dirty_ranges = full_viewport_dirty_range(context.viewport_rows);
    (
        rows,
        hyperlinks,
        current_rows,
        dirty_ranges,
        context.viewport_rows,
        context.viewport_rows,
    )
}

fn build_projected_snapshot_frame(context: &FrameBuildContext<'_>) -> BuiltFrameRows {
    let mut rows = Vec::with_capacity(context.viewport_rows);
    let mut hyperlinks = Vec::new();
    let mut current_rows = Vec::with_capacity(context.viewport_rows);
    for viewport_row in 0..context.viewport_rows {
        let display_row = context
            .viewport_display_start_row
            .saturating_add(viewport_row);
        let extracted = match context.display_projection.rows.get(display_row) {
            Some(DisplayProjectionRow::Source(source_row)) => extract_source_row(
                context.terminal,
                context.emulation,
                *source_row,
                viewport_row,
            ),
            Some(DisplayProjectionRow::FoldSummary(range_index)) => extract_fold_summary_row(
                context.terminal,
                &context.display_projection.collapsed[*range_index],
                viewport_row,
                context.viewport_cols,
            ),
            None => ExtractedVisibleRow {
                row: TerminalRow {
                    index: viewport_row,
                    text: String::new(),
                    wrapped: false,
                    style_runs: Vec::new(),
                    source_row: None,
                    source_end_row: None,
                },
                continues_from_previous: false,
                hyperlinks: Vec::new(),
            },
        };
        current_rows.push(cached_row_state_for(&extracted));
        hyperlinks.extend(extracted.hyperlinks.clone());
        rows.push(extracted.row);
    }
    let dirty_ranges = full_viewport_dirty_range(context.viewport_rows);
    (
        rows,
        hyperlinks,
        current_rows,
        dirty_ranges,
        context.viewport_rows,
        context.viewport_rows,
    )
}

fn full_viewport_dirty_range(viewport_rows: usize) -> Vec<TerminalDirtyRange> {
    if viewport_rows == 0 {
        Vec::new()
    } else {
        vec![TerminalDirtyRange {
            start: 0,
            end: viewport_rows,
        }]
    }
}

#[cfg(test)]
mod tests {
    use super::super::display_projection_for_terminal;
    use super::*;
    use crate::model::TerminalEmulation;
    use par_term_emu_core_rust::terminal::Terminal;

    #[test]
    fn contiguous_snapshot_emits_and_caches_the_full_viewport() {
        let mut terminal = Terminal::with_scrollback(12, 3, 16);
        terminal.process(b"one\r\ntwo");
        let projection = display_projection_for_terminal(&terminal);
        let context = FrameBuildContext {
            terminal: &terminal,
            emulation: TerminalEmulation::Xterm256,
            display_projection: &projection,
            viewport_start_row: 0,
            viewport_display_start_row: 0,
            viewport_rows: 3,
            viewport_cols: 12,
            scrollback_len: 0,
            alt_screen_active: false,
        };

        let (rows, hyperlinks, cached_rows, dirty_ranges, rows_scanned, rows_emitted) =
            build_snapshot_frame(&context);

        assert_eq!(rows.len(), 3);
        assert_eq!(rows[0].text.trim_end(), "one");
        assert_eq!(rows[1].text.trim_end(), "two");
        assert_eq!(rows[0].text.chars().count(), 12);
        assert!(hyperlinks.is_empty());
        assert_eq!(cached_rows.len(), 3);
        assert_eq!(dirty_ranges.len(), 1);
        assert_eq!((dirty_ranges[0].start, dirty_ranges[0].end), (0, 3));
        assert_eq!((rows_scanned, rows_emitted), (3, 3));
    }

    #[test]
    fn zero_height_snapshot_has_no_rows_or_damage() {
        let terminal = Terminal::new(12, 1);
        let projection = display_projection_for_terminal(&terminal);
        let context = FrameBuildContext {
            terminal: &terminal,
            emulation: TerminalEmulation::Xterm256,
            display_projection: &projection,
            viewport_start_row: 0,
            viewport_display_start_row: 0,
            viewport_rows: 0,
            viewport_cols: 12,
            scrollback_len: 0,
            alt_screen_active: false,
        };

        let (rows, hyperlinks, cached_rows, dirty_ranges, rows_scanned, rows_emitted) =
            build_snapshot_frame(&context);

        assert!(rows.is_empty());
        assert!(hyperlinks.is_empty());
        assert!(cached_rows.is_empty());
        assert!(dirty_ranges.is_empty());
        assert_eq!((rows_scanned, rows_emitted), (0, 0));
    }
}
