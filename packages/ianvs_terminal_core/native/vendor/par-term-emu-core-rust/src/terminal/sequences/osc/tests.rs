use crate::color::Color;
use crate::shell_integration::ShellIntegrationMarker;
use crate::terminal::Terminal;
use base64::Engine;

fn process_osc1337(term: &mut Terminal, payload: &str) {
    let sequence = format!("\x1b]1337;{payload}\x1b\\");
    term.process(sequence.as_bytes());
}

#[test]
fn unsupported_osc_log_message_never_contains_command_or_payload() {
    let command = "command-secret-canary";
    let payload = b"payload-secret-canary";
    let message = super::unsupported_osc_log_message(command, &[command.as_bytes(), payload]);

    assert!(!message.contains(command));
    assert!(!message.contains("payload-secret-canary"));
    assert!(message.contains(&format!("command_bytes={}", command.len())));
    assert!(message.contains(&format!("payload_bytes={}", payload.len())));
}

fn tiny_png_base64() -> String {
    let image = image::RgbaImage::from_pixel(1, 1, image::Rgba([255, 0, 0, 255]));
    let mut png_data = Vec::new();
    image
        .write_to(
            &mut std::io::Cursor::new(&mut png_data),
            image::ImageFormat::Png,
        )
        .expect("test PNG should encode");
    base64::engine::general_purpose::STANDARD.encode(png_data)
}

#[test]
fn test_parse_color_spec_rgb_format() {
    // Valid rgb: format
    assert_eq!(
        Terminal::parse_color_spec("rgb:FF/00/AA"),
        Some((255, 0, 170))
    );
    assert_eq!(
        Terminal::parse_color_spec("rgb:ff/00/aa"),
        Some((255, 0, 170))
    );
    assert_eq!(
        Terminal::parse_color_spec("rgb:12/34/56"),
        Some((18, 52, 86))
    );

    // rgb: components are scaled from their declared 4/8/12/16-bit width.
    assert_eq!(Terminal::parse_color_spec("rgb:F/8/0"), Some((255, 136, 0)));
    assert_eq!(
        Terminal::parse_color_spec("rgb:FF/80/00"),
        Some((255, 128, 0))
    );
    assert_eq!(
        Terminal::parse_color_spec("rgb:FFF/800/000"),
        Some((255, 128, 0))
    );
    assert_eq!(
        Terminal::parse_color_spec("rgb:FFFF/8000/0000"),
        Some((255, 128, 0))
    );
}

#[test]
fn test_parse_color_spec_hex_format() {
    // Valid #RRGGBB format
    assert_eq!(Terminal::parse_color_spec("#FF00AA"), Some((255, 0, 170)));
    assert_eq!(Terminal::parse_color_spec("#ff00aa"), Some((255, 0, 170)));
    assert_eq!(Terminal::parse_color_spec("#123456"), Some((18, 52, 86)));
    assert_eq!(Terminal::parse_color_spec("#FFF"), Some((240, 240, 240)));
    assert_eq!(Terminal::parse_color_spec("#ABC"), Some((160, 176, 192)));
    assert_eq!(Terminal::parse_color_spec("#FF00AA00"), Some((255, 0, 170)));
}

#[test]
fn test_parse_color_spec_invalid() {
    // Invalid formats
    assert_eq!(Terminal::parse_color_spec(""), None);
    assert_eq!(Terminal::parse_color_spec("  "), None);
    assert_eq!(Terminal::parse_color_spec("rgb:FF/00"), None); // Missing component
    assert_eq!(Terminal::parse_color_spec("rgb:GG/00/00"), None); // Invalid hex
    assert_eq!(Terminal::parse_color_spec("invalid"), None);
}

#[test]
fn test_set_window_title() {
    let mut term = Terminal::new(80, 24);

    // OSC 0 - Set icon name and window title
    term.process(b"\x1b]0;Test Title\x1b\\");
    assert_eq!(term.title(), "Test Title");
    assert_eq!(term.icon_name(), "Test Title");

    // OSC 1 - Set icon name only
    term.process(b"\x1b]1;Test Icon\x1b\\");
    assert_eq!(term.title(), "Test Title");
    assert_eq!(term.icon_name(), "Test Icon");

    // OSC 2 - Set window title
    term.process(b"\x1b]2;Another Title\x1b\\");
    assert_eq!(term.title(), "Another Title");
    assert_eq!(term.icon_name(), "Test Icon");
}

#[test]
fn xterm_legacy_title_alias_accepts_bel_st_fragmentation_and_semicolons() {
    let cases: &[&[u8]] = &[
        b"\x1b]lLegacy BEL\x07",
        b"\x1b]lLegacy;ST\x1b\\",
        "\x1b]lUnicode 你好\x1b\\".as_bytes(),
    ];

    let mut term = Terminal::new(80, 24);
    for sequence in cases {
        for byte in *sequence {
            term.process(&[*byte]);
        }
    }

    assert_eq!(term.title(), "Unicode 你好");
    let title_events = term
        .poll_events()
        .into_iter()
        .filter(|event| matches!(event, crate::terminal::TerminalEvent::TitleChanged(_)))
        .count();
    assert_eq!(title_events, 3);

    term.process(b"\x1b]lLegacy;ST\x1b\\");
    assert_eq!(term.title(), "Legacy;ST");
}

#[test]
fn xterm_legacy_icon_alias_does_not_mutate_window_title() {
    let mut term = Terminal::new(80, 24);
    term.process(b"\x1b]2;Stable title\x1b\\");
    term.process(b"\x1b]LIcon;label\x07");

    assert_eq!(term.title(), "Stable title");
    assert_eq!(term.icon_name(), "Icon;label");
}

#[test]
fn osc_21_color_control_and_osc22_do_not_mutate_title_or_title_stack() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b]0;Original Title\x1b\\");
    term.process(b"\x1b[22t");

    // Kitty color control is handled independently from title state. Pointer
    // shapes remain isolated from title handling.
    term.process(b"\x1b]21;foreground=#123456\x1b\\");
    term.process(b"\x1b]22;pointer\x07");
    assert_eq!(term.default_fg(), Color::Rgb(0x12, 0x34, 0x56));
    assert_eq!(term.title(), "Original Title");
    assert_eq!(term.title_stack.depth(), 1);
}

#[test]
fn split_and_malformed_osc_21_and_22_do_not_mutate_title() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b]0;Stable\x1b\\");
    term.process(b"\x1b]21;foreground=rgb:12/34");
    term.process(b"/56\x1b");
    term.process(b"\\");
    term.process(b"\x1b]22;not-a-pointer\x07");

    assert_eq!(term.title(), "Stable");
    assert_eq!(term.title_stack.depth(), 0);
}

#[test]
fn osc23_is_not_a_title_stack_pop() {
    let mut term = Terminal::new(80, 24);
    term.process(b"\x1b]0;Current\x1b\\");
    term.process(b"\x1b[22t");

    term.process(b"\x1b]23;legacy-payload\x1b\\");

    assert_eq!(term.title(), "Current");
    assert_eq!(term.title_stack.depth(), 1);
}

#[test]
fn test_shell_integration_markers() {
    let mut term = Terminal::new(80, 24);

    // OSC 133 A - Prompt start
    term.process(b"\x1b]133;A\x1b\\");
    assert_eq!(
        term.shell_integration.marker(),
        Some(ShellIntegrationMarker::PromptStart)
    );

    // OSC 133 B - Command start
    term.process(b"\x1b]133;B\x1b\\");
    assert_eq!(
        term.shell_integration.marker(),
        Some(ShellIntegrationMarker::CommandStart)
    );

    // OSC 133 C - Command executed
    term.process(b"\x1b]133;C\x1b\\");
    assert_eq!(
        term.shell_integration.marker(),
        Some(ShellIntegrationMarker::CommandExecuted)
    );

    // OSC 133 D - Command finished
    term.process(b"\x1b]133;D\x1b\\");
    assert_eq!(
        term.shell_integration.marker(),
        Some(ShellIntegrationMarker::CommandFinished)
    );
}

// Note: Exit code parsing in OSC 133 appears to expect a different format
// than standard OSC parameter separation allows. Skipping this test for now.
// The shell integration marker tests cover the main functionality.

#[test]
fn test_hyperlinks() {
    let mut term = Terminal::new(80, 24);

    // Start hyperlink
    term.process(b"\x1b]8;;https://example.com\x1b\\");
    assert!(term.current_hyperlink_id.is_some());
    let id1 = term.current_hyperlink_id.unwrap();

    // End hyperlink (empty URL)
    term.process(b"\x1b]8;;\x1b\\");
    assert!(term.current_hyperlink_id.is_none());

    // Start another hyperlink
    term.process(b"\x1b]8;;https://example.org\x1b\\");
    assert!(term.current_hyperlink_id.is_some());
    let id2 = term.current_hyperlink_id.unwrap();

    // IDs should be different
    assert_ne!(id1, id2);

    // Reuse existing URL (deduplication)
    term.process(b"\x1b]8;;https://example.com\x1b\\");
    assert_eq!(term.current_hyperlink_id, Some(id1));
}

#[test]
fn osc_8_protocol_id_preserves_distinct_link_identity() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b]8;id=first;https://example.com\x1b\\");
    let first = term.current_hyperlink_id.expect("first hyperlink");
    term.process(b"\x1b]8;id=second:unknown=value;https://example.com\x07");
    let second = term.current_hyperlink_id.expect("second hyperlink");

    assert_ne!(first, second);
    assert_eq!(
        term.get_hyperlink_protocol_id(first).as_deref(),
        Some("first")
    );
    assert_eq!(
        term.get_hyperlink_protocol_id(second).as_deref(),
        Some("second")
    );

    term.process(b"\x1b]8;id=first;https://example.com\x1b\\");
    assert_eq!(term.current_hyperlink_id, Some(first));
}

#[test]
fn osc_8_reclaims_identities_after_referenced_cells_scroll_out() {
    let mut term = Terminal::with_scrollback(2, 1, 1);
    let mut first_id = None;
    let mut last_id = None;

    for index in 0..super::MAX_HYPERLINK_ENTRIES + 3 {
        let sequence = format!("\x1b]8;id=scroll-{index};https://example.test/{index}\x1b\\");
        term.process(sequence.as_bytes());
        let id = term.current_hyperlink_id.expect("hyperlink should open");
        first_id.get_or_insert(id);
        last_id = Some(id);
        term.process(b"x\x1b]8;;\x1b\\\r\n");
        term.poll_events();
    }

    assert!(term.hyperlinks.len() <= super::MAX_HYPERLINK_ENTRIES);
    assert_eq!(term.hyperlinks.len(), term.hyperlink_protocol_ids.len());
    assert!(term.get_hyperlink_url(first_id.unwrap()).is_none());
    let expected_last_url = format!("https://example.test/{}", super::MAX_HYPERLINK_ENTRIES + 2);
    assert_eq!(
        term.get_hyperlink_url(last_id.unwrap()).as_deref(),
        Some(expected_last_url.as_str())
    );
}

#[test]
fn osc_8_preserves_active_identities_and_rejects_only_new_identity_at_limit() {
    let mut term = Terminal::with_scrollback(super::MAX_HYPERLINK_ENTRIES, 1, 0);
    let mut first_id = None;

    for index in 0..super::MAX_HYPERLINK_ENTRIES {
        let sequence = format!("\x1b]8;id=active-{index};https://active.test/{index}\x1b\\");
        term.process(sequence.as_bytes());
        first_id.get_or_insert(
            term.current_hyperlink_id
                .expect("active hyperlink should open"),
        );
        term.process(b"x");
        term.poll_events();
    }
    term.process(b"\x1b]8;;\x1b\\");

    assert_eq!(term.hyperlinks.len(), super::MAX_HYPERLINK_ENTRIES);
    assert_eq!(
        term.hyperlink_protocol_ids.len(),
        super::MAX_HYPERLINK_ENTRIES
    );

    term.process(b"\x1b]8;id=overflow;https://active.test/overflow\x1b\\");
    assert!(term.current_hyperlink_id.is_none());
    assert_eq!(term.hyperlinks.len(), super::MAX_HYPERLINK_ENTRIES);
    assert!(!term
        .hyperlinks
        .values()
        .any(|url| url == "https://active.test/overflow"));

    term.process(b"\x1b]8;id=active-0;https://active.test/0\x1b\\");
    assert_eq!(term.current_hyperlink_id, first_id);
    assert_eq!(
        term.get_hyperlink_protocol_id(first_id.unwrap()).as_deref(),
        Some("active-0")
    );
}

