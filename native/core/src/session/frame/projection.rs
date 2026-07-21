use par_term_emu_core_rust::terminal::Terminal;

#[derive(Clone, Debug)]
pub(in crate::session) enum DisplayProjectionRow {
    Source(usize),
    FoldSummary(usize),
}

#[derive(Clone, Debug)]
pub(in crate::session) struct CollapsedBlockRange {
    pub(in crate::session) id: String,
    pub(in crate::session) source_start_row: usize,
    pub(in crate::session) source_end_row: usize,
    pub(in crate::session) has_summary: bool,
}

#[derive(Clone, Debug)]
pub(in crate::session) struct DisplayProjection {
    pub(in crate::session) rows: Vec<DisplayProjectionRow>,
    pub(in crate::session) collapsed: Vec<CollapsedBlockRange>,
}

impl DisplayProjection {
    pub(in crate::session) fn identity(total_rows: usize) -> Self {
        Self {
            rows: (0..total_rows).map(DisplayProjectionRow::Source).collect(),
            collapsed: Vec::new(),
        }
    }

    pub(in crate::session) fn has_folds(&self) -> bool {
        !self.collapsed.is_empty()
    }

    pub(in crate::session) fn source_range(&self, row: &DisplayProjectionRow) -> (usize, usize) {
        match row {
            DisplayProjectionRow::Source(source) => (*source, *source),
            DisplayProjectionRow::FoldSummary(index) => {
                let range = &self.collapsed[*index];
                (range.source_start_row, range.source_end_row)
            }
        }
    }

    pub(in crate::session) fn display_index_for_source(&self, source_row: usize) -> Option<usize> {
        let index = self.rows.partition_point(|row| {
            let (_, end) = self.source_range(row);
            end < source_row
        });
        self.rows.get(index).and_then(|row| {
            let (start, end) = self.source_range(row);
            (source_row >= start && source_row <= end).then_some(index)
        })
    }

    pub(in crate::session) fn summary_id_for_source(&self, source_row: usize) -> Option<&str> {
        let index = self.display_index_for_source(source_row)?;
        let DisplayProjectionRow::FoldSummary(range_index) = self.rows.get(index)? else {
            return None;
        };
        Some(self.collapsed[*range_index].id.as_str())
    }

    pub(in crate::session) fn intersects_collapsed_range(
        &self,
        start_row: usize,
        end_row_exclusive: usize,
    ) -> bool {
        self.collapsed.iter().any(|range| {
            start_row <= range.source_end_row && end_row_exclusive > range.source_start_row
        })
    }
}

pub(in crate::session) fn display_projection_for_terminal(
    terminal: &Terminal,
) -> DisplayProjection {
    let (_, viewport_rows) = terminal.size();
    if terminal.is_alt_screen_active() {
        return DisplayProjection::identity(viewport_rows);
    }

    let grid = terminal.grid();
    let scrollback_len = grid.scrollback_len();
    let total_rows = scrollback_len.saturating_add(viewport_rows);
    if total_rows == 0 {
        return DisplayProjection::identity(0);
    }
    let first_retained_abs_row = grid.total_lines_scrolled().saturating_sub(scrollback_len);
    let last_retained_abs_row = first_retained_abs_row.saturating_add(total_rows - 1);
    let mut collapsed = terminal
        .iterm_blocks()
        .iter()
        .filter(|block| block.complete && block.folded && block.end_abs_row > block.start_abs_row)
        .filter(|block| {
            block.end_abs_row >= first_retained_abs_row
                && block.start_abs_row <= last_retained_abs_row
        })
        .map(|block| CollapsedBlockRange {
            id: block.id.clone(),
            source_start_row: block
                .start_abs_row
                .saturating_sub(first_retained_abs_row)
                .min(total_rows - 1),
            source_end_row: block
                .end_abs_row
                .saturating_sub(first_retained_abs_row)
                .min(total_rows - 1),
            has_summary: block.start_abs_row >= first_retained_abs_row,
        })
        .collect::<Vec<_>>();
    collapsed.sort_by(|left, right| {
        left.source_start_row
            .cmp(&right.source_start_row)
            .then_with(|| right.source_end_row.cmp(&left.source_end_row))
            .then_with(|| left.id.cmp(&right.id))
    });

    let mut merged: Vec<CollapsedBlockRange> = Vec::with_capacity(collapsed.len());
    for candidate in collapsed {
        if let Some(previous) = merged.last_mut()
            && candidate.source_start_row <= previous.source_end_row
        {
            previous.source_end_row = previous.source_end_row.max(candidate.source_end_row);
            continue;
        }
        merged.push(candidate);
    }
    if merged.is_empty() {
        return DisplayProjection::identity(total_rows);
    }

    let mut rows = Vec::with_capacity(total_rows);
    let mut source_row = 0usize;
    for (range_index, range) in merged.iter().enumerate() {
        while source_row < range.source_start_row {
            rows.push(DisplayProjectionRow::Source(source_row));
            source_row += 1;
        }
        if range.has_summary {
            rows.push(DisplayProjectionRow::FoldSummary(range_index));
        }
        source_row = range.source_end_row.saturating_add(1);
    }
    while source_row < total_rows {
        rows.push(DisplayProjectionRow::Source(source_row));
        source_row += 1;
    }

    DisplayProjection {
        rows,
        collapsed: merged,
    }
}

pub(in crate::session) fn projection_source_span(
    projection: &DisplayProjection,
    display_start_row: usize,
    viewport_rows: usize,
) -> Option<(usize, usize)> {
    let mut ranges = projection
        .rows
        .iter()
        .skip(display_start_row)
        .take(viewport_rows)
        .map(|row| projection.source_range(row));
    let first = ranges.next()?;
    Some(ranges.fold(first, |(start, end), (next_start, next_end)| {
        (start.min(next_start), end.max(next_end))
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identity_projection_preserves_source_indexes_and_viewport_span() {
        let terminal = Terminal::new(12, 4);
        let projection = display_projection_for_terminal(&terminal);

        assert!(!projection.has_folds());
        assert_eq!(projection.rows.len(), 4);
        assert_eq!(projection.display_index_for_source(0), Some(0));
        assert_eq!(projection.display_index_for_source(3), Some(3));
        assert_eq!(projection.display_index_for_source(4), None);
        assert_eq!(projection_source_span(&projection, 1, 2), Some((1, 2)));
    }

    #[test]
    fn nested_fold_projection_keeps_the_outer_summary_mapping() {
        let mut terminal = Terminal::with_scrollback(20, 6, 32);
        terminal.process(b"\x1b]1337;Block=id=outer;attr=start\x07outer\r\n");
        terminal.process(b"\x1b]1337;Block=id=inner;attr=start\x07inner\r\ninner-end");
        terminal.process(b"\x1b]1337;Block=id=inner;attr=end\x07\r\nouter-end");
        terminal.process(b"\x1b]1337;Block=id=outer;attr=end\x07");
        terminal.process(b"\x1b]1337;UpdateBlock=id=inner;action=fold\x07");
        terminal.process(b"\x1b]1337;UpdateBlock=id=outer;action=fold\x07");

        let projection = display_projection_for_terminal(&terminal);

        assert_eq!(projection.collapsed.len(), 1);
        assert_eq!(projection.collapsed[0].id, "outer");
        assert_eq!(projection.display_index_for_source(3), Some(0));
        assert_eq!(projection.summary_id_for_source(3), Some("outer"));
        assert_eq!(projection_source_span(&projection, 0, 1), Some((0, 3)));
    }
}
