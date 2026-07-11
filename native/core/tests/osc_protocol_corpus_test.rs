use par_term_emu_core_rust::color::Color;
use par_term_emu_core_rust::terminal::{Terminal, TerminalContextAction, TerminalEvent};
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
