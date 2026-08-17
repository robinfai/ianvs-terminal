use super::super::{
    TerminalThemeSnapshot, resolve_color_rgb, row_cells_for_visible_index, terminal_theme_snapshot,
};
use super::{DisplayProjection, projection_source_span};
use crate::model::TerminalGraphicPlacement;
use par_term_emu_core_rust::cell::Cell;
use par_term_emu_core_rust::color::Color;
use par_term_emu_core_rust::graphics::placeholder::{PlaceholderInfo, parse_diacritics};
use par_term_emu_core_rust::graphics::{ImageDimension, PLACEHOLDER_CHAR, TerminalGraphic};
use par_term_emu_core_rust::terminal::Terminal;
use std::sync::Arc;

pub(in crate::session) struct GraphicAssetSnapshot {
    pub(in crate::session) asset_id: u64,
    pub(in crate::session) asset_version: u64,
    pub(in crate::session) width: usize,
    pub(in crate::session) height: usize,
    pub(in crate::session) pixels: Arc<Vec<u8>>,
}

pub(in crate::session) fn build_graphic_placements(
    terminal: &Terminal,
    viewport_start_row: usize,
    viewport_rows: usize,
    scrollback_len: usize,
    alt_screen_active: bool,
    include_pending_cleared_kitty: bool,
) -> Vec<TerminalGraphicPlacement> {
    if viewport_rows == 0 {
        return Vec::new();
    }
    let (viewport_cols, total_viewport_rows) = terminal.size();
    let viewport_end_row = viewport_start_row.saturating_add(viewport_rows);
    let active_row_base = if alt_screen_active { 0 } else { scrollback_len };
    let mut placements = Vec::new();

    for graphic in terminal.all_graphics() {
        if graphic.alternate_screen != alt_screen_active {
            continue;
        }
        if let Some(placement) = graphic_placement_for_viewport(
            graphic,
            active_row_base.saturating_add(graphic.position.1),
            viewport_start_row,
            viewport_end_row,
            viewport_cols,
            total_viewport_rows,
            graphic.scroll_offset_rows,
        ) {
            placements.push(placement);
        }
    }

    if include_pending_cleared_kitty {
        for graphic in terminal.pending_cleared_kitty_graphics() {
            if graphic.alternate_screen != alt_screen_active {
                continue;
            }
            if let Some(placement) = graphic_placement_for_viewport(
                graphic,
                active_row_base.saturating_add(graphic.position.1),
                viewport_start_row,
                viewport_end_row,
                viewport_cols,
                total_viewport_rows,
                graphic.scroll_offset_rows,
            ) {
                placements.push(placement);
            }
        }
    }

    if !alt_screen_active {
        for graphic in terminal.all_scrollback_graphics() {
            let Some(scrollback_row) = graphic.scrollback_row else {
                continue;
            };
            if let Some(placement) = graphic_placement_for_viewport(
                graphic,
                scrollback_row,
                viewport_start_row,
                viewport_end_row,
                viewport_cols,
                total_viewport_rows,
                0,
            ) {
                placements.push(placement);
            }
        }
    }

    let theme = terminal_theme_snapshot(terminal);
    push_kitty_placeholder_graphic_placements(
        terminal,
        &theme,
        viewport_start_row,
        viewport_rows,
        viewport_end_row,
        viewport_cols,
        total_viewport_rows,
        alt_screen_active,
        &mut placements,
    );

    placements
}

#[allow(clippy::too_many_arguments)]
pub(in crate::session) fn build_projected_graphic_placements(
    terminal: &Terminal,
    projection: &DisplayProjection,
    display_start_row: usize,
    viewport_rows: usize,
    scrollback_len: usize,
    alt_screen_active: bool,
    include_pending_cleared_kitty: bool,
) -> Vec<TerminalGraphicPlacement> {
    if !projection.has_folds() {
        return build_graphic_placements(
            terminal,
            display_start_row,
            viewport_rows,
            scrollback_len,
            alt_screen_active,
            include_pending_cleared_kitty,
        );
    }
    let Some((source_start_row, source_end_row)) =
        projection_source_span(projection, display_start_row, viewport_rows)
    else {
        return Vec::new();
    };
    let physical_rows = source_end_row
        .saturating_sub(source_start_row)
        .saturating_add(1);
    build_graphic_placements(
        terminal,
        source_start_row,
        physical_rows,
        scrollback_len,
        alt_screen_active,
        include_pending_cleared_kitty,
    )
    .into_iter()
    .filter_map(|mut placement| {
        let source_row = source_start_row.saturating_add(placement.row);
        let source_end_exclusive = source_row.saturating_add(placement.height_cells.max(1));
        if projection.intersects_collapsed_range(source_row, source_end_exclusive) {
            return None;
        }
        let display_row = projection.display_index_for_source(source_row)?;
        if display_row < display_start_row
            || display_row >= display_start_row.saturating_add(viewport_rows)
        {
            return None;
        }
        placement.row = display_row.saturating_sub(display_start_row);
        Some(placement)
    })
    .collect()
}

