//! Color-related OSC sequence handling

use crate::color::Color;
use crate::terminal::Terminal;

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

        None
    }

    pub(crate) fn handle_osc_color(&mut self, command: &str, params: &[&[u8]]) {
        match command {
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
