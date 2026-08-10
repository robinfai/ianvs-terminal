//! State shared by Kitty OSC 21 color-control operations.

use crate::color::{Color, NamedColor};

pub(crate) const OSC21_SPECIAL_COLOR_COUNT: usize = 14;
pub(crate) const XTERM_SPECIAL_COLOR_COUNT: usize = 5;
pub(crate) const XTERM_SPECIAL_COLOR_MODE_COUNT: usize = 6;
pub(crate) const XTERM_DYNAMIC_COLOR_COUNT: usize = 10;

#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct Osc21ColorValue {
    pub color: Color,
    /// Explicit alpha suffix. `None` means the protocol default of 1.0.
    pub alpha: Option<f32>,
}

impl Osc21ColorValue {
    pub const fn opaque(color: Color) -> Self {
        Self { color, alpha: None }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(usize)]
pub(crate) enum Osc21SpecialColor {
    Foreground = 0,
    Background = 1,
    SelectionBackground = 2,
    SelectionForeground = 3,
    Cursor = 4,
    CursorText = 5,
    VisualBell = 6,
    TransparentBackground1 = 7,
    TransparentBackground2 = 8,
    TransparentBackground3 = 9,
    TransparentBackground4 = 10,
    TransparentBackground5 = 11,
    TransparentBackground6 = 12,
    TransparentBackground7 = 13,
}

impl Osc21SpecialColor {
    pub(crate) fn parse(key: &str) -> Option<Self> {
        Some(match key {
            "foreground" => Self::Foreground,
            "background" => Self::Background,
            "selection_background" => Self::SelectionBackground,
            "selection_foreground" => Self::SelectionForeground,
            "cursor" => Self::Cursor,
            "cursor_text" => Self::CursorText,
            "visual_bell" => Self::VisualBell,
            "transparent_background_color1" => Self::TransparentBackground1,
            "transparent_background_color2" => Self::TransparentBackground2,
            "transparent_background_color3" => Self::TransparentBackground3,
            "transparent_background_color4" => Self::TransparentBackground4,
            "transparent_background_color5" => Self::TransparentBackground5,
            "transparent_background_color6" => Self::TransparentBackground6,
            "transparent_background_color7" => Self::TransparentBackground7,
            _ => return None,
        })
    }