#[allow(clippy::too_many_arguments)]
fn push_kitty_placeholder_graphic_placements(
    terminal: &Terminal,
    theme: &TerminalThemeSnapshot,
    viewport_start_row: usize,
    viewport_rows: usize,
    viewport_end_row: usize,
    viewport_cols: usize,
    total_viewport_rows: usize,
    alt_screen_active: bool,
    placements: &mut Vec<TerminalGraphicPlacement>,
) {
    for viewport_row in 0..viewport_rows {
        let visible_index = viewport_start_row.saturating_add(viewport_row);
        let (cells, _) = row_cells_for_visible_index(terminal, visible_index);
        let mut column_offset = 0usize;
        let mut previous_placeholder: Option<PlaceholderInfo> = None;

        for cell in cells.unwrap_or_default() {
            if cell.flags.wide_char_spacer() {
                continue;
            }

            let column_start = column_offset;
            column_offset = column_offset.saturating_add(cell.width());
            let Some(mut placeholder_info) = placeholder_info_from_cell(cell, theme) else {
                previous_placeholder = None;
                continue;
            };

            if let Some(previous) = previous_placeholder {
                let expected_col = previous.col.unwrap_or(0).saturating_add(1);
                if placeholder_info.can_inherit_from(&previous, expected_col) {
                    placeholder_info.inherit_from(&previous);
                }
            }
            previous_placeholder = Some(placeholder_info);

            let Some(graphic) = terminal
                .graphics_store()
                .get_placeholder_graphic(&placeholder_info)
            else {
                continue;
            };
            if graphic.alternate_screen != alt_screen_active || graphic.pixels.is_empty() {
                continue;
            }
            if let Some(placement) = kitty_placeholder_placement_for_viewport(
                graphic,
                placeholder_info,
                column_start,
                visible_index,
                viewport_start_row,
                viewport_end_row,
                viewport_cols,
                total_viewport_rows,
            ) {
                placements.push(placement);
            }
        }
    }
}

fn placeholder_info_from_cell(
    cell: &Cell,
    theme: &TerminalThemeSnapshot,
) -> Option<PlaceholderInfo> {
    let grapheme = cell.get_grapheme();
    if !grapheme.starts_with(PLACEHOLDER_CHAR) {
        return None;
    }

    let diacritics: String = grapheme.chars().skip(1).collect();
    let (row, col, msb) = parse_diacritics(&diacritics);
    Some(
        PlaceholderInfo::from_color(color_to_u24(cell.fg, theme))
            .with_placement_id(
                cell.underline_color
                    .map_or(0, |color| color_to_u24(color, theme)),
            )
            .with_diacritics(row, col, msb),
    )
}

fn color_to_u24(color: Color, theme: &TerminalThemeSnapshot) -> u32 {
    let (red, green, blue) = resolve_color_rgb(color, &theme.ansi_palette);
    ((red as u32) << 16) | ((green as u32) << 8) | blue as u32
}

