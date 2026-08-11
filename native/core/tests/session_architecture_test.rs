const SESSION_SOURCE: &str = include_str!("../src/session.rs");
const PROTOCOL_CALLBACKS_SOURCE: &str = include_str!("../src/session/protocol_callbacks.rs");

#[test]
fn session_orchestrator_stays_within_its_post_extraction_line_budget() {
    const SESSION_LINE_BUDGET: usize = 13_500;
    let line_count = SESSION_SOURCE.lines().count();

    assert!(
        line_count <= SESSION_LINE_BUDGET,
        "session.rs has {line_count} lines, above its {SESSION_LINE_BUDGET}-line budget; \
         move another cohesive responsibility behind a session submodule"
    );
}

#[test]
fn protocol_callback_implementation_stays_out_of_session_orchestration() {
    assert!(SESSION_SOURCE.contains("mod protocol_callbacks;"));
    for implementation_marker in [
        "struct HostProtocolState",
        "fn handle_osc5522(",
        "fn callback_event_from_parser_event_with_terminal(",
        "fn parse_osc5522_metadata(",
    ] {
        assert!(
            !SESSION_SOURCE.contains(implementation_marker),
            "protocol implementation leaked back into session.rs: {implementation_marker}"
        );
        assert!(
            PROTOCOL_CALLBACKS_SOURCE.contains(implementation_marker),
            "protocol callback module lost expected implementation: {implementation_marker}"
        );
    }
}
