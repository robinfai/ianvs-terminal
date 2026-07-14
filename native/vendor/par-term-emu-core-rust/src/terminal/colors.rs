//! Terminal color configuration and management
//!
//! Handles terminal color settings including:
//! - ANSI/xterm palette (256 colors)
//! - Default foreground/background colors
//! - Cursor color
//! - Selection colors
//! - Link colors
//! - Bold text colors
//! - Color mode flags

use crate::cell::CellFlags;
use crate::color::Color;
use crate::terminal::color_control::{Osc21ColorValue, Osc21SpecialColor};
use crate::terminal::Terminal;

impl Terminal {
    /// Get default ANSI color palette
    pub(super) fn default_ansi_palette() -> [Color; 16] {
        [
            // Standard colors (0-7)
            Color::Rgb(0x14, 0x19, 0x1E), // 0: Black
            Color::Rgb(0xB4, 0x3C, 0x2A), // 1: Red
            Color::Rgb(0x00, 0x81, 0x5B), // 2: Green
            Color::Rgb(0xCF, 0xA5, 0x18), // 3: Yellow
            Color::Rgb(0x30, 0x65, 0xB8), // 4: Blue
            Color::Rgb(0x88, 0x18, 0xA3), // 5: Magenta
            Color::Rgb(0x00, 0x93, 0x99), // 6: Cyan
            Color::Rgb(0xE5, 0xE5, 0xE5), // 7: White
            // Bright colors (8-15)
            Color::Rgb(0x68, 0x73, 0x78), // 8: Bright Black
            Color::Rgb(0xFF, 0x61, 0x48), // 9: Bright Red
            Color::Rgb(0x00, 0xC9, 0x84), // 10: Bright Green
            Color::Rgb(0xFF, 0xC5, 0x31), // 11: Bright Yellow
            Color::Rgb(0x4F, 0x9C, 0xFE), // 12: Bright Blue
            Color::Rgb(0xC5, 0x4F, 0xFF), // 13: Bright Magenta
            Color::Rgb(0x00, 0xCC, 0xCC), // 14: Bright Cyan
            Color::Rgb(0xFF, 0xFF, 0xFF), // 15: Bright White
        ]
    }

    /// Get the default extended xterm color palette (indices 16-255).
    pub(super) fn default_extended_ansi_palette() -> [Color; 240] {
        std::array::from_fn(|offset| Color::Indexed((offset + 16) as u8))
    }

    pub(crate) fn sync_grid_blank_style(&mut self) {
        self.grid.set_blank_style(self.default_fg, self.default_bg);
        self.alt_grid
            .set_blank_style(self.default_fg, self.default_bg);
    }

    /// Get default foreground color (OSC 10)
    pub fn default_fg(&self) -> Color {
        self.default_fg
    }

    /// Set default foreground color (OSC 10)
    pub fn set_default_fg(&mut self, color: Color) {
        self.baseline_default_fg = color;
        self.osc21_color_state.set_baseline(
            Osc21SpecialColor::Foreground,
            Osc21ColorValue::opaque(color),
        );
        for command in [10, 13, 15, 18] {
            self.osc21_color_state
                .set_xterm_dynamic_baseline(command, color);
        }
        for index in 0..5 {
            self.osc21_color_state
                .set_xterm_special_baseline(index, color);
        }
        self.set_dynamic_default_fg(color);
    }

    pub(crate) fn set_dynamic_default_fg(&mut self, color: Color) {
        self.osc21_color_state.set_xterm_dynamic(10, color);
        self.osc21_color_state.set_current(
            Osc21SpecialColor::Foreground,
            Some(Osc21ColorValue::opaque(color)),
        );
        let previous = self.default_fg;
        if previous == color {
            return;
        }
        self.default_fg = color;
        if self.flags.fg_is_default() {
            self.fg = color;
        }
        if self.saved_flags.fg_is_default() {
            self.saved_fg = color;
        }
        self.replace_default_fg_in_cells(color);
        self.sync_grid_blank_style();
        self.mark_full_repaint("default_color_changed");
    }

    /// Get default background color (OSC 11)
    pub fn default_bg(&self) -> Color {
        self.default_bg
    }

    /// Set default background color (OSC 11)
    pub fn set_default_bg(&mut self, color: Color) {
        self.baseline_default_bg = color;
        self.osc21_color_state.set_baseline(
            Osc21SpecialColor::Background,
            Osc21ColorValue::opaque(color),
        );
        for command in [11, 14, 16] {
            self.osc21_color_state
                .set_xterm_dynamic_baseline(command, color);
        }
        self.set_dynamic_default_bg(color);
    }

    pub(crate) fn set_dynamic_default_bg(&mut self, color: Color) {
        self.osc21_color_state.set_xterm_dynamic(11, color);
        self.osc21_color_state.set_current(
            Osc21SpecialColor::Background,
            Some(Osc21ColorValue::opaque(color)),
        );
        let previous = self.default_bg;
        if previous == color {
            return;
        }
        self.default_bg = color;
        if self.flags.bg_is_default() {
            self.bg = color;
        }
        if self.saved_flags.bg_is_default() {
            self.saved_bg = color;
        }
        self.replace_default_bg_in_cells(color);
        self.sync_grid_blank_style();
        self.mark_full_repaint("default_color_changed");
    }

    fn replace_default_fg_in_cells(&mut self, color: Color) {
        self.grid.replace_default_foreground(color);
        self.alt_grid.replace_default_foreground(color);
    }

    fn replace_default_bg_in_cells(&mut self, color: Color) {
        self.grid.replace_default_background(color);
        self.alt_grid.replace_default_background(color);
    }

    /// Get cursor color (OSC 12)
    pub fn cursor_color(&self) -> Color {
        self.cursor_color
    }

    /// Set cursor color (OSC 12)
    pub fn set_cursor_color(&mut self, color: Color) {
        self.baseline_cursor_color = color;
        self.osc21_color_state
            .set_baseline(Osc21SpecialColor::Cursor, Osc21ColorValue::opaque(color));
        self.osc21_color_state.set_xterm_dynamic_baseline(12, color);
        self.set_dynamic_cursor_color(color);
    }

    pub(crate) fn set_dynamic_cursor_color(&mut self, color: Color) {
        self.osc21_color_state.set_xterm_dynamic(12, color);
        self.osc21_color_state.set_current(
            Osc21SpecialColor::Cursor,
            Some(Osc21ColorValue::opaque(color)),
        );
        if self.cursor_color == color {
            return;
        }
        self.cursor_color = color;
        self.mark_full_repaint("cursor_color_changed");
    }

    /// Get link/hyperlink color
    pub fn link_color(&self) -> Color {
        self.link_color
    }

