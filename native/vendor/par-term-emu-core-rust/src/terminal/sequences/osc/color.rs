//! Color-related OSC sequence handling

use crate::color::Color;
use crate::terminal::color_control::{Osc21ColorValue, Osc21SpecialColor};
use crate::terminal::Terminal;

const MAX_OSC21_RESPONSE_BYTES: usize = 4 * 1024;

impl Terminal {
    fn parse_color_component(component: &str) -> Option<u8> {
        let component = component.trim();
        if component.is_empty()
            || component.len() > 4
            || !component.bytes().all(|byte| byte.is_ascii_hexdigit())
        {
            return None;
        }

        let normalized = format!("{:0<2}", &component[..component.len().min(2)]);
        u8::from_str_radix(&normalized, 16).ok()
    }

    fn parse_rgb_color_component(component: &str) -> Option<u8> {
        let component = component.trim();
        if component.is_empty()
            || component.len() > 4
            || !component.bytes().all(|byte| byte.is_ascii_hexdigit())
        {
            return None;
        }

        let value = u32::from_str_radix(component, 16).ok()?;
        let source_max = (1_u32 << (component.len() * 4)) - 1;
        Some(((value * 255 + source_max / 2) / source_max) as u8)
    }

    fn parse_hash_color_spec(spec: &str) -> Option<(u8, u8, u8)> {
        let hex = spec.strip_prefix('#')?;
        if !hex.bytes().all(|byte| byte.is_ascii_hexdigit()) {
            return None;
        }

        let (channels, width) = match hex.len() {
            3 => (3, 1),
            4 => (4, 1),
            6 => (3, 2),
            8 => (4, 2),
            9 => (3, 3),
            12 => (3, 4),
            16 => (4, 4),
            _ => return None,
        };

        let r = Self::parse_color_component(&hex[0..width])?;
        let g = Self::parse_color_component(&hex[width..width * 2])?;
        let b = Self::parse_color_component(&hex[width * 2..width * 3])?;
        if channels == 4 {
            Self::parse_color_component(&hex[width * 3..width * 4])?;
        }
        Some((r, g, b))
    }

    fn parse_rgbi_color_spec(spec: &str) -> Option<(u8, u8, u8)> {
        let values = spec.strip_prefix("rgbi:")?.split('/').collect::<Vec<_>>();
        if values.len() != 3 {
            return None;
        }
        let component = |value: &str| {
            let value = value.trim().parse::<f64>().ok()?;
            value
                .is_finite()
                .then(|| (value.clamp(0.0, 1.0) * 255.0).round() as u8)
        };
        Some((
            component(values[0])?,
            component(values[1])?,
            component(values[2])?,
        ))
    }

    fn parse_named_color_spec(spec: &str) -> Option<(u8, u8, u8)> {
        Some(match spec.to_ascii_lowercase().as_str() {
            "black" => (0x00, 0x00, 0x00),
            "white" => (0xff, 0xff, 0xff),
            "red" | "red1" => (0xff, 0x00, 0x00),
            "red2" => (0xee, 0x00, 0x00),
            "red3" => (0xcd, 0x00, 0x00),
            "red4" | "darkred" => (0x8b, 0x00, 0x00),
            "green" | "green1" => (0x00, 0xff, 0x00),
            "green2" => (0x00, 0xee, 0x00),
            "green3" => (0x00, 0xcd, 0x00),
            "green4" => (0x00, 0x8b, 0x00),
            "blue" | "blue1" => (0x00, 0x00, 0xff),
            "blue2" => (0x00, 0x00, 0xee),
            "blue3" => (0x00, 0x00, 0xcd),
            "blue4" => (0x00, 0x00, 0x8b),
            "yellow" => (0xff, 0xff, 0x00),
            "magenta" => (0xff, 0x00, 0xff),
            "cyan" => (0x00, 0xff, 0xff),
            "orange" | "orange1" => (0xff, 0xa5, 0x00),
            "gold" | "gold1" => (0xff, 0xd7, 0x00),
            "gray" | "grey" => (0xbe, 0xbe, 0xbe),
            "brown" => (0xa5, 0x2a, 0x2a),
            "purple" => (0xa0, 0x20, 0xf0),
            "pink" => (0xff, 0xc0, 0xcb),
            "snow" | "snow1" => (0xff, 0xfa, 0xfa),
            "azure" | "azure1" => (0xf0, 0xff, 0xff),
            "linen" => (0xfa, 0xf0, 0xe6),
            "tan" => (0xd2, 0xb4, 0x8c),
            "peru" => (0xcd, 0x85, 0x3f),
            "sienna" => (0xa0, 0x52, 0x2d),
            "salmon" => (0xfa, 0x80, 0x72),
            "bisque" => (0xff, 0xe4, 0xc4),
            _ => return None,
        })
    }

