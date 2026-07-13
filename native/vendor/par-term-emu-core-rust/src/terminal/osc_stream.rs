//! Bounded, capability-aware ingress filtering for OSC control strings.
//!
//! `vte::Parser` intentionally accepts arbitrarily-sized OSC strings.  PTY
//! output is untrusted, so the terminal keeps a small streaming state machine
//! in front of VTE and only forwards complete OSC strings that fit the limit
//! for their semantic intent.  Rejected strings are discarded through their
//! terminator without retaining their payload.

use std::borrow::Cow;

const KIB: usize = 1024;
const MIB: usize = 1024 * KIB;
const MAX_OSC_COMMAND_BYTES: usize = 64;
const MAX_CLASSIFICATION_PREFIX_BYTES: usize = 128;

/// Semantic class used to select an OSC payload limit and report diagnostics.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum OscIntent {
    Appearance = 0,
    CurrentDirectory = 1,
    Hyperlink = 2,
    Notification = 3,
    ShellIntegration = 4,
    UserVariableOrBadge = 5,
    Clipboard = 6,
    Media = 7,
    FileTransfer = 8,
    IanvsPrivate = 9,
    DragDrop = 10,
    Custom = 11,
}

impl OscIntent {
    pub const COUNT: usize = 12;

    /// Maximum semantic payload bytes for this intent.
    pub const fn payload_limit(self) -> usize {
        match self {
            Self::Appearance | Self::CurrentDirectory | Self::UserVariableOrBadge => 4 * KIB,
            Self::Hyperlink | Self::ShellIntegration => 16 * KIB,
            Self::Notification | Self::IanvsPrivate => 8 * KIB,
            Self::DragDrop => 4 * KIB,
            Self::Clipboard => 4 * MIB,
            Self::Media | Self::FileTransfer => 64 * MIB,
            Self::Custom => 4 * KIB,
        }
    }
}

/// Capabilities that can be independently enabled for parsing.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OscCapability {
    Appearance,
    Metadata,
    Hyperlink,
    ClipboardWrite,
    ClipboardRead,
    Notification,
    Media,
    HostAction,
    FileTransfer,
    DragDrop,
    CustomProtocol,
}

/// Parser policy for OSC semantic capabilities.
///
/// Parsing a notification, hyperlink, file-transfer, or similar request does
/// not authorize the embedding application to execute it.  Consumers must
/// additionally check [`OscCapability::HostAction`] before performing an
/// external side effect.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct OscCapabilityPolicy {
    pub appearance: bool,
    pub metadata: bool,
    pub hyperlink: bool,
    pub clipboard_write: bool,
    pub clipboard_read: bool,
    pub notification: bool,
    pub media: bool,
    pub host_action: bool,
    pub file_transfer: bool,
    pub drag_drop: bool,
    pub custom_protocol: bool,
}

impl Default for OscCapabilityPolicy {
    fn default() -> Self {
        Self {
            // Preserve the parser's historical behavior by default.  Host
            // execution and clipboard reads remain opt-in.
            appearance: true,
            metadata: true,
            hyperlink: true,
            clipboard_write: true,
            clipboard_read: false,
            notification: true,
            media: true,
            host_action: false,
            file_transfer: true,
            // OSC 72 coordinates privileged OS drag/drop and file access.
            // Embedders must opt in only after installing a product bridge.
            drag_drop: false,
            custom_protocol: true,
        }
    }
}

impl OscCapabilityPolicy {
    pub const fn allows(self, capability: OscCapability) -> bool {
        match capability {
            OscCapability::Appearance => self.appearance,
            OscCapability::Metadata => self.metadata,
            OscCapability::Hyperlink => self.hyperlink,
            OscCapability::ClipboardWrite => self.clipboard_write,
            OscCapability::ClipboardRead => self.clipboard_read,
            OscCapability::Notification => self.notification,
            OscCapability::Media => self.media,
            OscCapability::HostAction => self.host_action,
            OscCapability::FileTransfer => self.file_transfer,
            OscCapability::DragDrop => self.drag_drop,
            OscCapability::CustomProtocol => self.custom_protocol,
        }
    }

    pub fn set(&mut self, capability: OscCapability, allowed: bool) {
        match capability {
            OscCapability::Appearance => self.appearance = allowed,
            OscCapability::Metadata => self.metadata = allowed,
            OscCapability::Hyperlink => self.hyperlink = allowed,
            OscCapability::ClipboardWrite => self.clipboard_write = allowed,
            OscCapability::ClipboardRead => self.clipboard_read = allowed,
            OscCapability::Notification => self.notification = allowed,
            OscCapability::Media => self.media = allowed,
            OscCapability::HostAction => self.host_action = allowed,
            OscCapability::FileTransfer => self.file_transfer = allowed,
            OscCapability::DragDrop => self.drag_drop = allowed,
            OscCapability::CustomProtocol => self.custom_protocol = allowed,
        }
    }

    /// Check permission for an external side effect requested by an OSC.
    pub const fn allows_host_action(self, capability: OscCapability) -> bool {
        self.host_action && self.allows(capability)
    }
}

/// Aggregate result counters for a single OSC intent.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct OscIntentDiagnostics {
    pub accepted: u64,
    pub oversized: u64,
    pub policy_denied: u64,
}

/// Payload-free diagnostics for the bounded OSC ingress gate.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct OscIngressDiagnostics {
    counters: [OscIntentDiagnostics; OscIntent::COUNT],
}

impl Default for OscIngressDiagnostics {
    fn default() -> Self {
        Self {
            counters: [OscIntentDiagnostics::default(); OscIntent::COUNT],
        }
    }
}

impl OscIngressDiagnostics {
    pub const fn for_intent(&self, intent: OscIntent) -> OscIntentDiagnostics {
        self.counters[intent as usize]
    }

    pub fn accepted_total(&self) -> u64 {
        self.counters.iter().map(|entry| entry.accepted).sum()
    }

    pub fn oversized_total(&self) -> u64 {
        self.counters.iter().map(|entry| entry.oversized).sum()
    }

    pub fn policy_denied_total(&self) -> u64 {
        self.counters.iter().map(|entry| entry.policy_denied).sum()
    }

    fn record_accepted(&mut self, intent: OscIntent) {
        let counter = &mut self.counters[intent as usize].accepted;
        *counter = counter.saturating_add(1);
    }

    fn record_oversized(&mut self, intent: OscIntent) {
        let counter = &mut self.counters[intent as usize].oversized;
        *counter = counter.saturating_add(1);
    }

    fn record_policy_denied(&mut self, intent: OscIntent) {
        let counter = &mut self.counters[intent as usize].policy_denied;
        *counter = counter.saturating_add(1);
    }
}

#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct OscClassificationContext {
    pub multipart_is_file_transfer: Option<bool>,
}

#[derive(Clone, Copy, Debug)]
struct Classification {
    intent: OscIntent,
    capability: OscCapability,
}

impl Classification {
    const fn new(intent: OscIntent, capability: OscCapability) -> Self {
        Self { intent, capability }
    }
}

#[derive(Clone, Copy, Debug, Default)]
struct Utf8Tracker {
    remaining: u8,
    next_min: u8,
    next_max: u8,
}

impl Utf8Tracker {
    fn is_idle(self) -> bool {
        self.remaining == 0
    }

    /// Consume a required continuation byte.  `false` asks the caller to
    /// re-evaluate the byte as a new scalar/control byte.
    fn consume_continuation(&mut self, byte: u8) -> bool {
        if self.remaining == 0 {
            return false;
        }
        if !(self.next_min..=self.next_max).contains(&byte) {
            *self = Self::default();
            return false;
        }
        self.remaining -= 1;
        self.next_min = 0x80;
        self.next_max = 0xbf;
        true
    }

    fn start(&mut self, byte: u8) {
        *self = match byte {
            0xc2..=0xdf => Self {
                remaining: 1,
                next_min: 0x80,
                next_max: 0xbf,
            },
            0xe0 => Self {
                remaining: 2,
                next_min: 0xa0,
                next_max: 0xbf,
            },
            0xe1..=0xec | 0xee..=0xef => Self {
                remaining: 2,
                next_min: 0x80,
                next_max: 0xbf,
            },
            0xed => Self {
                remaining: 2,
                next_min: 0x80,
                next_max: 0x9f,
            },
            0xf0 => Self {
                remaining: 3,
                next_min: 0x90,
                next_max: 0xbf,
            },
            0xf1..=0xf3 => Self {
                remaining: 3,
                next_min: 0x80,
                next_max: 0xbf,
            },
            0xf4 => Self {
                remaining: 3,
                next_min: 0x80,
                next_max: 0x8f,
            },
            _ => Self::default(),
        };
    }
}

