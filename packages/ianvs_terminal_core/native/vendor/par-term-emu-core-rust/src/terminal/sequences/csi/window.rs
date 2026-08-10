//! Window-related CSI sequence handling (XTWINOPS, etc.)

use crate::terminal::{OscCapability, Terminal};
use vte::Params;

const TITLE_STACK_LIMIT: usize = 10;

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub(crate) struct SavedTitle {
    window_title: Option<String>,
    icon_name: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct TitleStack {
    entries: [SavedTitle; TITLE_STACK_LIMIT],
    next: usize,
    depth: usize,
}

impl Default for TitleStack {
    fn default() -> Self {
        Self {
            entries: std::array::from_fn(|_| SavedTitle::default()),
            next: 0,
            depth: 0,
        }
    }
}

impl TitleStack {
    pub(crate) fn depth(&self) -> usize {
        self.depth
    }

    pub(crate) fn retained_bytes(&self) -> usize {
        self.entries
            .iter()
            .map(|entry| {
                entry.window_title.as_ref().map_or(0, String::len)
                    + entry.icon_name.as_ref().map_or(0, String::len)
            })
            .sum()
    }

    fn store(&mut self, selector: u16, index: u16, title: &str, icon_name: &str) -> bool {
        let Some(entry) = selected_title(selector, title, icon_name) else {
            return false;
        };
        let slot = if index == 0 {
            let slot = self.next;
            self.next = (self.next + 1) % TITLE_STACK_LIMIT;
            self.depth = (self.depth + 1).min(TITLE_STACK_LIMIT);
            slot
        } else if (1..=TITLE_STACK_LIMIT as u16).contains(&index) {
            usize::from(index - 1)
        } else {
            return false;
        };
        self.entries[slot] = entry;
        true
    }

    fn restore(&mut self, selector: u16, index: u16) -> Option<SavedTitle> {
        if selector > 2 {
            return None;
        }
        let (slot, pop) = if index == 0 {
            if self.depth == 0 {
                return None;
            }
            self.next = (self.next + TITLE_STACK_LIMIT - 1) % TITLE_STACK_LIMIT;
            self.depth -= 1;
            (self.next, true)
        } else if (1..=TITLE_STACK_LIMIT as u16).contains(&index) {
            (usize::from(index - 1), false)
        } else {
            return None;
        };

        let mut entry = self.entries[slot].clone();
        for offset in 1..TITLE_STACK_LIMIT {
            if entry.window_title.is_some() && entry.icon_name.is_some() {
                break;
            }
            let older = (slot + TITLE_STACK_LIMIT - offset) % TITLE_STACK_LIMIT;
            if entry.window_title.is_none() {
                entry.window_title = self.entries[older].window_title.clone();
            }
            if entry.icon_name.is_none() {
                entry.icon_name = self.entries[older].icon_name.clone();
            }
        }
        if pop {
            self.entries[slot] = SavedTitle::default();
        }
        Some(entry)
    }
}

fn selected_title(selector: u16, title: &str, icon_name: &str) -> Option<SavedTitle> {
    match selector {
        0 => Some(SavedTitle {
            window_title: Some(title.to_string()),
            icon_name: Some(icon_name.to_string()),
        }),
        1 => Some(SavedTitle {
            window_title: None,
            icon_name: Some(icon_name.to_string()),
        }),
        2 => Some(SavedTitle {
            window_title: Some(title.to_string()),
            icon_name: None,
        }),
        _ => None,
    }
}

impl Terminal {
    pub(crate) fn handle_xtsmgraphics(&mut self, params: &Params) {
        let values = params
            .iter()
            .flat_map(|subparams| subparams.iter().copied())
            .collect::<Vec<u16>>();
        let item = values.first().copied().unwrap_or(0);
        let action = values.get(1).copied().unwrap_or(0);

        let known_item = matches!(item, 1..=3);
        if !known_item {
            self.push_response(xtsmgraphics_response(item, 1, &[0]).as_bytes());
            return;
        }
        let known_action = matches!(action, 1..=4);
        if !known_action {
            self.push_response(xtsmgraphics_response(item, 2, &[0]).as_bytes());
            return;
        }
        if matches!(action, 2 | 3) {
            self.push_response(xtsmgraphics_response(item, 3, &[0]).as_bytes());
            return;
        }

        match item {
            1 => {
                self.push_response(xtsmgraphics_response(item, 0, &[256]).as_bytes());
            }
            2 => {
                let limits = self.sixel_limits();
                let max_width = limits.max_width.min(u16::MAX as usize) as u16;
                let max_height = limits.max_height.min(u16::MAX as usize) as u16;
                if action == 4 || self.pixel_width == 0 || self.pixel_height == 0 {
                    self.push_response(
                        xtsmgraphics_response(item, 0, &[max_width, max_height]).as_bytes(),
                    );
                } else {
                    let width = self
                        .pixel_width
                        .min(limits.max_width)
                        .min(u16::MAX as usize) as u16;
                    let height = self
                        .pixel_height
                        .min(limits.max_height)
                        .min(u16::MAX as usize) as u16;
                    self.push_response(xtsmgraphics_response(item, 0, &[width, height]).as_bytes());
                }
            }
            3 => {
                self.push_response(xtsmgraphics_response(item, 3, &[0]).as_bytes());
            }
            _ => unreachable!(),
        }
    }

    pub(crate) fn handle_csi_window(
        &mut self,
        action: char,
        params: &Params,
        intermediates: &[u8],
    ) {
        let (cols, rows) = self.size();

        if intermediates.contains(&b'>') && matches!(action, 't' | 'T') {
            self.handle_xterm_title_modes(action == 't', params);
            return;
        }

        if intermediates.contains(&b'$') {
            match action {
                'x' => {
                    // DECFRA - Fill Rectangular Area: CSI Pc ; Pt ; Pl ; Pb ; Pr $ x
                    let mut iter = params.iter();
                    let pc =
                        iter.next().and_then(|p| p.first()).copied().unwrap_or(0) as u8 as char;
                    let pt = iter.next().and_then(|p| p.first()).copied().unwrap_or(1) as usize;
                    let pl = iter.next().and_then(|p| p.first()).copied().unwrap_or(1) as usize;
                    let pb = iter
                        .next()
                        .and_then(|p| p.first())
                        .copied()
                        .unwrap_or(rows as u16) as usize;
                    let pr = iter
                        .next()
                        .and_then(|p| p.first())
                        .copied()
                        .unwrap_or(cols as u16) as usize;

                    let top = pt.saturating_sub(1);
                    let left = pl.saturating_sub(1);
                    let bottom = pb.saturating_sub(1);
                    let right = pr.saturating_sub(1);

                    let mut fill_cell = crate::cell::Cell::new(pc);
                    fill_cell.fg = self.fg;
                    fill_cell.bg = self.bg;
                    fill_cell
                        .flags
                        .set_fg_is_default(self.flags.fg_is_default());
                    fill_cell
                        .flags
                        .set_bg_is_default(self.flags.bg_is_default());
                    fill_cell.flags = self.flags;

                    self.active_grid_mut()
                        .fill_rectangle(fill_cell, top, left, bottom, right);
                    self.delete_graphics_in_rect(
                        left,
                        top,
                        right.saturating_add(1),
                        bottom.saturating_add(1),
                    );
                }
                'v' => {
                    // DECCRA - Copy Rectangular Area: CSI Pt ; Pl ; Pb ; Pr ; Pp ; Dt ; Dl ; Dp $ v
                    let mut iter = params.iter();
                    let pt = iter.next().and_then(|p| p.first()).copied().unwrap_or(1) as usize;
                    let pl = iter.next().and_then(|p| p.first()).copied().unwrap_or(1) as usize;
                    let pb = iter
                        .next()
                        .and_then(|p| p.first())
                        .copied()
                        .unwrap_or(rows as u16) as usize;
                    let pr = iter
                        .next()
                        .and_then(|p| p.first())
                        .copied()
                        .unwrap_or(cols as u16) as usize;
                    let _pp = iter.next(); // Source page
                    let dt = iter.next().and_then(|p| p.first()).copied().unwrap_or(1) as usize;
                    let dl = iter.next().and_then(|p| p.first()).copied().unwrap_or(1) as usize;

                    let src_top = pt.saturating_sub(1);
                    let src_left = pl.saturating_sub(1);
                    let src_bottom = pb.saturating_sub(1);
                    let src_right = pr.saturating_sub(1);
                    let dst_top = dt.saturating_sub(1);
                    let dst_left = dl.saturating_sub(1);

                    let copy_target_rect =
                        if src_top < rows && src_left < cols && dst_top < rows && dst_left < cols {
                            let src_bottom = src_bottom.min(rows.saturating_sub(1));
                            let src_right = src_right.min(cols.saturating_sub(1));
                            if src_top <= src_bottom && src_left <= src_right {
                                let height = src_bottom - src_top + 1;
                                let width = src_right - src_left + 1;
                                let dst_bottom = dst_top.saturating_add(height - 1).min(rows - 1);
                                let dst_right = dst_left.saturating_add(width - 1).min(cols - 1);
                                Some((dst_top, dst_left, dst_bottom, dst_right))
                            } else {
                                None
                            }
                        } else {
                            None
                        };

                    self.active_grid_mut().copy_rectangle(
                        src_top, src_left, src_bottom, src_right, dst_top, dst_left,
                    );
                    if let Some((dst_top, dst_left, dst_bottom, dst_right)) = copy_target_rect {
                        self.delete_graphics_in_rect(
                            dst_left,
                            dst_top,
                            dst_right.saturating_add(1),
                            dst_bottom.saturating_add(1),
                        );
                    }
                }
                'z' => {
                    // DECERA - Erase Rectangular Area: CSI Pt ; Pl ; Pb ; Pr $ z
                    let mut iter = params.iter();
                    let pt = iter.next().and_then(|p| p.first()).copied().unwrap_or(1) as usize;
                    let pl = iter.next().and_then(|p| p.first()).copied().unwrap_or(1) as usize;
                    let pb = iter
                        .next()
                        .and_then(|p| p.first())
                        .copied()
                        .unwrap_or(rows as u16) as usize;
                    let pr = iter
                        .next()
                        .and_then(|p| p.first())
                        .copied()
                        .unwrap_or(cols as u16) as usize;

                    let top = pt.saturating_sub(1);
                    let left = pl.saturating_sub(1);
                    let bottom = pb.saturating_sub(1);
                    let right = pr.saturating_sub(1);

                    self.active_grid_mut()
                        .erase_rectangle_unconditional(top, left, bottom, right);
                    self.delete_graphics_in_rect(
                        left,
                        top,
                        right.saturating_add(1),
                        bottom.saturating_add(1),
                    );
                }
                '{' => {
                    // DECSERA - Selective Erase Rectangular Area: CSI Pt ; Pl ; Pb ; Pr $ {
                    let mut iter = params.iter();
                    let pt = iter.next().and_then(|p| p.first()).copied().unwrap_or(1) as usize;
                    let pl = iter.next().and_then(|p| p.first()).copied().unwrap_or(1) as usize;
                    let pb = iter
                        .next()
                        .and_then(|p| p.first())
                        .copied()
                        .unwrap_or(rows as u16) as usize;
                    let pr = iter
                        .next()
                        .and_then(|p| p.first())
                        .copied()
                        .unwrap_or(cols as u16) as usize;

                    let top = pt.saturating_sub(1);
                    let left = pl.saturating_sub(1);
                    let bottom = pb.saturating_sub(1);
                    let right = pr.saturating_sub(1);

                    self.active_grid_mut()
                        .erase_rectangle(top, left, bottom, right);
                }
                'r' | 't' => {
                    // DECCARA - Change Attributes in Rectangular Area: CSI Pt ; Pl ; Pb ; Pr ; Ps1 ; Ps2 ... $ r
                    // DECRARA - Reverse Attributes in Rectangular Area: CSI Pt ; Pl ; Pb ; Pr ; Ps1 ; Ps2 ... $ t
                    let mut iter = params.iter();
                    let pt = iter.next().and_then(|p| p.first()).copied().unwrap_or(1) as usize;
                    let pl = iter.next().and_then(|p| p.first()).copied().unwrap_or(1) as usize;
                    let pb = iter
                        .next()
                        .and_then(|p| p.first())
                        .copied()
                        .unwrap_or(rows as u16) as usize;
                    let pr = iter
                        .next()
                        .and_then(|p| p.first())
                        .copied()
                        .unwrap_or(cols as u16) as usize;

                    let top = pt.saturating_sub(1);
                    let left = pl.saturating_sub(1);
                    let bottom = pb.saturating_sub(1);
                    let right = pr.saturating_sub(1);

                    let mut attributes = Vec::new();
                    for param_slice in iter {
                        if let Some(&p) = param_slice.first() {
                            attributes.push(p);
                        }
                    }

                    if action == 'r' {
                        self.active_grid_mut().change_attributes_in_rectangle(
                            top,
                            left,
                            bottom,
                            right,
                            &attributes,
                        );
                    } else {
                        self.active_grid_mut().reverse_attributes_in_rectangle(
                            top,
                            left,
                            bottom,
                            right,
                            &attributes,
                        );
                    }
                }
                _ => {}
            }
            return;
        }

        match action {
            't' => {
                // Window manipulation (XTWINOPS) or DECSWBV (Set Warning Bell Volume)
                let mut iter = params.iter();
                let n = iter.next().and_then(|p| p.first()).copied().unwrap_or(0);

                // DECSWBV - Set Warning Bell Volume: CSI Ps t or CSI Ps SP t
                if params.iter().count() == 1 && (n <= 8 || intermediates.contains(&b' ')) {
                    self.warning_bell_volume = n.min(8) as u8;
                    // If it was just a bell volume sequence, we can return early
                    // unless it's a value that overlaps with XTWINOPS (unlikely for n > 8)
                    if n > 8 {
                        return;
                    }
                }

                match n {
                    0..=8 => {
                        // Already handled above, but kept for match exhaustiveness/structure
                    }
                    14 => {
                        // Report text area size in pixels
                        let response =
                            format!("\x1b[4;{};{}t", self.pixel_height, self.pixel_width);
                        self.push_response(response.as_bytes());
                    }
                    16 => {
                        // Report character cell size in pixels
                        let (cpw, cph) = (10, 20); // Default cell size
                        let response = format!("\x1b[6;{};{}t", cph, cpw);
                        self.push_response(response.as_bytes());
                    }
                    18 => {
                        // Report text area size in characters
                        let response = format!("\x1b[8;{};{}t", rows, cols);
                        self.push_response(response.as_bytes());
                    }
                    20 if self.osc_capability_allowed(OscCapability::Appearance) => {
                        let response =
                            title_report(b'L', self.icon_name(), self.title_mode_enabled(1));
                        self.push_response(&response);
                    }
                    21 if self.osc_capability_allowed(OscCapability::Appearance) => {
                        let response = title_report(b'l', self.title(), self.title_mode_enabled(1));
                        self.push_response(&response);
                    }
                    22 => {
                        if self.osc_capability_allowed(OscCapability::Appearance) {
                            let selector = window_param(params, 1);
                            let index = window_param(params, 2);
                            let title = self.title.clone();
                            let icon_name = self.icon_name.clone();
                            self.title_stack.store(selector, index, &title, &icon_name);
                        }
                    }
                    23 => {
                        if self.osc_capability_allowed(OscCapability::Appearance) {
                            let selector = window_param(params, 1);
                            let index = window_param(params, 2);
                            if let Some(entry) = self.title_stack.restore(selector, index) {
                                if matches!(selector, 0 | 1) {
                                    if let Some(icon_name) = entry.icon_name {
                                        self.set_protocol_icon_name(icon_name);
                                    }
                                }
                                if matches!(selector, 0 | 2) {
                                    if let Some(title) = entry.window_title {
                                        self.set_protocol_window_title(title);
                                    }
                                }
                            }
                        }
                    }
                    _ => {}
                }
            }
            'r' => {
                // Set scrolling region (DECSTBM)
                let mut iter = params.iter();
                let top = iter.next().and_then(|p| p.first()).copied().unwrap_or(1) as usize;
                let bottom = iter.next().and_then(|p| p.first()).copied().unwrap_or(0) as usize;

                let top = if top == 0 { 1 } else { top };
                let bottom = if bottom == 0 { rows } else { bottom };

                let top = top.saturating_sub(1);
                let bottom = bottom.saturating_sub(1).min(rows.saturating_sub(1));

                if top < bottom {
                    self.scroll_region_top = top;
                    self.scroll_region_bottom = bottom;
                    // Reset cursor to (0,0) relative to region if origin mode
                    self.cursor.goto(0, if self.origin_mode { top } else { 0 });
                }
            }
            's' => {
                // Set left and right margins (DECSLRM) - only if DECLRMM is set
                if self.use_lr_margins {
                    let mut iter = params.iter();
                    let left = iter.next().and_then(|p| p.first()).copied().unwrap_or(1) as usize;
                    let right = iter
                        .next()
                        .and_then(|p| p.first())
                        .copied()
                        .unwrap_or(cols as u16) as usize;

                    let left = left.saturating_sub(1);
                    let right = right.saturating_sub(1).min(cols.saturating_sub(1));

                    if left < right {
                        self.left_margin = left;
                        self.right_margin = right;
                    }
                }
            }
            _ => {}
        }
    }

    fn handle_xterm_title_modes(&mut self, set: bool, params: &Params) {
        if !self.osc_capability_allowed(OscCapability::Appearance) {
            return;
        }
        let modes = params
            .iter()
            .flat_map(|values| values.iter().copied())
            .collect::<Vec<_>>();
        if modes.is_empty() {
            self.title_modes = 0;
            return;
        }
        for mode in modes {
            if mode < 4 {
                let bit = 1 << mode;
                if set {
                    self.title_modes |= bit;
                } else {
                    self.title_modes &= !bit;
                }
            }
        }
    }
}

fn window_param(params: &Params, index: usize) -> u16 {
    params
        .iter()
        .nth(index)
        .and_then(|values| values.first())
        .copied()
        .unwrap_or(0)
}

fn title_report(command: u8, text: &str, hex_encoded: bool) -> Vec<u8> {
    let mut response = Vec::with_capacity(5 + text.len() * if hex_encoded { 2 } else { 1 });
    response.extend_from_slice(b"\x1b]");
    response.push(command);
    if hex_encoded {
        const HEX: &[u8; 16] = b"0123456789ABCDEF";
        for byte in text.as_bytes() {
            response.push(HEX[usize::from(byte >> 4)]);
            response.push(HEX[usize::from(byte & 0x0f)]);
        }
    } else {
        response.extend_from_slice(text.as_bytes());
    }
    response.extend_from_slice(b"\x1b\\");
    response
}

fn xtsmgraphics_response(item: u16, status: u16, payload: &[u16]) -> String {
    let mut parts = vec![item, status];
    parts.extend_from_slice(payload);
    format!(
        "\x1b[?{}S",
        parts
            .iter()
            .map(u16::to_string)
            .collect::<Vec<String>>()
            .join(";")
    )
}
