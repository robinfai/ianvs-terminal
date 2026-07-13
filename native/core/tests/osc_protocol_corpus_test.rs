use par_term_emu_core_rust::color::Color;
use par_term_emu_core_rust::terminal::{
    DragDropAction, OscCapability, Terminal, TerminalContextAction, TerminalEvent,
};
use serde_json::Value;

const CORPUS: &str = include_str!("fixtures/osc/osc_protocol_corpus_v1.json");

fn decode_hex(encoded: &str) -> Vec<u8> {
    assert!(!encoded.is_empty());
    assert_eq!(encoded.len() % 2, 0);
    (0..encoded.len())
        .step_by(2)
        .map(|index| u8::from_str_radix(&encoded[index..index + 2], 16).unwrap())
        .collect()
}

fn wire_chunks(case: &Value) -> Vec<Vec<u8>> {
    let wire = &case["wire"];
    if let Some(chunks) = wire["chunks_hex"].as_array() {
        return chunks
            .iter()
            .map(|chunk| decode_hex(chunk.as_str().unwrap()))
            .collect();
    }

    let mut generated = decode_hex(wire["prefix_hex"].as_str().unwrap());
    let repeated = decode_hex(wire["repeat_hex"].as_str().unwrap());
    assert_eq!(repeated.len(), 1);
    generated.extend(std::iter::repeat_n(
        repeated[0],
        wire["repeat_count"].as_u64().unwrap() as usize,
    ));
    generated.extend(decode_hex(wire["suffix_hex"].as_str().unwrap()));
    vec![generated]
}

fn write_hyperlink_probe(terminal: &mut Terminal) -> Option<(String, Option<String>)> {
    terminal.process(b"X");
    let hyperlink_id = terminal.active_grid().row(0).unwrap()[0]
        .flags
        .hyperlink_id?;
    Some((
        terminal.get_hyperlink_url(hyperlink_id).unwrap(),
        terminal.get_hyperlink_protocol_id(hyperlink_id),
    ))
}