    /// Set link/hyperlink color
    pub fn set_link_color(&mut self, color: Color) {
        self.link_color = color;
    }

    /// Runtime iTerm2 bold-color override from OSC 1337 SetColors.
    pub fn iterm_bold_color(&self) -> Option<Color> {
        self.osc21_color_state.iterm_bold_color()
    }

    pub(crate) fn set_dynamic_iterm_bold_color(&mut self, color: Option<Color>) {
        if self.osc21_color_state.iterm_bold_color() == color {
            return;
        }
        self.osc21_color_state.set_iterm_bold_color(color);
        self.mark_full_repaint("iterm_bold_color_changed");
    }

    /// Runtime iTerm2 link-color override from OSC 1337 SetColors.
    pub fn iterm_link_color(&self) -> Option<Color> {
        self.osc21_color_state.iterm_link_color()
    }

    pub(crate) fn set_dynamic_iterm_link_color(&mut self, color: Option<Color>) {
        if self.osc21_color_state.iterm_link_color() == color {
            return;
        }
        self.osc21_color_state.set_iterm_link_color(color);
        self.mark_full_repaint("iterm_link_color_changed");
    }

    /// Runtime iTerm2 underline-decoration color from OSC 1337 SetColors.
    pub fn iterm_underline_color(&self) -> Option<Color> {
        self.osc21_color_state.iterm_underline_color()
    }

    pub(crate) fn set_dynamic_iterm_underline_color(&mut self, color: Option<Color>) {
        if self.osc21_color_state.iterm_underline_color() == color {
            return;
        }
        self.osc21_color_state.set_iterm_underline_color(color);
        self.mark_full_repaint("iterm_underline_color_changed");
    }

    /// Current iTerm2 tab color from the profile baseline or OSC overrides.
    pub fn iterm_tab_color(&self) -> Option<Color> {
        self.osc21_color_state.iterm_tab_color()
    }

    /// Configure the session/profile tab-color baseline used by iTerm2 resets.
    pub fn set_iterm_tab_color_baseline(&mut self, color: Option<Color>) {
        if self.osc21_color_state.iterm_tab_color() == color {
            self.osc21_color_state.set_iterm_tab_color_baseline(color);
            return;
        }
        self.osc21_color_state.set_iterm_tab_color_baseline(color);
        self.mark_full_repaint("iterm_tab_color_baseline_changed");
    }

    pub(crate) fn set_dynamic_iterm_tab_color(&mut self, color: Option<Color>) {
        let previous = self.osc21_color_state.iterm_tab_color();
        let color = match color {
            Some(color) => Some(color),
            None => self.osc21_color_state.reset_iterm_tab_color(),
        };
        if previous == color {
            return;
        }
        self.osc21_color_state.set_iterm_tab_color(color);
        self.mark_full_repaint("iterm_tab_color_changed");
    }

    /// Runtime iTerm2 cursor-text color from OSC 1337 SetColors.
    pub fn iterm_cursor_text_color(&self) -> Option<Color> {
        self.osc21_color_state
            .current(Osc21SpecialColor::CursorText)
            .map(|value| value.color)
    }

    pub(crate) fn set_dynamic_iterm_cursor_text_color(&mut self, color: Option<Color>) {
        let value = color.map(Osc21ColorValue::opaque);
        if self
            .osc21_color_state
            .current(Osc21SpecialColor::CursorText)
            == value
        {
            return;
        }
        self.osc21_color_state
            .set_current(Osc21SpecialColor::CursorText, value);
        self.mark_full_repaint("iterm_cursor_text_color_changed");
    }

    /// Get bold text custom color
    pub fn bold_color(&self) -> Color {
        self.bold_color
    }

    /// Set bold text custom color
    pub fn set_bold_color(&mut self, color: Color) {
        self.bold_color = color;
        self.osc21_color_state.set_xterm_special_baseline(0, color);
    }

    /// Get cursor guide color
    pub fn cursor_guide_color(&self) -> Color {
        self.cursor_guide_color
    }

    /// Set cursor guide color
    pub fn set_cursor_guide_color(&mut self, color: Color) {
        if self.cursor_guide_color == color {
            return;
        }
        self.cursor_guide_color = color;
        self.mark_full_repaint("cursor_guide_color_changed");
    }

    /// Get badge color
    pub fn badge_color(&self) -> Color {
        self.badge_color
    }

    /// Set badge color
    pub fn set_badge_color(&mut self, color: Color) {
        self.badge_color = color;
    }

    /// Get match/search highlight color
    pub fn match_color(&self) -> Color {
        self.match_color
    }

    /// Set match/search highlight color
    pub fn set_match_color(&mut self, color: Color) {
        self.match_color = color;
    }

    /// Get selection background color
    pub fn selection_bg_color(&self) -> Color {
        self.selection_bg_color
    }

    /// Set selection background color
    pub fn set_selection_bg_color(&mut self, color: Color) {
        self.osc21_color_state.set_baseline(
            Osc21SpecialColor::SelectionBackground,
            Osc21ColorValue::opaque(color),
        );
        self.osc21_color_state.set_xterm_dynamic_baseline(17, color);
        self.set_dynamic_selection_bg_color(color);
    }

    pub(crate) fn set_dynamic_selection_bg_color(&mut self, color: Color) {
        self.osc21_color_state.set_xterm_dynamic(17, color);
        self.osc21_color_state.set_current(
            Osc21SpecialColor::SelectionBackground,
            Some(Osc21ColorValue::opaque(color)),
        );
        if self.selection_bg_color == color {
            return;
        }
        self.selection_bg_color = color;
        self.mark_full_repaint("selection_color_changed");
    }

    /// Get selection foreground/text color
    pub fn selection_fg_color(&self) -> Color {
        self.selection_fg_color
    }

    /// Set selection foreground/text color
    pub fn set_selection_fg_color(&mut self, color: Color) {
        self.osc21_color_state.set_baseline(
            Osc21SpecialColor::SelectionForeground,
            Osc21ColorValue::opaque(color),
        );
        self.osc21_color_state.set_xterm_dynamic_baseline(19, color);
        self.set_dynamic_selection_fg_color(color);
    }

    pub(crate) fn set_dynamic_selection_fg_color(&mut self, color: Color) {
        self.osc21_color_state.set_xterm_dynamic(19, color);
        self.osc21_color_state.set_current(
            Osc21SpecialColor::SelectionForeground,
            Some(Osc21ColorValue::opaque(color)),
        );
        if self.selection_fg_color == color {
            return;
        }
        self.selection_fg_color = color;
        self.mark_full_repaint("selection_color_changed");
    }

    /// Get whether to use custom bold color
    pub fn use_bold_color(&self) -> bool {
        self.use_bold_color
    }

