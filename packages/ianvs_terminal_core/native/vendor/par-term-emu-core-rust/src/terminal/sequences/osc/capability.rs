//! xterm OSC 60/61/62 optional runtime-feature queries.
//!
//! These sequences only disclose terminal-owned capability state. They never
//! mutate policy or authorize one of the reported operations.

use crate::terminal::{OscCapability, Terminal};

const COLOR_OPS: &[&str] = &["SetColor", "GetColor", "GetAnsiColor"];
const FONT_OPS: &[&str] = &["SetFont", "GetFont"];
const MOUSE_OPS: &[&str] = &[
    "X10",
    "Locator",
    "VT200Click",
    "VT200Hilite",
    "AnyButton",
    "AnyEvent",
    "FocusEvent",
    "Extended",
    "SGR",
    "URXVT",
    "AlternateScroll",
];
const DISALLOWED_MOUSE_OPS: &[&str] = &["Locator", "VT200Hilite"];
const PASTE_OPS: &[&str] = &[
    "NUL", "SOH", "STX", "ETX", "EOT", "ENQ", "ACK", "BEL", "BS", "HT", "LF", "VT", "FF", "CR",
    "SO", "SI", "DLE", "DC1", "DC2", "DC3", "DC4", "NAK", "SYN", "ETB", "CAN", "EM", "SUB", "ESC",
    "FS", "GS", "RS", "US", "NL", "C0", "DEL", "STTY",
];
const DISALLOWED_PASTE_OPS: &[&str] = &[
    "NUL", "SOH", "STX", "ETX", "EOT", "ENQ", "ACK", "BEL", "BS", "HT", "LF", "VT", "FF", "CR",
    "SO", "SI", "DLE", "DC1", "DC2", "DC3", "DC4", "NAK", "SYN", "ETB", "CAN", "EM", "SUB", "ESC",
    "FS", "GS", "RS", "US", "C0", "DEL", "STTY",
];
const TCAP_OPS: &[&str] = &["SetTcap", "GetTcap"];
const WINDOW_OPS: &[&str] = &[
    "RestoreWin",
    "MinimizeWin",
    "SetWinPosition",
    "SetWinSizePixels",
    "RaiseWin",
    "LowerWin",
    "RefreshWin",
    "SetWinSizeChars",
    "MaximizeWin",
    "FullscreenWin",
    "GetWinState",
    "GetWinPosition",
    "GetWinSizePixels",
    "GetWinSizeChars",
    "GetScreenSizeChars",
    "GetIconTitle",
    "GetWinTitle",
    "PushTitle",
    "PopTitle",
    "SetWinLines",
    "ColumnMode",
    "GetChecksum",
    "SetChecksum",
    "GetSelection",
    "SetSelection",
    "SetXprop",
    "StatusLine",
];

impl Terminal {
    pub(crate) fn handle_osc_capability_query(
        &mut self,
        command: &str,
        params: &[&[u8]],
        bell_terminated: bool,
    ) {
        let values = match command {
            "60" if params.len() == 1 => Some(self.allowed_xterm_operation_categories()),
            "61" if params.len() == 2 => std::str::from_utf8(params[1])
                .ok()
                .and_then(|category| self.disallowed_xterm_operations(category)),
            "62" if params.len() == 2 => std::str::from_utf8(params[1])
                .ok()
                .and_then(allowable_xterm_operations),
            _ => None,
        };
        let Some(values) = values else {
            return;
        };

        let mut response = format!("\x1b]{command}");
        if !values.is_empty() {
            response.push(';');
            response.push_str(&values.join(","));
        }
        if bell_terminated {
            response.push('\x07');
        } else {
            response.push_str("\x1b\\");
        }
        self.push_response(response.as_bytes());
    }

    fn allowed_xterm_operation_categories(&self) -> Vec<&'static str> {
        let mut result = Vec::with_capacity(3);
        if self.osc_capability_allowed(OscCapability::Appearance) {
            result.push("allowColorOps");
            result.push("allowFontOps");
        }
        if self.osc_capability_allowed(OscCapability::Metadata) {
            result.push("allowTitleOps");
        }
        // The other xterm top-level categories stay disabled. OSC 61 reports
        // the narrower mouse/window exceptions that remain usable while their
        // parent category is disabled.
        result
    }

    fn disallowed_xterm_operations(&self, category: &str) -> Option<Vec<&'static str>> {
        let category = category.to_ascii_lowercase();
        match category.as_str() {
            // OSC 61 reports the configured fallback deny-list that applies
            // when its OSC 60 parent category is disabled, not a second copy
            // of the current OSC 60 state.
            "allowcolorops" => Some(COLOR_OPS.to_vec()),
            "allowfontops" => Some(FONT_OPS.to_vec()),
            "allowmouseops" => Some(DISALLOWED_MOUSE_OPS.to_vec()),
            "allowpastecontrols" => Some(DISALLOWED_PASTE_OPS.to_vec()),
            "allowtcapops" => Some(TCAP_OPS.to_vec()),
            "allowtitleops" => Some(Vec::new()),
            "allowwinops" | "allowwindowops" => Some(self.disallowed_xterm_window_operations()),
            _ => None,
        }
    }

    fn disallowed_xterm_window_operations(&self) -> Vec<&'static str> {
        WINDOW_OPS
            .iter()
            .copied()
            .filter(|operation| match *operation {
                "GetWinSizePixels" | "GetWinSizeChars" | "PushTitle" | "PopTitle"
                | "GetChecksum" => false,
                "GetSelection" => !self.osc_capability_allowed(OscCapability::ClipboardRead),
                "SetSelection" => !self.osc_capability_allowed(OscCapability::ClipboardWrite),
                _ => true,
            })
            .collect()
    }
}

