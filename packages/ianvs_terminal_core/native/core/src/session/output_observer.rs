//! Conservative live-output trigger observations, independent of viewport frames.
//! Each event is self-contained. Dropped events can lose matches, never join text.
use serde_json::{Value, json};
use vte::{Params, Parser, Perform};

const MAX_TEXT_BYTES: usize = 4096;
const MAX_EVENTS: usize = 64;

#[derive(Default)]
pub(super) struct OutputObserver {
    // vte without std keeps OSC payload in a fixed 1024-byte ArrayVec.
    parser: Parser,
    text: OutputText,
}

#[derive(Default)]
struct OutputText {
    line: u64,
    revision: u64,
    value: String,
    suppressed: bool,
    alternate: bool,
    enabled: bool,
    pending_cr: bool,
    dropped: usize,
    generation: u64,
    seen_content: bool,
    changed: bool,
    events: Vec<Value>,
}

impl OutputObserver {
    pub(super) fn set_enabled(&mut self, enabled: bool) -> u64 {
        if self.text.enabled != enabled {
            self.text.enabled = enabled;
            self.text.suppressed = self.text.seen_content;
            self.text.value.clear();
            self.text.changed = false;
            self.text.generation += 1;
            self.text.line += 1;
        }
        self.text.generation
    }

    pub(super) fn observe(&mut self, bytes: &[u8]) -> Vec<Value> {
        self.parser.advance(&mut self.text, bytes);
        // A partial UTF-8 codepoint (or escape sequence) may not invoke print
        // yet. Enabling between reads must not adopt its pre-subscription prefix.
        self.text.seen_content |= bytes.last().is_some_and(|byte| *byte != b'\n');
        self.text.publish(false);
        if self.text.dropped > 0 {
            self.text.events.push(json!({"subscription": self.text.generation.to_string(), "lineId": self.text.line.to_string(), "revision": self.text.revision.to_string(), "text": "", "complete": false, "dropped": self.text.dropped}));
            self.text.dropped = 0;
        }
        std::mem::take(&mut self.text.events)
    }
}

impl OutputText {
    fn publish(&mut self, complete: bool) {
        if self.enabled
            && self.changed
            && !self.suppressed
            && !self.alternate
            && !self.value.is_empty()
        {
            if self.events.len() >= MAX_EVENTS {
                self.dropped += 1;
                self.changed = false;
                return;
            }
            self.revision += 1;
            self.events.push(json!({"subscription": self.generation.to_string(), "lineId": self.line.to_string(),
                "revision": self.revision.to_string(), "text": self.value, "complete": complete, "dropped": 0}));
        }
        self.changed = false;
    }
    fn suppress(&mut self) {
        self.value.clear();
        self.seen_content = true;
        self.suppressed = true;
        self.changed = false;
    }
}

