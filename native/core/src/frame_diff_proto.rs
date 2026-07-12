use crate::model::{
    TerminalCursor, TerminalDirtyRange, TerminalFrameDiff, TerminalFrameKind, TerminalFrameModes,
    TerminalGraphicPlacement, TerminalHyperlinkRange, TerminalRow, TerminalSelection,
    TerminalSizedTextPlacement, TerminalStyleRun,
};
use crate::proto::frame_diff as pb;
use prost::Message;

pub fn encode_frame_diff(frame: &TerminalFrameDiff) -> Result<Vec<u8>, prost::EncodeError> {
    let message = to_proto_frame(frame);
    let mut bytes = Vec::with_capacity(message.encoded_len());
    message.encode(&mut bytes)?;
    Ok(bytes)
}

pub fn decode_frame_diff_for_test(
    bytes: &[u8],
) -> Result<pb::TerminalFrameDiff, prost::DecodeError> {
    pb::TerminalFrameDiff::decode(bytes)
}

fn to_proto_frame(frame: &TerminalFrameDiff) -> pb::TerminalFrameDiff {
    pb::TerminalFrameDiff {
        frame_schema_version: frame.frame_schema_version.clone(),
        frame_kind: match frame.frame_kind {
            TerminalFrameKind::Snapshot => pb::TerminalFrameKind::Snapshot as i32,
            TerminalFrameKind::Delta => pb::TerminalFrameKind::Delta as i32,
        },
        rows: frame.rows.iter().map(to_proto_row).collect(),
        cursor: Some(to_proto_cursor(&frame.cursor)),
        selection: frame.selection.as_ref().map(to_proto_selection),
        viewport_rows: u16_to_u32(frame.viewport_rows),
        viewport_cols: u16_to_u32(frame.viewport_cols),
        dirty_ranges: frame
            .dirty_ranges
            .iter()
            .map(to_proto_dirty_range)
            .collect(),
        scrollback_offset: usize_to_u32(frame.scrollback_offset),
        scrollback_max_offset: usize_to_u32(frame.scrollback_max_offset),
        global_bottom_row: Some(frame.global_bottom_row),
        viewport_start_row: usize_to_u32(frame.viewport_start_row),
        viewport_row_shift: frame.viewport_row_shift,
        default_foreground: color_to_proto(frame.default_foreground.as_deref()),
        default_background: color_to_proto(frame.default_background.as_deref()),
        cursor_color: color_to_proto(frame.cursor_color.as_deref()),
        pointer_shape: frame.pointer_shape.clone().unwrap_or_default(),
        modes: Some(to_proto_modes(&frame.modes)),
        window_title: frame.window_title.clone().unwrap_or_default(),
        window_icon_name: frame.window_icon_name.clone().unwrap_or_default(),
        hyperlinks: frame.hyperlinks.iter().map(to_proto_hyperlink).collect(),
        sized_text: frame.sized_text.iter().map(to_proto_sized_text).collect(),
        inline_images: Vec::new(),
        graphics: frame.graphics.iter().map(to_proto_graphic).collect(),
    }
}

fn to_proto_sized_text(placement: &TerminalSizedTextPlacement) -> pb::TerminalSizedTextPlacement {
    pb::TerminalSizedTextPlacement {
        text: placement.text.clone(),
        row: usize_to_u32(placement.row),
        col: usize_to_u32(placement.col),
        width_cells: usize_to_u32(placement.width_cells),
        height_cells: usize_to_u32(placement.height_cells),
        source_row_offset_cells: usize_to_u32(placement.source_row_offset_cells),
        visible_height_cells: usize_to_u32(placement.visible_height_cells),
        scale: u32::from(placement.scale),
        subscale_n: u32::from(placement.subscale_n),
        subscale_d: u32::from(placement.subscale_d),
        vertical_align: u32::from(placement.vertical_align),
        horizontal_align: u32::from(placement.horizontal_align),
        natural_width: placement.natural_width,
        foreground: color_to_proto(placement.foreground.as_deref()),
        background: color_to_proto(placement.background.as_deref()),
        bold: placement.bold,
        dim: placement.dim,
        italic: placement.italic,
        underline: placement.underline,
        blink: placement.blink,
        inverse: placement.inverse,
    }
}

fn to_proto_row(row: &TerminalRow) -> pb::TerminalRow {
    pb::TerminalRow {
        index: usize_to_u32(row.index),
        text: row.text.clone(),
        wrapped: row.wrapped,
        modified_at_micros: 0,
        style_runs: row.style_runs.iter().map(to_proto_style_run).collect(),
    }
}

fn to_proto_style_run(run: &TerminalStyleRun) -> pb::TerminalStyleRun {
    pb::TerminalStyleRun {
        start: usize_to_u32(run.start),
        end: usize_to_u32(run.end),
        foreground: color_to_proto(run.foreground.as_deref()),
        background: color_to_proto(run.background.as_deref()),
        bold: run.bold,
        dim: run.dim,
        italic: run.italic,
        underline: run.underline,
        blink: run.blink,
        inverse: run.inverse,
    }
}