#[derive(Clone, Debug, Default)]
enum ScanState {
    #[default]
    Ground,
    Escape,
    Osc(OscSequence),
}

#[derive(Clone, Debug)]
struct OscSequence {
    content: Vec<u8>,
    escape_pending: bool,
    utf8: Utf8Tracker,
    oversized_intent: Option<OscIntent>,
    command_separator: Option<usize>,
    classification: Classification,
    #[cfg(test)]
    classification_scan_bytes: usize,
}

impl Default for OscSequence {
    fn default() -> Self {
        Self {
            content: Vec::new(),
            escape_pending: false,
            utf8: Utf8Tracker::default(),
            oversized_intent: None,
            command_separator: None,
            classification: Classification::new(OscIntent::Custom, OscCapability::CustomProtocol),
            #[cfg(test)]
            classification_scan_bytes: 0,
        }
    }
}

impl OscSequence {
    fn append(&mut self, byte: u8, context: OscClassificationContext) {
        if self.oversized_intent.is_some() {
            return;
        }

        self.content.push(byte);
        if self.command_separator.is_none() {
            if byte == b';' {
                let separator = self.content.len() - 1;
                self.command_separator = Some(separator);
                self.refresh_classification(context);
                if separator > MAX_OSC_COMMAND_BYTES {
                    self.discard_oversized(context);
                }
            } else if self.content.len() > MAX_OSC_COMMAND_BYTES {
                self.discard_oversized(context);
            }
            return;
        }

        let separator = self.command_separator.expect("separator checked above");
        let payload_len = self.content.len().saturating_sub(separator + 1);
        if payload_len <= MAX_CLASSIFICATION_PREFIX_BYTES {
            self.refresh_classification(context);
        }
        if measured_payload_len(&self.content, separator, self.classification)
            > self.classification.intent.payload_limit()
        {
            self.discard_oversized(context);
        }
    }

    fn refresh_classification(&mut self, context: OscClassificationContext) {
        let Some(separator) = self.command_separator else {
            return;
        };
        let prefix_end = self
            .content
            .len()
            .min(separator + 1 + MAX_CLASSIFICATION_PREFIX_BYTES);
        self.classification = classify_osc(&self.content[..prefix_end], false, context);
        #[cfg(test)]
        {
            self.classification_scan_bytes =
                self.classification_scan_bytes.saturating_add(prefix_end);
        }
    }

    fn discard_oversized(&mut self, context: OscClassificationContext) {
        if self.oversized_intent.is_none() {
            // Resolve any classification (notably iTerm inline media versus
            // file transfer) that is intentionally deferred until completion.
            self.oversized_intent = Some(classify_osc(&self.content, true, context).intent);
            #[cfg(test)]
            {
                self.classification_scan_bytes = self
                    .classification_scan_bytes
                    .saturating_add(self.content.len());
            }
            // Drop the sensitive/untrusted payload immediately.  Only the
            // intent counter survives until the terminator.
            self.content = Vec::new();
        }
    }
}

/// Streaming OSC gate for the raw PTY byte stream.
///
/// Tmux auto-detection may return slices of that same raw stream; those bytes
/// must not be filtered a second time.
#[derive(Clone, Debug, Default)]
pub(crate) struct OscStreamGate {
    state: ScanState,
    ground_utf8: Utf8Tracker,
    ground_utf8_buffer: Vec<u8>,
    multipart_context_override: Option<Option<bool>>,
    diagnostics: OscIngressDiagnostics,
    #[cfg(test)]
    classification_scan_bytes: usize,
}

impl OscStreamGate {
    pub fn filter<'a>(
        &mut self,
        input: &'a [u8],
        policy: OscCapabilityPolicy,
        context: OscClassificationContext,
    ) -> Cow<'a, [u8]> {
        if let Some(tracker) = self.scan_passthrough(input) {
            self.ground_utf8 = tracker;
            return Cow::Borrowed(input);
        }

        // A rejected OSC may arrive in one enormous caller-provided chunk.
        // Reserving the whole chunk here would recreate the memory-exhaustion
        // problem the gate exists to prevent.
        let mut output = Vec::with_capacity(input.len().min(64 * KIB));
        for &byte in input {
            self.process_byte(byte, policy, context, &mut output);
        }
        Cow::Owned(output)
    }

    pub const fn diagnostics(&self) -> OscIngressDiagnostics {
        self.diagnostics
    }

    pub fn take_diagnostics(&mut self) -> OscIngressDiagnostics {
        std::mem::take(&mut self.diagnostics)
    }

    /// Bytes retained while waiting for a split UTF-8 scalar or OSC terminator.
    pub(crate) fn retained_bytes(&self) -> usize {
        let sequence_bytes = match &self.state {
            ScanState::Osc(sequence) => sequence.content.len(),
            _ => 0,
        };
        self.ground_utf8_buffer.len().saturating_add(sequence_bytes)
    }

    /// Clear an incomplete control string while retaining session diagnostics.
    pub fn reset_in_flight(&mut self) {
        self.state = ScanState::Ground;
        self.ground_utf8 = Utf8Tracker::default();
        self.ground_utf8_buffer.clear();
        self.multipart_context_override = None;
    }

    #[cfg(test)]
    fn classification_scan_bytes(&self) -> usize {
        let in_flight = match &self.state {
            ScanState::Osc(sequence) => sequence.classification_scan_bytes,
            _ => 0,
        };
        self.classification_scan_bytes.saturating_add(in_flight)
    }

    fn scan_passthrough(&self, input: &[u8]) -> Option<Utf8Tracker> {
        if !matches!(self.state, ScanState::Ground) || !self.ground_utf8_buffer.is_empty() {
            return None;
        }

        let mut tracker = self.ground_utf8;
        for &byte in input {
            if !tracker.is_idle() && tracker.consume_continuation(byte) {
                continue;
            }
            if byte == b'\x1b' || byte == 0x9d {
                return None;
            }
            tracker.start(byte);
        }
        tracker.is_idle().then_some(tracker)
    }

    fn process_byte(
        &mut self,
        byte: u8,
        policy: OscCapabilityPolicy,
        external_context: OscClassificationContext,
        output: &mut Vec<u8>,
    ) {
        let mut reprocess = true;
        while reprocess {
            let context = OscClassificationContext {
                multipart_is_file_transfer: self
                    .multipart_context_override
                    .unwrap_or(external_context.multipart_is_file_transfer),
            };
            reprocess = false;
            match &mut self.state {
                ScanState::Ground => {
                    if !self.ground_utf8.is_idle() {
                        if self.ground_utf8.consume_continuation(byte) {
                            self.ground_utf8_buffer.push(byte);
                            if self.ground_utf8.is_idle() {
                                output.append(&mut self.ground_utf8_buffer);
                            }
                            continue;
                        }
                        // Preserve malformed/incomplete bytes exactly, then
                        // interpret the current byte independently.
                        output.append(&mut self.ground_utf8_buffer);
                        reprocess = true;
                        continue;
                    }
                    match byte {
                        b'\x1b' => self.state = ScanState::Escape,
                        0x9d => self.state = ScanState::Osc(OscSequence::default()),
                        _ => {
                            self.ground_utf8.start(byte);
                            if self.ground_utf8.is_idle() {
                                output.push(byte);
                            } else {
                                self.ground_utf8_buffer.push(byte);
                            }
                        }
                    }
                }
                ScanState::Escape => {
                    if byte == b']' {
                        self.state = ScanState::Osc(OscSequence::default());
                    } else {
                        output.push(b'\x1b');
                        self.state = ScanState::Ground;
                        reprocess = true;
                    }
                }
                ScanState::Osc(sequence) => {
                    if sequence.escape_pending {
                        sequence.escape_pending = false;
                        if byte == b'\\' {
                            self.finish_osc(policy, context, false, output);
                            continue;
                        }
                        sequence.append(b'\x1b', context);
                        reprocess = true;
                        continue;
                    }

                    if !sequence.utf8.is_idle() && sequence.utf8.consume_continuation(byte) {
                        sequence.append(byte, context);
                        continue;
                    }

                    match byte {
                        b'\x07' => self.finish_osc(policy, context, true, output),
                        0x9c => self.finish_osc(policy, context, false, output),
                        b'\x1b' => sequence.escape_pending = true,
                        _ => {
                            sequence.utf8.start(byte);
                            sequence.append(byte, context);
                        }
                    }
                }
            }
        }
    }

    fn finish_osc(
        &mut self,
        policy: OscCapabilityPolicy,
        context: OscClassificationContext,
        bell_terminated: bool,
        output: &mut Vec<u8>,
    ) {
        let ScanState::Osc(mut sequence) = std::mem::take(&mut self.state) else {
            return;
        };
        #[cfg(test)]
        {
            // Completion performs at most one whole-sequence classification.
            self.classification_scan_bytes = self
                .classification_scan_bytes
                .saturating_add(sequence.classification_scan_bytes)
                .saturating_add(sequence.content.len());
        }
        self.ground_utf8 = Utf8Tracker::default();
        self.ground_utf8_buffer.clear();

        if let Some(intent) = sequence.oversized_intent {
            self.diagnostics.record_oversized(intent);
            return;
        }

        let classification = classify_osc(&sequence.content, true, context);
        match multipart_transition(&sequence.content) {
            Some(MultipartTransition::Started { file_transfer }) => {
                self.multipart_context_override = Some(Some(file_transfer));
            }
            Some(MultipartTransition::Ended) => {
                self.multipart_context_override = Some(None);
            }
            None => {}
        }
        if !policy.allows(classification.capability) {
            self.diagnostics.record_policy_denied(classification.intent);
            return;
        }
        self.diagnostics.record_accepted(classification.intent);
        output.extend_from_slice(b"\x1b]");
        output.append(&mut sequence.content);
        if bell_terminated {
            output.push(b'\x07');
        } else {
            output.extend_from_slice(b"\x1b\\");
        }
    }
}

