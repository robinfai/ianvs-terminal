//! DCS (Device Control String) sequence handling dispatcher

mod sixel;

use crate::debug;
use crate::graphics::{next_graphic_id, GraphicProtocol, ImageDimension, TerminalGraphic};
use crate::terminal::Terminal;
use vte::Params;

fn sixel_display_width_for_pixel_aspect(
    width: usize,
    pixel_aspect_ratio: Option<(u16, u16)>,
) -> Option<usize> {
    let (pan, pad) = pixel_aspect_ratio?;
    if pan == 0 || pad == 0 || pan == pad {
        return None;
    }
    let pan = pan as usize;
    let pad = pad as usize;
    let scaled_width = width.saturating_mul(pan).saturating_add(pad / 2) / pad;
    Some(scaled_width.max(1))
}

fn parse_sixel_repeat_count(value: &str) -> usize {
    if value.is_empty() {
        return 1;
    }
    let mut count = 0usize;
    for byte in value.bytes() {
        if !byte.is_ascii_digit() {
            return 1;
        }
        count = count
            .saturating_mul(10)
            .saturating_add((byte - b'0') as usize);
    }
    count
}

impl Terminal {
    /// VTE hook - start of DCS sequence
    pub(in crate::terminal) fn dcs_hook(
        &mut self,
        params: &Params,
        intermediates: &[u8],
        _ignore: bool,
        action: char,
    ) {
        let is_sixel = action == 'q' && intermediates.is_empty();
        if is_sixel && self.disable_insecure_sequences {
            debug::log(
                debug::DebugLevel::Debug,
                "SECURITY",
                "Blocked Sixel DCS (disable_insecure_sequences=true)",
            );
            return;
        }

        self.dcs_active = true;
        self.dcs_action = Some(action);
        self.dcs_buffer.clear();

        if is_sixel {
            self.handle_sixel_hook(params);
        }
    }

    /// VTE put - data for DCS sequence
    pub(in crate::terminal) fn dcs_put(&mut self, byte: u8) {
        if !self.dcs_active {
            return;
        }

        if self.dcs_action == Some('q') && self.sixel_parser.is_some() {
            let is_sixel_data = (63..=126).contains(&byte);

            if is_sixel_data {
                let mut pending_repeat = None;
                let has_repeat = !self.dcs_buffer.is_empty() && self.dcs_buffer[0] == b'!';

                if has_repeat {
                    // Parse repeat count
                    let s = std::str::from_utf8(&self.dcs_buffer[1..]).unwrap_or("1");
                    let count = parse_sixel_repeat_count(s);
                    pending_repeat = Some(count);
                    self.dcs_buffer.clear();
                } else if !self.dcs_buffer.is_empty() {
                    // Process any other pending commands (colors)
                    self.process_sixel_command();
                }

                // Feed to parser
                if let Some(parser) = &mut self.sixel_parser {
                    if let Some(count) = pending_repeat {
                        parser.parse_repeat(count, byte as char);
                    } else {
                        parser.parse_sixel(byte as char);
                    }
                }
            } else if byte == b'-' {
                if !self.dcs_buffer.is_empty() {
                    self.process_sixel_command();
                }
                if let Some(p) = &mut self.sixel_parser {
                    p.new_line();
                }
            } else if byte == b'$' {
                if !self.dcs_buffer.is_empty() {
                    self.process_sixel_command();
                }
                if let Some(p) = &mut self.sixel_parser {
                    p.carriage_return();
                }
            } else {
                // Control chars or parameters (#, ", !, digits)
                // If starting a new command, process previous one
                if (byte == b'#' || byte == b'"' || byte == b'!') && !self.dcs_buffer.is_empty() {
                    self.process_sixel_command();
                }
                self.dcs_buffer.push(byte);
            }
        } else {
            self.dcs_buffer.push(byte);
        }
    }

    /// VTE unhook - end of DCS sequence
    pub(in crate::terminal) fn dcs_unhook(&mut self) {
        if !self.dcs_active {
            return;
        }

        if self.dcs_action == Some('q') && self.sixel_parser.is_some() {
            self.process_sixel_command();
            if let Some(parser) = self.sixel_parser.take() {
                if !parser.has_sixel_data() {
                    self.dcs_active = false;
                    self.dcs_action = None;
                    self.dcs_buffer.clear();
                    return;
                }

                let position = (self.cursor.col, self.cursor.row);
                let pixel_aspect_ratio = parser.raster_pixel_aspect_ratio();
                let sixel_graphic = parser.build_graphic(position);

                // Convert SixelGraphic to TerminalGraphic
                let mut pixels = Vec::with_capacity(sixel_graphic.width * sixel_graphic.height * 4);
                for y in 0..sixel_graphic.height {
                    for x in 0..sixel_graphic.width {
                        if let Some((r, g, b, a)) = sixel_graphic.get_pixel(x, y) {
                            pixels.push(r);
                            pixels.push(g);
                            pixels.push(b);
                            pixels.push(a);
                        } else {
                            pixels.extend_from_slice(&[0, 0, 0, 0]);
                        }
                    }
                }

                let mut graphic = TerminalGraphic::new(
                    next_graphic_id(),
                    GraphicProtocol::Sixel,
                    position,
                    sixel_graphic.width,
                    sixel_graphic.height,
                    pixels,
                );

                let (cell_w, cell_h) = self.cell_dimensions;
                graphic.set_alternate_screen(self.alt_screen_active);
                graphic.set_cell_dimensions(cell_w, cell_h);
                if let Some(display_width) =
                    sixel_display_width_for_pixel_aspect(sixel_graphic.width, pixel_aspect_ratio)
                {
                    graphic.placement.requested_width =
                        ImageDimension::pixels(display_width as f64);
                    graphic.placement.requested_height =
                        ImageDimension::pixels(sixel_graphic.height as f64);
                    graphic.placement.preserve_aspect_ratio = false;
                }

                let (cols, rows) = self.size();
                let (graphic_width_in_cols, graphic_height_in_rows) =
                    graphic.resolved_cell_span(Some(cols), Some(rows));
                graphic.set_display_cell_span(graphic_width_in_cols, graphic_height_in_rows);
                let should_add_graphic =
                    self.advance_cursor_after_graphic_block(&mut graphic, graphic_height_in_rows);

                let row = graphic.position.1;
                if should_add_graphic && self.graphics_store.add_graphic(graphic) {
                    self.terminal_events
                        .push(crate::terminal::TerminalEvent::GraphicsAdded(row));
                }
            }
        }

        self.dcs_active = false;
        self.dcs_action = None;
        self.dcs_buffer.clear();
    }
}

#[cfg(test)]
mod tests;