fn to_proto_cursor(cursor: &TerminalCursor) -> pb::TerminalCursor {
    pb::TerminalCursor {
        row: usize_to_u32(cursor.row),
        col: usize_to_u32(cursor.col),
        visible: cursor.visible,
    }
}

fn to_proto_selection(selection: &TerminalSelection) -> pb::TerminalSelection {
    pb::TerminalSelection {
        present: true,
        start_row: usize_to_u32(selection.start_row),
        start_col: usize_to_u32(selection.start_col),
        end_row: usize_to_u32(selection.end_row),
        end_col: usize_to_u32(selection.end_col),
    }
}

fn to_proto_dirty_range(range: &TerminalDirtyRange) -> pb::TerminalDirtyRange {
    pb::TerminalDirtyRange {
        start: usize_to_u32(range.start),
        end: usize_to_u32(range.end),
    }
}

fn to_proto_modes(modes: &TerminalFrameModes) -> pb::TerminalFrameModes {
    pb::TerminalFrameModes {
        alternate_screen: modes.alternate_screen,
        alternate_scroll: modes.alternate_scroll,
        application_cursor: modes.application_cursor,
        application_keypad: modes.application_keypad,
        insert_mode: modes.insert_mode,
        origin_mode: modes.origin_mode,
        line_feed_new_line_mode: modes.line_feed_new_line_mode,
        hide_cursor: modes.hide_cursor,
        bracketed_paste: modes.bracketed_paste,
        focus_tracking: modes.focus_tracking,
        char_protected: modes.char_protected,
        mouse_mode: modes.mouse_mode.clone(),
        mouse_encoding: modes.mouse_encoding.clone(),
        kitty_keyboard_flags: u16_to_u32(modes.kitty_keyboard_flags),
        synchronized_output: modes.synchronized_output,
    }
}

fn to_proto_hyperlink(link: &TerminalHyperlinkRange) -> pb::TerminalHyperlinkRange {
    pb::TerminalHyperlinkRange {
        row: usize_to_u32(link.row),
        start_col: usize_to_u32(link.start_col),
        end_col: usize_to_u32(link.end_col),
        uri: link.uri.clone(),
        protocol_id: link.protocol_id.clone().unwrap_or_default(),
    }
}

fn to_proto_graphic(graphic: &TerminalGraphicPlacement) -> pb::TerminalGraphicPlacement {
    pb::TerminalGraphicPlacement {
        placement_id: graphic.placement_id,
        render_id: graphic.render_id,
        asset_key: Some(pb::TerminalGraphicAssetKey {
            asset_id: graphic.asset_id,
            asset_version: graphic.asset_version,
        }),
        protocol: graphic.protocol.clone(),
        row: usize_to_u32(graphic.row),
        col: usize_to_u32(graphic.col),
        width_px: usize_to_u32(graphic.width_px),
        height_px: usize_to_u32(graphic.height_px),
        width_cells: usize_to_u32(graphic.width_cells),
        height_cells: usize_to_u32(graphic.height_cells),
        source_x_offset_px: usize_to_u32(graphic.source_x_offset_px),
        visible_width_px: usize_to_u32(graphic.visible_width_px),
        source_y_offset_px: usize_to_u32(graphic.source_y_offset_px),
        visible_height_px: usize_to_u32(graphic.visible_height_px),
        z_index: graphic.z_index,
        x_offset_px: u32_to_i32(graphic.x_offset_px),
        y_offset_px: u32_to_i32(graphic.y_offset_px),
        preserve_aspect_ratio: graphic.preserve_aspect_ratio,
    }
}

fn color_to_proto(value: Option<&str>) -> Option<pb::ColorRgb> {
    let value = value?;
    let hex = value.strip_prefix('#')?;
    if hex.len() != 6 {
        return None;
    }
    let rgb = u32::from_str_radix(hex, 16).ok()?;
    Some(pb::ColorRgb { present: true, rgb })
}

fn u16_to_u32(value: u16) -> u32 {
    u32::from(value)
}

fn usize_to_u32(value: usize) -> u32 {
    value.min(u32::MAX as usize) as u32
}

fn u32_to_i32(value: u32) -> i32 {
    value.min(i32::MAX as u32) as i32
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn graphic_identities_preserve_values_above_u32_range() {
        let graphic = TerminalGraphicPlacement {
            render_id: 4_294_967_303,
            placement_id: 4_294_967_301,
            asset_id: 4_294_967_307,
            asset_version: 3_205_628_038_470_320,
            protocol: "kitty".to_string(),
            row: 1,
            col: 2,
            width_px: 192,
            height_px: 208,
            width_cells: 9,
            height_cells: 5,
            source_x_offset_px: 0,
            visible_width_px: 192,
            source_y_offset_px: 0,
            visible_height_px: 208,
            z_index: 0,
            x_offset_px: 0,
            y_offset_px: 0,
            preserve_aspect_ratio: true,
        };

        let encoded = to_proto_graphic(&graphic);

        assert_eq!(encoded.render_id, graphic.render_id);
        assert_eq!(encoded.placement_id, graphic.placement_id);
        let asset_key = encoded.asset_key.expect("graphic asset key");
        assert_eq!(asset_key.asset_id, graphic.asset_id);
        assert_eq!(asset_key.asset_version, graphic.asset_version);
    }
}