    pub(crate) const fn transparent_slot(self) -> Option<usize> {
        let index = self as usize;
        if index >= Self::TransparentBackground1 as usize {
            Some(index - Self::TransparentBackground1 as usize)
        } else {
            None
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Osc21ColorControlState {
    current: [Option<Osc21ColorValue>; OSC21_SPECIAL_COLOR_COUNT],
    baselines: [Option<Osc21ColorValue>; OSC21_SPECIAL_COLOR_COUNT],
    palette_alpha: [Option<f32>; 256],
    xterm_special_current: [Color; XTERM_SPECIAL_COLOR_COUNT],
    xterm_special_baselines: [Color; XTERM_SPECIAL_COLOR_COUNT],
    xterm_special_modes: [bool; XTERM_SPECIAL_COLOR_MODE_COUNT],
    xterm_special_mode_baselines: [bool; XTERM_SPECIAL_COLOR_MODE_COUNT],
    xterm_dynamic_current: [Color; XTERM_DYNAMIC_COLOR_COUNT],
    xterm_dynamic_baselines: [Color; XTERM_DYNAMIC_COLOR_COUNT],
    selection_foreground_enabled: bool,
    selection_foreground_enabled_baseline: bool,
    iterm_bold_color: Option<Color>,
    iterm_link_color: Option<Color>,
    iterm_underline_color: Option<Color>,
    iterm_tab_color: Option<Color>,
    iterm_tab_color_baseline: Option<Color>,
}

impl Default for Osc21ColorControlState {
    fn default() -> Self {
        let mut current = [None; OSC21_SPECIAL_COLOR_COUNT];
        current[Osc21SpecialColor::Foreground as usize] =
            Some(Osc21ColorValue::opaque(Color::Named(NamedColor::White)));
        current[Osc21SpecialColor::Background as usize] =
            Some(Osc21ColorValue::opaque(Color::Named(NamedColor::Black)));
        current[Osc21SpecialColor::SelectionBackground as usize] =
            Some(Osc21ColorValue::opaque(Color::Rgb(0xb5, 0xd5, 0xff)));
        current[Osc21SpecialColor::SelectionForeground as usize] =
            Some(Osc21ColorValue::opaque(Color::Rgb(0x00, 0x00, 0x00)));
        current[Osc21SpecialColor::Cursor as usize] =
            Some(Osc21ColorValue::opaque(Color::Named(NamedColor::White)));
        let xterm_special = [Color::Named(NamedColor::White); XTERM_SPECIAL_COLOR_COUNT];
        let xterm_dynamic = [
            Color::Named(NamedColor::White),
            Color::Named(NamedColor::Black),
            Color::Named(NamedColor::White),
            Color::Named(NamedColor::White),
            Color::Named(NamedColor::Black),
            Color::Named(NamedColor::White),
            Color::Named(NamedColor::Black),
            Color::Rgb(0xb5, 0xd5, 0xff),
            Color::Named(NamedColor::White),
            Color::Rgb(0x00, 0x00, 0x00),
        ];
        Self {
            baselines: current,
            current,
            palette_alpha: [None; 256],
            xterm_special_current: xterm_special,
            xterm_special_baselines: xterm_special,
            xterm_special_modes: [false; XTERM_SPECIAL_COLOR_MODE_COUNT],
            xterm_special_mode_baselines: [false; XTERM_SPECIAL_COLOR_MODE_COUNT],
            xterm_dynamic_current: xterm_dynamic,
            xterm_dynamic_baselines: xterm_dynamic,
            selection_foreground_enabled: false,
            selection_foreground_enabled_baseline: false,
            iterm_bold_color: None,
            iterm_link_color: None,
            iterm_underline_color: None,
            iterm_tab_color: None,
            iterm_tab_color_baseline: None,
        }
    }
}

impl Osc21ColorControlState {
    pub(crate) fn current(&self, key: Osc21SpecialColor) -> Option<Osc21ColorValue> {
        self.current[key as usize]
    }

    pub(crate) fn set_current(&mut self, key: Osc21SpecialColor, value: Option<Osc21ColorValue>) {
        self.current[key as usize] = value;
    }

    pub(crate) fn set_baseline(&mut self, key: Osc21SpecialColor, value: Osc21ColorValue) {
        self.baselines[key as usize] = Some(value);
        self.current[key as usize] = Some(value);
    }

    pub(crate) fn reset(&mut self, key: Osc21SpecialColor) -> Option<Osc21ColorValue> {
        let baseline = self.baselines[key as usize];
        self.current[key as usize] = baseline;
        baseline
    }

    pub(crate) fn reset_runtime_to_baselines(&mut self) {
        self.current = self.baselines;
        self.palette_alpha = [None; 256];
        self.xterm_special_current = self.xterm_special_baselines;
        self.xterm_special_modes = self.xterm_special_mode_baselines;
        self.xterm_dynamic_current = self.xterm_dynamic_baselines;
        self.selection_foreground_enabled = self.selection_foreground_enabled_baseline;
        self.iterm_bold_color = None;
        self.iterm_link_color = None;
        self.iterm_underline_color = None;
        self.iterm_tab_color = self.iterm_tab_color_baseline;
    }

    pub(crate) fn palette_alpha(&self, index: usize) -> Option<f32> {
        self.palette_alpha.get(index).copied().flatten()
    }

    pub(crate) fn set_palette_alpha(&mut self, index: usize, alpha: Option<f32>) {
        if let Some(slot) = self.palette_alpha.get_mut(index) {
            *slot = alpha;
        }
    }

    pub(crate) fn reset_palette_alpha(&mut self) {
        self.palette_alpha = [None; 256];
    }

    pub(crate) fn xterm_special(&self, index: usize) -> Option<Color> {
        self.xterm_special_current.get(index).copied()
    }

    pub(crate) fn set_xterm_special(&mut self, index: usize, color: Color) {
        if let Some(slot) = self.xterm_special_current.get_mut(index) {
            *slot = color;
        }
    }

    pub(crate) fn set_xterm_special_baseline(&mut self, index: usize, color: Color) {
        if let (Some(current), Some(baseline)) = (
            self.xterm_special_current.get_mut(index),
            self.xterm_special_baselines.get_mut(index),
        ) {
            *current = color;
            *baseline = color;
        }
    }

    pub(crate) fn reset_xterm_special(&mut self, index: usize) {
        if let (Some(current), Some(baseline)) = (
            self.xterm_special_current.get_mut(index),
            self.xterm_special_baselines.get(index),
        ) {
            *current = *baseline;
        }
    }

    pub(crate) fn xterm_special_mode(&self, index: usize) -> Option<bool> {
        self.xterm_special_modes.get(index).copied()
    }

    pub(crate) fn set_xterm_special_mode(&mut self, index: usize, enabled: bool) {
        if let Some(slot) = self.xterm_special_modes.get_mut(index) {
            *slot = enabled;
        }
    }

    pub(crate) fn set_xterm_special_mode_baseline(&mut self, index: usize, enabled: bool) {
        if let (Some(current), Some(baseline)) = (
            self.xterm_special_modes.get_mut(index),
            self.xterm_special_mode_baselines.get_mut(index),
        ) {
            *current = enabled;
            *baseline = enabled;
        }
    }

    pub(crate) fn xterm_dynamic(&self, command: usize) -> Option<Color> {
        let index = command.checked_sub(10)?;
        self.xterm_dynamic_current.get(index).copied()
    }

    pub(crate) fn set_xterm_dynamic(&mut self, command: usize, color: Color) {
        let Some(index) = command.checked_sub(10) else {
            return;
        };
        if let Some(slot) = self.xterm_dynamic_current.get_mut(index) {
            *slot = color;
        }
    }

    pub(crate) fn set_xterm_dynamic_baseline(&mut self, command: usize, color: Color) {
        let Some(index) = command.checked_sub(10) else {
            return;
        };
        if let (Some(current), Some(baseline)) = (
            self.xterm_dynamic_current.get_mut(index),
            self.xterm_dynamic_baselines.get_mut(index),
        ) {
            *current = color;
            *baseline = color;
        }
    }

    pub(crate) fn reset_xterm_dynamic(&mut self, command: usize) -> Option<Color> {
        let index = command.checked_sub(10)?;
        let baseline = *self.xterm_dynamic_baselines.get(index)?;
        *self.xterm_dynamic_current.get_mut(index)? = baseline;
        Some(baseline)
    }

    pub(crate) fn selection_foreground_enabled(&self) -> bool {
        self.selection_foreground_enabled
    }

    pub(crate) fn set_selection_foreground_enabled(&mut self, enabled: bool) {
        self.selection_foreground_enabled = enabled;
    }

    pub(crate) fn set_selection_foreground_enabled_baseline(&mut self, enabled: bool) {
        self.selection_foreground_enabled = enabled;
        self.selection_foreground_enabled_baseline = enabled;
    }

    pub(crate) fn reset_selection_foreground_enabled(&mut self) -> bool {
        self.selection_foreground_enabled = self.selection_foreground_enabled_baseline;
        self.selection_foreground_enabled
    }

    pub(crate) const fn iterm_link_color(&self) -> Option<Color> {
        self.iterm_link_color
    }

    pub(crate) const fn iterm_bold_color(&self) -> Option<Color> {
        self.iterm_bold_color
    }

    pub(crate) fn set_iterm_bold_color(&mut self, color: Option<Color>) {
        self.iterm_bold_color = color;
    }

    pub(crate) fn set_iterm_link_color(&mut self, color: Option<Color>) {
        self.iterm_link_color = color;
    }

    pub(crate) const fn iterm_underline_color(&self) -> Option<Color> {
        self.iterm_underline_color
    }

    pub(crate) fn set_iterm_underline_color(&mut self, color: Option<Color>) {
        self.iterm_underline_color = color;
    }

    pub(crate) const fn iterm_tab_color(&self) -> Option<Color> {
        self.iterm_tab_color
    }

    pub(crate) fn set_iterm_tab_color(&mut self, color: Option<Color>) {
        self.iterm_tab_color = color;
    }

    pub(crate) fn set_iterm_tab_color_baseline(&mut self, color: Option<Color>) {
        self.iterm_tab_color_baseline = color;
        self.iterm_tab_color = color;
    }

    pub(crate) fn reset_iterm_tab_color(&mut self) -> Option<Color> {
        self.iterm_tab_color = self.iterm_tab_color_baseline;
        self.iterm_tab_color
    }
}
