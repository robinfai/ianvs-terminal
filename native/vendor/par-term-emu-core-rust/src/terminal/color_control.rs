//! State shared by Kitty OSC 21 color-control operations.

use crate::color::{Color, NamedColor};

pub(crate) const OSC21_SPECIAL_COLOR_COUNT: usize = 14;

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
        Self {
            baselines: current,
            current,
            palette_alpha: [None; 256],
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
}