    /// Set whether to use custom bold color
    pub fn set_use_bold_color(&mut self, use_bold: bool) {
        self.use_bold_color = use_bold;
        self.osc21_color_state
            .set_xterm_special_mode_baseline(0, use_bold);
    }

    /// Get whether to use custom underline color
    pub fn use_underline_color(&self) -> bool {
        self.use_underline_color
    }

    /// Set whether to use custom underline color
    pub fn set_use_underline_color(&mut self, use_underline: bool) {
        self.use_underline_color = use_underline;
        self.osc21_color_state
            .set_xterm_special_mode_baseline(1, use_underline);
    }

    /// Get whether to show cursor guide
    pub fn use_cursor_guide(&self) -> bool {
        self.use_cursor_guide
    }

    /// Set whether to show cursor guide
    pub fn set_use_cursor_guide(&mut self, use_guide: bool) {
        if self.use_cursor_guide == use_guide {
            return;
        }
        self.use_cursor_guide = use_guide;
        self.mark_full_repaint("cursor_guide_visibility_changed");
    }

    /// Get whether to use custom selected text color
    pub fn use_selected_text_color(&self) -> bool {
        self.use_selected_text_color
    }

    /// Set whether to use custom selected text color
    pub fn set_use_selected_text_color(&mut self, use_selected: bool) {
        self.use_selected_text_color = use_selected;
        self.osc21_color_state
            .set_selection_foreground_enabled_baseline(use_selected);
    }

    pub(crate) fn set_dynamic_selected_text_color_enabled(&mut self, enabled: bool) {
        self.osc21_color_state
            .set_selection_foreground_enabled(enabled);
        if self.use_selected_text_color == enabled {
            return;
        }
        self.use_selected_text_color = enabled;
        self.mark_full_repaint("selection_color_changed");
    }

    /// Current xterm OSC 5 resource color for indices 0 through 4.
    pub fn xterm_special_color(&self, index: usize) -> Option<Color> {
        self.osc21_color_state.xterm_special(index)
    }

    /// Current xterm OSC 6/106 mode for indices 0 through 5.
    pub fn xterm_special_color_mode(&self, index: usize) -> Option<bool> {
        self.osc21_color_state.xterm_special_mode(index)
    }

    /// Resolve the active xterm attribute color for a cell. Attribute colors
    /// only override default-sourced foregrounds, matching xterm's default
    /// `colorAttrMode=false` behavior.
    pub fn xterm_attribute_color(&self, flags: CellFlags) -> Option<Color> {
        if !flags.foreground_is_default()
            && self.osc21_color_state.xterm_special_mode(5) != Some(true)
        {
            return None;
        }
        [
            (3, flags.reverse()),
            (2, flags.blink()),
            (0, flags.bold()),
            (1, flags.underline()),
            (4, flags.italic()),
        ]
        .into_iter()
        .find_map(|(index, active)| {
            (active && self.osc21_color_state.xterm_special_mode(index) == Some(true))
                .then(|| self.osc21_color_state.xterm_special(index))
                .flatten()
        })
    }

    /// Whether the current selected-text resource should override glyph color.
    pub fn selection_foreground_color_enabled(&self) -> bool {
        self.osc21_color_state.selection_foreground_enabled()
    }

    pub(crate) fn set_dynamic_xterm_special_color(&mut self, index: usize, color: Color) {
        if self.osc21_color_state.xterm_special(index) == Some(color) {
            return;
        }
        self.osc21_color_state.set_xterm_special(index, color);
        if index == 0 {
            self.bold_color = color;
        }
        self.mark_full_repaint("xterm_special_color_changed");
    }

    pub(crate) fn reset_dynamic_xterm_special_color(&mut self, index: usize) {
        self.osc21_color_state.reset_xterm_special(index);
        if let Some(color) = self.osc21_color_state.xterm_special(index) {
            if index == 0 {
                self.bold_color = color;
            }
        }
        self.mark_full_repaint("xterm_special_color_changed");
    }

    pub(crate) fn set_dynamic_xterm_special_mode(&mut self, index: usize, enabled: bool) {
        if self.osc21_color_state.xterm_special_mode(index) == Some(enabled) {
            return;
        }
        self.osc21_color_state
            .set_xterm_special_mode(index, enabled);
        if index == 0 {
            self.use_bold_color = enabled;
        } else if index == 1 {
            self.use_underline_color = enabled;
        }
        self.mark_full_repaint("xterm_special_color_mode_changed");
    }

    pub(crate) fn xterm_dynamic_color(&self, command: usize) -> Option<Color> {
        self.osc21_color_state.xterm_dynamic(command)
    }

    pub(crate) fn set_dynamic_xterm_color(&mut self, command: usize, color: Color) {
        match command {
            10 => self.set_dynamic_default_fg(color),
            11 => self.set_dynamic_default_bg(color),
            12 => self.set_dynamic_cursor_color(color),
            17 => self.set_dynamic_selection_bg_color(color),
            19 => {
                self.set_dynamic_selection_fg_color(color);
                self.set_dynamic_selected_text_color_enabled(true);
            }
            13..=16 | 18 => {
                if self.osc21_color_state.xterm_dynamic(command) == Some(color) {
                    return;
                }
                self.osc21_color_state.set_xterm_dynamic(command, color);
                self.mark_full_repaint("xterm_dynamic_color_changed");
            }
            _ => {}
        }
    }

    pub(crate) fn reset_dynamic_xterm_color(&mut self, command: usize) {
        let Some(color) = self.osc21_color_state.reset_xterm_dynamic(command) else {
            return;
        };
        match command {
            10 => self.set_dynamic_default_fg(color),
            11 => self.set_dynamic_default_bg(color),
            12 => self.set_dynamic_cursor_color(color),
            17 => self.set_dynamic_selection_bg_color(color),
            19 => {
                self.set_dynamic_selection_fg_color(color);
                let enabled = self.osc21_color_state.reset_selection_foreground_enabled();
                self.set_dynamic_selected_text_color_enabled(enabled);
            }
            13..=16 | 18 => self.mark_full_repaint("xterm_dynamic_color_changed"),
            _ => {}
        }
    }

    /// Get whether smart cursor color is enabled
    pub fn smart_cursor_color(&self) -> bool {
        self.smart_cursor_color
    }

    /// Set whether smart cursor color is enabled
    pub fn set_smart_cursor_color(&mut self, smart_cursor: bool) {
        self.smart_cursor_color = smart_cursor;
    }