#[test]
fn shared_osc_corpus_executes_against_the_native_streaming_parser() {
    let corpus: Value = serde_json::from_str(CORPUS).unwrap();
    assert_eq!(corpus["schema_version"], "ianvs-osc-corpus-v1");

    for case in corpus["cases"].as_array().unwrap() {
        let id = case["id"].as_str().unwrap();
        let mut terminal = Terminal::new(80, 4);
        if id == "malformed_base64" {
            terminal.process(b"\x1b]52;c;c2VudGluZWw=\x1b\\");
            assert_eq!(terminal.clipboard(), Some("sentinel"));
        }
        if id == "osc72_drop_target_negotiation" {
            terminal.set_osc_capability_allowed(OscCapability::DragDrop, true);
        }

        for chunk in wire_chunks(case) {
            terminal.process(&chunk);
        }

        match id {
            "bel_terminator" => assert_eq!(
                write_hyperlink_probe(&mut terminal),
                Some((
                    "https://example.test/bel".to_string(),
                    Some("bel".to_string()),
                )),
            ),
            "st_terminator" => assert_eq!(
                write_hyperlink_probe(&mut terminal),
                Some((
                    "https://example.test/st".to_string(),
                    Some("st".to_string()),
                )),
            ),
            "split_escape_introducer" => assert_eq!(terminal.title(), "split-introducer"),
            "split_st_terminator" => assert_eq!(terminal.title(), "split-terminator"),
            "split_utf8_scalar" => assert_eq!(terminal.title(), "utf8-你好"),
            "empty_parameter" => assert_eq!(
                write_hyperlink_probe(&mut terminal),
                Some(("https://example.test/empty".to_string(), None)),
            ),
            "missing_parameter" => {
                assert_eq!(write_hyperlink_probe(&mut terminal), None);
            }
            "duplicate_parameter" => assert_eq!(
                write_hyperlink_probe(&mut terminal),
                Some((
                    "https://example.test/duplicate".to_string(),
                    Some("first".to_string()),
                )),
            ),
            "oversized_payload" => assert_eq!(terminal.title(), ""),
            "malformed_base64" => assert_eq!(terminal.clipboard(), Some("sentinel")),
            "malformed_percent_encoding" => assert!(
                terminal
                    .current_directory()
                    .is_none_or(|cwd| !cwd.contains('%')),
                "{id}: malformed percent escape reached cwd state: {:?}",
                terminal.current_directory(),
            ),
            "unknown_key" => assert_eq!(
                write_hyperlink_probe(&mut terminal),
                Some((
                    "https://example.test/unknown".to_string(),
                    Some("known".to_string()),
                )),
            ),
            "mixed_supported_unsupported" => {
                assert_eq!(terminal.title(), "supported-title");
                assert_eq!(
                    write_hyperlink_probe(&mut terminal),
                    Some((
                        "https://example.test/mixed".to_string(),
                        Some("mixed".to_string()),
                    )),
                );
            }
            "osc99_chunked_base64" => {
                let notification = terminal.take_notifications().pop().unwrap();
                assert_eq!(notification.source, "osc99");
                assert_eq!(notification.identifier.as_deref(), Some("corpus"));
                assert_eq!(notification.title, "Title");
                assert_eq!(notification.message, "Body");
            }
            "osc21_batch_and_osc23_noop" => {
                assert_eq!(terminal.title(), "stable-title");
                assert_eq!(terminal.default_fg(), Color::Rgb(0x12, 0x34, 0x56));
                assert_eq!(
                    terminal.get_ansi_color(196),
                    Some(Color::Rgb(0xab, 0xcd, 0xef))
                );
                assert_eq!(terminal.drain_responses(), b"\x1b]21;future=?\x1b\\");
            }
            "xterm_special_dynamic_colors" => {
                assert_eq!(
                    terminal.xterm_special_color(0),
                    Some(Color::Named(
                        par_term_emu_core_rust::color::NamedColor::White
                    ))
                );
                assert_eq!(terminal.xterm_special_color_mode(0), Some(false));
                assert_eq!(
                    terminal.get_selection_bg_color(),
                    Color::Rgb(0x11, 0x22, 0x33)
                );
                assert_eq!(terminal.get_selection_fg_color(), Color::Rgb(0, 0, 0));
                assert!(!terminal.selection_foreground_color_enabled());
                assert_eq!(
                    terminal.drain_responses(),
                    b"\x1b]5;0;rgb:ffff/0000/ffff\x1b\\\x1b]17;rgb:1111/2222/3333\x1b\\\x1b]18;rgb:1818/1818/1818\x1b\\\x1b]19;rgb:dddd/eeee/ffff\x1b\\"
                );
            }
            "iterm_color_extensions" => {
                assert_eq!(terminal.default_fg(), Color::Rgb(0x11, 0x22, 0x33));
                assert_eq!(terminal.default_bg(), Color::Rgb(0x80, 0x80, 0x80));
                assert_eq!(
                    terminal.iterm_bold_color(),
                    Some(Color::Rgb(0xff, 0x00, 0xff))
                );
                assert_eq!(
                    terminal.iterm_underline_color(),
                    Some(Color::Rgb(0x00, 0xff, 0x00))
                );
                assert_eq!(
                    terminal.iterm_link_color(),
                    Some(Color::Rgb(0x00, 0xff, 0xff))
                );
                assert_eq!(terminal.cursor_color(), Color::Rgb(0xff, 0xff, 0x00));
                assert_eq!(
                    terminal.iterm_cursor_text_color(),
                    Some(Color::Rgb(0x00, 0x00, 0xff))
                );
                assert_eq!(terminal.iterm_tab_color(), None);
                assert_eq!(
                    terminal.get_ansi_color(1),
                    Some(Color::Rgb(0xaa, 0xbb, 0xcc))
                );
                assert_eq!(
                    terminal.drain_responses(),
                    b"\x1b]4;-2;rgb:8080/8080/8080\x1b\\\x1b]4;-1;rgb:1111/2222/3333\x1b\\"
                );
            }
            "osc1337_annotations" => {
                let annotations = terminal
                    .poll_events()
                    .into_iter()
                    .filter_map(|event| match event {
                        TerminalEvent::ItermAnnotation {
                            message,
                            visible,
                            start_col,
                            end_col,
                            ..
                        } => Some((message, visible, start_col, end_col)),
                        _ => None,
                    })
                    .collect::<Vec<_>>();
                assert_eq!(
                    annotations,
                    vec![
                        ("Visible note".to_string(), true, 7, 11),
                        ("Hidden note".to_string(), false, 0, 6),
                    ]
                );
                assert_eq!(terminal.title(), "osc1337-annotation-corpus-ok");
            }
            "osc22_pointer_shape_stack" => {
                assert_eq!(terminal.pointer_shape_name(), Some("crosshair"));
                assert_eq!(
                    terminal.drain_responses(),
                    b"\x1b]22;crosshair,text,default,1,0\x1b\\\x1b]22;help\x1b\\\x1b]22;crosshair\x1b\\"
                );
            }
            "osc66_sized_text_edit_recovery" => {
                let anchor = terminal.grid().get(1, 0).expect("OSC 66 anchor");
                assert_eq!(anchor.get_grapheme(), "Z");
                let metadata = anchor.multicell.expect("OSC 66 metadata");
                assert_eq!(metadata.scale, 2);
                assert_eq!(metadata.width, 1);
                assert!(metadata.natural_width);
                assert_eq!(terminal.grid().get(4, 1).unwrap().get_grapheme(), "x");
            }
            "osc3008_malformed_close_recovery" => {
                let contexts = terminal
                    .poll_events()
                    .into_iter()
                    .filter_map(|event| match event {
                        TerminalEvent::TerminalContextChanged(event) => Some(event),
                        _ => None,
                    })
                    .collect::<Vec<_>>();
                assert_eq!(contexts.len(), 3, "unknown end must be ignored");
                assert_eq!(contexts[0].action, TerminalContextAction::Start);
                assert_eq!(contexts[0].metadata.user.as_deref(), Some("dev;ops"));
                assert_eq!(contexts[1].depth, 2);
                assert_eq!(contexts[2].action, TerminalContextAction::End);
                assert_eq!(contexts[2].implicit_closed_count, 1);
                assert_eq!(contexts[2].end_metadata.as_ref().unwrap().status, Some(0));
            }
            "osc72_drop_target_negotiation" => {
                let commands = terminal
                    .poll_events()
                    .into_iter()
                    .filter_map(|event| match event {
                        TerminalEvent::DragDropCommand(command) => Some(*command),
                        _ => None,
                    })
                    .collect::<Vec<_>>();
                assert_eq!(commands.len(), 3);
                assert_eq!(commands[0].action, DragDropAction::AcceptDrops);
                assert_eq!(commands[0].identifier, Some(7));
                assert_eq!(commands[0].payload, b"text/plain text/uri-list");
                assert_eq!(commands[1].action, DragDropAction::DropMove);
                assert_eq!(commands[1].operation, Some(1));
                assert_eq!(commands[2].action, DragDropAction::RequestDropData);
                assert_eq!(commands[2].x, Some(1));
            }
            "osc1337_clear_buffer" => {
                assert_eq!(terminal.scrollback_len(), 0);
                assert_eq!(terminal.title(), "osc1337-clear-corpus-ok");
                let visible = terminal.active_grid().rows();
                let visible = (0..visible)
                    .map(|row| terminal.active_grid().row_text(row))
                    .collect::<String>();
                assert!(visible.contains("after-clear"));
                assert!(!visible.contains("old-"));
                assert!(terminal.poll_events().iter().any(|event| matches!(
                    event,
                    TerminalEvent::ScreenCleared {
                        include_scrollback: true
                    }
                )));
            }
            "osc1337_cursor_guide" => {
                assert!(terminal.use_cursor_guide());
                assert_eq!(terminal.title(), "osc1337-cursor-guide-corpus-ok");
            }
            "osc1337_clipboard_copy" => {
                assert_eq!(terminal.title(), "osc1337-clipboard-corpus-ok");
                let visible = (0..terminal.active_grid().rows())
                    .map(|row| terminal.active_grid().row_text(row))
                    .collect::<String>();
                assert!(visible.contains("STREAM-CORPUS"));
            }
            "osc1337_shell_metadata_and_cell_size" => {
                let events = terminal.poll_events();
                assert!(events.iter().any(|event| matches!(
                    event,
                    TerminalEvent::ShellIntegrationVersion { version, shell }
                        if version == "17" && shell.as_deref() == Some("zsh")
                )));
                assert!(events.iter().any(|event| matches!(
                    event,
                    TerminalEvent::ShellIntegrationEvent {
                        source: par_term_emu_core_rust::terminal::event::ShellIntegrationSource::Osc1337,
                        event_type,
                        ..
                    } if event_type == "mark"
                )));
                assert!(
                    events
                        .iter()
                        .any(|event| matches!(event, TerminalEvent::CellSizeReportRequested))
                );
            }
            "osc1337_dynamic_cursor_shape" => {
                assert_eq!(
                    terminal.cursor().shape_override(),
                    Some(par_term_emu_core_rust::cursor::CursorShape::Block)
                );
                assert_eq!(terminal.cursor().blink_override(), Some(true));
            }
            "osc1337_blocks" => {
                assert_eq!(terminal.title(), "osc1337-block-corpus-ok");
                let blocks = terminal.iterm_blocks();
                assert_eq!(blocks.len(), 2);
                let outer = blocks.iter().find(|block| block.id == "outer").unwrap();
                assert_eq!(outer.block_type.as_deref(), Some("build"));
                assert_eq!((outer.start_abs_row, outer.end_abs_row), (0, 2));
                assert!(outer.complete);
                assert!(outer.folded);
                assert!(outer.render);
                let inner = blocks.iter().find(|block| block.id == "inner").unwrap();
                assert_eq!((inner.start_abs_row, inner.end_abs_row), (1, 2));
                assert!(inner.complete);
                assert!(!inner.folded);
                assert!(!inner.render);
            }
            "osc133_semantic_prompt_aid" => {
                let events = terminal.poll_events();
                assert!(events.iter().any(|event| matches!(
                    event,
                    TerminalEvent::ShellIntegrationEvent {
                        event_type,
                        prompt_kind: Some(kind),
                        aid: Some(aid),
                        fresh_line: Some(false),
                        ..
                    } if event_type == "semantic_prompt" && kind == "secondary" && aid == "outer"
                )));
                assert!(events.iter().any(|event| matches!(
                    event,
                    TerminalEvent::ShellIntegrationEvent {
                        event_type,
                        aid: Some(aid),
                        exit_code: Some(0),
                        ..
                    } if event_type == "command_finished" && aid == "outer"
                )));
            }
            "osc5522_binary_mime_clipboard" => {
                assert_eq!(terminal.title(), "osc5522-corpus-ok");
            }
            "osc21337_tab_status" => {
                assert_eq!(terminal.title(), "osc21337-corpus-ok");
                let events = terminal.poll_events();
                assert!(events.iter().any(|event| matches!(
                    event,
                    TerminalEvent::TabStatusChanged(update)
                        if update.indicator.as_deref() == Some("#ff9500")
                            && update.status.as_deref() == Some("Working;phase")
                            && update.status_color.as_deref() == Some("#5f87ff")
                )));
                assert!(events.iter().any(|event| matches!(
                    event,
                    TerminalEvent::TabStatusChanged(update)
                        if update.status_present
                            && update.status.is_none()
                            && update.status_color_present
                            && update.status_color.is_none()
                )));
            }
            "tmux_passthrough" => assert_eq!(
                write_hyperlink_probe(&mut terminal),
                Some((
                    "https://example.test/tmux".to_string(),
                    Some("tmux".to_string()),
                )),
            ),
            "screen_passthrough" => assert_eq!(
                write_hyperlink_probe(&mut terminal),
                Some((
                    "https://example.test/screen".to_string(),
                    Some("screen".to_string()),
                )),
            ),
            unexpected => panic!("unhandled OSC corpus case: {unexpected}"),
        }

        assert!(
            terminal.drain_responses().is_empty(),
            "{id}: corpus case emitted an unexpected PTY response",
        );
    }
}