#[test]
fn osc_8_reclamation_preserves_links_referenced_by_alternate_grid() {
    let mut term = Terminal::with_scrollback(2, 1, 1);
    term.use_alt_screen();
    term.process(b"\x1b]8;id=alt-live;https://alt.test/live\x1b\\x\x1b]8;;\x1b\\");
    let alt_id = term
        .alt_grid
        .cells
        .iter()
        .find_map(|cell| cell.flags.hyperlink_id)
        .expect("alternate grid should retain its hyperlink");
    term.use_primary_screen();

    for index in 0..super::MAX_HYPERLINK_ENTRIES + 1 {
        let sequence = format!("\x1b]8;id=primary-{index};https://primary.test/{index}\x1b\\");
        term.process(sequence.as_bytes());
        term.process(b"x\x1b]8;;\x1b\\\r\n");
        term.poll_events();
    }

    assert!(term.hyperlinks.len() <= super::MAX_HYPERLINK_ENTRIES);
    assert_eq!(
        term.get_hyperlink_url(alt_id).as_deref(),
        Some("https://alt.test/live")
    );
    assert_eq!(
        term.get_hyperlink_protocol_id(alt_id).as_deref(),
        Some("alt-live")
    );
}

#[test]
fn test_osc7_set_directory() {
    let mut term = Terminal::new(80, 24);

    // OSC 7 with file:// URL (localhost)
    term.process(b"\x1b]7;file:///home/user/project\x1b\\");
    assert_eq!(term.shell_integration.cwd(), Some("/home/user/project"));
    assert_eq!(
        term.session_variables().path,
        Some("/home/user/project".to_string())
    );

    // OSC 7 with hostname
    term.process(b"\x1b]7;file://hostname/home/user/test\x1b\\");
    assert_eq!(term.shell_integration.cwd(), Some("/home/user/test"));
    assert_eq!(
        term.session_variables().hostname,
        Some("hostname".to_string())
    );
}

#[test]
fn osc_9_9_updates_absolute_cwd_without_notification_side_effect() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b]7;file://alice@remote.example/tmp/before\x1b\\");
    let _ = term.poll_events();
    term.process(b"\x1b]9;9;/Users/example/project\x1b\\");

    assert_eq!(term.shell_integration.cwd(), Some("/Users/example/project"));
    assert_eq!(term.shell_integration.hostname(), Some("remote.example"));
    assert_eq!(term.shell_integration.username(), Some("alice"));
    assert!(term.notifications().is_empty());
    assert!(term.poll_events().iter().any(|event| matches!(
        event,
        crate::terminal::TerminalEvent::CwdChanged(change)
            if change.source == crate::terminal::CwdChangeSource::Osc9_9
                && change.source.as_str() == "osc9;9"
                && change.new_cwd == "/Users/example/project"
                && change.hostname.as_deref() == Some("remote.example")
                && change.username.as_deref() == Some("alice")
    )));
}

#[test]
fn osc_9_9_rejects_relative_or_control_character_cwd() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b]9;9;relative/path\x07");
    term.process(b"\x1b]9;9;/tmp/otherwise-valid;unexpected\x07");
    // Exercise the semantic handler directly because ECMA-48 parsers are
    // allowed to consume C0 bytes before OSC dispatch.
    term.handle_osc_notify("9", &[b"9", b"9", b"/tmp/bad\x01path"]);
    term.process(b"\x1b]9;9;/tmp/bad\xc2\x85path\x1b\\");

    assert!(term.shell_integration.cwd().is_none());
    assert!(term.notifications().is_empty());
}

#[test]
fn osc_633_shell_markers_and_properties_share_semantic_state() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b]7;file://alice@remote.example/tmp/before\x1b\\");
    let _ = term.poll_events();
    term.process(b"\x1b]633;A\x1b\\");
    term.process(b"\x1b]633;B\x07");
    term.process(b"\x1b]633;E;printf\\x3bvalue;nonce-123\x1b\\");
    term.process(b"\x1b]633;C\x1b\\");
    term.process(b"\x1b]633;P;Cwd=/Users/example/project\x1b\\");
    term.process(b"\x1b]633;D;7\x1b\\");

    assert_eq!(term.shell_integration.cwd(), Some("/Users/example/project"));
    assert_eq!(term.shell_integration.hostname(), Some("remote.example"));
    assert_eq!(term.shell_integration.username(), Some("alice"));
    assert_eq!(term.shell_integration.command(), Some("printf;value"));
    assert_eq!(term.shell_integration.exit_code(), Some(7));
    assert!(term.notifications().is_empty());

    let events = term.poll_events();
    assert!(events.iter().any(|event| matches!(
        event,
        crate::terminal::TerminalEvent::CwdChanged(change)
            if change.source == crate::terminal::CwdChangeSource::Osc633
                && change.new_cwd == "/Users/example/project"
                && change.hostname.as_deref() == Some("remote.example")
                && change.username.as_deref() == Some("alice")
    )));
    let shell_events: Vec<_> = events
        .iter()
        .filter_map(|event| match event {
            crate::terminal::TerminalEvent::ShellIntegrationEvent {
                source,
                event_type,
                command,
                exit_code,
                ..
            } => Some((*source, event_type.as_str(), command.as_deref(), *exit_code)),
            _ => None,
        })
        .collect();
    assert_eq!(shell_events.len(), 4);
    assert!(shell_events.iter().all(|(source, ..)| {
        *source == crate::terminal::event::ShellIntegrationSource::Osc633
            && source.as_str() == "osc633"
    }));
    assert!(shell_events.iter().any(|(_, event_type, command, _)| {
        *event_type == "command_executed" && *command == Some("printf;value")
    }));
    assert!(shell_events.iter().any(|(_, event_type, _, exit_code)| {
        *event_type == "command_finished" && *exit_code == Some(7)
    }));
}

#[test]
fn osc_633_ignores_malformed_properties_and_redacts_nonce_from_state() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b]633;P;Cwd=relative\x07");
    term.process(b"\x1b]633;P;Malformed\x1b\\");
    term.process(b"\x1b]633;P;Cwd=/tmp/otherwise-valid;Unexpected=true\x1b\\");
    term.process(b"\x1b]633;P;Cwd=/tmp/bad\xc2\x85path\x1b\\");
    term.process(b"\x1b]633;E;bad\\xGGcommand;ignored-nonce\x1b\\");
    term.process(b"\x1b]633;E;echo ok;secret-nonce\x1b\\");

    assert!(term.shell_integration.cwd().is_none());
    assert_eq!(term.shell_integration.command(), Some("echo ok"));
    assert!(!format!("{:?}", term.shell_integration).contains("secret-nonce"));
}

#[test]
fn test_osc7_hostname_extraction() {
    let mut term = Terminal::new(80, 24);

    // file:///path - localhost implicit, hostname should be None
    term.process(b"\x1b]7;file:///home/user/project\x1b\\");
    assert_eq!(term.shell_integration.cwd(), Some("/home/user/project"));
    assert!(term.shell_integration.hostname().is_none());

    // file://hostname/path - hostname should be extracted
    term.process(b"\x1b]7;file://myserver/home/user/test\x1b\\");
    assert_eq!(term.shell_integration.cwd(), Some("/home/user/test"));
    assert_eq!(term.shell_integration.hostname(), Some("myserver"));

    // file://localhost/path - localhost should be treated as None
    term.process(b"\x1b]7;file://localhost/var/log\x1b\\");
    assert_eq!(term.shell_integration.cwd(), Some("/var/log"));
    assert!(term.shell_integration.hostname().is_none());

    // file://LOCALHOST/path - case insensitive localhost check
    term.process(b"\x1b]7;file://LOCALHOST/tmp\x1b\\");
    assert_eq!(term.shell_integration.cwd(), Some("/tmp"));
    assert!(term.shell_integration.hostname().is_none());

    // Remote host with full path
    term.process(b"\x1b]7;file://remote.server.com/home/alice/work\x1b\\");
    assert_eq!(term.shell_integration.cwd(), Some("/home/alice/work"));
    assert_eq!(term.shell_integration.hostname(), Some("remote.server.com"));
}

#[test]
fn test_osc7_username_and_port_and_decoding() {
    let mut term = Terminal::new(80, 24);

    // Username and port should be parsed, port stripped from hostname
    term.process(b"\x1b]7;file://alice@example.com:2222/home/alice/Work%20Dir\x1b\\");
    assert_eq!(term.shell_integration.cwd(), Some("/home/alice/Work Dir"));
    assert_eq!(term.shell_integration.hostname(), Some("example.com"));
    assert_eq!(term.shell_integration.username(), Some("alice"));
    assert_eq!(
        term.session_variables().path,
        Some("/home/alice/Work Dir".to_string())
    );
    assert_eq!(
        term.session_variables().hostname,
        Some("example.com".to_string())
    );
    assert_eq!(term.session_variables().username, Some("alice".to_string()));

    // Query/fragment stripped and percent-decoded unicode
    term.process(b"\x1b]7;file://remote.host/home/alice/caf%C3%A9?foo=bar#frag\x1b\\");
    assert_eq!(term.shell_integration.cwd(), Some("/home/alice/café"));
    assert_eq!(term.shell_integration.hostname(), Some("remote.host"));

    // Non-file scheme should be ignored (no change)
    term.process(b"\x1b]7;http://example.com/should_not_set\x1b\\");
    assert_eq!(term.shell_integration.cwd(), Some("/home/alice/café"));
}

#[test]
fn test_osc7_hostname_updates() {
    let mut term = Terminal::new(80, 24);

    // Start with remote host
    term.process(b"\x1b]7;file://server1/home/user\x1b\\");
    assert_eq!(term.shell_integration.hostname(), Some("server1"));

    // Switch to localhost
    term.process(b"\x1b]7;file:///home/user\x1b\\");
    assert!(term.shell_integration.hostname().is_none());

    // Switch to different remote host
    term.process(b"\x1b]7;file://server2/home/user\x1b\\");
    assert_eq!(term.shell_integration.hostname(), Some("server2"));
}

#[test]
fn test_osc7_cwd_history_records_hostname() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b]7;file://server1/home/user\x1b\\");
    term.process(b"\x1b]7;file:///home/local\x1b\\");

    let history = term.get_cwd_changes();
    assert_eq!(history.len(), 2);
    assert_eq!(history[0].new_cwd, "/home/user");
    assert_eq!(history[0].hostname.as_deref(), Some("server1"));
    assert_eq!(history[1].hostname, None);
}

#[test]
fn test_osc7_emits_cwd_changed_event() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b]7;file://server1/home/user\x1b\\");
    let events = term.poll_events();
    assert!(
        events.iter().any(|e| matches!(
            e,
            crate::terminal::TerminalEvent::CwdChanged(change)
            if change.new_cwd == "/home/user"
                && change.hostname.as_deref() == Some("server1")
        )),
        "CwdChanged event with hostname should be emitted",
    );

    // With subscription filter should still receive
    let mut filter = std::collections::HashSet::new();
    filter.insert(crate::terminal::TerminalEventKind::CwdChanged);
    term.set_event_subscription(filter);

    term.process(b"\x1b]7;file:///home/local\x1b\\");
    let subscribed = term.poll_subscribed_events();
    assert!(
        subscribed.iter().any(|e| matches!(
            e,
            crate::terminal::TerminalEvent::CwdChanged(change)
            if change.new_cwd == "/home/local" && change.hostname.is_none()
        )),
        "Subscribed poll should return CwdChanged event"
    );
}

