struct ParserAlias;

impl ParserAlias {
    fn poll_events(&mut self) -> Vec<()> {
        Vec::new()
    }
}

struct SessionState {
    terminal: ParserAlias,
}

fn drain(state: &mut SessionState) {
    let _events = state.terminal.poll_events();
}

fn drain_through_alias(parser: &mut ParserAlias) {
    let _events = parser.poll_events();
}

fn drain_associated(state: &mut SessionState) {
    let _events = ParserAlias::poll_events(&mut state.terminal);
}