#[allow(clippy::too_many_arguments)]
fn kitty_placeholder_placement_for_viewport(
    graphic: &TerminalGraphic,
    placeholder_info: PlaceholderInfo,
    placeholder_col: usize,
    absolute_row: usize,
    viewport_start_row: usize,
    viewport_end_row: usize,
    viewport_cols: usize,
    total_viewport_rows: usize,
) -> Option<TerminalGraphicPlacement> {
    let row = placeholder_info.row? as usize;
    let col = placeholder_info.col? as usize;
    let (source_x, source_y, source_width, source_height) = graphic.source_rect_pixels()?;
    let (span_cols, span_rows) = graphic.display_cell_span.unwrap_or_else(|| {
        graphic.resolved_cell_span(Some(viewport_cols), Some(total_viewport_rows))
    });
    if col >= span_cols || row >= span_rows {
        return None;
    }

    let tile_start_x = source_width.saturating_mul(col) / span_cols.max(1);
    let tile_end_x = source_width.saturating_mul(col.saturating_add(1)) / span_cols.max(1);
    let tile_start_y = source_height.saturating_mul(row) / span_rows.max(1);
    let tile_end_y = source_height.saturating_mul(row.saturating_add(1)) / span_rows.max(1);
    let tile_width = tile_end_x.saturating_sub(tile_start_x).max(1);
    let tile_height = tile_end_y.saturating_sub(tile_start_y).max(1);

    let mut placeholder_graphic = graphic.clone();
    placeholder_graphic.position = (placeholder_col, 0);
    placeholder_graphic.placement.source_x_offset =
        source_x.saturating_add(tile_start_x).min(u32::MAX as usize) as u32;
    placeholder_graphic.placement.source_y_offset =
        source_y.saturating_add(tile_start_y).min(u32::MAX as usize) as u32;
    placeholder_graphic.placement.source_width = Some(tile_width.min(u32::MAX as usize) as u32);
    placeholder_graphic.placement.source_height = Some(tile_height.min(u32::MAX as usize) as u32);
    placeholder_graphic.placement.requested_width = ImageDimension::cells(1.0);
    placeholder_graphic.placement.requested_height = ImageDimension::cells(1.0);
    placeholder_graphic.placement.columns = Some(1);
    placeholder_graphic.placement.rows = Some(1);
    placeholder_graphic.placement.x_offset = 0;
    placeholder_graphic.placement.y_offset = 0;
    placeholder_graphic.set_display_cell_span(1, 1);

    graphic_placement_for_viewport(
        &placeholder_graphic,
        absolute_row,
        viewport_start_row,
        viewport_end_row,
        viewport_cols,
        total_viewport_rows,
        0,
    )
}