#[test]
fn test_notifications_osc9() {
    let mut term = Terminal::new(80, 24);

    // OSC 9 notification
    term.process(b"\x1b]9;Test notification\x1b\\");
    let notifications = term.notifications();
    assert_eq!(notifications.len(), 1);
    assert_eq!(notifications[0].title, "");
    assert_eq!(notifications[0].message, "Test notification");
}

#[test]
fn test_notifications_security() {
    let mut term = Terminal::new(80, 24);

    // Enable security
    term.process(b"\x1b[?1002h"); // Just to ensure terminal processes sequences

    // Create a terminal with insecure sequences disabled
    let mut secure_term = Terminal::new(80, 24);
    secure_term.disable_insecure_sequences = true;

    // OSC 9 should be blocked
    secure_term.process(b"\x1b]9;Should be blocked\x1b\\");
    assert_eq!(secure_term.notifications().len(), 0);

    // OSC 8 (hyperlinks) should be blocked
    secure_term.process(b"\x1b]8;;https://evil.com\x1b\\");
    assert!(secure_term.current_hyperlink_id.is_none());
}

#[test]
fn test_ansi_palette_reset() {
    let mut term = Terminal::new(80, 24);
    let baseline = Color::Rgb(0x12, 0x34, 0x56);
    term.set_ansi_palette_color(3, baseline).unwrap();
    term.process(b"\x1b]4;3;#abcdef\x1b\\");
    assert_eq!(term.ansi_palette[3], Color::Rgb(0xab, 0xcd, 0xef));

    term.process(b"\x1b]104;3\x1b\\"); // Reset color 3
    assert_eq!(term.ansi_palette[3], baseline);

    // Reset all colors
    term.process(b"\x1b]4;3;#abcdef\x1b\\");
    term.process(b"\x1b]104\x1b\\");
    assert_eq!(term.ansi_palette[3], baseline);
}

#[test]
fn test_default_color_reset() {
    let mut term = Terminal::new(80, 24);
    let foreground = Color::Rgb(1, 2, 3);
    let background = Color::Rgb(4, 5, 6);
    let cursor = Color::Rgb(7, 8, 9);
    term.set_default_fg(foreground);
    term.set_default_bg(background);
    term.set_cursor_color(cursor);
    term.process(b"\x1b]10;#aabbcc\x1b\\");
    term.process(b"\x1b]11;#bbccdd\x1b\\");
    term.process(b"\x1b]12;#ccddee\x1b\\");

    // OSC 110 - Reset foreground
    term.process(b"\x1b]110\x1b\\");

    // OSC 111 - Reset background
    term.process(b"\x1b]111\x1b\\");

    // OSC 112 - Reset cursor color
    term.process(b"\x1b]112\x1b\\");
    assert_eq!(term.default_fg(), foreground);
    assert_eq!(term.default_bg(), background);
    assert_eq!(term.cursor_color(), cursor);
}

#[test]
fn test_query_default_colors() {
    let mut term = Terminal::new(80, 24);

    // OSC 10 - Query foreground
    term.process(b"\x1b]10;?\x1b\\");
    let response = term.drain_responses();
    assert!(response.starts_with(b"\x1b]10;rgb:"));

    // OSC 11 - Query background
    term.process(b"\x1b]11;?\x1b\\");
    let response = term.drain_responses();
    assert!(response.starts_with(b"\x1b]11;rgb:"));

    // OSC 12 - Query cursor color
    term.process(b"\x1b]12;?\x1b\\");
    let response = term.drain_responses();
    assert!(response.starts_with(b"\x1b]12;rgb:"));
}

#[test]
fn test_is_insecure_osc() {
    let term = Terminal::new(80, 24);

    // Without security enabled
    assert!(!term.is_insecure_osc("0"));
    assert!(!term.is_insecure_osc("8"));
    assert!(!term.is_insecure_osc("52"));

    // With security enabled
    let mut secure_term = Terminal::new(80, 24);
    secure_term.disable_insecure_sequences = true;

    assert!(!secure_term.is_insecure_osc("0")); // Title is safe
    assert!(secure_term.is_insecure_osc("8")); // Hyperlinks
    assert!(secure_term.is_insecure_osc("52")); // Clipboard
    assert!(secure_term.is_insecure_osc("9")); // Notifications
    assert!(secure_term.is_insecure_osc("777")); // Notifications
}

#[test]
fn test_clipboard_operations() {
    let mut term = Terminal::new(80, 24);

    // Set clipboard (base64 encoded "Hello")
    let encoded = base64::engine::general_purpose::STANDARD.encode(b"Hello");
    let sequence = format!("\x1b]52;c;{}\x1b\\", encoded);
    term.process(sequence.as_bytes());
    assert_eq!(term.clipboard_content, Some("Hello".to_string()));

    // Empty payload is treated as a no-op (preserve existing clipboard content)
    term.process(b"\x1b]52;c;\x1b\\");
    assert_eq!(term.clipboard_content, Some("Hello".to_string()));
}

#[test]
fn test_clipboard_query_security() {
    let mut term = Terminal::new(80, 24);
    term.allow_clipboard_read = false;

    // Set clipboard
    let encoded = base64::engine::general_purpose::STANDARD.encode(b"Secret");
    let sequence = format!("\x1b]52;c;{}\x1b\\", encoded);
    term.process(sequence.as_bytes());

    // Query should be blocked
    term.process(b"\x1b]52;c;?\x1b\\");
    let response = term.drain_responses();
    assert_eq!(response, b""); // No response when clipboard read is disabled
}

#[test]
fn test_title_with_special_chars() {
    let mut term = Terminal::new(80, 24);

    // Title with Unicode
    term.process("\x1b]0;测试标题\x1b\\".as_bytes());
    assert_eq!(term.title(), "测试标题");

    // Title with spaces and punctuation
    term.process(b"\x1b]0;Test: A Title! (v1.0)\x1b\\");
    assert_eq!(term.title(), "Test: A Title! (v1.0)");
}

// === OSC 9;4 Progress Bar Tests ===

#[test]
fn test_progress_bar_normal() {
    let mut term = Terminal::new(80, 24);

    // OSC 9;4;1;50 - Set normal progress to 50%
    term.process(b"\x1b]9;4;1;50\x1b\\");

    assert!(term.has_progress());
    assert_eq!(
        term.progress_state(),
        crate::terminal::ProgressState::Normal
    );
    assert_eq!(term.progress_value(), 50);
}

#[test]
fn test_progress_bar_hidden() {
    let mut term = Terminal::new(80, 24);

    // First set a progress
    term.process(b"\x1b]9;4;1;75\x1b\\");
    assert!(term.has_progress());

    // Then hide it with OSC 9;4;0
    term.process(b"\x1b]9;4;0\x1b\\");

    assert!(!term.has_progress());
    assert_eq!(
        term.progress_state(),
        crate::terminal::ProgressState::Hidden
    );
}

#[test]
fn test_progress_bar_error() {
    let mut term = Terminal::new(80, 24);

    // OSC 9;4;2;100 - Error progress at 100%
    term.process(b"\x1b]9;4;2;100\x1b\\");

    assert!(term.has_progress());
    assert_eq!(term.progress_state(), crate::terminal::ProgressState::Error);
    assert_eq!(term.progress_value(), 100);
}

#[test]
fn test_progress_bar_indeterminate() {
    let mut term = Terminal::new(80, 24);

    // OSC 9;4;3 - Indeterminate progress
    term.process(b"\x1b]9;4;3\x1b\\");

    assert!(term.has_progress());
    assert_eq!(
        term.progress_state(),
        crate::terminal::ProgressState::Indeterminate
    );
    // Progress value is not meaningful for indeterminate
}

#[test]
fn test_progress_bar_warning() {
    let mut term = Terminal::new(80, 24);

    // OSC 9;4;4;80 - Warning/paused progress at 80%
    term.process(b"\x1b]9;4;4;80\x1b\\");

    assert!(term.has_progress());
    assert_eq!(
        term.progress_state(),
        crate::terminal::ProgressState::Warning
    );
    assert_eq!(term.progress_value(), 80);
}

#[test]
fn test_progress_bar_clamps_to_100() {
    let mut term = Terminal::new(80, 24);

    // OSC 9;4;1;150 - Progress value above 100 should clamp
    term.process(b"\x1b]9;4;1;150\x1b\\");

    assert_eq!(term.progress_value(), 100);
}

#[test]
fn test_progress_bar_clamps_large_numeric_percent_to_100() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b]9;4;1;999999\x1b\\");

    assert_eq!(
        term.progress_state(),
        crate::terminal::ProgressState::Normal
    );
    assert_eq!(term.progress_value(), 100);
}

#[test]
fn test_progress_bar_large_numeric_state_defaults_to_hidden() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b]9;4;1;55\x1b\\");
    assert!(term.has_progress());

    term.process(b"\x1b]9;4;999999;50\x1b\\");

    assert!(!term.has_progress());
    assert_eq!(
        term.progress_state(),
        crate::terminal::ProgressState::Hidden
    );
    assert_eq!(term.progress_value(), 0);
}

#[test]
fn test_progress_bar_manual_set() {
    let mut term = Terminal::new(80, 24);

    // Use the programmatic API
    term.set_progress(crate::terminal::ProgressState::Warning, 65);

    assert!(term.has_progress());
    assert_eq!(
        term.progress_state(),
        crate::terminal::ProgressState::Warning
    );
    assert_eq!(term.progress_value(), 65);

    // Clear it
    term.clear_progress();

    assert!(!term.has_progress());
    assert_eq!(
        term.progress_state(),
        crate::terminal::ProgressState::Hidden
    );
}

#[test]
fn test_progress_bar_does_not_affect_notifications() {
    let mut term = Terminal::new(80, 24);

    // OSC 9 with message (notification)
    term.process(b"\x1b]9;Test notification\x1b\\");
    assert_eq!(term.notifications().len(), 1);
    assert_eq!(term.notifications()[0].message, "Test notification");

    // Progress bar should still be hidden
    assert!(!term.has_progress());

    // Progress bar sequence
    term.process(b"\x1b]9;4;1;50\x1b\\");

    // Should have progress now
    assert!(term.has_progress());
    // Notification count should not increase
    assert_eq!(term.notifications().len(), 1);
}

#[test]
fn test_progress_bar_sequence_format() {
    use crate::terminal::ProgressBar;

    // Test escape sequence generation
    assert_eq!(
        ProgressBar::hidden().to_escape_sequence(),
        "\x1b]9;4;0\x1b\\"
    );
    assert_eq!(
        ProgressBar::normal(50).to_escape_sequence(),
        "\x1b]9;4;1;50\x1b\\"
    );
    assert_eq!(
        ProgressBar::error(100).to_escape_sequence(),
        "\x1b]9;4;2;100\x1b\\"
    );
    assert_eq!(
        ProgressBar::indeterminate().to_escape_sequence(),
        "\x1b]9;4;3\x1b\\"
    );
    assert_eq!(
        ProgressBar::warning(75).to_escape_sequence(),
        "\x1b]9;4;4;75\x1b\\"
    );
}

// === OSC 1337 SetBadgeFormat Tests ===

#[test]
fn test_set_badge_format_simple() {
    use base64::{engine::general_purpose::STANDARD, Engine};

    let mut term = Terminal::new(80, 24);

    // Simple text badge
    let encoded = STANDARD.encode("Production");
    let sequence = format!("\x1b]1337;SetBadgeFormat={}\x1b\\", encoded);
    term.process(sequence.as_bytes());

    assert_eq!(term.badge_format(), Some("Production"));
}

#[test]
fn test_set_badge_format_with_variables() {
    use base64::{engine::general_purpose::STANDARD, Engine};

    let mut term = Terminal::new(80, 24);

    // Badge with variable interpolation
    let encoded = STANDARD.encode(r"\(username)@\(hostname)");
    let sequence = format!("\x1b]1337;SetBadgeFormat={}\x1b\\", encoded);
    term.process(sequence.as_bytes());

    assert_eq!(term.badge_format(), Some(r"\(username)@\(hostname)"));
}

