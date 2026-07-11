//! Kitty OSC 22 mouse-pointer shape state.

/// Ianvs keeps more than the protocol-required minimum of sixteen entries while
/// still bounding both screen-local stacks.
pub(crate) const MAX_POINTER_SHAPE_STACK_DEPTH: usize = 32;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum PointerShape {
    Alias,
    Cell,
    Copy,
    Crosshair,
    Default,
    EastResize,
    EastWestResize,
    Grab,
    Grabbing,
    Help,
    Move,
    NorthResize,
    NorthEastResize,
    NorthEastSouthWestResize,
    NoDrop,
    NotAllowed,
    NorthSouthResize,
    NorthWestResize,
    NorthWestSouthEastResize,
    Pointer,
    Progress,
    SouthResize,
    SouthEastResize,
    SouthWestResize,
    Text,
    VerticalText,
    WestResize,
    Wait,
    ZoomIn,
    ZoomOut,
}

impl PointerShape {
    pub(crate) const ALL: [Self; 30] = [
        Self::Alias,
        Self::Cell,
        Self::Copy,
        Self::Crosshair,
        Self::Default,
        Self::EastResize,
        Self::EastWestResize,
        Self::Grab,
        Self::Grabbing,
        Self::Help,
        Self::Move,
        Self::NorthResize,
        Self::NorthEastResize,
        Self::NorthEastSouthWestResize,
        Self::NoDrop,
        Self::NotAllowed,
        Self::NorthSouthResize,
        Self::NorthWestResize,
        Self::NorthWestSouthEastResize,
        Self::Pointer,
        Self::Progress,
        Self::SouthResize,
        Self::SouthEastResize,
        Self::SouthWestResize,
        Self::Text,
        Self::VerticalText,
        Self::WestResize,
        Self::Wait,
        Self::ZoomIn,
        Self::ZoomOut,
    ];

    pub(crate) const fn wire_name(self) -> &'static str {
        match self {
            Self::Alias => "alias",
            Self::Cell => "cell",
            Self::Copy => "copy",
            Self::Crosshair => "crosshair",
            Self::Default => "default",
            Self::EastResize => "e-resize",
            Self::EastWestResize => "ew-resize",
            Self::Grab => "grab",
            Self::Grabbing => "grabbing",
            Self::Help => "help",
            Self::Move => "move",
            Self::NorthResize => "n-resize",
            Self::NorthEastResize => "ne-resize",
            Self::NorthEastSouthWestResize => "nesw-resize",
            Self::NoDrop => "no-drop",
            Self::NotAllowed => "not-allowed",
            Self::NorthSouthResize => "ns-resize",
            Self::NorthWestResize => "nw-resize",
            Self::NorthWestSouthEastResize => "nwse-resize",
            Self::Pointer => "pointer",
            Self::Progress => "progress",
            Self::SouthResize => "s-resize",
            Self::SouthEastResize => "se-resize",
            Self::SouthWestResize => "sw-resize",
            Self::Text => "text",
            Self::VerticalText => "vertical-text",
            Self::WestResize => "w-resize",
            Self::Wait => "wait",
            Self::ZoomIn => "zoom-in",
            Self::ZoomOut => "zoom-out",
        }
    }

    pub(crate) fn parse_canonical(name: &str) -> Option<Self> {
        Self::ALL
            .into_iter()
            .find(|shape| shape.wire_name() == name)
    }

    /// Optional xterm/X11 compatibility aliases accepted by Kitty itself.
    pub(crate) fn parse_set_name(name: &str) -> Option<Self> {
        Self::parse_canonical(name).or_else(|| {
            Some(match name {
                "left_ptr" => Self::Default,
                "xterm" | "ibeam" => Self::Text,
                "pointing_hand" | "hand2" | "hand" => Self::Pointer,
                "question_arrow" | "whats_this" => Self::Help,
                "clock" | "watch" => Self::Wait,
                "half-busy" | "left_ptr_watch" => Self::Progress,
                "tcross" => Self::Crosshair,
                "plus" | "cross" => Self::Cell,
                "fleur" | "pointer-move" => Self::Move,
                "right_side" => Self::EastResize,
                "top_right_corner" => Self::NorthEastResize,
                "top_left_corner" => Self::NorthWestResize,
                "top_side" => Self::NorthResize,
                "bottom_right_corner" => Self::SouthEastResize,
                "bottom_left_corner" => Self::SouthWestResize,
                "bottom_side" => Self::SouthResize,
                "left_side" => Self::WestResize,
                "sb_h_double_arrow" | "split_h" => Self::EastWestResize,
                "sb_v_double_arrow" | "split_v" => Self::NorthSouthResize,
                "size_bdiag" | "size-bdiag" => Self::NorthEastSouthWestResize,
                "size_fdiag" | "size-fdiag" => Self::NorthWestSouthEastResize,
                "zoom_in" => Self::ZoomIn,
                "zoom_out" => Self::ZoomOut,
                "dnd-link" => Self::Alias,
                "dnd-copy" => Self::Copy,
                "forbidden" | "crossed_circle" => Self::NotAllowed,
                "dnd-no-drop" => Self::NoDrop,
                "openhand" | "hand1" => Self::Grab,
                "closedhand" | "dnd-none" => Self::Grabbing,
                _ => return None,
            })
        })
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub(crate) struct PointerShapeState {
    primary: Vec<Option<PointerShape>>,
    alternate: Vec<Option<PointerShape>>,
}

impl PointerShapeState {
    fn active_stack(&self, alternate_screen: bool) -> &Vec<Option<PointerShape>> {
        if alternate_screen {
            &self.alternate
        } else {
            &self.primary
        }
    }

    fn active_stack_mut(&mut self, alternate_screen: bool) -> &mut Vec<Option<PointerShape>> {
        if alternate_screen {
            &mut self.alternate
        } else {
            &mut self.primary
        }
    }

    pub(crate) fn current(&self, alternate_screen: bool) -> Option<PointerShape> {
        self.active_stack(alternate_screen)
            .last()
            .copied()
            .flatten()
    }

    pub(crate) fn set_current(
        &mut self,
        alternate_screen: bool,
        shape: Option<PointerShape>,
    ) -> bool {
        let stack = self.active_stack_mut(alternate_screen);
        if let Some(current) = stack.last_mut() {
            if *current == shape {
                return false;
            }
            *current = shape;
        } else {
            stack.push(shape);
        }
        true
    }

    pub(crate) fn push(&mut self, alternate_screen: bool, shape: PointerShape) -> bool {
        let stack = self.active_stack_mut(alternate_screen);
        if stack.len() == MAX_POINTER_SHAPE_STACK_DEPTH {
            stack.remove(0);
        }
        stack.push(Some(shape));
        true
    }

    pub(crate) fn pop(&mut self, alternate_screen: bool) -> bool {
        self.active_stack_mut(alternate_screen).pop().is_some()
    }

    #[cfg(test)]
    pub(crate) fn active_depth(&self, alternate_screen: bool) -> usize {
        self.active_stack(alternate_screen).len()
    }
}