fn allowable_xterm_operations(category: &str) -> Option<Vec<&'static str>> {
    let category = category.to_ascii_lowercase();
    match category.as_str() {
        "allowcolorops" => Some(COLOR_OPS.to_vec()),
        "allowfontops" => Some(FONT_OPS.to_vec()),
        "allowmouseops" => Some(MOUSE_OPS.to_vec()),
        "allowpastecontrols" => Some(PASTE_OPS.to_vec()),
        "allowtcapops" => Some(TCAP_OPS.to_vec()),
        // xterm reports this top-level category but defines no subcategory
        // table for it.
        "allowtitleops" => Some(Vec::new()),
        "allowwinops" | "allowwindowops" => Some(WINDOW_OPS.to_vec()),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn osc60_reports_exact_allowed_categories_and_mirrors_terminator() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]60\x1b\\");
        terminal.process(b"\x1b]60\x07");

        assert_eq!(
            terminal.drain_responses(),
            b"\x1b]60;allowColorOps,allowFontOps,allowTitleOps\x1b\\\x1b]60;allowColorOps,allowFontOps,allowTitleOps\x07"
        );

        terminal.set_osc_capability_allowed(OscCapability::Appearance, false);
        terminal.process(b"\x1b]60\x1b\\");
        assert_eq!(terminal.drain_responses(), b"\x1b]60;allowTitleOps\x1b\\");
        terminal.set_osc_capability_allowed(OscCapability::Metadata, false);
        terminal.process(b"\x1b]60\x1b\\");
        assert_eq!(terminal.drain_responses(), b"\x1b]60\x1b\\");
    }

    #[test]
    fn osc61_reports_fallback_disallowed_operations() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]61;allowMouseOps\x1b\\");
        terminal.process(b"\x1b]61;ALLOWFONTOPS\x07");
        terminal.process(b"\x1b]61;allowColorOps\x1b\\");
        terminal.set_osc_capability_allowed(OscCapability::Appearance, false);
        terminal.process(b"\x1b]61;allowColorOps\x1b\\");

        assert_eq!(
            terminal.drain_responses(),
            b"\x1b]61;Locator,VT200Hilite\x1b\\\x1b]61;SetFont,GetFont\x07\x1b]61;SetColor,GetColor,GetAnsiColor\x1b\\\x1b]61;SetColor,GetColor,GetAnsiColor\x1b\\"
        );
    }

    #[test]
    fn osc61_window_reply_tracks_clipboard_read_and_write_policy() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]61;allowWinOps\x1b\\");
        let default_reply = String::from_utf8(terminal.drain_responses()).unwrap();
        assert_eq!(
            default_reply,
            "\x1b]61;RestoreWin,MinimizeWin,SetWinPosition,SetWinSizePixels,RaiseWin,LowerWin,RefreshWin,SetWinSizeChars,MaximizeWin,FullscreenWin,GetWinState,GetWinPosition,GetScreenSizeChars,GetIconTitle,GetWinTitle,SetWinLines,ColumnMode,SetChecksum,GetSelection,SetXprop,StatusLine\x1b\\"
        );

        terminal.set_osc_capability_allowed(OscCapability::ClipboardRead, true);
        terminal.set_osc_capability_allowed(OscCapability::ClipboardWrite, false);
        terminal.process(b"\x1b]61;allowWindowOps\x1b\\");
        let changed_reply = String::from_utf8(terminal.drain_responses()).unwrap();
        assert!(!changed_reply.contains("GetSelection"));
        assert!(changed_reply.contains("SetSelection"));

        terminal.set_osc_capability_allowed(OscCapability::ClipboardWrite, true);
        terminal.set_disable_insecure_sequences(true);
        terminal.process(b"\x1b]61;allowWindowOps\x1b\\");
        let legacy_denied_reply = String::from_utf8(terminal.drain_responses()).unwrap();
        assert!(legacy_denied_reply.contains("GetSelection"));
        assert!(legacy_denied_reply.contains("SetSelection"));
    }

    #[test]
    fn osc62_reports_official_allowable_tables_and_alias() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]62;allowColorOps\x1b\\");
        terminal.process(b"\x1b]62;allowWinOps\x07");
        terminal.process(b"\x1b]62;allowTitleOps\x1b\\");

        assert_eq!(
            String::from_utf8(terminal.drain_responses()).unwrap(),
            "\x1b]62;SetColor,GetColor,GetAnsiColor\x1b\\\x1b]62;RestoreWin,MinimizeWin,SetWinPosition,SetWinSizePixels,RaiseWin,LowerWin,RefreshWin,SetWinSizeChars,MaximizeWin,FullscreenWin,GetWinState,GetWinPosition,GetWinSizePixels,GetWinSizeChars,GetScreenSizeChars,GetIconTitle,GetWinTitle,PushTitle,PopTitle,SetWinLines,ColumnMode,GetChecksum,SetChecksum,GetSelection,SetSelection,SetXprop,StatusLine\x07\x1b]62\x1b\\"
        );
    }

    #[test]
    fn osc61_and_osc62_cover_font_paste_and_tcap_tables_exactly() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]61;allowPasteControls\x1b\\");
        terminal.process(b"\x1b]62;allowPasteControls\x1b\\");
        terminal.process(b"\x1b]62;allowFontOps\x1b\\");
        terminal.process(b"\x1b]62;allowTcapOps\x1b\\");

        assert_eq!(
            String::from_utf8(terminal.drain_responses()).unwrap(),
            "\x1b]61;NUL,SOH,STX,ETX,EOT,ENQ,ACK,BEL,BS,HT,LF,VT,FF,CR,SO,SI,DLE,DC1,DC2,DC3,DC4,NAK,SYN,ETB,CAN,EM,SUB,ESC,FS,GS,RS,US,C0,DEL,STTY\x1b\\\x1b]62;NUL,SOH,STX,ETX,EOT,ENQ,ACK,BEL,BS,HT,LF,VT,FF,CR,SO,SI,DLE,DC1,DC2,DC3,DC4,NAK,SYN,ETB,CAN,EM,SUB,ESC,FS,GS,RS,US,NL,C0,DEL,STTY\x1b\\\x1b]62;SetFont,GetFont\x1b\\\x1b]62;SetTcap,GetTcap\x1b\\"
        );
    }

    #[test]
    fn capability_queries_reject_missing_unknown_extra_and_echoed_responses() {
        let mut terminal = Terminal::new(80, 24);
        terminal.process(b"\x1b]60;unexpected\x1b\\");
        terminal.process(b"\x1b]61\x1b\\");
        terminal.process(b"\x1b]61;unknown\x1b\\");
        terminal.process(b"\x1b]62;allowColorOps;extra\x1b\\");
        terminal.process(b"\x1b]60;allowColorOps,allowMouseOps\x1b\\");
        terminal.process(b"\x1b]61;SetFont,GetFont\x1b\\");
        assert!(terminal.drain_responses().is_empty());
    }

    #[test]
    fn capability_queries_survive_every_byte_fragmentation_and_policy_gate() {
        let sequence = b"\x1b]62;allowMouseOps\x1b\\";
        for split in 1..sequence.len() {
            let mut terminal = Terminal::new(80, 24);
            terminal.process(&sequence[..split]);
            terminal.process(&sequence[split..]);
            assert_eq!(
                terminal.drain_responses(),
                b"\x1b]62;X10,Locator,VT200Click,VT200Hilite,AnyButton,AnyEvent,FocusEvent,Extended,SGR,URXVT,AlternateScroll\x1b\\"
            );
        }

        let mut denied = Terminal::new(80, 24);
        denied.set_osc_capability_allowed(OscCapability::CustomProtocol, false);
        denied.process(sequence);
        assert!(denied.drain_responses().is_empty());
    }

    #[test]
    fn oversized_capability_query_is_discarded_and_later_osc_recovers() {
        let mut terminal = Terminal::new(80, 24);
        let mut sequence = b"\x1b]61;".to_vec();
        sequence.extend(std::iter::repeat_n(b'x', 4097));
        sequence.extend_from_slice(b"\x1b\\\x1b]2;capability-recovered\x1b\\");

        terminal.process(&sequence);

        assert_eq!(terminal.title(), "capability-recovered");
        assert!(terminal.drain_responses().is_empty());
        assert_eq!(
            terminal
                .osc_ingress_diagnostics()
                .for_intent(crate::terminal::OscIntent::Custom)
                .oversized,
            1
        );
    }
}