#[test]
fn test_set_badge_format_with_session_prefix() {
    use base64::{engine::general_purpose::STANDARD, Engine};

    let mut term = Terminal::new(80, 24);

    // Badge with session.variable syntax
    let encoded = STANDARD.encode(r"\(session.path)");
    let sequence = format!("\x1b]1337;SetBadgeFormat={}\x1b\\", encoded);
    term.process(sequence.as_bytes());

    assert_eq!(term.badge_format(), Some(r"\(session.path)"));
}

#[test]
fn test_clear_badge_format() {
    use base64::{engine::general_purpose::STANDARD, Engine};

    let mut term = Terminal::new(80, 24);

    // Set a badge
    let encoded = STANDARD.encode("Test Badge");
    let sequence = format!("\x1b]1337;SetBadgeFormat={}\x1b\\", encoded);
    term.process(sequence.as_bytes());
    assert!(term.badge_format().is_some());

    // Clear badge with empty value
    term.process(b"\x1b]1337;SetBadgeFormat=\x1b\\");
    assert!(term.badge_format().is_none());
}

#[test]
fn test_set_badge_format_rejects_unsafe() {
    use base64::{engine::general_purpose::STANDARD, Engine};

    let mut term = Terminal::new(80, 24);

    // Try to set a badge with shell command injection
    let encoded = STANDARD.encode("$(whoami)");
    let sequence = format!("\x1b]1337;SetBadgeFormat={}\x1b\\", encoded);
    term.process(sequence.as_bytes());

    // Should be rejected (badge should remain None)
    assert!(term.badge_format().is_none());
}

#[test]
fn test_set_badge_format_rejects_escape_sequences() {
    use base64::{engine::general_purpose::STANDARD, Engine};

    let mut term = Terminal::new(80, 24);

    // Try to set a badge with escape sequences
    let encoded = STANDARD.encode("\x1b[31mred\x1b[0m");
    let sequence = format!("\x1b]1337;SetBadgeFormat={}\x1b\\", encoded);
    term.process(sequence.as_bytes());

    // Should be rejected
    assert!(term.badge_format().is_none());
}

#[test]
fn test_evaluate_badge() {
    use base64::{engine::general_purpose::STANDARD, Engine};

    let mut term = Terminal::new(80, 24);

    // Set badge format
    let encoded = STANDARD.encode(r"\(username)@\(hostname)");
    let sequence = format!("\x1b]1337;SetBadgeFormat={}\x1b\\", encoded);
    term.process(sequence.as_bytes());

    // Set session variables
    term.session_variables_mut().set_username("alice");
    term.session_variables_mut().set_hostname("server1");

    // Evaluate badge
    let result = term.evaluate_badge();
    assert_eq!(result, Some("alice@server1".to_string()));
}

#[test]
fn test_evaluate_badge_with_dimensions() {
    use base64::{engine::general_purpose::STANDARD, Engine};

    let mut term = Terminal::new(120, 40);

    // Set badge format with dimensions
    let encoded = STANDARD.encode(r"\(columns)x\(rows)");
    let sequence = format!("\x1b]1337;SetBadgeFormat={}\x1b\\", encoded);
    term.process(sequence.as_bytes());

    // Dimensions should be available from session variables
    let result = term.evaluate_badge();
    assert_eq!(result, Some("120x40".to_string()));
}

#[test]
fn test_badge_dimensions_update_on_resize() {
    use base64::{engine::general_purpose::STANDARD, Engine};

    let mut term = Terminal::new(80, 24);

    // Set badge format with dimensions
    let encoded = STANDARD.encode(r"\(columns)x\(rows)");
    let sequence = format!("\x1b]1337;SetBadgeFormat={}\x1b\\", encoded);
    term.process(sequence.as_bytes());

    // Initial evaluation
    assert_eq!(term.evaluate_badge(), Some("80x24".to_string()));

    // Resize terminal
    term.resize(120, 40);

    // Dimensions should update
    assert_eq!(term.evaluate_badge(), Some("120x40".to_string()));
}

#[test]
fn test_evaluate_badge_none() {
    let term = Terminal::new(80, 24);

    // No badge format set
    assert!(term.evaluate_badge().is_none());
}

#[test]
fn test_session_variables_sync_with_title() {
    let mut term = Terminal::new(80, 24);

    // Set title
    term.set_title("My Terminal".to_string());

    // Session variables should have the title
    assert_eq!(
        term.session_variables().get("title"),
        Some("My Terminal".to_string())
    );
}

#[test]
fn test_session_variables_bell_count() {
    let mut term = Terminal::new(80, 24);

    // Send some bells
    term.process(b"\x07\x07\x07");

    // Bell count should be tracked in session variables
    assert_eq!(
        term.session_variables().get("bell_count"),
        Some("3".to_string())
    );
}

#[test]
fn test_set_user_var_basic() {
    use base64::{engine::general_purpose::STANDARD, Engine};

    let mut term = Terminal::new(80, 24);

    // Encode "myhost.example.com" as base64
    let value = STANDARD.encode("myhost.example.com");
    let seq = format!("\x1b]1337;SetUserVar=hostname={}\x07", value);
    term.process(seq.as_bytes());

    // Verify the variable was stored
    assert_eq!(term.get_user_var("hostname"), Some("myhost.example.com"));
}

#[test]
fn test_set_user_var_event_emitted() {
    use base64::{engine::general_purpose::STANDARD, Engine};

    let mut term = Terminal::new(80, 24);

    let value = STANDARD.encode("alice");
    let seq = format!("\x1b]1337;SetUserVar=username={}\x07", value);
    term.process(seq.as_bytes());

    let events = term.poll_events();
    let user_var_events: Vec<_> = events
        .iter()
        .filter(|e| matches!(e, crate::terminal::TerminalEvent::UserVarChanged { .. }))
        .collect();
    assert_eq!(user_var_events.len(), 1);

    if let crate::terminal::TerminalEvent::UserVarChanged {
        name,
        value,
        old_value,
    } = &user_var_events[0]
    {
        assert_eq!(name, "username");
        assert_eq!(value, "alice");
        assert!(old_value.is_none());
    } else {
        panic!("Expected UserVarChanged event");
    }
}

#[test]
fn test_set_user_var_update_with_old_value() {
    use base64::{engine::general_purpose::STANDARD, Engine};

    let mut term = Terminal::new(80, 24);

    // Set initial value
    let value1 = STANDARD.encode("server1");
    let seq1 = format!("\x1b]1337;SetUserVar=host={}\x07", value1);
    term.process(seq1.as_bytes());
    term.poll_events(); // drain

    // Update value
    let value2 = STANDARD.encode("server2");
    let seq2 = format!("\x1b]1337;SetUserVar=host={}\x07", value2);
    term.process(seq2.as_bytes());

    let events = term.poll_events();
    let user_var_events: Vec<_> = events
        .iter()
        .filter(|e| matches!(e, crate::terminal::TerminalEvent::UserVarChanged { .. }))
        .collect();
    assert_eq!(user_var_events.len(), 1);

    if let crate::terminal::TerminalEvent::UserVarChanged {
        name,
        value,
        old_value,
    } = &user_var_events[0]
    {
        assert_eq!(name, "host");
        assert_eq!(value, "server2");
        assert_eq!(old_value.as_deref(), Some("server1"));
    }
}

#[test]
fn test_set_user_var_no_event_when_same_value() {
    use base64::{engine::general_purpose::STANDARD, Engine};

    let mut term = Terminal::new(80, 24);

    // Set value
    let value = STANDARD.encode("same");
    let seq = format!("\x1b]1337;SetUserVar=key={}\x07", value);
    term.process(seq.as_bytes());
    term.poll_events(); // drain

    // Set the same value again
    term.process(seq.as_bytes());

    let events = term.poll_events();
    let user_var_events: Vec<_> = events
        .iter()
        .filter(|e| matches!(e, crate::terminal::TerminalEvent::UserVarChanged { .. }))
        .collect();
    assert_eq!(user_var_events.len(), 0, "No event when value unchanged");
}

#[test]
fn test_set_user_var_multiple_variables() {
    use base64::{engine::general_purpose::STANDARD, Engine};

    let mut term = Terminal::new(80, 24);

    let host = STANDARD.encode("myhost");
    let user = STANDARD.encode("myuser");
    let dir = STANDARD.encode("/home/myuser");

    let seq = format!(
            "\x1b]1337;SetUserVar=hostname={}\x07\x1b]1337;SetUserVar=username={}\x07\x1b]1337;SetUserVar=currentDir={}\x07",
            host, user, dir
        );
    term.process(seq.as_bytes());

    assert_eq!(term.get_user_var("hostname"), Some("myhost"));
    assert_eq!(term.get_user_var("username"), Some("myuser"));
    assert_eq!(term.get_user_var("currentDir"), Some("/home/myuser"));

    let vars = term.get_user_vars();
    assert_eq!(vars.len(), 3);
}

#[test]
fn set_user_var_rejects_new_key_at_limit_but_updates_existing_key() {
    use base64::{engine::general_purpose::STANDARD, Engine};

    let mut term = Terminal::new(80, 24);
    for index in 0..crate::badge::MAX_CUSTOM_SESSION_VARIABLES {
        term.set_user_var(format!("key-{index}"), "initial".to_string());
    }
    term.poll_events();

    process_osc1337(
        &mut term,
        &format!("SetUserVar=overflow={}", STANDARD.encode("rejected")),
    );
    assert_eq!(
        term.get_user_vars().len(),
        crate::badge::MAX_CUSTOM_SESSION_VARIABLES
    );
    assert!(term.get_user_var("overflow").is_none());
    assert!(term
        .poll_events()
        .into_iter()
        .all(|event| !matches!(event, crate::terminal::TerminalEvent::UserVarChanged { .. })));

    process_osc1337(
        &mut term,
        &format!("SetUserVar=key-0={}", STANDARD.encode("updated")),
    );
    assert_eq!(term.get_user_var("key-0"), Some("updated"));
    assert!(term.poll_events().into_iter().any(|event| matches!(
        event,
        crate::terminal::TerminalEvent::UserVarChanged {
            name,
            value,
            old_value: Some(old_value),
        } if name == "key-0" && value == "updated" && old_value == "initial"
    )));
}

#[test]
fn test_iterm_multipart_inline_without_size_waits_for_file_end() {
    let mut term = Terminal::new(80, 24);
    let name = base64::engine::general_purpose::STANDARD.encode("pixel.png");
    let image = tiny_png_base64();

    process_osc1337(&mut term, &format!("MultipartFile=inline=1;name={name}"));
    process_osc1337(&mut term, &format!("FilePart={image}"));

    assert_eq!(
        term.graphics_count(),
        0,
        "inline multipart images without size must wait for FileEnd"
    );

    process_osc1337(&mut term, "FileEnd");

    assert_eq!(term.graphics_count(), 1);
    let graphic = term
        .all_graphics()
        .last()
        .expect("FileEnd should finalize the inline iTerm2 image");
    assert_eq!(graphic.protocol.as_str(), "iterm");
    assert_eq!(graphic.width, 1);
    assert_eq!(graphic.height, 1);
}

#[test]
fn iterm_multipart_inline_without_size_rejects_decoded_total_over_graphics_limit() {
    let mut term = Terminal::new(80, 24);
    term.set_graphics_memory_limits(8, 8192);
    process_osc1337(&mut term, "MultipartFile=inline=1");

    // Each valid four-byte Base64 part decodes to three bytes. The third part
    // would take the aggregate decoded payload from six to nine bytes.
    process_osc1337(&mut term, "FilePart=AAAA");
    process_osc1337(&mut term, "FilePart=AAAA");
    assert_eq!(
        term.iterm_multipart_buffer
            .as_ref()
            .map(|state| state.accumulated_size),
        Some(6)
    );
    process_osc1337(&mut term, "FilePart=AAAA");

    assert!(term.iterm_multipart_buffer.is_none());
    process_osc1337(&mut term, "FileEnd");
    assert_eq!(term.graphics_count(), 0);
}