    fn format_color_response(&self, command: &str, color: Color) -> String {
        let (r, g, b) = self.resolve_color_rgb(color);
        let r16 = (r as u16) * 257;
        let g16 = (g as u16) * 257;
        let b16 = (b as u16) * 257;
        format!(
            "\x1b]{};rgb:{:04x}/{:04x}/{:04x}\x1b\\",
            command, r16, g16, b16
        )
    }

    /// Parse X11/xterm color specification to RGB tuple
    pub(crate) fn parse_color_spec(spec: &str) -> Option<(u8, u8, u8)> {
        let spec = spec.trim();

        if spec.is_empty() {
            return None;
        }

        let lower = spec.to_ascii_lowercase();
        if lower.starts_with("rgb:") || lower.starts_with("rgba:") {
            let offset = if lower.starts_with("rgba:") { 5 } else { 4 };
            let parts: Vec<&str> = spec[offset..].split('/').collect();
            if parts.len() != 3 && parts.len() != 4 {
                return None;
            }

            let r = Self::parse_rgb_color_component(parts[0])?;
            let g = Self::parse_rgb_color_component(parts[1])?;
            let b = Self::parse_rgb_color_component(parts[2])?;
            if parts.len() == 4 {
                Self::parse_rgb_color_component(parts[3])?;
            }
            return Some((r, g, b));
        }

        if spec.starts_with('#') {
            return Self::parse_hash_color_spec(spec);
        }

        if lower.starts_with("rgbi:") {
            return Self::parse_rgbi_color_spec(&lower);
        }

        Self::parse_named_color_spec(spec)
    }

    fn parse_osc21_color_value(spec: &str, allow_negative_alpha: bool) -> Option<Osc21ColorValue> {
        let (color_spec, alpha) = if let Some((color, alpha)) = spec.rsplit_once('@') {
            (color, Some(alpha.trim().parse::<f32>().ok()?))
        } else {
            (spec, None)
        };
        let alpha = match alpha {
            Some(alpha) if alpha.is_finite() => Some(if allow_negative_alpha {
                alpha.min(1.0)
            } else {
                alpha.clamp(0.0, 1.0)
            }),
            Some(_) => return None,
            None => None,
        };
        let (red, green, blue) = Self::parse_color_spec(color_spec)?;
        Some(Osc21ColorValue {
            color: Color::Rgb(red, green, blue),
            alpha,
        })
    }

    fn format_osc21_color_value(&self, value: Osc21ColorValue) -> String {
        let (red, green, blue) = self.resolve_color_rgb(value.color);
        let mut encoded = format!("rgb:{red:02x}/{green:02x}/{blue:02x}");
        if let Some(alpha) = value.alpha {
            let mut alpha = format!("{alpha:.3}");
            while alpha.ends_with('0') {
                alpha.pop();
            }
            if alpha.ends_with('.') {
                alpha.push('0');
            }
            encoded.push('@');
            encoded.push_str(&alpha);
        }
        encoded
    }

    fn osc21_query_value(&self, key: &str) -> Option<String> {
        if let Ok(index) = key.parse::<usize>() {
            let color = self.get_ansi_color(index)?;
            return Some(self.format_osc21_color_value(Osc21ColorValue {
                color,
                alpha: self.osc21_color_state.palette_alpha(index),
            }));
        }
        let special = Osc21SpecialColor::parse(key)?;
        Some(
            self.osc21_color_state
                .current(special)
                .map_or_else(String::new, |value| self.format_osc21_color_value(value)),
        )
    }