impl Perform for OutputText {
    fn print(&mut self, ch: char) {
        self.seen_content = true;
        if self.pending_cr {
            self.suppress();
        }
        if !self.enabled || self.suppressed || self.alternate {
            return;
        }
        if self.value.len() + ch.len_utf8() > MAX_TEXT_BYTES {
            self.dropped += 1;
            self.suppress();
            return;
        }
        self.value.push(ch);
        self.changed = true;
    }
    fn execute(&mut self, byte: u8) {
        match byte {
            b'\n' => {
                self.publish(true);
                self.line += 1;
                self.value.clear();
                self.suppressed = false;
                self.pending_cr = false;
                self.seen_content = false;
            }
            // CR is commonly followed by LF. Preserve the preceding text for
            // that LF, but any following printable update is suppressed below.
            b'\r' => {
                self.pending_cr = true;
            }
            b'\t' => self.print('\t'),
            8 | 11 | 12 => self.suppress(),
            _ => (),
        }
    }
    fn csi_dispatch(&mut self, params: &Params, intermediates: &[u8], ignore: bool, action: char) {
        if !ignore && intermediates == b"?" && matches!(action, 'h' | 'l') {
            for param in params.iter() {
                if matches!(param.first(), Some(47 | 1047 | 1049)) {
                    self.alternate = action == 'h';
                }
            }
        }
        // SGR is display-only; all other cursor/erase/mode operations make
        // this logical line unsuitable for side-effect matching until LF.
        if ignore || action != 'm' || !intermediates.is_empty() {
            self.suppress();
        }
    }
    fn hook(&mut self, _: &Params, _: &[u8], _: bool, _: char) {
        self.suppress();
    }
    fn osc_dispatch(&mut self, params: &[&[u8]], _: bool) {
        // Only metadata and hyperlinks are known not to alter cursor contents.
        if !matches!(
            params.first().copied(),
            Some(b"0" | b"1" | b"2" | b"7" | b"8" | b"133" | b"633")
        ) {
            self.suppress();
        }
    }
    fn esc_dispatch(&mut self, _: &[u8], _: bool, byte: u8) {
        if byte == b'c' {
            self.alternate = false;
        }
        self.suppress();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn enabling_during_split_utf8_does_not_include_pre_subscription_bytes() {
        let mut observer = OutputObserver::default();
        let bytes = "错误".as_bytes();
        observer.observe(&bytes[..1]);
        observer.set_enabled(true);
        assert!(observer.observe(&bytes[1..]).is_empty());
        assert_eq!(observer.observe("\n错误".as_bytes())[0]["text"], "错误");
    }
    #[test]
    fn subscriptions_start_at_safe_boundaries_and_change_identity() {
        let mut observer = OutputObserver::default();
        assert_eq!(observer.set_enabled(true), 1);
        assert_eq!(observer.set_enabled(true), 1);
        assert_eq!(observer.observe(b"Password:")[0]["subscription"], "1");
        assert_eq!(observer.set_enabled(false), 2);
        assert!(observer.observe(b" secret").is_empty());
        assert_eq!(observer.set_enabled(true), 3);
        assert!(observer.observe(b"Password:").is_empty());
        assert_eq!(observer.observe(b"\nPassword:")[0]["subscription"], "3");
    }
    #[test]
    fn enabling_mid_sequence_does_not_expose_osc_or_dcs_payload() {
        let mut observer = OutputObserver::default();
        observer.observe(b"\x1b]0;");
        observer.set_enabled(true);
        assert!(observer.observe(b"Password:\x07").is_empty());
        observer.set_enabled(false);
        observer.observe(b"\x1bP");
        observer.set_enabled(true);
        assert!(observer.observe(b"qPassword:\x1b\\").is_empty());
    }
    #[test]
    fn same_read_edits_and_graphics_do_not_publish_erased_matches() {
        for bytes in [
            b"Password:\r\x1b[2K".as_slice(),
            b"Pass\x0bword:",
            b"Pass\x0cword:",
            b"Pass\x1bPqimage\x1b\\word:",
            b"Pass\x1b_Gimage\x1b\\word:",
            b"Pass\x1b]1337;File=payload\x07word:",
        ] {
            let mut observer = OutputObserver::default();
            observer.set_enabled(true);
            assert!(observer.observe(bytes).is_empty(), "{bytes:?}");
        }
        let mut observer = OutputObserver::default();
        observer.set_enabled(true);
        assert!(observer.observe(b"\x1b[?1049hPassword:\x1bc").is_empty());
        assert_eq!(observer.observe(b"\nrestored")[0]["text"], "restored");
    }
    #[test]
    fn split_utf8_and_control_payloads_do_not_enter_text() {
        let mut observer = OutputObserver::default();
        observer.text.enabled = true;
        assert!(observer.observe(b"\x1b]0;ERROR").is_empty());
        assert!(observer.observe(b"\x07\x1bPERROR\x1b\\\n").is_empty());
        let bytes = "错".as_bytes();
        assert!(observer.observe(&bytes[..1]).is_empty());
        assert_eq!(observer.observe(&bytes[1..])[0]["text"], "错");
        assert_eq!(
            observer.observe(b"\x1b[31m ERROR\r\n")[0]["text"],
            "错 ERROR"
        );
    }
    #[test]
    fn snapshots_are_independent_and_line_identity_survives_partial_updates() {
        let mut observer = OutputObserver::default();
        observer.text.enabled = true;
        let first = observer.observe(b"Pass");
        let second = observer.observe(b"word:");
        assert_eq!(second[0]["text"], "Password:");
        assert_eq!(first[0]["lineId"], second[0]["lineId"]);
        assert!(observer.observe(b"\x1b[0m").is_empty());
        let next = observer.observe(b"\nPassword:");
        assert_ne!(second[0]["lineId"], next[0]["lineId"]);
    }
    #[test]
    fn edits_alt_screen_and_overflow_cannot_splice_a_match() {
        let mut observer = OutputObserver::default();
        observer.text.enabled = true;
        observer.observe(b"Pass");
        assert!(observer.observe(b"\x08word:").is_empty());
        assert!(
            observer
                .observe(b"\n\x1b[?1049hERROR\nERROR\x1b[?1049lERROR")
                .is_empty()
        );
        let overflow = observer.observe(
            &[
                vec![b'\n'],
                vec![b'x'; MAX_TEXT_BYTES + 1],
                b"ERROR".to_vec(),
            ]
            .concat(),
        );
        assert_eq!(overflow[0]["dropped"], 1);
        assert_eq!(overflow[0]["text"], "");
        assert_eq!(observer.observe(b"\nclean")[0]["text"], "clean");
    }
    #[test]
    fn event_batches_are_bounded_without_carrying_dropped_fragments() {
        let mut observer = OutputObserver::default();
        observer.text.enabled = true;
        assert_eq!(
            observer.observe(&b"line\n".repeat(1000)).len(),
            MAX_EVENTS + 1
        );
        let next = observer.observe(b"next");
        assert_eq!(next[0]["lineId"], "1000");
        assert_eq!(next[0]["text"], "next");
    }
}