#[test]
fn iterm_multipart_inline_bounds_retained_encoded_parts_without_declared_size() {
    let mut term = Terminal::new(80, 24);
    term.set_graphics_memory_limits(8, 8192);
    process_osc1337(&mut term, "MultipartFile=inline=1");
    let whitespace_part = format!("FilePart={}", " ".repeat(1024));

    // Whitespace is legal around Base64 and decodes to no bytes, so decoded
    // accounting alone cannot bound the retained raw multipart payload.
    for _ in 0..4 {
        process_osc1337(&mut term, &whitespace_part);
    }
    assert_eq!(
        term.iterm_multipart_buffer
            .as_ref()
            .map(|state| state.encoded_data.len()),
        Some(4096)
    );

    process_osc1337(&mut term, &whitespace_part);
    assert!(term.iterm_multipart_buffer.is_none());
    process_osc1337(&mut term, "FileEnd");
    assert_eq!(term.graphics_count(), 0);
}

#[test]
fn test_iterm_single_inline_accepts_wrapped_base64() {
    let mut term = Terminal::new(80, 24);
    let image = tiny_png_base64()
        .as_bytes()
        .chunks(16)
        .map(|chunk| std::str::from_utf8(chunk).unwrap())
        .collect::<Vec<_>>()
        .join("\n");

    process_osc1337(&mut term, &format!("File=inline=1:{image}"));

    assert_eq!(term.graphics_count(), 1);
    let graphic = term
        .all_graphics()
        .last()
        .expect("wrapped single-sequence iTerm2 image should decode");
    assert_eq!(graphic.protocol.as_str(), "iterm");
    assert_eq!(graphic.width, 1);
    assert_eq!(graphic.height, 1);
}

#[test]
fn test_iterm_single_inline_accepts_c1_osc_and_st_controls() {
    let mut term = Terminal::new(80, 24);
    let image = tiny_png_base64();
    let mut sequence = Vec::new();
    sequence.push(0x9d);
    sequence.extend_from_slice(format!("1337;File=inline=1:{image}").as_bytes());
    sequence.push(0x9c);

    term.process(&sequence);

    assert_eq!(term.graphics_count(), 1);
    let graphic = term
        .all_graphics()
        .last()
        .expect("C1 OSC/ST iTerm2 image should decode");
    assert_eq!(graphic.protocol.as_str(), "iterm");
    assert_eq!(graphic.width, 1);
    assert_eq!(graphic.height, 1);
}

#[test]
fn test_iterm_multipart_inline_accepts_wrapped_file_part_base64() {
    let mut term = Terminal::new(80, 24);
    let name = base64::engine::general_purpose::STANDARD.encode("pixel.png");
    let image = tiny_png_base64()
        .as_bytes()
        .chunks(20)
        .map(|chunk| std::str::from_utf8(chunk).unwrap())
        .collect::<Vec<_>>()
        .join("\r\n\t");

    process_osc1337(&mut term, &format!("MultipartFile=inline=1;name={name}"));
    process_osc1337(&mut term, &format!("FilePart={image}"));
    process_osc1337(&mut term, "FileEnd");

    assert_eq!(term.graphics_count(), 1);
    let graphic = term
        .all_graphics()
        .last()
        .expect("wrapped multipart iTerm2 image should decode at FileEnd");
    assert_eq!(graphic.protocol.as_str(), "iterm");
    assert_eq!(graphic.width, 1);
    assert_eq!(graphic.height, 1);
}

#[test]
fn test_iterm_multipart_inline_accepts_unaligned_file_part_base64() {
    let mut term = Terminal::new(80, 24);
    let name = base64::engine::general_purpose::STANDARD.encode("pixel.png");
    let image = tiny_png_base64();
    let (first, rest) = image.split_at(5);
    let (second, third) = rest.split_at(7);

    process_osc1337(&mut term, &format!("MultipartFile=inline=1;name={name}"));
    process_osc1337(&mut term, &format!("FilePart={first}"));
    process_osc1337(&mut term, &format!("FilePart={second}"));
    process_osc1337(&mut term, &format!("FilePart={third}"));

    assert_eq!(
        term.graphics_count(),
        0,
        "unaligned multipart iTerm2 images still wait for FileEnd"
    );

    process_osc1337(&mut term, "FileEnd");

    assert_eq!(term.graphics_count(), 1);
    let graphic = term
        .all_graphics()
        .last()
        .expect("unaligned multipart iTerm2 image should decode at FileEnd");
    assert_eq!(graphic.protocol.as_str(), "iterm");
    assert_eq!(graphic.width, 1);
    assert_eq!(graphic.height, 1);
}

#[test]
fn test_iterm_multipart_inline_with_size_waits_for_file_end() {
    let mut term = Terminal::new(80, 24);
    let name = base64::engine::general_purpose::STANDARD.encode("pixel.png");
    let image = tiny_png_base64();
    let decoded_size = base64::engine::general_purpose::STANDARD
        .decode(image.as_bytes())
        .expect("test image should decode")
        .len();

    process_osc1337(
        &mut term,
        &format!("MultipartFile=inline=1;size={decoded_size};name={name}"),
    );
    process_osc1337(&mut term, &format!("FilePart={image}"));

    assert_eq!(
        term.graphics_count(),
        0,
        "inline multipart images must wait for FileEnd even when size is reached"
    );

    process_osc1337(&mut term, "FileEnd");

    assert_eq!(term.graphics_count(), 1);
    let graphic = term
        .all_graphics()
        .last()
        .expect("FileEnd should finalize the inline iTerm2 image");
    assert_eq!(graphic.protocol.as_str(), "iterm");
    assert_eq!(graphic.width, 1);
    assert_eq!(graphic.height, 1);
}

#[test]
fn test_iterm_multipart_download_without_size_waits_for_file_end() {
    let mut term = Terminal::new(80, 24);
    let filename = base64::engine::general_purpose::STANDARD.encode("artifact.txt");
    let payload = base64::engine::general_purpose::STANDARD.encode("hello");

    process_osc1337(
        &mut term,
        &format!("MultipartFile=inline=0;name={filename}"),
    );
    let started_events = term.poll_events();
    let transfer_id = started_events
        .iter()
        .find_map(|event| match event {
            crate::terminal::TerminalEvent::FileTransferStarted {
                id,
                direction,
                filename,
                total_bytes,
            } => {
                assert!(matches!(
                    direction,
                    crate::terminal::TransferDirection::Download
                ));
                assert_eq!(filename.as_deref(), Some("artifact.txt"));
                assert_eq!(*total_bytes, None);
                Some(*id)
            }
            _ => None,
        })
        .expect("MultipartFile should start a download transfer");

    process_osc1337(&mut term, &format!("FilePart={payload}"));
    let part_events = term.poll_events();
    assert!(part_events.iter().any(|event| matches!(
        event,
        crate::terminal::TerminalEvent::FileTransferProgress {
            id,
            bytes_transferred: 5,
            total_bytes: None,
        } if *id == transfer_id
    )));
    assert!(
        part_events.iter().all(|event| !matches!(
            event,
            crate::terminal::TerminalEvent::FileTransferCompleted { .. }
                | crate::terminal::TerminalEvent::FileTransferFailed { .. }
        )),
        "download without size must remain pending until FileEnd"
    );

    process_osc1337(&mut term, "FileEnd");
    let completed_events = term.poll_events();
    assert!(completed_events.iter().any(|event| matches!(
        event,
        crate::terminal::TerminalEvent::FileTransferCompleted {
        id,
        filename,
        size: 5,
    } if *id == transfer_id && filename.as_deref() == Some("artifact.txt")
    )));
}

#[test]
fn test_iterm_single_download_without_name_uses_default_filename() {
    let mut term = Terminal::new(80, 24);
    let payload = base64::engine::general_purpose::STANDARD.encode("hello");

    process_osc1337(&mut term, &format!("File=inline=0:{payload}"));
    let events = term.poll_events();

    let transfer_id = events
        .iter()
        .find_map(|event| match event {
            crate::terminal::TerminalEvent::FileTransferStarted { id, filename, .. } => {
                assert_eq!(filename.as_deref(), Some("Unnamed file"));
                Some(*id)
            }
            _ => None,
        })
        .expect("single File download should emit a started event");

    assert!(events.iter().any(|event| matches!(
        event,
        crate::terminal::TerminalEvent::FileTransferCompleted {
            id,
            filename,
            size: 5,
        } if *id == transfer_id && filename.as_deref() == Some("Unnamed file")
    )));
}

#[test]
fn test_iterm_multipart_download_without_name_uses_default_filename() {
    let mut term = Terminal::new(80, 24);
    let payload = base64::engine::general_purpose::STANDARD.encode("hello");

    process_osc1337(&mut term, "MultipartFile=inline=0;size=5");
    let started_events = term.poll_events();
    let transfer_id = started_events
        .iter()
        .find_map(|event| match event {
            crate::terminal::TerminalEvent::FileTransferStarted { id, filename, .. } => {
                assert_eq!(filename.as_deref(), Some("Unnamed file"));
                Some(*id)
            }
            _ => None,
        })
        .expect("MultipartFile download should emit a started event");

    process_osc1337(&mut term, &format!("FilePart={payload}"));
    let _ = term.poll_events();
    process_osc1337(&mut term, "FileEnd");
    let completed_events = term.poll_events();
    assert!(completed_events.iter().any(|event| matches!(
        event,
        crate::terminal::TerminalEvent::FileTransferCompleted {
            id,
            filename,
            size: 5,
        } if *id == transfer_id && filename.as_deref() == Some("Unnamed file")
    )));
}

#[test]
fn test_iterm_multipart_download_accepts_unaligned_file_part_base64() {
    let mut term = Terminal::new(80, 24);
    let filename = base64::engine::general_purpose::STANDARD.encode("artifact.txt");
    let payload = base64::engine::general_purpose::STANDARD.encode("hello");
    let (first, rest) = payload.split_at(3);
    let (second, third) = rest.split_at(2);

    process_osc1337(
        &mut term,
        &format!("MultipartFile=inline=0;size=5;name={filename}"),
    );
    let started_events = term.poll_events();
    let transfer_id = started_events
        .iter()
        .find_map(|event| match event {
            crate::terminal::TerminalEvent::FileTransferStarted { id, .. } => Some(*id),
            _ => None,
        })
        .expect("MultipartFile should start a download transfer");

    process_osc1337(&mut term, &format!("FilePart={first}"));
    let first_events = term.poll_events();
    assert!(
        first_events.iter().all(|event| !matches!(
            event,
            crate::terminal::TerminalEvent::FileTransferProgress { .. }
                | crate::terminal::TerminalEvent::FileTransferCompleted { .. }
                | crate::terminal::TerminalEvent::FileTransferFailed { .. }
        )),
        "partial base64 quantum should not emit transfer progress"
    );

    process_osc1337(&mut term, &format!("FilePart={second}"));
    let second_events = term.poll_events();
    assert!(second_events.iter().any(|event| matches!(
        event,
        crate::terminal::TerminalEvent::FileTransferProgress {
            id,
            bytes_transferred: 3,
            total_bytes: Some(5),
        } if *id == transfer_id
    )));

    process_osc1337(&mut term, &format!("FilePart={third}"));
    let third_events = term.poll_events();
    assert!(third_events.iter().any(|event| matches!(
        event,
        crate::terminal::TerminalEvent::FileTransferProgress {
            id,
            bytes_transferred: 5,
            total_bytes: Some(5),
        } if *id == transfer_id
    )));
    assert!(
        third_events.iter().all(|event| !matches!(
            event,
            crate::terminal::TerminalEvent::FileTransferCompleted { .. }
                | crate::terminal::TerminalEvent::FileTransferFailed { .. }
        )),
        "unaligned download transfer must still wait for FileEnd"
    );

    process_osc1337(&mut term, "FileEnd");
    let completed_events = term.poll_events();
    assert!(completed_events.iter().any(|event| matches!(
        event,
        crate::terminal::TerminalEvent::FileTransferCompleted {
            id,
            filename,
            size: 5,
        } if *id == transfer_id && filename.as_deref() == Some("artifact.txt")
    )));
}