    /// Set ANSI/xterm palette color (0-255) and establish its reset baseline.
    ///
    /// # Arguments
    /// * `index` - Palette index (0-255)
    /// * `color` - RGB color
    ///
    /// # Returns
    /// Ok(()) if index is valid, Err if index >= 256
    pub fn set_ansi_palette_color(&mut self, index: usize, color: Color) -> Result<(), String> {
        if index >= 256 {
            return Err(format!("Invalid palette index: {} (must be 0-255)", index));
        }

        let changed = self.get_ansi_color(index) != Some(color);
        if index < 16 {
            self.ansi_palette[index] = color;
            self.baseline_ansi_palette[index] = color;
        } else {
            self.extended_ansi_palette[index - 16] = color;
            self.baseline_extended_ansi_palette[index - 16] = color;
        }
        self.osc21_color_state.set_palette_alpha(index, None);
        if changed {
            self.mark_full_repaint("ansi_palette_changed");
        }
        Ok(())
    }

    /// Set the runtime palette value without changing the session/profile
    /// baseline used by OSC 104.
    pub(crate) fn set_dynamic_ansi_palette_color(&mut self, index: usize, color: Color) {
        self.osc21_color_state.set_palette_alpha(index, None);
        if self.get_ansi_color(index) == Some(color) {
            return;
        }

        match index {
            0..=15 => self.ansi_palette[index] = color,
            16..=255 => self.extended_ansi_palette[index - 16] = color,
            _ => return,
        }
        self.mark_full_repaint("ansi_palette_changed");
    }

    /// Restore one runtime palette value to its session/profile baseline.
    pub(crate) fn reset_dynamic_ansi_palette_color(&mut self, index: usize) {
        let baseline = match index {
            0..=15 => self.baseline_ansi_palette[index],
            16..=255 => self.baseline_extended_ansi_palette[index - 16],
            _ => return,
        };
        self.set_dynamic_ansi_palette_color(index, baseline);
        self.osc21_color_state.set_palette_alpha(index, None);
    }

    /// Restore all runtime palette values to their session/profile baseline.
    pub(crate) fn reset_dynamic_ansi_palette(&mut self) {
        self.osc21_color_state.reset_palette_alpha();
        if self.ansi_palette == self.baseline_ansi_palette
            && self.extended_ansi_palette == self.baseline_extended_ansi_palette
        {
            return;
        }

        self.ansi_palette = self.baseline_ansi_palette;
        self.extended_ansi_palette = self.baseline_extended_ansi_palette;
        self.mark_full_repaint("ansi_palette_changed");
    }

    /// Resolve named and indexed colors through the current mutable palette.
    pub fn resolve_color_rgb(&self, color: Color) -> (u8, u8, u8) {
        match color {
            Color::Named(named) => self.ansi_palette[named as usize].to_rgb(),
            Color::Indexed(index) => self
                .get_ansi_color(index as usize)
                .unwrap_or(color)
                .to_rgb(),
            Color::Rgb(red, green, blue) => (red, green, blue),
        }
    }

    /// Set the faint/dim text alpha multiplier
    pub fn set_faint_text_alpha(&mut self, alpha: f32) {
        self.faint_text_alpha = alpha.clamp(0.0, 1.0);
    }

    /// Get the faint/dim text alpha multiplier
    pub fn faint_text_alpha(&self) -> f32 {
        self.faint_text_alpha
    }

    /// Get the legacy 16-color ANSI palette view (indices 0-15).
    ///
    /// Use [`Terminal::get_ansi_color`] to read any index through 255.
    pub fn get_ansi_palette(&self) -> &[Color; 16] {
        &self.ansi_palette
    }

    /// Snapshot the complete current ANSI/xterm palette (indices 0-255).
    pub fn get_ansi_palette_256(&self) -> [Color; 256] {
        std::array::from_fn(|index| {
            self.get_ansi_color(index)
                .unwrap_or(Color::Indexed(index as u8))
        })
    }

    /// Get current cursor color
    pub fn get_cursor_color(&self) -> Color {
        self.cursor_color
    }

    /// Get current link/hyperlink color
    pub fn get_link_color(&self) -> Color {
        self.link_color
    }

    /// Get current selection background color
    pub fn get_selection_bg_color(&self) -> Color {
        self.selection_bg_color
    }

    /// Get current selection foreground/text color
    pub fn get_selection_fg_color(&self) -> Color {
        self.selection_fg_color
    }

    /// Convert RGB to HSV
    pub fn rgb_to_hsv_color(&self, r: u8, g: u8, b: u8) -> crate::terminal::screen::ColorHSV {
        crate::terminal::screen::rgb_to_hsv(r, g, b)
    }

    /// Convert HSV to RGB
    pub fn hsv_to_rgb_color(&self, hsv: crate::terminal::screen::ColorHSV) -> (u8, u8, u8) {
        crate::terminal::screen::hsv_to_rgb(hsv)
    }

    /// Convert RGB to HSL
    pub fn rgb_to_hsl_color(&self, r: u8, g: u8, b: u8) -> crate::terminal::screen::ColorHSL {
        crate::terminal::screen::rgb_to_hsl(r, g, b)
    }

    /// Convert HSL to RGB
    pub fn hsl_to_rgb_color(&self, hsl: crate::terminal::screen::ColorHSL) -> (u8, u8, u8) {
        crate::terminal::screen::hsl_to_rgb(hsl)
    }

    /// Generate color palette
    pub fn generate_color_palette(
        &self,
        r: u8,
        g: u8,
        b: u8,
        mode: crate::terminal::screen::ThemeMode,
    ) -> crate::terminal::screen::ColorPalette {
        self.generate_theme(Color::Rgb(r, g, b), mode)
    }

    /// Calculate color distance
    pub fn color_distance(&self, r1: u8, g1: u8, b1: u8, r2: u8, g2: u8, b2: u8) -> f32 {
        let dr = r1 as f32 - r2 as f32;
        let dg = g1 as f32 - g2 as f32;
        let db = b1 as f32 - b2 as f32;
        (dr * dr + dg * dg + db * db).sqrt()
    }

    // === Feature 8: Advanced Color Operations ===

