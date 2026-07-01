//! Sixel graphics DCS sequence handling

use super::parse_sixel_repeat_count;
use crate::sixel;
use crate::terminal::Terminal;
use vte::Params;

/// Maximum number of sixel color registers
const MAX_SIXEL_COLORS: usize = 4096;

fn parse_sixel_u16_param(value: &str) -> Option<u16> {
    if value.is_empty() {
        Some(0)
    } else {
        value.parse::<u16>().ok()
    }
}

fn parse_sixel_usize_param(value: &str) -> Option<usize> {
    if value.is_empty() {
        Some(0)
    } else {
        value.parse::<usize>().ok()
    }
}

impl Terminal {
    /// Process accumulated Sixel command from DCS buffer
    pub(crate) fn process_sixel_command(&mut self) {
        if self.dcs_buffer.is_empty() {
            return;
        }

        let Some(parser) = &mut self.sixel_parser else {
            return;
        };

        let buffer_str = String::from_utf8_lossy(&self.dcs_buffer);
        let command = buffer_str.chars().next().unwrap_or('\0');

        match command {
            '#' => {
                // Color command: #Pc or #Pc;Pu;Px;Py;Pz
                let params: Vec<&str> = buffer_str[1..].split(';').collect();
                if let Some(color_idx) = params
                    .first()
                    .and_then(|value| parse_sixel_usize_param(value))
                {
                    if color_idx >= MAX_SIXEL_COLORS {
                        // Reject out-of-range color indices
                    } else if params.len() == 1 {
                        // Select color
                        parser.select_color(color_idx);
                    } else if params.len() >= 5 {
                        // Define color
                        if let (Some(color_system), Some(x), Some(y), Some(z)) = (
                            parse_sixel_u16_param(params[1])
                                .and_then(|value| value.try_into().ok()),
                            parse_sixel_u16_param(params[2]),
                            parse_sixel_u16_param(params[3]),
                            parse_sixel_u16_param(params[4]),
                        ) {
                            parser.define_color(color_idx, color_system, x, y, z);
                        }
                    }
                }
            }
            '"' => {
                // Raster attributes: "Pan;Pad;Ph;Pv
                let params: Vec<&str> = buffer_str[1..].split(';').collect();
                if params.len() >= 4 {
                    if let (Some(pan), Some(pad), Some(width), Some(height)) = (
                        parse_sixel_u16_param(params[0]),
                        parse_sixel_u16_param(params[1]),
                        parse_sixel_usize_param(params[2]),
                        parse_sixel_usize_param(params[3]),
                    ) {
                        parser.set_raster_attributes(pan, pad, width, height);
                    }
                }
            }
            '!' => {
                // Repeat sequence: !Pn character
                if buffer_str.len() >= 2 {
                    let count_str = &buffer_str[1..buffer_str.len() - 1];
                    let repeat_char = buffer_str.chars().last().unwrap_or('?');
                    let count = parse_sixel_repeat_count(count_str);
                    parser.parse_repeat(count, repeat_char);
                }
            }
            _ => {}
        }

        self.dcs_buffer.clear();
    }

    pub(crate) fn handle_sixel_hook(&mut self, params: &Params) {
        let mut parser = sixel::SixelParser::new_with_limits(self.sixel_limits);

        // Convert Params to Vec<u16> for set_params
        let params_vec: Vec<u16> = params
            .iter()
            .map(|subparams| subparams.first().copied().unwrap_or(0))
            .collect();

        parser.set_params(&params_vec);

        self.sixel_parser = Some(parser);
    }
}