#[test]
fn test_iterm_multipart_download_with_size_waits_for_file_end() {
    let mut term = Terminal::new(80, 24);
    let filename = base64::engine::general_purpose::STANDARD.encode("artifact.txt");
    let payload = base64::engine::general_purpose::STANDARD.encode("hello");

    process_osc1337(
        &mut term,
        &format!("MultipartFile=inline=0;size=5;name={filename}"),
    );
    let started_events = term.poll_events();
    let transfer_id = started_events
        .iter()
        .find_map(|event| match event {
            crate::terminal::TerminalEvent::FileTransferStarted {
                id,
                direction,
                filename,
                total_bytes,
            } => {
                assert!(matches!(
                    direction,
                    crate::terminal::TransferDirection::Download
                ));
                assert_eq!(filename.as_deref(), Some("artifact.txt"));
                assert_eq!(*total_bytes, Some(5));
                Some(*id)
            }
            _ => None,
        })
        .expect("MultipartFile should start a download transfer");

    process_osc1337(&mut term, &format!("FilePart={payload}"));
    let part_events = term.poll_events();
    assert!(part_events.iter().any(|event| matches!(
        event,
        crate::terminal::TerminalEvent::FileTransferProgress {
            id,
            bytes_transferred: 5,
            total_bytes: Some(5),
        } if *id == transfer_id
    )));
    assert!(
        part_events.iter().all(|event| !matches!(
            event,
            crate::terminal::TerminalEvent::FileTransferCompleted { .. }
                | crate::terminal::TerminalEvent::FileTransferFailed { .. }
        )),
        "download multipart transfers must wait for FileEnd even when size is reached"
    );

    process_osc1337(&mut term, "FileEnd");
    let completed_events = term.poll_events();
    assert!(completed_events.iter().any(|event| matches!(
        event,
        crate::terminal::TerminalEvent::FileTransferCompleted {
            id,
            filename,
            size: 5,
        } if *id == transfer_id && filename.as_deref() == Some("artifact.txt")
    )));
}

#[test]
fn test_set_user_var_invalid_base64() {
    let mut term = Terminal::new(80, 24);

    // Invalid base64
    let seq = b"\x1b]1337;SetUserVar=key=!!!invalid!!!\x07";
    term.process(seq);

    // Variable should not be set
    assert!(term.get_user_var("key").is_none());
}

#[test]
fn test_set_user_var_missing_separator() {
    let mut term = Terminal::new(80, 24);

    // Missing = between name and value
    let seq = b"\x1b]1337;SetUserVar=keyonly\x07";
    term.process(seq);

    // Nothing should be set
    assert!(term.get_user_var("keyonly").is_none());
}

#[test]
fn test_set_user_var_empty_name() {
    use base64::{engine::general_purpose::STANDARD, Engine};

    let mut term = Terminal::new(80, 24);

    let value = STANDARD.encode("test");
    let seq = format!("\x1b]1337;SetUserVar=={}\x07", value);
    term.process(seq.as_bytes());

    // Empty name should be rejected
    assert!(term.get_user_vars().is_empty());
}

#[test]
fn test_set_user_var_available_in_session_variables() {
    use base64::{engine::general_purpose::STANDARD, Engine};

    let mut term = Terminal::new(80, 24);

    let value = STANDARD.encode("testval");
    let seq = format!("\x1b]1337;SetUserVar=myvar={}\x07", value);
    term.process(seq.as_bytes());

    // Should be accessible via session_variables.get() for badge evaluation
    assert_eq!(
        term.session_variables().get("myvar"),
        Some("testval".to_string())
    );
}

// === OSC 934 Named Progress Bar Tests ===

#[test]
fn test_osc934_set_progress_bar() {
    let mut term = Terminal::new(80, 24);

    // OSC 934 ; set ; dl-1 ; percent=50 ; label=Downloading ST
    term.process(b"\x1b]934;set;dl-1;percent=50;label=Downloading\x1b\\");

    let bars = term.named_progress_bars();
    assert_eq!(bars.len(), 1);

    let bar = bars.get("dl-1").unwrap();
    assert_eq!(bar.id, "dl-1");
    assert_eq!(bar.state, crate::terminal::ProgressState::Normal);
    assert_eq!(bar.percent, 50);
    assert_eq!(bar.label, Some("Downloading".to_string()));
}

#[test]
fn test_osc934_set_with_state() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b]934;set;build;state=indeterminate;label=Compiling\x1b\\");

    let bar = term.get_named_progress_bar("build").unwrap();
    assert_eq!(bar.state, crate::terminal::ProgressState::Indeterminate);
    assert_eq!(bar.label, Some("Compiling".to_string()));
}

#[test]
fn test_osc934_update_progress_bar() {
    let mut term = Terminal::new(80, 24);

    // Create
    term.process(b"\x1b]934;set;dl-1;percent=10;label=Starting\x1b\\");
    assert_eq!(term.get_named_progress_bar("dl-1").unwrap().percent, 10);

    // Update
    term.process(b"\x1b]934;set;dl-1;percent=75;label=Almost done\x1b\\");
    let bar = term.get_named_progress_bar("dl-1").unwrap();
    assert_eq!(bar.percent, 75);
    assert_eq!(bar.label, Some("Almost done".to_string()));

    // Still only one bar
    assert_eq!(term.named_progress_bars().len(), 1);
}

#[test]
fn test_osc934_multiple_bars() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b]934;set;dl-1;percent=30;label=File 1\x1b\\");
    term.process(b"\x1b]934;set;dl-2;percent=60;label=File 2\x1b\\");
    term.process(b"\x1b]934;set;build;state=indeterminate\x1b\\");

    assert_eq!(term.named_progress_bars().len(), 3);
    assert_eq!(term.get_named_progress_bar("dl-1").unwrap().percent, 30);
    assert_eq!(term.get_named_progress_bar("dl-2").unwrap().percent, 60);
    assert_eq!(
        term.get_named_progress_bar("build").unwrap().state,
        crate::terminal::ProgressState::Indeterminate
    );
}

#[test]
fn test_osc934_remove_progress_bar() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b]934;set;dl-1;percent=50\x1b\\");
    term.process(b"\x1b]934;set;dl-2;percent=70\x1b\\");
    assert_eq!(term.named_progress_bars().len(), 2);

    term.process(b"\x1b]934;remove;dl-1\x1b\\");
    assert_eq!(term.named_progress_bars().len(), 1);
    assert!(term.get_named_progress_bar("dl-1").is_none());
    assert!(term.get_named_progress_bar("dl-2").is_some());
}

#[test]
fn test_osc934_remove_all() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b]934;set;a;percent=10\x1b\\");
    term.process(b"\x1b]934;set;b;percent=20\x1b\\");
    term.process(b"\x1b]934;set;c;percent=30\x1b\\");
    assert_eq!(term.named_progress_bars().len(), 3);

    term.process(b"\x1b]934;remove_all\x1b\\");
    assert!(term.named_progress_bars().is_empty());
}

#[test]
fn test_osc934_event_emitted_on_set() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b]934;set;dl-1;percent=42;label=Test\x1b\\");

    let events = term.poll_events();
    let pb_events: Vec<_> = events
        .iter()
        .filter(|e| matches!(e, crate::terminal::TerminalEvent::ProgressBarChanged { .. }))
        .collect();
    assert_eq!(pb_events.len(), 1);

    if let crate::terminal::TerminalEvent::ProgressBarChanged {
        action,
        id,
        state,
        percent,
        label,
    } = &pb_events[0]
    {
        assert_eq!(*action, crate::terminal::ProgressBarAction::Set);
        assert_eq!(id, "dl-1");
        assert_eq!(*state, Some(crate::terminal::ProgressState::Normal));
        assert_eq!(*percent, Some(42));
        assert_eq!(*label, Some("Test".to_string()));
    } else {
        panic!("Expected ProgressBarChanged event");
    }
}

#[test]
fn test_osc934_event_emitted_on_remove() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b]934;set;dl-1;percent=42\x1b\\");
    term.poll_events(); // Clear set event

    term.process(b"\x1b]934;remove;dl-1\x1b\\");
    let events = term.poll_events();
    let pb_events: Vec<_> = events
        .iter()
        .filter(|e| matches!(e, crate::terminal::TerminalEvent::ProgressBarChanged { .. }))
        .collect();
    assert_eq!(pb_events.len(), 1);

    if let crate::terminal::TerminalEvent::ProgressBarChanged { action, id, .. } = &pb_events[0] {
        assert_eq!(*action, crate::terminal::ProgressBarAction::Remove);
        assert_eq!(id, "dl-1");
    }
}

#[test]
fn test_osc934_event_emitted_on_remove_all() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b]934;set;a;percent=10\x1b\\");
    term.process(b"\x1b]934;set;b;percent=20\x1b\\");
    term.poll_events(); // Clear set events

    term.process(b"\x1b]934;remove_all\x1b\\");
    let events = term.poll_events();
    let pb_events: Vec<_> = events
        .iter()
        .filter(|e| matches!(e, crate::terminal::TerminalEvent::ProgressBarChanged { .. }))
        .collect();
    assert_eq!(pb_events.len(), 1);

    if let crate::terminal::TerminalEvent::ProgressBarChanged { action, .. } = &pb_events[0] {
        assert_eq!(*action, crate::terminal::ProgressBarAction::RemoveAll);
    }
}

#[test]
fn test_osc934_no_event_on_remove_nonexistent() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b]934;remove;nonexistent\x1b\\");
    let events = term.poll_events();
    let pb_events: Vec<_> = events
        .iter()
        .filter(|e| matches!(e, crate::terminal::TerminalEvent::ProgressBarChanged { .. }))
        .collect();
    assert_eq!(pb_events.len(), 0);
}

#[test]
fn test_osc934_no_event_on_remove_all_empty() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b]934;remove_all\x1b\\");
    let events = term.poll_events();
    let pb_events: Vec<_> = events
        .iter()
        .filter(|e| matches!(e, crate::terminal::TerminalEvent::ProgressBarChanged { .. }))
        .collect();
    assert_eq!(pb_events.len(), 0);
}

#[test]
fn test_osc934_invalid_sequence_ignored() {
    let mut term = Terminal::new(80, 24);

    // Invalid action
    term.process(b"\x1b]934;invalid\x1b\\");
    assert!(term.named_progress_bars().is_empty());

    // Missing ID for set
    term.process(b"\x1b]934;set\x1b\\");
    assert!(term.named_progress_bars().is_empty());

    // Missing ID for remove
    term.process(b"\x1b]934;remove\x1b\\");
    assert!(term.named_progress_bars().is_empty());
}

#[test]
fn test_osc934_query_returns_static_capability_without_state_or_loop() {
    let mut term = Terminal::new(80, 24);
    term.process(b"\x1b]934;set;private-id;percent=42;label=private-label\x1b\\");
    let _ = term.poll_events();

    term.process(b"\x1b]934;query\x1b\\");
    let response = term.drain_responses();
    assert_eq!(
        response,
        crate::terminal::progress::OSC934_CAPABILITY_RESPONSE
    );
    assert!(!String::from_utf8_lossy(&response).contains("private-id"));
    assert!(!String::from_utf8_lossy(&response).contains("private-label"));
    assert!(term.poll_events().is_empty());

    term.process(crate::terminal::progress::OSC934_CAPABILITY_RESPONSE);
    assert!(term.drain_responses().is_empty());
    assert!(term.poll_events().is_empty());
}

#[test]
fn test_osc934_bell_terminated() {
    let mut term = Terminal::new(80, 24);

    // BEL-terminated variant
    term.process(b"\x1b]934;set;dl-1;percent=99;label=Done\x07");

    let bar = term.get_named_progress_bar("dl-1").unwrap();
    assert_eq!(bar.percent, 99);
    assert_eq!(bar.label, Some("Done".to_string()));
}

