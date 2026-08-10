//! Bounded wire model for Kitty OSC 72 drag-and-drop commands.

/// Maximum metadata bytes accepted before the payload separator.
pub const MAX_OSC72_METADATA_BYTES: usize = 1024;
/// Normative per-packet payload bound from the Kitty protocol.
pub const MAX_OSC72_PAYLOAD_BYTES: usize = 4096;

/// One Kitty OSC 72 command sent by the child process to the terminal host.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DragDropCommand {
    pub action: DragDropAction,
    pub more: bool,
    pub identifier: Option<u32>,
    pub operation: Option<u32>,
    pub x: Option<i32>,
    pub y: Option<i32>,
    pub pixel_x: Option<i32>,
    pub pixel_y: Option<i32>,
    pub payload: Vec<u8>,
}

impl DragDropCommand {
    pub(crate) fn retained_bytes(&self) -> usize {
        self.payload.len()
    }
}

/// OSC 72 `t` metadata values.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DragDropAction {
    AcceptDrops,
    StopAcceptingDrops,
    DropMove,
    Drop,
    RequestDropData,
    DropError,
    OfferDrag,
    PresentOfferData,
    PresentDragImage,
    OfferEvent,
    OfferError,
    UriListData,
    Query,
}

impl DragDropAction {
    pub const fn wire_name(self) -> &'static str {
        match self {
            Self::AcceptDrops => "a",
            Self::StopAcceptingDrops => "A",
            Self::DropMove => "m",
            Self::Drop => "M",
            Self::RequestDropData => "r",
            Self::DropError => "R",
            Self::OfferDrag => "o",
            Self::PresentOfferData => "p",
            Self::PresentDragImage => "P",
            Self::OfferEvent => "e",
            Self::OfferError => "E",
            Self::UriListData => "k",
            Self::Query => "q",
        }
    }

    pub(crate) const fn parse(value: u8) -> Option<Self> {
        match value {
            b'a' => Some(Self::AcceptDrops),
            b'A' => Some(Self::StopAcceptingDrops),
            b'm' => Some(Self::DropMove),
            b'M' => Some(Self::Drop),
            b'r' => Some(Self::RequestDropData),
            b'R' => Some(Self::DropError),
            b'o' => Some(Self::OfferDrag),
            b'p' => Some(Self::PresentOfferData),
            b'P' => Some(Self::PresentDragImage),
            b'e' => Some(Self::OfferEvent),
            b'E' => Some(Self::OfferError),
            b'k' => Some(Self::UriListData),
            b'q' => Some(Self::Query),
            _ => None,
        }
    }
}