#[derive(Clone, Copy, Debug)]
enum MultipartTransition {
    Started { file_transfer: bool },
    Ended,
}

fn multipart_transition(content: &[u8]) -> Option<MultipartTransition> {
    let payload = content.strip_prefix(b"1337;")?;
    if payload.starts_with(b"MultipartFile=") {
        let inline = payload
            .split(|byte| *byte == b';')
            .any(|parameter| parameter == b"inline=1" || parameter == b"MultipartFile=inline=1");
        return Some(MultipartTransition::Started {
            file_transfer: !inline,
        });
    }
    if payload.starts_with(b"File=") || payload == b"FileEnd" {
        return Some(MultipartTransition::Ended);
    }
    None
}

fn measured_payload_len(content: &[u8], separator: usize, classification: Classification) -> usize {
    let command = &content[..separator];
    let payload = &content[separator + 1..];
    match (command, classification.intent) {
        (b"9", OscIntent::CurrentDirectory) => payload.strip_prefix(b"9;").unwrap_or(payload).len(),
        (b"633", OscIntent::CurrentDirectory) => {
            payload.strip_prefix(b"P;Cwd=").unwrap_or(payload).len()
        }
        (b"1337", OscIntent::CurrentDirectory) => payload
            .strip_prefix(b"CurrentDir=")
            .or_else(|| payload.strip_prefix(b"RemoteHost="))
            .unwrap_or(payload)
            .len(),
        (b"1337", OscIntent::UserVariableOrBadge) => payload
            .strip_prefix(b"SetBadgeFormat=")
            .or_else(|| payload.strip_prefix(b"SetUserVar="))
            .unwrap_or(payload)
            .len(),
        (b"52" | b"5522", OscIntent::Clipboard) => payload
            .iter()
            .take(MAX_OSC_COMMAND_BYTES + 1)
            .position(|byte| *byte == b';')
            .map_or(payload.len(), |selection_end| {
                payload.len().saturating_sub(selection_end + 1)
            }),
        // The OSC 934 version-1 specification defines its 8 KiB boundary
        // over the complete `934;...` payload, matching the command parser.
        (b"66", OscIntent::Appearance) | (b"72", OscIntent::DragDrop) => payload
            .iter()
            .position(|byte| *byte == b';')
            .map_or(payload.len(), |metadata_end| {
                payload.len().saturating_sub(metadata_end + 1)
            }),
        (b"934", OscIntent::IanvsPrivate) => content.len(),
        _ => payload.len(),
    }
}

fn classify_osc(
    content: &[u8],
    complete: bool,
    context: OscClassificationContext,
) -> Classification {
    let (command, payload) = match content.iter().position(|byte| *byte == b';') {
        Some(separator) => (&content[..separator], &content[separator + 1..]),
        None if complete => (content, &[][..]),
        None => {
            return Classification::new(OscIntent::Custom, OscCapability::CustomProtocol);
        }
    };

    match command {
        b"0" | b"1" | b"2" | b"4" | b"5" | b"6" | b"10" | b"11" | b"12" | b"13" | b"14" | b"15"
        | b"16" | b"17" | b"18" | b"19" | b"21" | b"22" | b"23" | b"66" | b"104" | b"105"
        | b"106" | b"110" | b"111" | b"112" | b"113" | b"114" | b"115" | b"116" | b"117"
        | b"118" | b"119" => Classification::new(OscIntent::Appearance, OscCapability::Appearance),
        b"7" => Classification::new(OscIntent::CurrentDirectory, OscCapability::Metadata),
        b"8" => Classification::new(OscIntent::Hyperlink, OscCapability::Hyperlink),
        b"72" => Classification::new(OscIntent::DragDrop, OscCapability::DragDrop),
        b"9" => classify_osc_9(payload, complete),
        b"52" => {
            if !complete
                && payload.len() > MAX_OSC_COMMAND_BYTES
                && !payload
                    .iter()
                    .take(MAX_OSC_COMMAND_BYTES + 1)
                    .any(|byte| *byte == b';')
            {
                return Classification::new(OscIntent::Custom, OscCapability::CustomProtocol);
            }
            let capability = if complete && osc_52_is_read_query(payload) {
                OscCapability::ClipboardRead
            } else {
                OscCapability::ClipboardWrite
            };
            Classification::new(OscIntent::Clipboard, capability)
        }
        b"5522" => {
            let capability = if complete && osc_5522_is_type_list_query(payload) {
                // The official protocol explicitly permits MIME enumeration
                // without a read prompt. It returns names, never clipboard data.
                OscCapability::ClipboardWrite
            } else if payload.starts_with(b"type=read") {
                OscCapability::ClipboardRead
            } else {
                OscCapability::ClipboardWrite
            };
            Classification::new(OscIntent::Clipboard, capability)
        }
        b"133" => Classification::new(OscIntent::ShellIntegration, OscCapability::Metadata),
        b"21337" => Classification::new(OscIntent::Appearance, OscCapability::Appearance),
        b"3008" => Classification::new(OscIntent::ShellIntegration, OscCapability::Metadata),
        b"633" => {
            if payload.starts_with(b"P;Cwd=") {
                Classification::new(OscIntent::CurrentDirectory, OscCapability::Metadata)
            } else {
                Classification::new(OscIntent::ShellIntegration, OscCapability::Metadata)
            }
        }
        b"99" | b"777" => Classification::new(OscIntent::Notification, OscCapability::Notification),
        // Ianvs-private progress/capability protocol has its own documented
        // 8 KiB bound, independent of the generic custom-protocol limit.
        b"934" => Classification::new(OscIntent::IanvsPrivate, OscCapability::CustomProtocol),
        b"1337" => classify_osc_1337(payload, context, complete),
        _ => Classification::new(OscIntent::Custom, OscCapability::CustomProtocol),
    }
}

fn osc_5522_is_type_list_query(payload: &[u8]) -> bool {
    payload.starts_with(b"type=read")
        && payload
            .splitn(2, |byte| *byte == b';')
            .nth(1)
            .is_some_and(|encoded| encoded == b"Lg==")
}

fn classify_osc_9(payload: &[u8], complete: bool) -> Classification {
    if payload.starts_with(b"9;") || (complete && payload == b"9") {
        Classification::new(OscIntent::CurrentDirectory, OscCapability::Metadata)
    } else if payload.starts_with(b"4;") || (complete && payload == b"4") {
        // Progress is metadata, not authorization for a system notification.
        Classification::new(OscIntent::Notification, OscCapability::Metadata)
    } else {
        Classification::new(OscIntent::Notification, OscCapability::Notification)
    }
}

fn osc_52_is_read_query(payload: &[u8]) -> bool {
    payload
        .iter()
        .position(|byte| *byte == b';')
        .is_some_and(|separator| &payload[separator + 1..] == b"?")
}