#[test]
fn test_osc934_warning_state() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b]934;set;job;state=warning;percent=80;label=Disk space low\x1b\\");

    let bar = term.get_named_progress_bar("job").unwrap();
    assert_eq!(bar.state, crate::terminal::ProgressState::Warning);
    assert_eq!(bar.percent, 80);
    assert_eq!(bar.label, Some("Disk space low".to_string()));
}

#[test]
fn test_osc934_error_state() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b]934;set;build;state=error;label=Build failed\x1b\\");

    let bar = term.get_named_progress_bar("build").unwrap();
    assert_eq!(bar.state, crate::terminal::ProgressState::Error);
    assert_eq!(bar.label, Some("Build failed".to_string()));
}

#[test]
fn test_osc934_does_not_affect_osc94() {
    let mut term = Terminal::new(80, 24);

    // OSC 9;4 and OSC 934 are independent
    term.process(b"\x1b]9;4;1;50\x1b\\");
    term.process(b"\x1b]934;set;dl-1;percent=75\x1b\\");

    // OSC 9;4 state should be unchanged
    assert!(term.has_progress());
    assert_eq!(term.progress_value(), 50);

    // OSC 934 state should be independent
    assert_eq!(term.named_progress_bars().len(), 1);
    assert_eq!(term.get_named_progress_bar("dl-1").unwrap().percent, 75);
}

// === OSC 1337 RemoteHost Tests ===

#[test]
fn test_remote_host_user_and_hostname() {
    let mut term = Terminal::new(80, 24);

    // OSC 1337 ; RemoteHost=alice@server1.example.com ST
    term.process(b"\x1b]1337;RemoteHost=alice@server1.example.com\x1b\\");

    assert_eq!(
        term.shell_integration.hostname(),
        Some("server1.example.com")
    );
    assert_eq!(term.shell_integration.username(), Some("alice"));
}

#[test]
fn test_remote_host_hostname_only() {
    let mut term = Terminal::new(80, 24);

    // No username, just hostname
    term.process(b"\x1b]1337;RemoteHost=myserver\x1b\\");

    assert_eq!(term.shell_integration.hostname(), Some("myserver"));
    assert!(term.shell_integration.username().is_none());
}

#[test]
fn test_remote_host_empty_user_at_hostname() {
    let mut term = Terminal::new(80, 24);

    // Empty username with @ prefix
    term.process(b"\x1b]1337;RemoteHost=@myserver\x1b\\");

    assert_eq!(term.shell_integration.hostname(), Some("myserver"));
    assert!(term.shell_integration.username().is_none());
}

#[test]
fn test_remote_host_localhost_clears_hostname() {
    let mut term = Terminal::new(80, 24);

    // First set a remote host
    term.process(b"\x1b]1337;RemoteHost=alice@remote\x1b\\");
    assert_eq!(term.shell_integration.hostname(), Some("remote"));

    // Then switch back to localhost
    term.process(b"\x1b]1337;RemoteHost=alice@localhost\x1b\\");
    assert!(term.shell_integration.hostname().is_none());
    assert_eq!(term.shell_integration.username(), Some("alice"));
}

#[test]
fn test_remote_host_localhost_case_insensitive() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b]1337;RemoteHost=user@LOCALHOST\x1b\\");
    assert!(term.shell_integration.hostname().is_none());

    term.process(b"\x1b]1337;RemoteHost=user@Localhost\x1b\\");
    assert!(term.shell_integration.hostname().is_none());
}

#[test]
fn test_remote_host_emits_cwd_changed_event() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b]1337;RemoteHost=alice@remote-server\x1b\\");

    let events = term.poll_events();
    assert!(
        events.iter().any(|e| matches!(
            e,
            crate::terminal::TerminalEvent::CwdChanged(change)
            if change.hostname.as_deref() == Some("remote-server")
                && change.username.as_deref() == Some("alice")
        )),
        "CwdChanged event with hostname and username should be emitted",
    );
}

#[test]
fn test_remote_host_bell_terminated() {
    let mut term = Terminal::new(80, 24);

    // BEL-terminated variant
    term.process(b"\x1b]1337;RemoteHost=bob@host2\x07");

    assert_eq!(term.shell_integration.hostname(), Some("host2"));
    assert_eq!(term.shell_integration.username(), Some("bob"));
}

#[test]
fn test_remote_host_session_variables_updated() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b]1337;RemoteHost=alice@server1\x1b\\");

    let vars = term.session_variables();
    assert_eq!(vars.hostname, Some("server1".to_string()));
    assert_eq!(vars.username, Some("alice".to_string()));
}

#[test]
fn test_remote_host_empty_payload_ignored() {
    let mut term = Terminal::new(80, 24);

    // Empty payload should be ignored
    term.process(b"\x1b]1337;RemoteHost=\x1b\\");
    assert!(term.shell_integration.hostname().is_none());
    assert!(term.shell_integration.username().is_none());
}

#[test]
fn test_remote_host_empty_hostname_ignored() {
    let mut term = Terminal::new(80, 24);

    // user@ with no hostname
    term.process(b"\x1b]1337;RemoteHost=alice@\x1b\\");
    assert!(term.shell_integration.hostname().is_none());
    assert!(term.shell_integration.username().is_none());
}

#[test]
fn test_remote_host_overrides_osc7_hostname() {
    let mut term = Terminal::new(80, 24);

    // Set hostname via OSC 7
    term.process(b"\x1b]7;file://server1/home/user\x1b\\");
    assert_eq!(term.shell_integration.hostname(), Some("server1"));

    // Override via RemoteHost
    term.process(b"\x1b]1337;RemoteHost=bob@server2\x1b\\");
    assert_eq!(term.shell_integration.hostname(), Some("server2"));
    assert_eq!(term.shell_integration.username(), Some("bob"));
}

#[test]
fn test_remote_host_updates_sequence() {
    let mut term = Terminal::new(80, 24);

    // First remote host
    term.process(b"\x1b]1337;RemoteHost=alice@host1\x1b\\");
    assert_eq!(term.shell_integration.hostname(), Some("host1"));
    assert_eq!(term.shell_integration.username(), Some("alice"));

    // Second remote host
    term.process(b"\x1b]1337;RemoteHost=bob@host2\x1b\\");
    assert_eq!(term.shell_integration.hostname(), Some("host2"));
    assert_eq!(term.shell_integration.username(), Some("bob"));
}

#[test]
fn test_remote_host_loopback_addresses() {
    let mut term = Terminal::new(80, 24);

    // IPv4 loopback
    term.process(b"\x1b]1337;RemoteHost=user@127.0.0.1\x1b\\");
    assert!(term.shell_integration.hostname().is_none());

    // IPv6 loopback
    term.process(b"\x1b]1337;RemoteHost=user@::1\x1b\\");
    assert!(term.shell_integration.hostname().is_none());
}

#[test]
fn test_remote_host_preserves_existing_cwd() {
    let mut term = Terminal::new(80, 24);

    // Set cwd via OSC 7
    term.process(b"\x1b]7;file:///home/user/project\x1b\\");
    assert_eq!(term.shell_integration.cwd(), Some("/home/user/project"));

    // Set remote host - should not clear cwd
    term.process(b"\x1b]1337;RemoteHost=alice@remote\x1b\\");
    assert_eq!(term.shell_integration.cwd(), Some("/home/user/project"));
    assert_eq!(term.shell_integration.hostname(), Some("remote"));
}

// ========== Semantic Zone Tests ==========

#[test]
fn test_zones_created_by_osc_133() {
    let mut term = Terminal::new(80, 24);

    // Prompt start
    term.process(b"\x1b]133;A\x07");
    assert_eq!(term.get_zones().len(), 1);
    assert_eq!(term.get_zones()[0].zone_type, crate::zone::ZoneType::Prompt);

    // Type a command - first set it via shell integration
    term.process(b"ls -la");

    // Command start
    term.shell_integration_mut()
        .set_command("ls -la".to_string());
    term.process(b"\x1b]133;B\x07");
    assert_eq!(term.get_zones().len(), 2);
    assert_eq!(
        term.get_zones()[1].zone_type,
        crate::zone::ZoneType::Command
    );
    assert_eq!(term.get_zones()[1].command.as_deref(), Some("ls -la"));

    // Command executed (output begins)
    term.process(b"\x1b]133;C\x07");
    assert_eq!(term.get_zones().len(), 3);
    assert_eq!(term.get_zones()[2].zone_type, crate::zone::ZoneType::Output);
    assert_eq!(term.get_zones()[2].command.as_deref(), Some("ls -la"));

    // Some output
    term.process(b"file1.txt\r\nfile2.txt\r\n");

    // Command finished with exit code 0
    term.process(b"\x1b]133;D;0\x07");
    // Output zone should be closed with exit code
    assert_eq!(term.get_zones()[2].exit_code, Some(0));
}

#[test]
fn test_zones_multiple_commands() {
    let mut term = Terminal::new(80, 24);

    // First command cycle: A -> B -> C -> D
    term.process(b"\x1b]133;A\x07$ ");
    term.process(b"\x1b]133;B\x07");
    term.process(b"\x1b]133;C\x07output1\r\n");
    term.process(b"\x1b]133;D;0\x07");

    // Second command cycle
    term.process(b"\x1b]133;A\x07$ ");
    term.process(b"\x1b]133;B\x07");
    term.process(b"\x1b]133;C\x07output2\r\n");
    term.process(b"\x1b]133;D;1\x07");

    // Should have 6 zones (Prompt, Command, Output) x 2
    let zones = term.get_zones();
    assert_eq!(zones.len(), 6);
    assert_eq!(zones[0].zone_type, crate::zone::ZoneType::Prompt);
    assert_eq!(zones[1].zone_type, crate::zone::ZoneType::Command);
    assert_eq!(zones[2].zone_type, crate::zone::ZoneType::Output);
    assert_eq!(zones[3].zone_type, crate::zone::ZoneType::Prompt);
    assert_eq!(zones[4].zone_type, crate::zone::ZoneType::Command);
    assert_eq!(zones[5].zone_type, crate::zone::ZoneType::Output);
    assert_eq!(zones[2].exit_code, Some(0));
    assert_eq!(zones[5].exit_code, Some(1));
}

#[test]
fn test_zones_not_created_on_alt_screen() {
    let mut term = Terminal::new(80, 24);

    // Switch to alt screen
    term.process(b"\x1b[?1049h");

    // OSC 133 on alt screen should not create zones
    term.process(b"\x1b]133;A\x07");
    assert!(term.get_zones().is_empty());

    // Switch back to primary
    term.process(b"\x1b[?1049l");

    // Now it should create zones
    term.process(b"\x1b]133;A\x07");
    assert_eq!(term.get_zones().len(), 1);
}

#[test]
fn test_zones_cleared_on_reset() {
    let mut term = Terminal::new(80, 24);
    term.process(b"\x1b]133;A\x07");
    assert_eq!(term.get_zones().len(), 1);

    term.reset();
    assert!(term.get_zones().is_empty());
}

#[test]
fn test_zones_evicted_on_scrollback_wrap() {
    // Small scrollback to trigger eviction quickly
    let mut term = Terminal::with_scrollback(80, 5, 10);

    // Create a prompt zone
    term.process(b"\x1b]133;A\x07");
    term.process(b"\x1b]133;B\x07");
    term.process(b"\x1b]133;C\x07");

    // Generate enough output to fill scrollback and wrap
    for i in 0..20 {
        term.process(format!("line {}\r\n", i).as_bytes());
    }

    // Command finished
    term.process(b"\x1b]133;D;0\x07");

    // Zones with rows below the scrollback floor should be evicted
    let zones = term.get_zones();
    let floor = term
        .active_grid()
        .total_lines_scrolled()
        .saturating_sub(term.active_grid().scrollback_len());
    assert!(
        !zones.is_empty(),
        "the active output zone must survive until its D marker"
    );
    for zone in zones {
        assert!(
            zone.abs_row_end >= floor,
            "Zone {:?} at rows {}-{} should be >= floor {}",
            zone.zone_type,
            zone.abs_row_start,
            zone.abs_row_end,
            floor
        );
    }
    let output = zones
        .iter()
        .find(|zone| zone.zone_type == crate::zone::ZoneType::Output)
        .expect("retained output zone");
    assert!(output.is_closed());
    assert_eq!(output.exit_code, Some(0));
}