    /// Generate a color theme from a base color
    pub fn generate_theme(
        &self,
        base: Color,
        mode: crate::terminal::screen::ThemeMode,
    ) -> crate::terminal::screen::ColorPalette {
        let (r, g, b) = base.to_rgb();
        let hsv = crate::terminal::rgb_to_hsv(r, g, b);
        let mut colors = Vec::new();

        match mode {
            crate::terminal::screen::ThemeMode::Complementary => {
                let comp_h = (hsv.h + 180.0) % 360.0;
                colors.push(crate::terminal::hsv_to_rgb(
                    crate::terminal::screen::ColorHSV {
                        h: comp_h,
                        s: hsv.s,
                        v: hsv.v,
                    },
                ));
            }
            crate::terminal::screen::ThemeMode::Analogous => {
                for angle in &[-30.0, 30.0] {
                    let h = (hsv.h + angle + 360.0) % 360.0;
                    colors.push(crate::terminal::hsv_to_rgb(
                        crate::terminal::screen::ColorHSV {
                            h,
                            s: hsv.s,
                            v: hsv.v,
                        },
                    ));
                }
            }
            crate::terminal::screen::ThemeMode::Triadic => {
                for angle in &[120.0, 240.0] {
                    let h = (hsv.h + angle) % 360.0;
                    colors.push(crate::terminal::hsv_to_rgb(
                        crate::terminal::screen::ColorHSV {
                            h,
                            s: hsv.s,
                            v: hsv.v,
                        },
                    ));
                }
            }
            crate::terminal::screen::ThemeMode::Tetradic => {
                for angle in &[90.0, 180.0, 270.0] {
                    let h = (hsv.h + angle) % 360.0;
                    colors.push(crate::terminal::hsv_to_rgb(
                        crate::terminal::screen::ColorHSV {
                            h,
                            s: hsv.s,
                            v: hsv.v,
                        },
                    ));
                }
            }
            crate::terminal::screen::ThemeMode::SplitComplementary => {
                for angle in &[150.0, 210.0] {
                    let h = (hsv.h + angle) % 360.0;
                    colors.push(crate::terminal::hsv_to_rgb(
                        crate::terminal::screen::ColorHSV {
                            h,
                            s: hsv.s,
                            v: hsv.v,
                        },
                    ));
                }
            }
            crate::terminal::screen::ThemeMode::Monochromatic => {
                for v_offset in &[-0.2, 0.2, -0.4, 0.4] {
                    let v = (hsv.v + v_offset).clamp(0.0, 1.0);
                    colors.push(crate::terminal::hsv_to_rgb(
                        crate::terminal::screen::ColorHSV {
                            h: hsv.h,
                            s: hsv.s,
                            v,
                        },
                    ));
                }
            }
        }

        crate::terminal::screen::ColorPalette {
            base: (r, g, b),
            colors,
            mode,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_test_terminal() -> Terminal {
        Terminal::new(80, 24)
    }

    #[test]
    fn test_default_ansi_palette() {
        let palette = Terminal::default_ansi_palette();

        // Test standard colors (0-7)
        assert_eq!(palette[0], Color::Rgb(0x14, 0x19, 0x1E)); // Black
        assert_eq!(palette[1], Color::Rgb(0xB4, 0x3C, 0x2A)); // Red
        assert_eq!(palette[2], Color::Rgb(0x00, 0x81, 0x5B)); // Green
        assert_eq!(palette[3], Color::Rgb(0xCF, 0xA5, 0x18)); // Yellow
        assert_eq!(palette[4], Color::Rgb(0x30, 0x65, 0xB8)); // Blue
        assert_eq!(palette[5], Color::Rgb(0x88, 0x18, 0xA3)); // Magenta
        assert_eq!(palette[6], Color::Rgb(0x00, 0x93, 0x99)); // Cyan
        assert_eq!(palette[7], Color::Rgb(0xE5, 0xE5, 0xE5)); // White

        // Test bright colors (8-15)
        assert_eq!(palette[8], Color::Rgb(0x68, 0x73, 0x78)); // Bright Black
        assert_eq!(palette[9], Color::Rgb(0xFF, 0x61, 0x48)); // Bright Red
        assert_eq!(palette[10], Color::Rgb(0x00, 0xC9, 0x84)); // Bright Green
        assert_eq!(palette[11], Color::Rgb(0xFF, 0xC5, 0x31)); // Bright Yellow
        assert_eq!(palette[12], Color::Rgb(0x4F, 0x9C, 0xFE)); // Bright Blue
        assert_eq!(palette[13], Color::Rgb(0xC5, 0x4F, 0xFF)); // Bright Magenta
        assert_eq!(palette[14], Color::Rgb(0x00, 0xCC, 0xCC)); // Bright Cyan
        assert_eq!(palette[15], Color::Rgb(0xFF, 0xFF, 0xFF)); // Bright White
    }

    #[test]
    fn test_default_fg_get_set() {
        let mut term = create_test_terminal();
        let original = term.default_fg();

        let new_color = Color::Rgb(255, 100, 50);
        term.set_default_fg(new_color);

        assert_eq!(term.default_fg(), new_color);
        assert_ne!(term.default_fg(), original);
    }

    #[test]
    fn test_default_bg_get_set() {
        let mut term = create_test_terminal();
        let original = term.default_bg();

        let new_color = Color::Rgb(10, 20, 30);
        term.set_default_bg(new_color);

        assert_eq!(term.default_bg(), new_color);
        assert_ne!(term.default_bg(), original);
    }

    #[test]
    fn test_default_fg_update_preserves_explicit_same_color_cells() {
        let mut term = create_test_terminal();
        let original = term.default_fg();

        term.process(b"\x1b[37mX\x1b[0m");
        let new_color = Color::Rgb(10, 20, 30);
        term.set_default_fg(new_color);

        let row = term.active_grid().row(0).unwrap();
        assert_eq!(row[0].fg, original);
        assert_eq!(row[1].fg, new_color);
    }

    #[test]
    fn test_default_bg_update_preserves_explicit_same_color_cells() {
        let mut term = create_test_terminal();
        let original = term.default_bg();

        term.process(b"\x1b[40mX\x1b[0m");
        let new_color = Color::Rgb(10, 20, 30);
        term.set_default_bg(new_color);

        let row = term.active_grid().row(0).unwrap();
        assert_eq!(row[0].bg, original);
        assert_eq!(row[1].bg, new_color);
    }

    #[test]
    fn dynamic_defaults_recolor_existing_default_glyphs_but_not_explicit_same_rgb() {
        let mut term = create_test_terminal();
        let profile_fg = Color::Rgb(1, 2, 3);
        let profile_bg = Color::Rgb(4, 5, 6);
        term.set_default_fg(profile_fg);
        term.set_default_bg(profile_bg);

        term.process(b"A\x1b[38;2;1;2;3;48;2;4;5;6mB\x1b[0m");
        term.process(b"\x1b]10;#112233\x1b\\\x1b]11;#445566\x1b\\");

        let row = term.active_grid().row(0).unwrap();
        assert_eq!(row[0].fg, Color::Rgb(0x11, 0x22, 0x33));
        assert_eq!(row[0].bg, Color::Rgb(0x44, 0x55, 0x66));
        assert_eq!(row[1].fg, profile_fg);
        assert_eq!(row[1].bg, profile_bg);

        term.process(b"\x1b]110\x1b\\\x1b]111\x1b\\");
        term.process(b"\x1b]10;#778899\x1b\\\x1b]11;#aabbcc\x1b\\");
        let row = term.active_grid().row(0).unwrap();
        assert_eq!(row[0].fg, Color::Rgb(0x77, 0x88, 0x99));
        assert_eq!(row[0].bg, Color::Rgb(0xaa, 0xbb, 0xcc));
        assert_eq!(row[1].fg, profile_fg);
        assert_eq!(row[1].bg, profile_bg);
    }

    #[test]
    fn dynamic_defaults_recolor_scrollback_and_scrollback_export_by_provenance() {
        let mut term = Terminal::with_scrollback(4, 2, 8);
        let profile_fg = Color::Rgb(1, 2, 3);
        let profile_bg = Color::Rgb(4, 5, 6);
        term.set_default_fg(profile_fg);
        term.set_default_bg(profile_bg);
        term.process(b"A\x1b[38;2;1;2;3;48;2;4;5;6mB\x1b[0m\r\nC\r\nD");
        assert_eq!(term.grid().scrollback_len(), 1);

        term.process(b"\x1b]10;#112233\x1b\\\x1b]11;#445566\x1b\\");

        let scrollback = term.grid().scrollback_line(0).unwrap();
        assert_eq!(scrollback[0].fg, Color::Rgb(0x11, 0x22, 0x33));
        assert_eq!(scrollback[0].bg, Color::Rgb(0x44, 0x55, 0x66));
        assert_eq!(scrollback[1].fg, profile_fg);
        assert_eq!(scrollback[1].bg, profile_bg);

        let svg = term
            .screenshot(
                crate::screenshot::ScreenshotConfig {
                    format: crate::screenshot::ImageFormat::Svg,
                    ..Default::default()
                },
                1,
            )
            .expect("scrollback SVG");
        let svg = String::from_utf8(svg).unwrap();
        assert!(svg.contains("fill=\"rgb(17,34,51)\""), "{svg}");
        assert!(svg.contains("fill=\"rgb(1,2,3)\""), "{svg}");
    }

    #[test]
    fn ris_restores_and_preserves_profile_color_baselines() {
        let mut term = create_test_terminal();
        let profile_fg = Color::Rgb(1, 2, 3);
        let profile_bg = Color::Rgb(4, 5, 6);
        let profile_cursor = Color::Rgb(7, 8, 9);
        let profile_0 = Color::Rgb(10, 11, 12);
        let profile_16 = Color::Rgb(13, 14, 15);
        let profile_255 = Color::Rgb(16, 17, 18);
        term.set_default_fg(profile_fg);
        term.set_default_bg(profile_bg);
        term.set_cursor_color(profile_cursor);
        term.set_ansi_palette_color(0, profile_0).unwrap();
        term.set_ansi_palette_color(16, profile_16).unwrap();
        term.set_ansi_palette_color(255, profile_255).unwrap();

        term.process(b"\x1b]10;#202122\x1b\\\x1b]11;#303132\x1b\\");
        term.process(b"\x1b]12;#404142\x1b\\");
        term.process(b"\x1b]4;0;#505152;16;#606162;255;#707172\x1b\\");
        term.process(b"\x1bc");

        assert_eq!(term.default_fg(), profile_fg);
        assert_eq!(term.default_bg(), profile_bg);
        assert_eq!(term.cursor_color(), profile_cursor);
        assert_eq!(term.get_ansi_color(0), Some(profile_0));
        assert_eq!(term.get_ansi_color(16), Some(profile_16));
        assert_eq!(term.get_ansi_color(255), Some(profile_255));

        term.process(b"\x1b]10;#808182\x1b\\\x1b]11;#909192\x1b\\");
        term.process(b"\x1b]12;#a0a1a2\x1b\\");
        term.process(b"\x1b]4;0;#b0b1b2;16;#c0c1c2;255;#d0d1d2\x1b\\");
        term.process(b"\x1b]104\x1b\\\x1b]110\x1b\\\x1b]111\x1b\\\x1b]112\x1b\\");

        assert_eq!(term.default_fg(), profile_fg);
        assert_eq!(term.default_bg(), profile_bg);
        assert_eq!(term.cursor_color(), profile_cursor);
        assert_eq!(term.get_ansi_color(0), Some(profile_0));
        assert_eq!(term.get_ansi_color(16), Some(profile_16));
        assert_eq!(term.get_ansi_color(255), Some(profile_255));
    }

    #[test]
    fn ris_reseeds_blank_cells_for_profile_baseline_after_scroll_and_erase() {
        let mut term = Terminal::with_scrollback(4, 2, 8);
        let profile_fg = Color::Rgb(1, 2, 3);
        let profile_bg = Color::Rgb(4, 5, 6);
        term.set_default_fg(profile_fg);
        term.set_default_bg(profile_bg);
        term.process(b"\x1b]10;#112233\x1b\\\x1b]11;#445566\x1b\\\x1bc");

        term.process(b"X\r\nY\r\nZ");
        let row = term.active_grid().row(1).unwrap();
        assert_eq!(row[1].fg, profile_fg);
        assert_eq!(row[1].bg, profile_bg);

        term.process(b"\r\x1b[2K");
        let row = term.active_grid().row(1).unwrap();
        assert!(row.iter().all(|cell| cell.fg == profile_fg));
        assert!(row.iter().all(|cell| cell.bg == profile_bg));
    }

    #[test]
    fn dynamic_color_queries_resolve_indexed_values_through_current_palette() {
        let mut term = create_test_terminal();
        term.set_default_fg(Color::Indexed(196));
        term.set_default_bg(Color::Indexed(196));
        term.set_cursor_color(Color::Indexed(196));
        term.process(b"\x1b]4;196;#123456\x1b\\");

        term.process(b"\x1b]10;?\x1b\\\x1b]11;?\x1b\\\x1b]12;?\x1b\\");

        assert_eq!(
            term.drain_responses(),
            b"\x1b]10;rgb:1212/3434/5656\x1b\\\x1b]11;rgb:1212/3434/5656\x1b\\\x1b]12;rgb:1212/3434/5656\x1b\\"
        );
    }

    #[test]
    fn test_cursor_color_get_set() {
        let mut term = create_test_terminal();
        let original = term.cursor_color();

        let new_color = Color::Rgb(128, 200, 255);
        term.set_cursor_color(new_color);

        assert_eq!(term.cursor_color(), new_color);
        assert_ne!(term.cursor_color(), original);
    }

    #[test]
    fn test_link_color_get_set() {
        let mut term = create_test_terminal();
        let original = term.link_color();

        let new_color = Color::Rgb(0, 0, 255);
        term.set_link_color(new_color);

        assert_eq!(term.link_color(), new_color);
        assert_ne!(term.link_color(), original);
    }

    #[test]
    fn test_bold_color_get_set() {
        let mut term = create_test_terminal();
        let original = term.bold_color();

        let new_color = Color::Rgb(255, 255, 0);
        term.set_bold_color(new_color);

        assert_eq!(term.bold_color(), new_color);
        assert_ne!(term.bold_color(), original);
    }

    #[test]
    fn test_cursor_guide_color_get_set() {
        let mut term = create_test_terminal();
        let original = term.cursor_guide_color();

        let new_color = Color::Rgb(100, 100, 100);
        term.set_cursor_guide_color(new_color);

        assert_eq!(term.cursor_guide_color(), new_color);
        assert_ne!(term.cursor_guide_color(), original);
    }

    #[test]
    fn test_badge_color_get_set() {
        let mut term = create_test_terminal();
        let original = term.badge_color();

        let new_color = Color::Rgb(200, 50, 50);
        term.set_badge_color(new_color);

        assert_eq!(term.badge_color(), new_color);
        assert_ne!(term.badge_color(), original);
    }

    #[test]
    fn test_match_color_get_set() {
        let mut term = create_test_terminal();
        let original = term.match_color();

        let new_color = Color::Rgb(255, 255, 100);
        term.set_match_color(new_color);

        assert_eq!(term.match_color(), new_color);
        assert_ne!(term.match_color(), original);
    }

    #[test]
    fn test_selection_bg_color_get_set() {
        let mut term = create_test_terminal();
        let original = term.selection_bg_color();

        let new_color = Color::Rgb(64, 64, 128);
        term.set_selection_bg_color(new_color);

        assert_eq!(term.selection_bg_color(), new_color);
        assert_ne!(term.selection_bg_color(), original);
    }

    #[test]
    fn test_selection_fg_color_get_set() {
        let mut term = create_test_terminal();
        let original = term.selection_fg_color();

        let new_color = Color::Rgb(255, 255, 255);
        term.set_selection_fg_color(new_color);

        assert_eq!(term.selection_fg_color(), new_color);
        assert_ne!(term.selection_fg_color(), original);
    }

    #[test]
    fn test_use_bold_color_get_set() {
        let mut term = create_test_terminal();
        let original = term.use_bold_color();

        term.set_use_bold_color(!original);
        assert_eq!(term.use_bold_color(), !original);

        term.set_use_bold_color(original);
        assert_eq!(term.use_bold_color(), original);
    }

    #[test]
    fn test_use_underline_color_get_set() {
        let mut term = create_test_terminal();
        let original = term.use_underline_color();

        term.set_use_underline_color(!original);
        assert_eq!(term.use_underline_color(), !original);

        term.set_use_underline_color(original);
        assert_eq!(term.use_underline_color(), original);
    }

    #[test]
    fn test_use_cursor_guide_get_set() {
        let mut term = create_test_terminal();
        let original = term.use_cursor_guide();

        term.set_use_cursor_guide(!original);
        assert_eq!(term.use_cursor_guide(), !original);

        term.set_use_cursor_guide(original);
        assert_eq!(term.use_cursor_guide(), original);
    }

    #[test]
    fn test_use_selected_text_color_get_set() {
        let mut term = create_test_terminal();
        let original = term.use_selected_text_color();

        term.set_use_selected_text_color(!original);
        assert_eq!(term.use_selected_text_color(), !original);

        term.set_use_selected_text_color(original);
        assert_eq!(term.use_selected_text_color(), original);
    }

    #[test]
    fn test_smart_cursor_color_get_set() {
        let mut term = create_test_terminal();
        let original = term.smart_cursor_color();

        term.set_smart_cursor_color(!original);
        assert_eq!(term.smart_cursor_color(), !original);

        term.set_smart_cursor_color(original);
        assert_eq!(term.smart_cursor_color(), original);
    }

    #[test]
    fn test_faint_text_alpha_get_set() {
        let mut term = create_test_terminal();

        // Default should be 0.5
        assert!((term.faint_text_alpha() - 0.5).abs() < f32::EPSILON);

        // Set to a different value
        term.set_faint_text_alpha(0.3);
        assert!((term.faint_text_alpha() - 0.3).abs() < f32::EPSILON);

        // Test clamping above 1.0
        term.set_faint_text_alpha(1.5);
        assert!((term.faint_text_alpha() - 1.0).abs() < f32::EPSILON);

        // Test clamping below 0.0
        term.set_faint_text_alpha(-0.5);
        assert!((term.faint_text_alpha() - 0.0).abs() < f32::EPSILON);

        // Reset to default
        term.set_faint_text_alpha(0.5);
        assert!((term.faint_text_alpha() - 0.5).abs() < f32::EPSILON);
    }

    #[test]
    fn test_set_ansi_palette_color_valid_indices() {
        let mut term = create_test_terminal();

        // Cover both the legacy ANSI palette and the extended xterm palette.
        for i in [0, 15, 16, 255] {
            let color = Color::Rgb(
                (i as u8).wrapping_mul(10),
                (i as u8).wrapping_mul(12),
                (i as u8).wrapping_mul(8),
            );
            let result = term.set_ansi_palette_color(i, color);
            assert!(result.is_ok());
            assert_eq!(term.get_ansi_color(i), Some(color));
        }
    }

    #[test]
    fn test_set_ansi_palette_color_invalid_index() {
        let mut term = create_test_terminal();

        // Test invalid indices
        let color = Color::Rgb(255, 0, 0);

        let result = term.set_ansi_palette_color(256, color);
        assert!(result.is_err());
        assert_eq!(
            result.unwrap_err(),
            "Invalid palette index: 256 (must be 0-255)"
        );

        let result = term.set_ansi_palette_color(1000, color);
        assert!(result.is_err());
    }

    #[test]
    fn test_set_ansi_palette_color_boundary() {
        let mut term = create_test_terminal();

        // Test boundary indices
        let color = Color::Rgb(128, 128, 128);

        // Index 0 should work
        assert!(term.set_ansi_palette_color(0, color).is_ok());

        // Index 15 should work
        assert!(term.set_ansi_palette_color(15, color).is_ok());

        // Extended palette boundaries should work.
        assert!(term.set_ansi_palette_color(16, color).is_ok());
        assert!(term.set_ansi_palette_color(255, color).is_ok());

        // Index 256 is outside the xterm palette.
        assert!(term.set_ansi_palette_color(256, color).is_err());
    }

    #[test]
    fn test_ansi_palette_preservation() {
        let mut term = create_test_terminal();

        // Modify some palette colors
        let red = Color::Rgb(255, 0, 0);
        let green = Color::Rgb(0, 255, 0);
        let blue = Color::Rgb(0, 0, 255);

        term.set_ansi_palette_color(1, red).unwrap();
        term.set_ansi_palette_color(2, green).unwrap();
        term.set_ansi_palette_color(4, blue).unwrap();

        // Verify they are preserved
        assert_eq!(term.ansi_palette[1], red);
        assert_eq!(term.ansi_palette[2], green);
        assert_eq!(term.ansi_palette[4], blue);

        // Verify others remain unchanged (default palette)
        let default_palette = Terminal::default_ansi_palette();
        assert_eq!(term.ansi_palette[0], default_palette[0]);
        assert_eq!(term.ansi_palette[3], default_palette[3]);
        assert_eq!(term.ansi_palette[5], default_palette[5]);
    }

    #[test]
    fn test_multiple_color_settings() {
        let mut term = create_test_terminal();

        // Set multiple colors at once
        let fg = Color::Rgb(255, 255, 255);
        let bg = Color::Rgb(0, 0, 0);
        let cursor = Color::Rgb(255, 0, 0);
        let link = Color::Rgb(0, 0, 255);

        term.set_default_fg(fg);
        term.set_default_bg(bg);
        term.set_cursor_color(cursor);
        term.set_link_color(link);

        // Verify all are set correctly
        assert_eq!(term.default_fg(), fg);
        assert_eq!(term.default_bg(), bg);
        assert_eq!(term.cursor_color(), cursor);
        assert_eq!(term.link_color(), link);
    }

    #[test]
    fn test_color_flags_independence() {
        let mut term = create_test_terminal();

        // Test that boolean flags are independent
        term.set_use_bold_color(true);
        term.set_use_underline_color(false);
        term.set_use_cursor_guide(true);
        term.set_use_selected_text_color(false);
        term.set_smart_cursor_color(true);

        assert!(term.use_bold_color());
        assert!(!term.use_underline_color());
        assert!(term.use_cursor_guide());
        assert!(!term.use_selected_text_color());
        assert!(term.smart_cursor_color());
    }

    #[test]
    fn test_ansi_palette_indexed_colors() {
        let mut term = create_test_terminal();

        // Test that we can set and retrieve all 16 ANSI colors
        let test_colors: Vec<Color> = (0..16_u8)
            .map(|i| {
                let r = i.saturating_mul(16);
                let g = i.saturating_mul(15);
                let b = 255_u8.saturating_sub(i.saturating_mul(16));
                Color::Rgb(r, g, b)
            })
            .collect();

        for (i, color) in test_colors.iter().enumerate() {
            term.set_ansi_palette_color(i, *color).unwrap();
        }

        for (i, expected_color) in test_colors.iter().enumerate() {
            assert_eq!(term.ansi_palette[i], *expected_color);
        }
    }

    #[test]
    fn osc4_extended_palette_set_query_and_profile_baseline_reset() {
        let mut term = create_test_terminal();
        let profile_baseline = Color::Rgb(0x12, 0x34, 0x56);
        term.set_ansi_palette_color(196, profile_baseline).unwrap();
        let _ = term.drain_active_screen_damage();

        term.process(b"\x1b]4;196;#abcdef\x1b\\");
        assert_eq!(term.get_ansi_color(196), Some(Color::Rgb(0xab, 0xcd, 0xef)));
        let damage = term.drain_active_screen_damage();
        assert!(damage.full_repaint);
        assert_eq!(
            damage.snapshot_fallback_reason.as_deref(),
            Some("ansi_palette_changed")
        );

        term.process(b"\x1b]4;196;?\x1b\\");
        assert_eq!(
            term.drain_responses(),
            b"\x1b]4;196;rgb:abab/cdcd/efef\x1b\\"
        );
        assert!(!term.drain_active_screen_damage().full_repaint);

        term.process(b"\x1b]104;196\x1b\\");
        assert_eq!(term.get_ansi_color(196), Some(profile_baseline));
    }

    #[test]
    fn osc4_multi_pair_and_osc104_multi_index_cover_palette_boundaries() {
        let mut term = create_test_terminal();
        let baselines = [
            (0, Color::Rgb(1, 2, 3)),
            (15, Color::Rgb(4, 5, 6)),
            (16, Color::Rgb(7, 8, 9)),
            (255, Color::Rgb(10, 11, 12)),
        ];
        for (index, color) in baselines {
            term.set_ansi_palette_color(index, color).unwrap();
        }

        term.process(b"\x1b]4;0;#101112;15;#202122;16;#303132;255;#404142\x1b\\");
        assert_eq!(term.get_ansi_color(0), Some(Color::Rgb(0x10, 0x11, 0x12)));
        assert_eq!(term.get_ansi_color(15), Some(Color::Rgb(0x20, 0x21, 0x22)));
        assert_eq!(term.get_ansi_color(16), Some(Color::Rgb(0x30, 0x31, 0x32)));
        assert_eq!(term.get_ansi_color(255), Some(Color::Rgb(0x40, 0x41, 0x42)));

        term.process(b"\x1b]104;0;16;255\x1b\\");
        assert_eq!(term.get_ansi_color(0), Some(baselines[0].1));
        assert_eq!(term.get_ansi_color(15), Some(Color::Rgb(0x20, 0x21, 0x22)));
        assert_eq!(term.get_ansi_color(16), Some(baselines[2].1));
        assert_eq!(term.get_ansi_color(255), Some(baselines[3].1));

        term.process(b"\x1b]104\x1b\\");
        assert_eq!(term.get_ansi_color(15), Some(baselines[1].1));
    }

    #[test]
    fn osc4_ignores_invalid_indices_without_mutating_or_responding() {
        let mut term = create_test_terminal();
        let before = term.get_ansi_color(255);
        let _ = term.drain_active_screen_damage();

        term.process(b"\x1b]4;261;#abcdef;999;?\x1b\\");

        assert_eq!(term.get_ansi_color(255), before);
        assert!(term.drain_responses().is_empty());
        assert!(!term.drain_active_screen_damage().full_repaint);
    }

    #[test]
    fn resolve_color_rgb_uses_runtime_extended_palette() {
        let mut term = create_test_terminal();
        term.process(b"\x1b]4;196;#123456\x1b\\");

        assert_eq!(
            term.resolve_color_rgb(Color::Indexed(196)),
            (0x12, 0x34, 0x56)
        );
    }

    #[test]
    fn terminal_svg_and_html_exports_use_runtime_extended_palette() {
        let mut term = Terminal::new(4, 2);
        term.process(b"\x1b[38;5;196mX\x1b[0m");
        term.process(b"\x1b]4;196;#123456\x1b\\");

        let svg = term
            .screenshot(
                crate::screenshot::ScreenshotConfig {
                    format: crate::screenshot::ImageFormat::Svg,
                    ..Default::default()
                },
                0,
            )
            .expect("SVG screenshot");
        let svg = String::from_utf8(svg).unwrap();
        assert!(svg.contains("fill=\"rgb(18,52,86)\""), "{svg}");

        let html = term.export_html(false);
        assert!(html.contains("color: rgb(18, 52, 86)"), "{html}");
    }
}
