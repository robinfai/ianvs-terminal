fn resolve(state: &crate::session::TerminalState) {
    let _ = crate::session::selection_text_for_terminal(&state.terminal, request());
}