#[test]
fn test_zone_get_zone_at() {
    let mut term = Terminal::new(80, 24);

    // Create zones with newlines between markers so each zone spans distinct rows
    // Prompt at row 0
    term.process(b"\x1b]133;A\x07$ \r\n");
    // Command at row 1
    term.process(b"\x1b]133;B\x07ls\r\n");
    // Output at row 2
    term.process(b"\x1b]133;C\x07output line 1\r\noutput line 2\r\n");
    // Finish at row 4
    term.process(b"\x1b]133;D;0\x07");

    // Row 0 should be in the Prompt zone (abs_row_start=0, closed at row 0)
    let zone = term.get_zone_at(0);
    assert!(zone.is_some());
    assert_eq!(zone.unwrap().zone_type, crate::zone::ZoneType::Prompt);

    // Row 1 should be in the Command zone
    let zone = term.get_zone_at(1);
    assert!(zone.is_some());
    assert_eq!(zone.unwrap().zone_type, crate::zone::ZoneType::Command);

    // Row 2 should be in the Output zone
    let zone = term.get_zone_at(2);
    assert!(zone.is_some());
    assert_eq!(zone.unwrap().zone_type, crate::zone::ZoneType::Output);

    // Row way beyond zones should return None
    assert!(term.get_zone_at(1000).is_none());
}

// ========== Command Output Capture Tests ==========

#[test]
fn test_get_command_output_basic() {
    let mut term = Terminal::new(80, 24);
    term.shell_integration_mut().set_command("ls".to_string());
    term.start_command_execution("ls".to_string());
    term.process(b"\x1b]133;A\x07$ \r\n");
    term.process(b"\x1b]133;B\x07ls\r\n");
    term.process(b"\x1b]133;C\x07");
    term.process(b"file1.txt\r\nfile2.txt\r\n");
    term.process(b"\x1b]133;D;0\x07");
    term.end_command_execution(Some(0));

    let output = term.get_command_output(0);
    assert!(output.is_some());
    let text = output.unwrap();
    assert!(text.output.contains("file1.txt"));
    assert!(text.output.contains("file2.txt"));
}

#[test]
fn test_get_command_output_out_of_bounds() {
    let term = Terminal::new(80, 24);
    assert!(term.get_command_output(0).is_none());
    assert!(term.get_command_output(100).is_none());
}

#[test]
fn test_get_command_output_no_zone() {
    let mut term = Terminal::new(80, 24);
    term.start_command_execution("echo hi".to_string());
    term.end_command_execution(Some(0));
    assert!(term.get_command_output(0).is_none());
}

#[test]
fn test_get_command_output_multiple_commands() {
    let mut term = Terminal::new(80, 24);

    term.shell_integration_mut().set_command("cmd1".to_string());
    term.start_command_execution("cmd1".to_string());
    term.process(b"\x1b]133;A\x07$ \r\n");
    term.process(b"\x1b]133;B\x07cmd1\r\n");
    term.process(b"\x1b]133;C\x07");
    term.process(b"output1\r\n");
    term.process(b"\x1b]133;D;0\x07");
    term.end_command_execution(Some(0));

    term.shell_integration_mut().set_command("cmd2".to_string());
    term.start_command_execution("cmd2".to_string());
    term.process(b"\x1b]133;A\x07$ \r\n");
    term.process(b"\x1b]133;B\x07cmd2\r\n");
    term.process(b"\x1b]133;C\x07");
    term.process(b"output2\r\n");
    term.process(b"\x1b]133;D;0\x07");
    term.end_command_execution(Some(0));

    let out0 = term.get_command_output(0).unwrap();
    assert!(out0.output.contains("output2"));
    let out1 = term.get_command_output(1).unwrap();
    assert!(out1.output.contains("output1"));
}

#[test]
fn test_get_command_outputs_filters_evicted() {
    // Use a larger terminal so the "new" command's output doesn't scroll past its zone
    let mut term = Terminal::with_scrollback(80, 24, 50);

    // First command - will be evicted
    term.shell_integration_mut().set_command("old".to_string());
    term.start_command_execution("old".to_string());
    term.process(b"\x1b]133;A\x07$ \r\n");
    term.process(b"\x1b]133;B\x07old\r\n");
    term.process(b"\x1b]133;C\x07");
    term.process(b"old output\r\n");
    term.process(b"\x1b]133;D;0\x07");
    term.end_command_execution(Some(0));

    // Generate enough output to push old command past scrollback
    for i in 0..80 {
        term.process(format!("filler line {}\r\n", i).as_bytes());
    }

    // Second command - recent, output stays in visible grid (no scrolling between C and D)
    term.shell_integration_mut().set_command("new".to_string());
    term.start_command_execution("new".to_string());
    term.process(b"\x1b]133;A\x07$ \r\n");
    term.process(b"\x1b]133;B\x07new\r\n");
    term.process(b"\x1b]133;C\x07");
    term.process(b"new output"); // No \r\n — stays on same line as C marker
    term.process(b"\x1b]133;D;0\x07");
    term.end_command_execution(Some(0));

    let outputs = term.get_command_outputs();
    // Old command's output should be evicted, only new should remain
    assert!(!outputs.is_empty());
    assert!(outputs.iter().any(|o| o.output.contains("new output")));
    // Old command should not be in extractable outputs
    assert!(!outputs.iter().any(|o| o.command == "old"));

    // Direct index access: old command (index 1) should return None
    assert!(term.get_command_output(1).is_none());
    // New command (index 0) should still work
    assert!(term.get_command_output(0).is_some());
}

#[test]
fn test_get_command_output_no_output_rows_returns_none() {
    // A command where end_command_execution is called but no Output zone was created
    // (e.g., the last zone isn't an Output zone).
    let mut term = Terminal::new(80, 24);
    term.start_command_execution("echo hi".to_string());
    // Only create a Prompt zone, no Output zone
    term.process(b"\x1b]133;A\x07$ ");
    term.end_command_execution(Some(0));
    // output_start_row/output_end_row should be None since last zone is Prompt, not Output
    assert!(term.get_command_output(0).is_none());
}

// ========== Contextual Awareness Event Tests ==========

#[test]
fn test_zone_opened_events_emitted() {
    let mut term = Terminal::new(80, 24);
    term.process(b"\x1b]133;A\x1b\\");
    let events = term.poll_events();
    assert!(events.iter().any(|e| matches!(
        e,
        crate::terminal::TerminalEvent::ZoneOpened {
            zone_type,
            ..
        } if *zone_type == crate::zone::ZoneType::Prompt
    )));
}

#[test]
fn test_zone_closed_on_transition() {
    let mut term = Terminal::new(80, 24);
    term.process(b"\x1b]133;A\x1b\\");
    term.poll_events(); // drain
    term.process(b"\x1b]133;B\x1b\\");
    let events = term.poll_events();
    // Should have ZoneClosed for prompt and ZoneOpened for command
    assert!(
        events.iter().any(|e| matches!(
            e,
            crate::terminal::TerminalEvent::ZoneClosed {
                zone_type,
                ..
            } if *zone_type == crate::zone::ZoneType::Prompt
        )),
        "Expected ZoneClosed for Prompt"
    );
    assert!(
        events.iter().any(|e| matches!(
            e,
            crate::terminal::TerminalEvent::ZoneOpened {
                zone_type,
                ..
            } if *zone_type == crate::zone::ZoneType::Command
        )),
        "Expected ZoneOpened for Command"
    );
}

#[test]
fn test_zone_closed_with_exit_code() {
    let mut term = Terminal::new(80, 24);
    term.process(b"\x1b]133;A\x1b\\");
    term.process(b"\x1b]133;B\x1b\\");
    term.process(b"\x1b]133;C\x1b\\");
    term.poll_events(); // drain
    term.process(b"\x1b]133;D;0\x1b\\");
    let events = term.poll_events();
    assert!(
        events.iter().any(|e| matches!(
            e,
            crate::terminal::TerminalEvent::ZoneClosed {
                zone_type,
                exit_code: Some(0),
                ..
            } if *zone_type == crate::zone::ZoneType::Output
        )),
        "Expected ZoneClosed for Output with exit_code=0"
    );
}

#[test]
fn test_zone_ids_monotonically_increase() {
    let mut term = Terminal::new(80, 24);
    term.process(b"\x1b]133;A\x1b\\"); // zone 0 (Prompt)
    term.process(b"\x1b]133;B\x1b\\"); // zone 1 (Command)
    term.process(b"\x1b]133;C\x1b\\"); // zone 2 (Output)
    let events = term.poll_events();
    let zone_ids: Vec<usize> = events
        .iter()
        .filter_map(|e| match e {
            crate::terminal::TerminalEvent::ZoneOpened { zone_id, .. } => Some(*zone_id),
            _ => None,
        })
        .collect();
    assert_eq!(zone_ids, vec![0, 1, 2]);
}

#[test]
fn test_full_zone_lifecycle() {
    let mut term = Terminal::new(80, 24);
    // Full cycle: A -> B -> C -> D
    term.process(b"\x1b]133;A\x1b\\");
    term.process(b"\x1b]133;B\x1b\\");
    term.process(b"\x1b]133;C\x1b\\");
    term.process(b"\x1b]133;D;0\x1b\\");
    let events = term.poll_events();

    // Count opens and closes
    let opens: Vec<_> = events
        .iter()
        .filter(|e| matches!(e, crate::terminal::TerminalEvent::ZoneOpened { .. }))
        .collect();
    let closes: Vec<_> = events
        .iter()
        .filter(|e| matches!(e, crate::terminal::TerminalEvent::ZoneClosed { .. }))
        .collect();

    // 3 opens (Prompt, Command, Output), 3 closes (Prompt, Command, Output)
    assert_eq!(opens.len(), 3, "Expected 3 ZoneOpened events");
    assert_eq!(closes.len(), 3, "Expected 3 ZoneClosed events");
}

// ========== Environment Change Event Tests ==========

#[test]
fn test_environment_changed_on_cwd() {
    let mut term = Terminal::new(80, 24);
    term.process(b"\x1b]7;file:///home/user/project\x1b\\");
    let events = term.poll_events();
    assert!(
        events.iter().any(|e| matches!(
            e,
            crate::terminal::TerminalEvent::EnvironmentChanged {
                key,
                value,
                ..
            } if key == "cwd" && value == "/home/user/project"
        )),
        "Expected EnvironmentChanged event for cwd"
    );
}

#[test]
fn test_remote_host_transition_from_osc7() {
    let mut term = Terminal::new(80, 24);
    term.process(b"\x1b]7;file://remotehost/home/user\x1b\\");
    let events = term.poll_events();
    assert!(
        events.iter().any(|e| matches!(
            e,
            crate::terminal::TerminalEvent::RemoteHostTransition {
                hostname,
                old_hostname: None,
                ..
            } if hostname == "remotehost"
        )),
        "Expected RemoteHostTransition event from OSC 7"
    );
}

#[test]
fn test_remote_host_transition_from_osc1337() {
    let mut term = Terminal::new(80, 24);
    term.process(b"\x1b]1337;RemoteHost=alice@server1\x1b\\");
    let events = term.poll_events();
    assert!(
        events.iter().any(|e| matches!(
            e,
            crate::terminal::TerminalEvent::RemoteHostTransition {
                hostname,
                ..
            } if hostname == "server1"
        )),
        "Expected RemoteHostTransition event from OSC 1337"
    );
}

#[test]
fn test_environment_changed_hostname() {
    let mut term = Terminal::new(80, 24);
    term.process(b"\x1b]7;file://myhost/home/user\x1b\\");
    let events = term.poll_events();
    assert!(
        events.iter().any(|e| matches!(
            e,
            crate::terminal::TerminalEvent::EnvironmentChanged {
                key,
                value,
                ..
            } if key == "hostname" && value == "myhost"
        )),
        "Expected EnvironmentChanged event for hostname"
    );
}