pub(in crate::session) fn graphic_placement_for_viewport(
    graphic: &TerminalGraphic,
    absolute_start_row: usize,
    viewport_start_row: usize,
    viewport_end_row: usize,
    viewport_cols: usize,
    total_viewport_rows: usize,
    scrolled_top_rows: usize,
) -> Option<TerminalGraphicPlacement> {
    let geometry = graphic_display_geometry(graphic, viewport_cols, total_viewport_rows)?;
    let width_px = geometry.width_px;
    let height_px = geometry.height_px;
    let width_cells = geometry.width_cells;
    let height_cells = geometry.height_cells;
    let (cell_width_px, cell_height_px) = graphic_cell_dimensions_px(graphic);
    let terminal_width_px = viewport_cols.saturating_mul(cell_width_px);
    let x_offset_px = graphic.placement.x_offset as usize;
    let graphic_left_px = graphic
        .position
        .0
        .saturating_mul(cell_width_px)
        .saturating_add(x_offset_px);
    if terminal_width_px == 0 || graphic_left_px >= terminal_width_px {
        return None;
    }
    let source_x_offset_px = geometry.source_x_offset_px;
    let visible_width_px = geometry
        .visible_width_px
        .min(terminal_width_px.saturating_sub(graphic_left_px))
        .max(1);
    let scrolled_top_rows = scrolled_top_rows.min(height_cells);
    let displayed_height_cells = height_cells.saturating_sub(scrolled_top_rows);
    if displayed_height_cells == 0 {
        return None;
    }
    let absolute_end_row = absolute_start_row.saturating_add(displayed_height_cells);
    if absolute_end_row <= viewport_start_row || absolute_start_row >= viewport_end_row {
        return None;
    }
    let row = absolute_start_row.saturating_sub(viewport_start_row);
    let viewport_hidden_rows = viewport_start_row
        .saturating_sub(absolute_start_row)
        .min(displayed_height_cells);
    let hidden_rows = scrolled_top_rows.saturating_add(viewport_hidden_rows);
    let visible_height_cells = displayed_height_cells
        .saturating_sub(viewport_hidden_rows)
        .min(viewport_end_row.saturating_sub(absolute_start_row.max(viewport_start_row)));
    if visible_height_cells == 0 {
        return None;
    }
    let y_offset_px = graphic.placement.y_offset as usize;
    let hidden_px = hidden_rows.saturating_mul(cell_height_px);
    let visible_window_top_px = hidden_px;
    let visible_window_bottom_px =
        hidden_px.saturating_add(visible_height_cells.saturating_mul(cell_height_px));
    let image_top_px = y_offset_px;
    let image_bottom_px = y_offset_px.saturating_add(geometry.visible_height_px);
    let visible_image_top_px = image_top_px.max(visible_window_top_px);
    let visible_image_bottom_px = image_bottom_px.min(visible_window_bottom_px);
    if visible_image_bottom_px <= visible_image_top_px {
        return None;
    }
    let image_hidden_px = visible_image_top_px.saturating_sub(image_top_px);
    let source_y_offset_px = geometry
        .source_y_offset_px
        .saturating_add(image_hidden_px)
        .min(height_px.saturating_sub(1));
    let visible_height_px = visible_image_bottom_px.saturating_sub(visible_image_top_px);
    let effective_y_offset_px = visible_image_top_px.saturating_sub(hidden_px);
    let placement_id = graphic_placement_id(graphic);
    Some(TerminalGraphicPlacement {
        render_id: placement_id,
        placement_id,
        asset_id: graphic_asset_id(graphic),
        asset_version: graphic_asset_version(graphic),
        protocol: graphic.protocol.as_str().to_string(),
        row,
        col: graphic.position.0,
        width_px,
        height_px,
        width_cells: width_cells.max(1),
        height_cells: height_cells.max(1),
        source_x_offset_px,
        visible_width_px,
        source_y_offset_px,
        visible_height_px,
        z_index: graphic.placement.z_index,
        x_offset_px: graphic.placement.x_offset,
        y_offset_px: effective_y_offset_px.min(u32::MAX as usize) as u32,
        preserve_aspect_ratio: graphic.placement.preserve_aspect_ratio,
    })
}

struct GraphicDisplayGeometry {
    width_px: usize,
    height_px: usize,
    width_cells: usize,
    height_cells: usize,
    source_x_offset_px: usize,
    visible_width_px: usize,
    source_y_offset_px: usize,
    visible_height_px: usize,
}

fn graphic_placement_id(graphic: &TerminalGraphic) -> u64 {
    graphic.id
}

fn graphic_asset_id(graphic: &TerminalGraphic) -> u64 {
    graphic
        .kitty_image_id
        .or(graphic.animation_id)
        .map(u64::from)
        .unwrap_or(graphic.id)
}

fn graphic_asset_version(graphic: &TerminalGraphic) -> u64 {
    graphic.asset_version
}

pub(in crate::session) fn graphic_asset_snapshots(
    terminal: &Terminal,
) -> Vec<GraphicAssetSnapshot> {
    terminal
        .all_graphics()
        .iter()
        .chain(terminal.pending_cleared_kitty_graphics().iter())
        .chain(terminal.all_scrollback_graphics().iter())
        .chain(terminal.graphics_store().all_virtual_placements().values())
        .filter(|graphic| !graphic.pixels.is_empty())
        .map(|graphic| GraphicAssetSnapshot {
            asset_id: graphic_asset_id(graphic),
            asset_version: graphic_asset_version(graphic),
            width: graphic.width,
            height: graphic.height,
            pixels: Arc::clone(&graphic.pixels),
        })
        .collect()
}