fn classify_osc_1337(
    payload: &[u8],
    context: OscClassificationContext,
    complete: bool,
) -> Classification {
    if payload == b"CopyToClipboard"
        || payload.starts_with(b"CopyToClipboard=")
        || (!complete && b"CopyToClipboard=".starts_with(payload))
        || payload == b"EndCopy"
        || (!complete && b"EndCopy".starts_with(payload))
        || payload.starts_with(b"Copy=:")
        || (!complete && b"Copy=:".starts_with(payload))
    {
        return Classification::new(OscIntent::Clipboard, OscCapability::ClipboardWrite);
    }
    if payload == b"SetMark"
        || (!complete && b"SetMark".starts_with(payload))
        || payload == b"ClearScrollback"
        || (!complete && b"ClearScrollback".starts_with(payload))
        || payload.starts_with(b"ShellIntegrationVersion=")
        || (!complete && b"ShellIntegrationVersion=".starts_with(payload))
        || payload.starts_with(b"AddAnnotation=")
        || (!complete && b"AddAnnotation=".starts_with(payload))
        || payload.starts_with(b"AddHiddenAnnotation=")
        || (!complete && b"AddHiddenAnnotation=".starts_with(payload))
        || payload.starts_with(b"AddNote=")
        || (!complete && b"AddNote=".starts_with(payload))
        || payload.starts_with(b"AddHiddenNote=")
        || (!complete && b"AddHiddenNote=".starts_with(payload))
    {
        return Classification::new(OscIntent::ShellIntegration, OscCapability::Metadata);
    }
    if payload == b"ReportCellSize" || (!complete && b"ReportCellSize".starts_with(payload)) {
        return Classification::new(OscIntent::Appearance, OscCapability::Appearance);
    }
    if payload == b"HighlightCursorLine"
        || payload.starts_with(b"HighlightCursorLine=")
        || (!complete && b"HighlightCursorLine=".starts_with(payload))
    {
        return Classification::new(OscIntent::Appearance, OscCapability::Appearance);
    }
    if payload.starts_with(b"CursorShape=") || (!complete && b"CursorShape=".starts_with(payload)) {
        return Classification::new(OscIntent::Appearance, OscCapability::Appearance);
    }
    if payload.starts_with(b"SetColors=") || (!complete && b"SetColors=".starts_with(payload)) {
        return Classification::new(OscIntent::Appearance, OscCapability::Appearance);
    }
    if payload.starts_with(b"SetBadgeFormat=") {
        return Classification::new(OscIntent::UserVariableOrBadge, OscCapability::Appearance);
    }
    if payload.starts_with(b"SetUserVar=") {
        return Classification::new(OscIntent::UserVariableOrBadge, OscCapability::Metadata);
    }
    if payload.starts_with(b"RemoteHost=") || payload.starts_with(b"CurrentDir=") {
        return Classification::new(OscIntent::CurrentDirectory, OscCapability::Metadata);
    }
    if payload.starts_with(b"RequestUpload=") {
        return Classification::new(OscIntent::FileTransfer, OscCapability::FileTransfer);
    }
    if payload.starts_with(b"File=") || payload.starts_with(b"MultipartFile=") {
        if !complete {
            // Media and file-transfer data share the same 64 MiB ingress
            // limit.  Avoid rescanning a potentially huge, unterminated
            // header on every byte; resolve `inline=1` once at termination.
            return Classification::new(OscIntent::FileTransfer, OscCapability::FileTransfer);
        }
        let header = payload
            .split(|byte| *byte == b':')
            .next()
            .unwrap_or(payload);
        let inline = header.split(|byte| *byte == b';').any(|parameter| {
            parameter == b"inline=1"
                || parameter == b"File=inline=1"
                || parameter == b"MultipartFile=inline=1"
        });
        return if inline {
            Classification::new(OscIntent::Media, OscCapability::Media)
        } else {
            Classification::new(OscIntent::FileTransfer, OscCapability::FileTransfer)
        };
    }
    if payload.starts_with(b"FilePart=") || payload == b"FileEnd" {
        return if context.multipart_is_file_transfer == Some(false) {
            Classification::new(OscIntent::Media, OscCapability::Media)
        } else {
            Classification::new(OscIntent::FileTransfer, OscCapability::FileTransfer)
        };
    }

    Classification::new(OscIntent::Custom, OscCapability::CustomProtocol)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::terminal::Terminal;
    use std::time::{Duration, Instant};

    fn filter_owned(
        gate: &mut OscStreamGate,
        input: &[u8],
        policy: OscCapabilityPolicy,
        context: OscClassificationContext,
    ) -> Vec<u8> {
        gate.filter(input, policy, context).into_owned()
    }

    fn tmux_passthrough(inner: &[u8]) -> Vec<u8> {
        let mut wrapped = b"\x1bPtmux;".to_vec();
        for &byte in inner {
            if byte == b'\x1b' {
                wrapped.push(byte);
            }
            wrapped.push(byte);
        }
        wrapped.extend_from_slice(b"\x1b\\");
        wrapped
    }

    fn screen_passthrough(inner: &[u8]) -> Vec<u8> {
        let mut wrapped = b"\x1bP".to_vec();
        wrapped.extend_from_slice(inner);
        wrapped.extend_from_slice(b"\x1b\\");
        wrapped
    }

    #[test]
    fn intent_limits_match_protocol_budget() {
        assert_eq!(OscIntent::Appearance.payload_limit(), 4 * KIB);
        assert_eq!(OscIntent::CurrentDirectory.payload_limit(), 4 * KIB);
        assert_eq!(OscIntent::Hyperlink.payload_limit(), 16 * KIB);
        assert_eq!(OscIntent::Notification.payload_limit(), 8 * KIB);
        assert_eq!(OscIntent::ShellIntegration.payload_limit(), 16 * KIB);
        assert_eq!(OscIntent::UserVariableOrBadge.payload_limit(), 4 * KIB);
        assert_eq!(OscIntent::Clipboard.payload_limit(), 4 * MIB);
        assert_eq!(OscIntent::Media.payload_limit(), 64 * MIB);
        assert_eq!(OscIntent::FileTransfer.payload_limit(), 64 * MIB);
        assert_eq!(OscIntent::IanvsPrivate.payload_limit(), 8 * KIB);
        assert_eq!(OscIntent::DragDrop.payload_limit(), 4 * KIB);
        assert_eq!(OscIntent::Custom.payload_limit(), 4 * KIB);
    }

    #[test]
    fn fragmented_bel_st_utf8_and_non_terminating_escape_are_preserved() {
        let mut gate = OscStreamGate::default();
        let policy = OscCapabilityPolicy::default();
        let context = OscClassificationContext::default();

        assert!(filter_owned(&mut gate, b"before\x1b", policy, context).starts_with(b"before"));
        assert!(filter_owned(&mut gate, b"]2;\xd1", policy, context).is_empty());
        // 0x9c is both a C1 ST byte and the continuation byte of U+045C.
        assert!(filter_owned(&mut gate, b"\x9c-x\x1b", policy, context).is_empty());
        let completed = filter_owned(&mut gate, b"X-end\x1b", policy, context);
        assert!(completed.is_empty());
        let completed = filter_owned(&mut gate, b"\\after", policy, context);
        assert_eq!(completed, b"\x1b]2;\xd1\x9c-x\x1bX-end\x1b\\after");

        assert_eq!(
            gate.diagnostics()
                .for_intent(OscIntent::Appearance)
                .accepted,
            1
        );
    }

    #[test]
    fn oversize_sequence_discards_until_terminator_then_recovers() {
        let mut gate = OscStreamGate::default();
        let policy = OscCapabilityPolicy::default();
        let context = OscClassificationContext::default();
        let mut input = b"\x1b]2;".to_vec();
        input.extend(std::iter::repeat_n(b'x', 4 * KIB + 1));
        input.extend_from_slice(b"\x07visible");

        let filtered = filter_owned(&mut gate, &input, policy, context);
        assert_eq!(filtered, b"visible");
        let diagnostics = gate.diagnostics().for_intent(OscIntent::Appearance);
        assert_eq!(diagnostics.oversized, 1);
        assert_eq!(diagnostics.accepted, 0);
    }

    #[test]
    fn osc66_ingress_applies_the_4k_limit_to_text_not_metadata() {
        let policy = OscCapabilityPolicy::default();
        let context = OscClassificationContext::default();

        let mut exact = b"\x1b]66;s=2:w=2;".to_vec();
        exact.extend(std::iter::repeat_n(b'x', 4 * KIB));
        exact.push(b'\x07');
        let mut exact_gate = OscStreamGate::default();
        assert_eq!(
            filter_owned(&mut exact_gate, &exact, policy, context),
            exact
        );
        assert_eq!(
            exact_gate
                .diagnostics()
                .for_intent(OscIntent::Appearance)
                .accepted,
            1
        );

        let mut oversized = b"\x1b]66;s=2:w=2;".to_vec();
        oversized.extend(std::iter::repeat_n(b'x', 4 * KIB + 1));
        oversized.extend_from_slice(b"\x07recovered");
        let mut oversized_gate = OscStreamGate::default();
        assert_eq!(
            filter_owned(&mut oversized_gate, &oversized, policy, context),
            b"recovered"
        );
        assert_eq!(
            oversized_gate
                .diagnostics()
                .for_intent(OscIntent::Appearance)
                .oversized,
            1
        );
    }

    #[test]
    fn osc72_ingress_is_opt_in_and_bounds_each_encoded_payload() {
        let mut policy = OscCapabilityPolicy::default();
        let context = OscClassificationContext::default();
        let mut exact = b"\x1b]72;t=p:i=7:x=0;".to_vec();
        exact.extend(std::iter::repeat_n(b'A', 4 * KIB));
        exact.extend_from_slice(b"\x1b\\");

        let mut denied_gate = OscStreamGate::default();
        assert!(filter_owned(&mut denied_gate, &exact, policy, context).is_empty());
        assert_eq!(
            denied_gate
                .diagnostics()
                .for_intent(OscIntent::DragDrop)
                .policy_denied,
            1
        );

        policy.set(OscCapability::DragDrop, true);
        let mut exact_gate = OscStreamGate::default();
        assert_eq!(
            filter_owned(&mut exact_gate, &exact, policy, context),
            exact
        );

        let mut oversized = b"\x1b]72;t=p:i=7:x=0;".to_vec();
        oversized.extend(std::iter::repeat_n(b'A', 4 * KIB + 1));
        oversized.extend_from_slice(b"\x1b\\recovered");
        let mut oversized_gate = OscStreamGate::default();
        assert_eq!(
            filter_owned(&mut oversized_gate, &oversized, policy, context),
            b"recovered"
        );
        assert_eq!(
            oversized_gate
                .diagnostics()
                .for_intent(OscIntent::DragDrop)
                .oversized,
            1
        );
    }

    #[test]
    fn osc1337_shell_metadata_and_cell_query_use_independent_safe_capabilities() {
        let context = OscClassificationContext::default();
        let mark = b"\x1b]1337;SetMark\x1b\\";
        let version = b"\x1b]1337;ShellIntegrationVersion=17;zsh\x07";
        let cell_query = b"\x1b]1337;ReportCellSize\x1b\\";

        let mut metadata_denied = OscCapabilityPolicy::default();
        metadata_denied.set(OscCapability::Metadata, false);
        let mut gate = OscStreamGate::default();
        assert!(filter_owned(&mut gate, mark, metadata_denied, context).is_empty());
        assert!(filter_owned(&mut gate, version, metadata_denied, context).is_empty());
        assert_eq!(
            gate.diagnostics()
                .for_intent(OscIntent::ShellIntegration)
                .policy_denied,
            2
        );
        assert_eq!(
            filter_owned(&mut gate, cell_query, metadata_denied, context),
            cell_query
        );

        let mut appearance_denied = OscCapabilityPolicy::default();
        appearance_denied.set(OscCapability::Appearance, false);
        let mut gate = OscStreamGate::default();
        assert!(filter_owned(&mut gate, cell_query, appearance_denied, context).is_empty());
        assert_eq!(
            gate.diagnostics()
                .for_intent(OscIntent::Appearance)
                .policy_denied,
            1
        );
        assert_eq!(
            filter_owned(&mut gate, mark, appearance_denied, context),
            mark
        );
    }

    #[test]
    fn osc1337_clear_scrollback_is_bounded_metadata_not_a_host_action() {
        let sequence = b"\x1b]1337;ClearScrollback\x1b\\";

        let classification = classify_osc(
            &sequence[2..sequence.len() - 2],
            true,
            OscClassificationContext::default(),
        );
        assert_eq!(classification.intent, OscIntent::ShellIntegration);
        assert_eq!(classification.capability, OscCapability::Metadata);

        let mut metadata_denied = OscCapabilityPolicy::default();
        metadata_denied.set(OscCapability::Metadata, false);
        let mut gate = OscStreamGate::default();
        let output = filter_owned(
            &mut gate,
            sequence,
            metadata_denied,
            OscClassificationContext::default(),
        );
        assert!(output.is_empty());
        assert_eq!(
            gate.diagnostics()
                .for_intent(OscIntent::ShellIntegration)
                .policy_denied,
            1
        );

        let mut appearance_denied = OscCapabilityPolicy::default();
        appearance_denied.set(OscCapability::Appearance, false);
        let mut gate = OscStreamGate::default();
        let output = filter_owned(
            &mut gate,
            sequence,
            appearance_denied,
            OscClassificationContext::default(),
        );
        assert_eq!(output, sequence);
        assert!(!appearance_denied.allows_host_action(OscCapability::Metadata));
    }

    #[test]
    fn osc1337_cursor_guide_is_bounded_appearance_not_a_host_action() {
        let sequence = b"\x1b]1337;HighlightCursorLine=yes\x1b\\";
        let classification = classify_osc(
            &sequence[2..sequence.len() - 2],
            true,
            OscClassificationContext::default(),
        );
        assert_eq!(classification.intent, OscIntent::Appearance);
        assert_eq!(classification.capability, OscCapability::Appearance);

        let mut appearance_denied = OscCapabilityPolicy::default();
        appearance_denied.set(OscCapability::Appearance, false);
        let mut gate = OscStreamGate::default();
        assert!(filter_owned(
            &mut gate,
            sequence,
            appearance_denied,
            OscClassificationContext::default(),
        )
        .is_empty());
        assert_eq!(
            gate.diagnostics().for_intent(OscIntent::Appearance),
            OscIntentDiagnostics {
                policy_denied: 1,
                ..OscIntentDiagnostics::default()
            }
        );
        assert!(!appearance_denied.allows_host_action(OscCapability::Appearance));

        let oversized = format!(
            "\x1b]1337;HighlightCursorLine={}\x07",
            "y".repeat(OscIntent::Appearance.payload_limit() + 1)
        );
        let mut gate = OscStreamGate::default();
        assert!(filter_owned(
            &mut gate,
            oversized.as_bytes(),
            OscCapabilityPolicy::default(),
            OscClassificationContext::default(),
        )
        .is_empty());
        assert_eq!(
            gate.diagnostics()
                .for_intent(OscIntent::Appearance)
                .oversized,
            1
        );
    }

    #[test]
    fn osc1337_clipboard_commands_are_bounded_policy_gated_writes() {
        for sequence in [
            b"\x1b]1337;CopyToClipboard\x07".as_slice(),
            b"\x1b]1337;CopyToClipboard=find\x1b\\".as_slice(),
            b"\x1b]1337;EndCopy\x07".as_slice(),
            b"\x1b]1337;Copy=:aGVsbG8=\x1b\\".as_slice(),
        ] {
            let classification = classify_osc(
                &sequence[2..sequence.len() - if sequence.ends_with(b"\x1b\\") { 2 } else { 1 }],
                true,
                OscClassificationContext::default(),
            );
            assert_eq!(classification.intent, OscIntent::Clipboard);
            assert_eq!(classification.capability, OscCapability::ClipboardWrite);
        }

        let mut denied = OscCapabilityPolicy::default();
        denied.set(OscCapability::ClipboardWrite, false);
        let mut gate = OscStreamGate::default();
        let stream = b"\x1b]1337;CopyToClipboard\x07visible\x1b]1337;EndCopy\x07";
        assert_eq!(
            filter_owned(
                &mut gate,
                stream,
                denied,
                OscClassificationContext::default(),
            ),
            b"visible"
        );
        assert_eq!(
            gate.diagnostics().for_intent(OscIntent::Clipboard),
            OscIntentDiagnostics {
                policy_denied: 2,
                ..OscIntentDiagnostics::default()
            }
        );

        let oversized = format!(
            "\x1b]1337;Copy=:{}\x07",
            "A".repeat(OscIntent::Clipboard.payload_limit() + 1)
        );
        let mut gate = OscStreamGate::default();
        assert!(filter_owned(
            &mut gate,
            oversized.as_bytes(),
            OscCapabilityPolicy::default(),
            OscClassificationContext::default(),
        )
        .is_empty());
        assert_eq!(
            gate.diagnostics()
                .for_intent(OscIntent::Clipboard)
                .oversized,
            1
        );
    }

    #[test]
    fn osc1337_annotations_are_bounded_metadata_without_host_authority() {
        for sequence in [
            b"\x1b]1337;AddAnnotation=4|note\x07".as_slice(),
            b"\x1b]1337;AddHiddenAnnotation=hidden\x1b\\".as_slice(),
            b"\x1b]1337;AddNote=3|legacy\x07".as_slice(),
            b"\x1b]1337;AddHiddenNote=legacy\x07".as_slice(),
        ] {
            let payload_end = sequence.len() - if sequence.ends_with(b"\x1b\\") { 2 } else { 1 };
            let classification = classify_osc(
                &sequence[2..payload_end],
                true,
                OscClassificationContext::default(),
            );
            assert_eq!(classification.intent, OscIntent::ShellIntegration);
            assert_eq!(classification.capability, OscCapability::Metadata);
            assert_ne!(classification.capability, OscCapability::HostAction);
        }

        let mut denied = OscCapabilityPolicy::default();
        denied.set(OscCapability::Metadata, false);
        let mut gate = OscStreamGate::default();
        assert_eq!(
            filter_owned(
                &mut gate,
                b"before\x1b]1337;AddAnnotation=4|note\x07word after",
                denied,
                OscClassificationContext::default(),
            ),
            b"beforeword after"
        );
        assert_eq!(
            gate.diagnostics()
                .for_intent(OscIntent::ShellIntegration)
                .policy_denied,
            1
        );

        let oversized = format!(
            "\x1b]1337;AddAnnotation={}|note\x07",
            "4".repeat(OscIntent::ShellIntegration.payload_limit() + 1)
        );
        let mut gate = OscStreamGate::default();
        assert!(filter_owned(
            &mut gate,
            oversized.as_bytes(),
            OscCapabilityPolicy::default(),
            OscClassificationContext::default(),
        )
        .is_empty());
        assert_eq!(
            gate.diagnostics()
                .for_intent(OscIntent::ShellIntegration)
                .oversized,
            1
        );
    }

    #[test]
    fn every_parse_capability_can_be_denied_independently() {
        let cases: &[(OscCapability, &[u8], OscIntent)] = &[
            (
                OscCapability::Appearance,
                b"\x1b]2;title\x07",
                OscIntent::Appearance,
            ),
            (
                OscCapability::Metadata,
                b"\x1b]7;file:///tmp\x07",
                OscIntent::CurrentDirectory,
            ),
            (
                OscCapability::Hyperlink,
                b"\x1b]8;;https://example.test\x07",
                OscIntent::Hyperlink,
            ),
            (
                OscCapability::ClipboardWrite,
                b"\x1b]52;c;SGk=\x07",
                OscIntent::Clipboard,
            ),
            (
                OscCapability::ClipboardRead,
                b"\x1b]52;c;?\x07",
                OscIntent::Clipboard,
            ),
            (
                OscCapability::ClipboardWrite,
                b"\x1b]5522;type=write:id=w1\x1b\\",
                OscIntent::Clipboard,
            ),
            (
                OscCapability::ClipboardRead,
                b"\x1b]5522;type=read:id=r1;dGV4dC9wbGFpbg==\x1b\\",
                OscIntent::Clipboard,
            ),
            (
                OscCapability::Notification,
                b"\x1b]99;;hello\x1b\\",
                OscIntent::Notification,
            ),
            (
                OscCapability::Media,
                b"\x1b]1337;File=inline=1:AA==\x07",
                OscIntent::Media,
            ),
            (
                OscCapability::FileTransfer,
                b"\x1b]1337;RequestUpload=format=tgz\x07",
                OscIntent::FileTransfer,
            ),
            (
                OscCapability::DragDrop,
                b"\x1b]72;t=q:i=7;\x1b\\",
                OscIntent::DragDrop,
            ),
            (
                OscCapability::CustomProtocol,
                b"\x1b]999;private\x07",
                OscIntent::Custom,
            ),
        ];

        for &(capability, sequence, intent) in cases {
            let mut policy = OscCapabilityPolicy::default();
            policy.set(capability, true);

            let mut allowed_gate = OscStreamGate::default();
            let filtered = filter_owned(
                &mut allowed_gate,
                sequence,
                policy,
                OscClassificationContext::default(),
            );
            assert_eq!(filtered, sequence, "{capability:?} was not allowed");
            assert_eq!(
                allowed_gate.diagnostics().for_intent(intent).accepted,
                1,
                "{capability:?} did not report acceptance"
            );

            policy.set(capability, false);
            let mut gate = OscStreamGate::default();
            let filtered = filter_owned(
                &mut gate,
                sequence,
                policy,
                OscClassificationContext::default(),
            );
            assert!(filtered.is_empty(), "{capability:?} was not denied");
            assert_eq!(
                gate.diagnostics().for_intent(intent).policy_denied,
                1,
                "{capability:?} did not report a category-only denial"
            );
        }
    }

    #[test]
    fn osc5522_mime_type_listing_is_allowed_without_clipboard_read_permission() {
        let sequence = b"\x1b]5522;type=read:id=list;Lg==\x1b\\";
        let policy = OscCapabilityPolicy {
            clipboard_write: true,
            clipboard_read: false,
            ..OscCapabilityPolicy::default()
        };
        let mut gate = OscStreamGate::default();
        assert_eq!(
            filter_owned(
                &mut gate,
                sequence,
                policy,
                OscClassificationContext::default(),
            ),
            sequence
        );
    }

    #[test]
    fn osc1337_cursor_shape_uses_only_the_appearance_capability() {
        let sequence = b"\x1b]1337;CursorShape=1\x1b\\";
        let context = OscClassificationContext::default();

        let mut appearance_denied = OscCapabilityPolicy::default();
        appearance_denied.set(OscCapability::Appearance, false);
        let mut gate = OscStreamGate::default();
        assert!(filter_owned(&mut gate, sequence, appearance_denied, context).is_empty());
        assert_eq!(
            gate.diagnostics()
                .for_intent(OscIntent::Appearance)
                .policy_denied,
            1
        );

        let mut metadata_denied = OscCapabilityPolicy::default();
        metadata_denied.set(OscCapability::Metadata, false);
        let mut gate = OscStreamGate::default();
        assert_eq!(
            filter_owned(&mut gate, sequence, metadata_denied, context),
            sequence
        );
    }

    #[test]
    fn osc21337_uses_only_the_bounded_appearance_capability() {
        let sequence = b"\x1b]21337;indicator=#ff9500;status=Working;status-color=#5f87ff\x1b\\";
        let context = OscClassificationContext::default();

        let mut appearance_denied = OscCapabilityPolicy::default();
        appearance_denied.set(OscCapability::Appearance, false);
        let mut gate = OscStreamGate::default();
        assert!(filter_owned(&mut gate, sequence, appearance_denied, context).is_empty());
        assert_eq!(
            gate.diagnostics()
                .for_intent(OscIntent::Appearance)
                .policy_denied,
            1
        );

        let mut metadata_denied = OscCapabilityPolicy::default();
        metadata_denied.set(OscCapability::Metadata, false);
        let mut gate = OscStreamGate::default();
        assert_eq!(
            filter_owned(&mut gate, sequence, metadata_denied, context),
            sequence
        );

        let oversized = format!("\x1b]21337;status={}\x07", "x".repeat(4097));
        let mut gate = OscStreamGate::default();
        assert!(filter_owned(
            &mut gate,
            oversized.as_bytes(),
            OscCapabilityPolicy::default(),
            context,
        )
        .is_empty());
        assert_eq!(
            gate.diagnostics()
                .for_intent(OscIntent::Appearance)
                .oversized,
            1
        );
    }

    #[test]
    fn osc1337_set_colors_uses_only_the_bounded_appearance_capability() {
        let sequence = b"\x1b]1337;SetColors=fg=123,bg=456\x1b\\";
        let context = OscClassificationContext::default();

        let mut appearance_denied = OscCapabilityPolicy::default();
        appearance_denied.set(OscCapability::Appearance, false);
        let mut gate = OscStreamGate::default();
        assert!(filter_owned(&mut gate, sequence, appearance_denied, context).is_empty());
        assert_eq!(
            gate.diagnostics()
                .for_intent(OscIntent::Appearance)
                .policy_denied,
            1
        );

        let mut metadata_denied = OscCapabilityPolicy::default();
        metadata_denied.set(OscCapability::Metadata, false);
        let mut gate = OscStreamGate::default();
        assert_eq!(
            filter_owned(&mut gate, sequence, metadata_denied, context),
            sequence
        );
    }

    #[test]
    fn osc3008_uses_metadata_policy_and_shell_integration_budget() {
        let context = OscClassificationContext::default();
        let classification = classify_osc(b"3008;start=root;type=shell", true, context);
        assert_eq!(classification.intent, OscIntent::ShellIntegration);
        assert_eq!(classification.capability, OscCapability::Metadata);
        assert_eq!(classification.intent.payload_limit(), 16 * KIB);

        let mut policy = OscCapabilityPolicy::default();
        policy.set(OscCapability::Metadata, false);
        let mut gate = OscStreamGate::default();
        assert!(filter_owned(
            &mut gate,
            b"\x1b]3008;start=root;type=shell\x1b\\",
            policy,
            context,
        )
        .is_empty());
        assert_eq!(
            gate.diagnostics()
                .for_intent(OscIntent::ShellIntegration)
                .policy_denied,
            1
        );
    }

    #[test]
    fn host_action_permission_is_separate_from_request_parsing() {
        let mut policy = OscCapabilityPolicy::default();
        assert!(policy.allows(OscCapability::Notification));
        assert!(!policy.allows_host_action(OscCapability::Notification));
        policy.host_action = true;
        assert!(policy.allows_host_action(OscCapability::Notification));
        policy.notification = false;
        assert!(!policy.allows_host_action(OscCapability::Notification));
    }

    #[test]
    fn filtered_host_observer_sees_clipboard_request_without_authorizing_a_response() {
        let mut terminal = Terminal::new(32, 2);
        terminal.set_osc_capability_allowed(OscCapability::ClipboardRead, true);
        assert!(!terminal.allow_clipboard_read());

        let mut observed = Vec::new();
        terminal.process_with_filtered_input(b"\x1b]52;c;?\x1b\\", |filtered| {
            observed.extend_from_slice(filtered);
        });

        assert_eq!(observed, b"\x1b]52;c;?\x1b\\");
        assert!(terminal.drain_responses().is_empty());
    }

    #[test]
    fn ris_preserves_explicit_osc7_deny_policy() {
        let mut terminal = Terminal::new(32, 2);
        terminal.set_accept_osc7(false);
        terminal.process(b"\x1bc");
        terminal.process(b"\x1b]7;file:///tmp/should-not-apply\x1b\\");

        assert!(terminal.current_directory().is_none());
    }

    #[test]
    fn private_osc_934_uses_its_8k_budget() {
        let context = OscClassificationContext::default();
        let classification = classify_osc(b"934;progress", true, context);
        assert_eq!(classification.intent, OscIntent::IanvsPrivate);
        assert_eq!(classification.intent.payload_limit(), 8 * KIB);
        assert_eq!(classification.capability, OscCapability::CustomProtocol);

        let policy = OscCapabilityPolicy::default();
        let mut exact = b"\x1b]934;".to_vec();
        exact.extend(std::iter::repeat_n(b'x', 8 * KIB - b"934;".len()));
        exact.push(b'\x07');
        let mut exact_gate = OscStreamGate::default();
        assert_eq!(
            filter_owned(&mut exact_gate, &exact, policy, context),
            exact,
        );

        let mut oversized = b"\x1b]934;".to_vec();
        oversized.extend(std::iter::repeat_n(b'x', 8 * KIB + 1 - b"934;".len()));
        oversized.extend_from_slice(b"\x07recovered");
        let mut oversized_gate = OscStreamGate::default();
        assert_eq!(
            filter_owned(&mut oversized_gate, &oversized, policy, context),
            b"recovered",
        );
        assert_eq!(
            oversized_gate
                .diagnostics()
                .for_intent(OscIntent::IanvsPrivate)
                .oversized,
            1,
        );
    }

    #[test]
    fn terminal_gate_handles_split_utf8_and_split_st_before_vte() {
        let mut terminal = Terminal::new(32, 2);
        terminal.process(b"\x1b]2;prefix-\xd1");
        terminal.process(b"\x9c-suffix\x1b");
        assert_eq!(terminal.title(), "");
        terminal.process(b"\\visible");

        assert_eq!(terminal.title(), "prefix-ќ-suffix");
        assert_eq!(terminal.active_grid().row_text(0).trim_end(), "visible");
        assert_eq!(
            terminal
                .osc_ingress_diagnostics()
                .for_intent(OscIntent::Appearance)
                .accepted,
            1
        );
    }

    #[test]
    fn split_utf8_continuation_that_equals_c1_osc_is_not_reinterpreted() {
        let mut terminal = Terminal::new(32, 2);
        terminal.process(b"safe-\xd1");
        terminal.process(b"\x9d-text");

        assert_eq!(terminal.active_grid().row_text(0).trim_end(), "safe-ѝ-text");
        assert_eq!(terminal.osc_ingress_diagnostics().accepted_total(), 0);
    }

    #[test]
    fn terminal_gate_drops_oversize_title_and_resumes_following_text() {
        let mut terminal = Terminal::new(32, 2);
        terminal.process(b"\x1b]2;baseline\x07");

        let mut oversized = b"\x1b]2;".to_vec();
        oversized.extend(std::iter::repeat_n(b'x', 4 * KIB + 1));
        terminal.process(&oversized);
        terminal.process(b"\x1b");
        terminal.process(b"\\recovered");

        assert_eq!(terminal.title(), "baseline");
        assert_eq!(terminal.active_grid().row_text(0).trim_end(), "recovered");
        let diagnostics = terminal
            .osc_ingress_diagnostics()
            .for_intent(OscIntent::Appearance);
        assert_eq!(diagnostics.accepted, 1);
        assert_eq!(diagnostics.oversized, 1);
    }

    #[test]
    fn terminal_policy_keeps_parsing_separate_from_host_execution() {
        let mut terminal = Terminal::new(32, 2);
        assert!(!terminal.osc_host_action_allowed(OscCapability::Notification));

        terminal.process(b"\x1b]9;parsed request\x07");
        assert_eq!(terminal.notifications().len(), 1);

        terminal.set_osc_capability_allowed(OscCapability::Notification, false);
        terminal.process(b"\x1b]9;blocked request\x07");
        assert_eq!(terminal.notifications().len(), 1);
        assert_eq!(
            terminal
                .osc_ingress_diagnostics()
                .for_intent(OscIntent::Notification)
                .policy_denied,
            1
        );
    }

    #[test]
    fn legacy_insecure_switch_maps_to_historical_osc_capabilities() {
        let mut terminal = Terminal::new(32, 2);
        terminal.set_disable_insecure_sequences(true);

        assert!(!terminal.osc_capability_allowed(OscCapability::Hyperlink));
        assert!(!terminal.osc_capability_allowed(OscCapability::ClipboardWrite));
        assert!(!terminal.osc_capability_allowed(OscCapability::ClipboardRead));
        assert!(!terminal.osc_capability_allowed(OscCapability::Notification));
        assert!(!terminal.osc_capability_allowed(OscCapability::HostAction));
        assert!(terminal.osc_capability_allowed(OscCapability::Appearance));
        assert!(terminal.osc_capability_allowed(OscCapability::Metadata));
        assert!(terminal.osc_capability_allowed(OscCapability::Media));
        assert!(terminal.osc_capability_allowed(OscCapability::FileTransfer));
        assert!(!terminal.osc_capability_allowed(OscCapability::DragDrop));
    }

    #[test]
    fn ris_preserves_policy_and_diagnostics_but_clears_in_flight_osc() {
        let mut terminal = Terminal::new(32, 2);
        terminal.process(b"\x1b]2;accepted\x07");
        terminal.set_osc_capability_allowed(OscCapability::Appearance, false);
        terminal.set_disable_insecure_sequences(true);
        terminal.process(b"\x1b]2;incomplete");

        terminal.reset();
        terminal.process(b"orphaned\x07text");
        terminal.process(b"\x1b]2;still-blocked\x07");

        assert!(!terminal.osc_capability_allowed(OscCapability::Appearance));
        assert!(terminal.disable_insecure_sequences());
        assert_eq!(terminal.title(), "");
        assert!(terminal.active_grid().row_text(0).contains("orphaned"));
        assert_eq!(
            terminal
                .osc_ingress_diagnostics()
                .for_intent(OscIntent::Appearance)
                .accepted,
            1
        );
        assert_eq!(
            terminal
                .osc_ingress_diagnostics()
                .for_intent(OscIntent::Appearance)
                .policy_denied,
            1
        );
    }

    #[test]
    fn escape_c_does_not_reenable_denied_capabilities() {
        let mut terminal = Terminal::new(32, 2);
        terminal.set_osc_capability_allowed(OscCapability::Appearance, false);
        terminal.set_osc_capability_allowed(OscCapability::CustomProtocol, false);
        terminal.set_disable_insecure_sequences(true);

        terminal.process(b"\x1bc");
        terminal.process(b"\x1b]2;must-stay-blocked\x07");

        assert_eq!(terminal.title(), "");
        assert!(!terminal.osc_capability_allowed(OscCapability::Appearance));
        assert!(!terminal.osc_capability_allowed(OscCapability::CustomProtocol));
        assert!(terminal.disable_insecure_sequences());
    }

    #[test]
    fn synchronized_update_replay_does_not_double_count_osc() {
        let mut terminal = Terminal::new(32, 2);
        terminal.process(b"\x1b[?2026h");
        terminal.process(b"\x1b]2;buffered\x07");
        terminal.process(b"\x1b[?2026l");

        assert_eq!(terminal.title(), "buffered");
        assert_eq!(
            terminal
                .osc_ingress_diagnostics()
                .for_intent(OscIntent::Appearance)
                .accepted,
            1
        );
    }

    #[test]
    fn tmux_auto_detect_passthrough_counts_raw_osc_once() {
        let mut terminal = Terminal::new(32, 2);
        terminal.set_tmux_auto_detect(true);
        terminal.process(b"\x1b]2;tmux-prefix\x07");

        assert_eq!(terminal.title(), "tmux-prefix");
        assert_eq!(
            terminal
                .osc_ingress_diagnostics()
                .for_intent(OscIntent::Appearance)
                .accepted,
            1
        );
    }

    #[test]
    fn tmux_and_screen_passthrough_accept_every_header_split() {
        let inner = b"\x1b]934;set;job;percent=42\x07";
        for (name, wrapped) in [
            ("tmux", tmux_passthrough(inner)),
            ("screen", screen_passthrough(inner)),
        ] {
            for split in 0..=wrapped.len() {
                let mut terminal = Terminal::new(32, 2);
                terminal.process(&wrapped[..split]);
                terminal.process(&wrapped[split..]);

                assert_eq!(
                    terminal
                        .get_named_progress_bar("job")
                        .map(|bar| bar.percent),
                    Some(42),
                    "{name} lost its inner OSC at split {split}"
                );
                let diagnostics = terminal
                    .osc_ingress_diagnostics()
                    .for_intent(OscIntent::IanvsPrivate);
                assert_eq!(
                    diagnostics.accepted, 1,
                    "{name} did not accept exactly one OSC at split {split}"
                );
            }

            let mut terminal = Terminal::new(32, 2);
            for byte in wrapped.chunks(1) {
                terminal.process(byte);
            }
            assert_eq!(
                terminal
                    .get_named_progress_bar("job")
                    .map(|bar| bar.percent),
                Some(42),
                "{name} lost its byte-fragmented inner OSC"
            );
        }
    }

    #[test]
    fn passthrough_streams_oversized_osc_to_gate_before_outer_terminator() {
        let mut notification = b"\x1b]9;".to_vec();
        notification.extend(std::iter::repeat_n(b'x', 8 * KIB + 1));
        notification.push(b'\x07');

        let mut private = b"\x1b]934;".to_vec();
        private.extend(std::iter::repeat_n(b'x', 8 * KIB + 1 - b"934;".len()));
        private.push(b'\x07');

        for (intent_name, intent, inner) in [
            ("notification", OscIntent::Notification, notification),
            ("OSC 934", OscIntent::IanvsPrivate, private),
        ] {
            for (wrapper_name, mut wrapped) in [
                ("tmux", tmux_passthrough(&inner)),
                ("screen", screen_passthrough(&inner)),
            ] {
                let outer_st = wrapped.split_off(wrapped.len() - 2);
                let mut terminal = Terminal::new(32, 2);

                // The inner BEL has already completed the OSC, but the outer
                // DCS wrapper deliberately remains unterminated.
                terminal.process(&wrapped);

                assert_eq!(
                    terminal
                        .osc_ingress_diagnostics()
                        .for_intent(intent)
                        .oversized,
                    1,
                    "{wrapper_name} buffered oversized {intent_name} until outer ST"
                );
                assert!(terminal.notifications().is_empty());
                assert!(terminal.named_progress_bars().is_empty());

                terminal.process(&outer_st);
                terminal.process(b"recovered");
                assert_eq!(
                    terminal.active_grid().row_text(0).trim_end(),
                    "recovered",
                    "{wrapper_name} did not recover after oversized {intent_name}"
                );
            }
        }
    }

    #[test]
    fn tmux_and_screen_passthrough_cannot_bypass_capability_policy() {
        for (name, mut wrapped) in [
            ("tmux", tmux_passthrough(b"\x1b]2;blocked\x07")),
            ("screen", screen_passthrough(b"\x1b]2;blocked\x07")),
        ] {
            wrapped.extend_from_slice(b"recovered");
            let split = wrapped.len() / 2;
            let mut terminal = Terminal::new(32, 2);
            terminal.set_osc_capability_allowed(OscCapability::Appearance, false);

            terminal.process(&wrapped[..split]);
            terminal.process(&wrapped[split..]);

            assert_eq!(terminal.title(), "", "{name} bypassed appearance policy");
            assert_eq!(
                terminal.active_grid().row_text(0).trim_end(),
                "recovered",
                "{name} did not recover after the denied inner OSC"
            );
            let diagnostics = terminal
                .osc_ingress_diagnostics()
                .for_intent(OscIntent::Appearance);
            assert_eq!(diagnostics.policy_denied, 1, "{name} was not denied once");
            assert_eq!(diagnostics.accepted, 0, "{name} was counted twice");
        }
    }

    #[test]
    fn tmux_and_screen_passthrough_enforce_size_limit_and_recover() {
        let mut inner = b"\x1b]2;".to_vec();
        inner.extend(std::iter::repeat_n(b'x', 4 * KIB + 1));
        inner.push(b'\x07');

        for (name, mut wrapped) in [
            ("tmux", tmux_passthrough(&inner)),
            ("screen", screen_passthrough(&inner)),
        ] {
            wrapped.extend_from_slice(b"recovered");
            let mut terminal = Terminal::new(32, 2);
            terminal.process(b"\x1b]2;baseline\x07");
            terminal.take_osc_ingress_diagnostics();

            terminal.process(&wrapped);

            assert_eq!(terminal.title(), "baseline", "{name} accepted oversize OSC");
            assert_eq!(
                terminal.active_grid().row_text(0).trim_end(),
                "recovered",
                "{name} did not recover after oversize OSC"
            );
            let diagnostics = terminal
                .osc_ingress_diagnostics()
                .for_intent(OscIntent::Appearance);
            assert_eq!(diagnostics.oversized, 1, "{name} missed oversize OSC");
            assert_eq!(diagnostics.accepted, 0, "{name} counted inner OSC twice");
        }
    }

    #[test]
    fn one_megabyte_fragmented_media_classification_is_linear() {
        let media_bytes = MIB;
        let mut sequence = b"\x1b]1337;File=inline=1:".to_vec();
        sequence.extend(std::iter::repeat_n(b'A', media_bytes));
        sequence.push(b'\x07');

        let mut gate = OscStreamGate::default();
        let started = Instant::now();
        let mut forwarded = 0usize;
        for chunk in sequence.chunks(4093) {
            forwarded = forwarded.saturating_add(
                gate.filter(
                    chunk,
                    OscCapabilityPolicy::default(),
                    OscClassificationContext::default(),
                )
                .len(),
            );
        }

        assert_eq!(forwarded, sequence.len());
        assert_eq!(gate.diagnostics().for_intent(OscIntent::Media).accepted, 1);
        assert!(
            gate.classification_scan_bytes() <= sequence.len() + 32 * KIB,
            "classification rescanned an unbounded payload: {} scan bytes for {} input bytes",
            gate.classification_scan_bytes(),
            sequence.len()
        );
        assert!(
            started.elapsed() < Duration::from_secs(5),
            "1 MiB fragmented media gate took {:?}",
            started.elapsed()
        );
    }
}
