//! Window-related CSI sequence handling (XTWINOPS, etc.)

use crate::terminal::Terminal;
use vte::Params;

const TITLE_STACK_LIMIT: usize = 32;

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
                    22 => {
                        // Push icon name and window title to stack
                        if self.title_stack.len() >= TITLE_STACK_LIMIT {
                            self.title_stack.remove(0);
                        }
                        self.title_stack.push(self.title.clone());
                    }
                    23 => {
                        // Pop icon name and window title from stack
                        if let Some(title) = self.title_stack.pop() {
                            self.title = title;
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