fn graphic_display_geometry(
    graphic: &TerminalGraphic,
    viewport_cols: usize,
    viewport_rows: usize,
) -> Option<GraphicDisplayGeometry> {
    let (cell_width_px, cell_height_px) = graphic_cell_dimensions_px(graphic);
    let (source_x, source_y, source_width, source_height) = graphic.source_rect_pixels()?;
    let (visible_width_px, visible_height_px) = locked_iterm_display_size_px(graphic)
        .unwrap_or_else(|| {
            graphic.resolved_display_size_px(Some(viewport_cols), Some(viewport_rows))
        });

    let scale_x = visible_width_px as f64 / source_width as f64;
    let scale_y = visible_height_px as f64 / source_height as f64;
    let width_px = ((graphic.width as f64) * scale_x).round().max(1.0) as usize;
    let height_px = ((graphic.height as f64) * scale_y).round().max(1.0) as usize;
    let source_x_offset_px = ((source_x as f64) * scale_x).round() as usize;
    let source_y_offset_px = ((source_y as f64) * scale_y).round() as usize;
    let source_x_offset_px = source_x_offset_px.min(width_px.saturating_sub(1));
    let source_y_offset_px = source_y_offset_px.min(height_px.saturating_sub(1));
    let visible_width_px = visible_width_px
        .min(width_px.saturating_sub(source_x_offset_px))
        .max(1);
    let visible_height_px = visible_height_px
        .min(height_px.saturating_sub(source_y_offset_px))
        .max(1);
    let x_offset_px = graphic.placement.x_offset as usize;
    let y_offset_px = graphic.placement.y_offset as usize;
    let width_cells = x_offset_px
        .saturating_add(visible_width_px)
        .div_ceil(cell_width_px)
        .max(1);
    let height_cells = y_offset_px
        .saturating_add(visible_height_px)
        .div_ceil(cell_height_px)
        .max(1);
    Some(GraphicDisplayGeometry {
        width_px,
        height_px,
        width_cells,
        height_cells,
        source_x_offset_px,
        visible_width_px,
        source_y_offset_px,
        visible_height_px,
    })
}

fn locked_iterm_display_size_px(graphic: &TerminalGraphic) -> Option<(usize, usize)> {
    if graphic.protocol.as_str() != "iterm" {
        return None;
    }
    let (span_cols, span_rows) = graphic.display_cell_span?;
    let (cell_width_px, cell_height_px) = graphic_cell_dimensions_px(graphic);
    let (_, _, source_width, source_height) = graphic.source_rect_pixels()?;
    let width_bound = span_cols
        .saturating_mul(cell_width_px)
        .saturating_sub(graphic.placement.x_offset as usize)
        .max(1);
    let height_bound = span_rows
        .saturating_mul(cell_height_px)
        .saturating_sub(graphic.placement.y_offset as usize)
        .max(1);
    let scale = (width_bound as f64 / source_width.max(1) as f64)
        .min(height_bound as f64 / source_height.max(1) as f64);
    Some((
        (source_width as f64 * scale).floor().max(1.0) as usize,
        (source_height as f64 * scale).floor().max(1.0) as usize,
    ))
}

fn graphic_cell_dimensions_px(graphic: &TerminalGraphic) -> (usize, usize) {
    let (cell_width_px, cell_height_px) = graphic.cell_dimensions.unwrap_or((1, 1));
    (
        (cell_width_px as usize).max(1),
        (cell_height_px as usize).max(1),
    )
}

#[cfg(test)]
mod tests {
    use super::super::{CollapsedBlockRange, DisplayProjectionRow};
    use super::*;

    #[test]
    fn identity_projection_preserves_graphic_placement() {
        let mut terminal = Terminal::with_scrollback(8, 3, 8);
        terminal.process(b"\x1b_Ga=T,f=32,s=1,v=1,i=7;/wAA/w==\x1b\\");
        let projection = DisplayProjection::identity(3);

        let placements =
            build_projected_graphic_placements(&terminal, &projection, 0, 3, 0, false, false);

        assert_eq!(placements.len(), 1);
        assert_eq!((placements[0].row, placements[0].asset_id), (0, 7));
    }

    #[test]
    fn folded_source_range_hides_intersecting_graphic() {
        let mut terminal = Terminal::with_scrollback(8, 3, 8);
        terminal.process(b"\x1b_Ga=T,f=32,s=1,v=1,i=7;/wAA/w==\x1b\\");
        let projection = DisplayProjection {
            rows: vec![
                DisplayProjectionRow::FoldSummary(0),
                DisplayProjectionRow::Source(2),
            ],
            collapsed: vec![CollapsedBlockRange {
                id: "fold".to_string(),
                source_start_row: 0,
                source_end_row: 1,
                has_summary: true,
            }],
        };

        let placements =
            build_projected_graphic_placements(&terminal, &projection, 0, 2, 0, false, false);

        assert!(placements.is_empty());
    }
}