    fn apply_osc21_special(&mut self, key: Osc21SpecialColor, value: Option<Osc21ColorValue>) {
        self.osc21_color_state.set_current(key, value);
        match (key, value) {
            (Osc21SpecialColor::Foreground, Some(value)) => {
                self.set_dynamic_default_fg(value.color);
                self.osc21_color_state.set_current(key, Some(value));
            }
            (Osc21SpecialColor::Background, Some(value)) => {
                self.set_dynamic_default_bg(value.color);
                self.osc21_color_state.set_current(key, Some(value));
            }
            (Osc21SpecialColor::Cursor, Some(value)) => {
                self.set_dynamic_cursor_color(value.color);
                self.osc21_color_state.set_current(key, Some(value));
            }
            (Osc21SpecialColor::SelectionBackground, Some(value)) => {
                self.set_dynamic_selection_bg_color(value.color);
                self.osc21_color_state.set_current(key, Some(value));
            }
            (Osc21SpecialColor::SelectionForeground, Some(value)) => {
                self.set_dynamic_selection_fg_color(value.color);
                self.osc21_color_state.set_current(key, Some(value));
            }
            (Osc21SpecialColor::Cursor, None) => {
                self.set_dynamic_cursor_color(self.default_fg);
                self.osc21_color_state.set_current(key, None);
            }
            _ => {}
        }
    }

    fn reset_osc21_special(&mut self, key: Osc21SpecialColor) {
        let value = self.osc21_color_state.reset(key);
        self.apply_osc21_special(key, value);
    }

    fn handle_osc21_color_control(&mut self, params: &[&[u8]]) {
        let mut query_fields = Vec::new();
        for parameter in params.iter().skip(1) {
            let Ok(parameter) = std::str::from_utf8(parameter) else {
                continue;
            };
            if parameter.is_empty() || parameter.len() > 256 {
                continue;
            }
            let (key, value) = parameter
                .split_once('=')
                .map_or((parameter, None), |(key, value)| (key, Some(value)));
            if key.is_empty()
                || key.len() > 64
                || !key
                    .bytes()
                    .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'_')
            {
                continue;
            }

            if value == Some("?") {
                let value = self
                    .osc21_query_value(key)
                    .unwrap_or_else(|| "?".to_string());
                query_fields.push(format!("{key}={value}"));
                continue;
            }
            if self.disable_insecure_sequences {
                continue;
            }

            if let Ok(index) = key.parse::<usize>() {
                if index >= 256 {
                    continue;
                }
                match value {
                    None => self.reset_dynamic_ansi_palette_color(index),
                    Some("") => {}
                    Some(value) => {
                        if let Some(color) = Self::parse_osc21_color_value(value, false) {
                            self.set_dynamic_ansi_palette_color(index, color.color);
                            self.osc21_color_state.set_palette_alpha(index, color.alpha);
                        }
                    }
                }
                continue;
            }

            let Some(special) = Osc21SpecialColor::parse(key) else {
                continue;
            };
            match value {
                None => self.reset_osc21_special(special),
                Some("") => self.apply_osc21_special(special, None),
                Some(value) => {
                    if let Some(color) =
                        Self::parse_osc21_color_value(value, special.transparent_slot().is_some())
                    {
                        self.apply_osc21_special(special, Some(color));
                    }
                }
            }
        }

