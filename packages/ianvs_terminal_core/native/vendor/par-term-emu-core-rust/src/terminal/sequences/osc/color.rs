//! Color-related OSC sequence handling

use crate::color::Color;
use crate::terminal::color_control::{Osc21ColorValue, Osc21SpecialColor};
use crate::terminal::Terminal;

const MAX_OSC21_RESPONSE_BYTES: usize = 4 * 1024;

impl Terminal {
    fn handle_iterm_tab_color_components(&mut self, params: &[&[u8]]) -> bool {
        if params.get(1) != Some(&b"1".as_slice()) || params.get(2) != Some(&b"bg".as_slice()) {
            return false;
        }

        if params.len() == 5 && params[3] == b"*" && params[4] == b"default" {
            self.set_dynamic_iterm_tab_color(None);
            return true;
        }

        if params.len() != 6 || params[4] != b"brightness" {
            return true;
        }
        let Ok(value) = std::str::from_utf8(params[5]) else {
            return true;
        };
        if value.is_empty() || !value.bytes().all(|byte| byte.is_ascii_digit()) {
            return true;
        }
        let Ok(value) = value.parse::<u8>() else {
            return true;
        };
        let (mut red, mut green, mut blue) = self
            .iterm_tab_color()
            .map(|color| self.resolve_color_rgb(color))
            .unwrap_or((0, 0, 0));
        match params[3] {
            b"red" => red = value,
            b"green" => green = value,
            b"blue" => blue = value,
            _ => return true,
        }
        self.set_dynamic_iterm_tab_color(Some(Color::Rgb(red, green, blue)));
        true
    }

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
                self.set_dynamic_selected_text_color_enabled(true);
                self.osc21_color_state.set_current(key, Some(value));
            }
            (Osc21SpecialColor::Cursor, None) => {
                self.set_dynamic_cursor_color(self.default_fg);
                self.osc21_color_state.set_current(key, None);
            }
            (Osc21SpecialColor::SelectionForeground, None) => {
                self.set_dynamic_selected_text_color_enabled(false);
            }
            _ => {}
        }
    }

    fn reset_osc21_special(&mut self, key: Osc21SpecialColor) {
        let value = self.osc21_color_state.reset(key);
        self.apply_osc21_special(key, value);
        if key == Osc21SpecialColor::SelectionForeground {
            let enabled = self.osc21_color_state.reset_selection_foreground_enabled();
            self.set_dynamic_selected_text_color_enabled(enabled);
        }
    }

    fn handle_xterm_special_color(&mut self, params: &[&[u8]]) {
        for pair in params[1..].chunks_exact(2) {
            let (Some(index), Ok(spec)) = (
                std::str::from_utf8(pair[0])
                    .ok()
                    .and_then(|value| value.trim().parse::<usize>().ok()),
                std::str::from_utf8(pair[1]),
            ) else {
                continue;
            };
            if index >= 5 {
                continue;
            }
            let spec = spec.trim();
            if spec == "?" {
                if let Some(color) = self.xterm_special_color(index) {
                    let command = format!("5;{index}");
                    let response = self.format_color_response(&command, color);
                    self.push_response(response.as_bytes());
                }
            } else if !self.disable_insecure_sequences {
                if let Some((red, green, blue)) = Self::parse_color_spec(spec) {
                    self.set_dynamic_xterm_special_color(index, Color::Rgb(red, green, blue));
                }
            }
        }
    }

    fn handle_xterm_special_color_mode(&mut self, params: &[&[u8]]) {
        if self.disable_insecure_sequences {
            return;
        }
        for pair in params[1..].chunks_exact(2) {
            let (Some(index), Some(flag)) = (
                std::str::from_utf8(pair[0])
                    .ok()
                    .and_then(|value| value.trim().parse::<usize>().ok()),
                std::str::from_utf8(pair[1])
                    .ok()
                    .and_then(|value| value.trim().parse::<i64>().ok()),
            ) else {
                continue;
            };
            if index < 6 {
                self.set_dynamic_xterm_special_mode(index, flag != 0);
            }
        }
    }

    fn reset_xterm_special_colors(&mut self, params: &[&[u8]]) {
        if self.disable_insecure_sequences {
            return;
        }
        let reset_all = params.len() <= 1 || params.iter().skip(1).all(|value| value.is_empty());
        let indices = params.iter().skip(1).filter_map(|value| {
            std::str::from_utf8(value)
                .ok()
                .and_then(|value| value.trim().parse::<usize>().ok())
        });
        let indices = indices.collect::<Vec<_>>();
        if reset_all {
            for index in 0..5 {
                self.reset_dynamic_xterm_special_color(index);
            }
        } else {
            for index in indices {
                if index < 5 {
                    self.reset_dynamic_xterm_special_color(index);
                }
            }
        }
    }

    fn handle_xterm_dynamic_colors(&mut self, start_command: usize, params: &[&[u8]]) {
        for (offset, parameter) in params.iter().skip(1).enumerate() {
            let command = start_command.saturating_add(offset);
            if command > 19 {
                break;
            }
            let Ok(spec) = std::str::from_utf8(parameter) else {
                continue;
            };
            let spec = spec.trim();
            if spec == "?" {
                if let Some(color) = self.xterm_dynamic_color(command) {
                    let response = self.format_color_response(&command.to_string(), color);
                    self.push_response(response.as_bytes());
                }
            } else if !self.disable_insecure_sequences {
                if let Some((red, green, blue)) = Self::parse_color_spec(spec) {
                    self.set_dynamic_xterm_color(command, Color::Rgb(red, green, blue));
                }
            }
        }
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
            "5" => self.handle_xterm_special_color(params),
            "6" => {
                if !self.handle_iterm_tab_color_components(params) {
                    self.handle_xterm_special_color_mode(params);
                }
            }
            "106" => self.handle_xterm_special_color_mode(params),
            "4" => {
                // Set or query ANSI color palette entries (OSC 4).
                for pair in params[1..].chunks_exact(2) {
                    if let Ok(index_data) = std::str::from_utf8(pair[0]) {
                        if let Ok(index) = index_data.trim().parse::<i32>() {
                            if let Ok(colorspec) = std::str::from_utf8(pair[1]) {
                                let colorspec = colorspec.trim();
                                if colorspec == "?" {
                                    let color = match index {
                                        -2 => Some(self.default_bg()),
                                        -1 => Some(self.default_fg()),
                                        0..=255 => self.get_ansi_color(index as usize),
                                        256..=260 => self.xterm_special_color(index as usize - 256),
                                        _ => None,
                                    };
                                    if let Some(color) = color {
                                        let command = format!("4;{index}");
                                        let response = self.format_color_response(&command, color);
                                        self.push_response(response.as_bytes());
                                    }
                                } else if !self.disable_insecure_sequences {
                                    if let Some((r, g, b)) = Self::parse_color_spec(colorspec) {
                                        let color = Color::Rgb(r, g, b);
                                        if (0..=255).contains(&index) {
                                            self.set_dynamic_ansi_palette_color(
                                                index as usize,
                                                color,
                                            );
                                        } else if (256..=260).contains(&index) {
                                            self.set_dynamic_xterm_special_color(
                                                index as usize - 256,
                                                color,
                                            );
                                        }
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
                                    if index < 256 {
                                        self.reset_dynamic_ansi_palette_color(index);
                                    } else if let Some(index) = index.checked_sub(256) {
                                        if index < 5 {
                                            self.reset_dynamic_xterm_special_color(index);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            "10" | "11" | "12" | "13" | "14" | "15" | "16" | "17" | "18" | "19" => {
                if let Ok(start_command) = command.parse::<usize>() {
                    self.handle_xterm_dynamic_colors(start_command, params);
                }
            }
            "105" => self.reset_xterm_special_colors(params),
            "110" | "111" | "112" | "113" | "114" | "115" | "116" | "117" | "118" | "119" => {
                if !self.disable_insecure_sequences {
                    if let Ok(command) = command.parse::<usize>() {
                        self.reset_dynamic_xterm_color(command.saturating_sub(100));
                    }
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
    use crate::terminal::OscCapability;

    #[test]
    fn iterm_osc4_negative_indices_query_defaults_without_allowing_mutation() {
        let mut terminal = Terminal::new(80, 24);
        terminal.set_default_fg(Color::Rgb(0x12, 0x34, 0x56));
        terminal.set_default_bg(Color::Rgb(0x65, 0x43, 0x21));
        terminal.process(b"\x1b]4;-2;?;-1;?;-3;?\x1b\\");

        assert_eq!(
            terminal.drain_responses(),
            b"\x1b]4;-2;rgb:6565/4343/2121\x1b\\\x1b]4;-1;rgb:1212/3434/5656\x1b\\"
        );

        terminal.process(b"\x1b]4;-2;#ffffff;-1;#000000\x1b\\");
        assert_eq!(terminal.default_fg(), Color::Rgb(0x12, 0x34, 0x56));
        assert_eq!(terminal.default_bg(), Color::Rgb(0x65, 0x43, 0x21));
    }

    #[test]
    fn xterm_special_colors_modes_queries_and_targeted_resets_are_independent() {
        let mut terminal = Terminal::new(80, 24);
        terminal.set_default_fg(Color::Rgb(1, 2, 3));
        terminal.set_bold_color(Color::Rgb(4, 5, 6));
        terminal.process(b"\x1b]5;0;#aabbcc;1;rgb:11/22/33;2;red;3;green;4;blue;0;?;4;?\x1b\\");
        assert_eq!(
            terminal.xterm_special_color(0),
            Some(Color::Rgb(0xaa, 0xbb, 0xcc))
        );
        assert_eq!(
            terminal.xterm_special_color(4),
            Some(Color::Rgb(0, 0, 0xff))
        );
        assert_eq!(
            terminal.drain_responses(),
            b"\x1b]5;0;rgb:aaaa/bbbb/cccc\x1b\\\x1b]5;4;rgb:0000/0000/ffff\x1b\\"
        );

        terminal.process(b"\x1b]6;0;1;1;-2;2;0;3;1;4;1\x1b\\");
        assert_eq!(terminal.xterm_special_color_mode(0), Some(true));
        assert_eq!(terminal.xterm_special_color_mode(1), Some(true));
        assert_eq!(terminal.xterm_special_color_mode(2), Some(false));
        assert_eq!(terminal.xterm_special_color_mode(3), Some(true));
        assert_eq!(terminal.xterm_special_color_mode(4), Some(true));
        assert_eq!(terminal.xterm_special_color_mode(5), Some(false));

        terminal.process(b"\x1b]106;0;0;5;1\x1b\\");
        assert_eq!(terminal.xterm_special_color_mode(0), Some(false));
        assert_eq!(terminal.xterm_special_color_mode(5), Some(true));
        terminal.process(b"\x1b]106\x1b\\");
        assert_eq!(terminal.xterm_special_color_mode(5), Some(true));

        terminal.process(b"\x1b]4;260;#090807;260;?\x1b\\");
        assert_eq!(terminal.xterm_special_color(4), Some(Color::Rgb(9, 8, 7)));
        assert_eq!(
            terminal.drain_responses(),
            b"\x1b]4;260;rgb:0909/0808/0707\x1b\\"
        );
        terminal.process(b"\x1b]104;260\x1b\\");
        assert_eq!(terminal.xterm_special_color(4), Some(Color::Rgb(1, 2, 3)));

        terminal.process(b"\x1b]105;0;bad;9\x1b\\");
        assert_eq!(terminal.xterm_special_color(0), Some(Color::Rgb(4, 5, 6)));
        assert_eq!(
            terminal.xterm_special_color(1),
            Some(Color::Rgb(0x11, 0x22, 0x33))
        );
        assert_eq!(terminal.xterm_special_color_mode(0), Some(false));
        assert_eq!(terminal.xterm_special_color_mode(1), Some(true));

        terminal.process(b"\x1b]105\x1b\\\x1b]6;1;0;2;0;3;0;4;0;5;0\x1b\\");
        for index in 0..6 {
            assert_eq!(terminal.xterm_special_color_mode(index), Some(false));
        }
        assert_eq!(terminal.xterm_special_color(1), Some(Color::Rgb(1, 2, 3)));
    }

    #[test]
    fn iterm_osc6_tab_color_updates_incrementally_and_restores_profile_baseline() {
        let mut terminal = Terminal::new(80, 24);
        terminal.set_iterm_tab_color_baseline(Some(Color::Rgb(0x10, 0x20, 0x30)));

        let sequence = b"\x1b]6;1;bg;red;brightness;255\x07\x1b]6;1;bg;green;brightness;128\x1b\\\x1b]6;1;bg;blue;brightness;64\x07";
        for byte in sequence.chunks(1) {
            terminal.process(byte);
        }
        assert_eq!(
            terminal.iterm_tab_color(),
            Some(Color::Rgb(0xff, 0x80, 0x40))
        );

        let snapshot = terminal.capture_snapshot();
        terminal.process(b"\x1b]6;1;bg;red;brightness;1\x07");
        assert_eq!(
            terminal.iterm_tab_color(),
            Some(Color::Rgb(0x01, 0x80, 0x40))
        );
        terminal.restore_from_snapshot(snapshot);
        assert_eq!(
            terminal.iterm_tab_color(),
            Some(Color::Rgb(0xff, 0x80, 0x40))
        );

        terminal.process(b"\x1b]6;1;bg;*;default\x1b\\");
        assert_eq!(
            terminal.iterm_tab_color(),
            Some(Color::Rgb(0x10, 0x20, 0x30))
        );

        terminal.process(b"\x1b]6;1;bg;blue;brightness;255\x07\x1bc");
        assert_eq!(
            terminal.iterm_tab_color(),
            Some(Color::Rgb(0x10, 0x20, 0x30))
        );
    }

    #[test]
    fn iterm_osc6_tab_color_rejects_near_matches_without_breaking_xterm_modes() {
        let mut terminal = Terminal::new(80, 24);
        terminal.set_iterm_tab_color_baseline(Some(Color::Rgb(1, 2, 3)));
        for invalid in [
            b"\x1b]6;1;bg;red;brightness;256\x07".as_slice(),
            b"\x1b]6;1;bg;red;brightness;-1\x07".as_slice(),
            b"\x1b]6;1;bg;red;brightness;1x\x07".as_slice(),
            b"\x1b]6;1;bg;RED;brightness;1\x07".as_slice(),
            b"\x1b]6;1;bg;red;Brightness;1\x07".as_slice(),
            b"\x1b]6;1;bg;*;DEFAULT\x07".as_slice(),
            b"\x1b]6;1;bg;*;default;extra\x07".as_slice(),
        ] {
            terminal.process(invalid);
        }
        assert_eq!(terminal.iterm_tab_color(), Some(Color::Rgb(1, 2, 3)));

        terminal.process(b"\x1b]6;0;1;1;0\x1b\\");
        assert_eq!(terminal.xterm_special_color_mode(0), Some(true));
        assert_eq!(terminal.xterm_special_color_mode(1), Some(false));
        assert_eq!(terminal.iterm_tab_color(), Some(Color::Rgb(1, 2, 3)));
    }

    #[test]
    fn iterm_osc6_tab_color_respects_the_appearance_policy_gate() {
        let mut terminal = Terminal::new(80, 24);
        terminal.set_iterm_tab_color_baseline(Some(Color::Rgb(1, 2, 3)));
        terminal.set_osc_capability_allowed(OscCapability::Appearance, false);

        terminal.process(b"\x1b]6;1;bg;red;brightness;255\x07");

        assert_eq!(terminal.iterm_tab_color(), Some(Color::Rgb(1, 2, 3)));
    }

    #[test]
    fn xterm_dynamic_colors_apply_sequentially_query_and_reset_profile_baselines() {
        let mut terminal = Terminal::new(80, 24);
        terminal.set_default_fg(Color::Rgb(1, 2, 3));
        terminal.set_default_bg(Color::Rgb(4, 5, 6));
        terminal.set_cursor_color(Color::Rgb(7, 8, 9));
        terminal.set_selection_bg_color(Color::Rgb(10, 11, 12));
        terminal.set_selection_fg_color(Color::Rgb(13, 14, 15));
        terminal.process(
            b"\x1b]13;#130000;#140000;#150000;#160000;#170000;#180000;#190000;#ignored\x1b\\",
        );
        assert_eq!(terminal.get_selection_bg_color(), Color::Rgb(0x17, 0, 0));
        assert_eq!(terminal.get_selection_fg_color(), Color::Rgb(0x19, 0, 0));
        assert!(terminal.selection_foreground_color_enabled());

        terminal.process(b"\x1b]13;?;?;?;?;?;?;?\x1b\\");
        assert_eq!(
            terminal.drain_responses(),
            b"\x1b]13;rgb:1313/0000/0000\x1b\\\x1b]14;rgb:1414/0000/0000\x1b\\\x1b]15;rgb:1515/0000/0000\x1b\\\x1b]16;rgb:1616/0000/0000\x1b\\\x1b]17;rgb:1717/0000/0000\x1b\\\x1b]18;rgb:1818/0000/0000\x1b\\\x1b]19;rgb:1919/0000/0000\x1b\\"
        );

        terminal.process(b"\x1b]117\x1b\\\x1b]119\x1b\\");
        assert_eq!(terminal.get_selection_bg_color(), Color::Rgb(10, 11, 12));
        assert_eq!(terminal.get_selection_fg_color(), Color::Rgb(13, 14, 15));
        assert!(!terminal.selection_foreground_color_enabled());

        terminal.process(b"\x1b]10;#101010;#111111;#121212;?\x1b\\");
        assert_eq!(terminal.default_fg(), Color::Rgb(0x10, 0x10, 0x10));
        assert_eq!(terminal.default_bg(), Color::Rgb(0x11, 0x11, 0x11));
        assert_eq!(terminal.cursor_color(), Color::Rgb(0x12, 0x12, 0x12));
        assert_eq!(
            terminal.drain_responses(),
            b"\x1b]13;rgb:1313/0000/0000\x1b\\"
        );
    }

    #[test]
    fn xterm_color_state_survives_every_byte_split_and_ris_restores_baselines() {
        let sequence =
            b"\x1b]5;0;#abcdef\x1b\\\x1b]6;0;1\x1b\\\x1b]17;#123456;#181818;#654321\x1b\\";
        for split in 0..=sequence.len() {
            let mut terminal = Terminal::new(80, 24);
            terminal.process(&sequence[..split]);
            terminal.process(&sequence[split..]);
            assert_eq!(
                terminal.xterm_special_color(0),
                Some(Color::Rgb(0xab, 0xcd, 0xef))
            );
            assert_eq!(terminal.xterm_special_color_mode(0), Some(true));
            assert_eq!(
                terminal.get_selection_bg_color(),
                Color::Rgb(0x12, 0x34, 0x56)
            );
            assert_eq!(
                terminal.get_selection_fg_color(),
                Color::Rgb(0x65, 0x43, 0x21)
            );
            assert!(terminal.selection_foreground_color_enabled());

            let snapshot = terminal.capture_snapshot();
            terminal.process(b"\x1b]105\x1b\\\x1b]106;0;0\x1b\\\x1b]119\x1b\\");
            terminal.restore_from_snapshot(snapshot);
            assert_eq!(terminal.xterm_special_color_mode(0), Some(true));

            terminal.reset();
            assert_eq!(
                terminal.xterm_special_color(0),
                Some(Color::Named(crate::color::NamedColor::White))
            );
            assert_eq!(terminal.xterm_special_color_mode(0), Some(false));
            assert_eq!(
                terminal.get_selection_bg_color(),
                Color::Rgb(0xb5, 0xd5, 0xff)
            );
            assert!(!terminal.selection_foreground_color_enabled());
        }
    }

    #[test]
    fn xterm_special_pairs_obey_vte_field_ceiling_and_recover_next_sequence() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(
            b"\x1b]5;0;red;0;green;0;blue;0;yellow;0;cyan;0;magenta;0;#010203;0;#abcdef\x1b\\\x1b]5;0;?\x1b\\",
        );

        assert_eq!(terminal.xterm_special_color(0), Some(Color::Rgb(1, 2, 3)));
        assert_eq!(
            terminal.drain_responses(),
            b"\x1b]5;0;rgb:0101/0202/0303\x1b\\"
        );
    }

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