        if query_fields.is_empty() {
            return;
        }
        let mut response = String::from("\x1b]21");
        for field in query_fields {
            if response.len().saturating_add(field.len()).saturating_add(3)
                > MAX_OSC21_RESPONSE_BYTES
            {
                break;
            }
            response.push(';');
            response.push_str(&field);
        }
        response.push_str("\x1b\\");
        self.push_response(response.as_bytes());
    }

    pub(crate) fn handle_osc_color(&mut self, command: &str, params: &[&[u8]]) {
        match command {
            "21" => self.handle_osc21_color_control(params),
            "4" => {
                // Set or query ANSI color palette entries (OSC 4).
                for pair in params[1..].chunks_exact(2) {
                    if let Ok(index_data) = std::str::from_utf8(pair[0]) {
                        if let Ok(index) = index_data.trim().parse::<usize>() {
                            if let Ok(colorspec) = std::str::from_utf8(pair[1]) {
                                let colorspec = colorspec.trim();
                                if colorspec == "?" {
                                    if let Some(color) = self.get_ansi_color(index) {
                                        let command = format!("4;{index}");
                                        let response = self.format_color_response(&command, color);
                                        self.push_response(response.as_bytes());
                                    }
                                } else if !self.disable_insecure_sequences {
                                    if let Some((r, g, b)) = Self::parse_color_spec(colorspec) {
                                        self.set_dynamic_ansi_palette_color(
                                            index,
                                            Color::Rgb(r, g, b),
                                        );
                                    }
                                }
                            }
                        }
                    }
                }
            }
            "104" => {
                // Reset ANSI color palette (OSC 104)
                if !self.disable_insecure_sequences {
                    let indices = &params[1..];
                    if indices.is_empty() || indices.iter().all(|index| index.is_empty()) {
                        self.reset_dynamic_ansi_palette();
                    } else {
                        // xterm accepts a list of palette indices for OSC 104.
                        // Invalid and empty entries are ignored independently.
                        for data in indices {
                            if let Ok(data) = std::str::from_utf8(data) {
                                if let Ok(index) = data.trim().parse::<usize>() {
                                    self.reset_dynamic_ansi_palette_color(index);
                                }
                            }
                        }
                    }
                }
            }
            "10" | "11" | "12" => {
                // Query or set default colors
                if params.len() >= 2 {
                    if let Ok(data) = std::str::from_utf8(params[1]) {
                        let data = data.trim();
                        if data == "?" {
                            let color = match command {
                                "10" => self.default_fg,
                                "11" => self.default_bg,
                                "12" => self.cursor_color,
                                _ => unreachable!(),
                            };
                            let response = self.format_color_response(command, color);
                            self.push_response(response.as_bytes());
                        } else if !self.disable_insecure_sequences {
                            if let Some((r, g, b)) = Self::parse_color_spec(data) {
                                match command {
                                    "10" => self.set_dynamic_default_fg(Color::Rgb(r, g, b)),
                                    "11" => self.set_dynamic_default_bg(Color::Rgb(r, g, b)),
                                    "12" => self.set_dynamic_cursor_color(Color::Rgb(r, g, b)),
                                    _ => unreachable!(),
                                }
                            }
                        }
                    }
                }
            }
            "110" => {
                if !self.disable_insecure_sequences {
                    self.set_dynamic_default_fg(self.baseline_default_fg);
                }
            }
            "111" => {
                if !self.disable_insecure_sequences {
                    self.set_dynamic_default_bg(self.baseline_default_bg);
                }
            }
            "112" => {
                if !self.disable_insecure_sequences {
                    self.set_dynamic_cursor_color(self.baseline_cursor_color);
                }
            }
            _ => {}
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::terminal::color_control::Osc21SpecialColor;

    #[test]
    fn osc21_batches_set_query_dynamic_unknown_and_alpha_fields_in_order() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(
            b"\x1b]21;foreground=#123;background=rgbi:0/0.5/1;0=red4;cursor=#abcdef@0.5;cursor_text=;visual_bell=orange;transparent_background_color1=#112233@-1;foreground=?;background=?;0=?;cursor=?;cursor_text=?;visual_bell=?;transparent_background_color1=?;future_key=?\x1b\\",
        );

        assert_eq!(terminal.default_fg(), Color::Rgb(0x10, 0x20, 0x30));
        assert_eq!(terminal.default_bg(), Color::Rgb(0x00, 0x80, 0xff));
        assert_eq!(terminal.get_ansi_color(0), Some(Color::Rgb(0x8b, 0, 0)));
        assert_eq!(terminal.cursor_color(), Color::Rgb(0xab, 0xcd, 0xef));
        assert_eq!(
            terminal
                .osc21_color_state
                .current(Osc21SpecialColor::CursorText),
            None
        );
        assert_eq!(
            terminal.drain_responses(),
            b"\x1b]21;foreground=rgb:10/20/30;background=rgb:00/80/ff;0=rgb:8b/00/00;cursor=rgb:ab/cd/ef@0.5;cursor_text=;visual_bell=rgb:ff/a5/00;transparent_background_color1=rgb:11/22/33@-1.0;future_key=?\x1b\\"
        );
    }

    #[test]
    fn osc21_bare_keys_restore_profile_baselines_and_invalid_fields_are_isolated() {
        let mut terminal = Terminal::new(80, 24);
        terminal.set_default_fg(Color::Rgb(1, 2, 3));
        terminal.set_default_bg(Color::Rgb(4, 5, 6));
        terminal.set_cursor_color(Color::Rgb(7, 8, 9));
        terminal
            .set_ansi_palette_color(196, Color::Rgb(10, 11, 12))
            .unwrap();

        terminal.process(
            b"\x1b]21;foreground=#aabbcc;bad key=#ffffff;196=#ddeeff;cursor=not-a-color;background=#112233\x1b\\",
        );
        assert_eq!(terminal.default_fg(), Color::Rgb(0xaa, 0xbb, 0xcc));
        assert_eq!(terminal.default_bg(), Color::Rgb(0x11, 0x22, 0x33));
        assert_eq!(terminal.cursor_color(), Color::Rgb(7, 8, 9));
        assert_eq!(
            terminal.get_ansi_color(196),
            Some(Color::Rgb(0xdd, 0xee, 0xff))
        );

        terminal.process(b"\x1b]21;foreground;background;cursor;196;foreground=?;background=?;cursor=?;196=?\x1b\\");
        assert_eq!(terminal.default_fg(), Color::Rgb(1, 2, 3));
        assert_eq!(terminal.default_bg(), Color::Rgb(4, 5, 6));
        assert_eq!(terminal.cursor_color(), Color::Rgb(7, 8, 9));
        assert_eq!(terminal.get_ansi_color(196), Some(Color::Rgb(10, 11, 12)));
        assert_eq!(
            terminal.drain_responses(),
            b"\x1b]21;foreground=rgb:01/02/03;background=rgb:04/05/06;cursor=rgb:07/08/09;196=rgb:0a/0b/0c\x1b\\"
        );
    }

    #[test]
    fn osc21_state_survives_snapshot_and_ris_resets_runtime_to_baselines() {
        let mut terminal = Terminal::new(80, 24);
        terminal.set_default_fg(Color::Rgb(1, 2, 3));
        terminal.process(
            b"\x1b]21;foreground=#abcdef;visual_bell=#112233;transparent_background_color7=#445566@0.25\x1b\\",
        );
        let snapshot = terminal.capture_snapshot();

        terminal.process(b"\x1b]21;foreground=#000000;visual_bell=\x1b\\");
        terminal.restore_from_snapshot(snapshot);
        terminal
            .process(b"\x1b]21;foreground=?;visual_bell=?;transparent_background_color7=?\x1b\\");
        assert_eq!(
            terminal.drain_responses(),
            b"\x1b]21;foreground=rgb:ab/cd/ef;visual_bell=rgb:11/22/33;transparent_background_color7=rgb:44/55/66@0.25\x1b\\"
        );

        terminal.reset();
        terminal
            .process(b"\x1b]21;foreground=?;visual_bell=?;transparent_background_color7=?\x1b\\");
        assert_eq!(
            terminal.drain_responses(),
            b"\x1b]21;foreground=rgb:01/02/03;visual_bell=;transparent_background_color7=\x1b\\"
        );
    }

    #[test]
    fn osc21_survives_every_byte_split_with_bel_or_st() {
        for terminator in [b"\x07".as_slice(), b"\x1b\\".as_slice()] {
            let mut sequence = b"\x1b]21;foreground=#123456;foreground=?".to_vec();
            sequence.extend_from_slice(terminator);
            for split in 1..sequence.len() {
                let mut terminal = Terminal::new(80, 24);
                terminal.process(&sequence[..split]);
                terminal.process(&sequence[split..]);
                assert_eq!(terminal.default_fg(), Color::Rgb(0x12, 0x34, 0x56));
                assert_eq!(
                    terminal.drain_responses(),
                    b"\x1b]21;foreground=rgb:12/34/56\x1b\\",
                    "split={split}, terminator={terminator:?}"
                );
            }
        }
    }

    #[test]
    fn osc21_enforces_vte_fifteen_field_ceiling_and_recovers_next_sequence() {
        let mut terminal = Terminal::new(80, 24);
        let fields = (0..15)
            .map(|index| format!("{index}=#010203"))
            .collect::<Vec<_>>()
            .join(";");
        terminal.process(format!("\x1b]21;{fields};foreground=#abcdef\x1b\\").as_bytes());

        assert_eq!(terminal.get_ansi_color(14), Some(Color::Rgb(1, 2, 3)));
        assert_ne!(terminal.default_fg(), Color::Rgb(0xab, 0xcd, 0xef));

        terminal.process(b"\x1b]21;foreground=#abcdef;foreground=?\x1b\\");
        assert_eq!(terminal.default_fg(), Color::Rgb(0xab, 0xcd, 0xef));
        assert_eq!(
            terminal.drain_responses(),
            b"\x1b]21;foreground=rgb:ab/cd/ef\x1b\\"
        );
    }
}
