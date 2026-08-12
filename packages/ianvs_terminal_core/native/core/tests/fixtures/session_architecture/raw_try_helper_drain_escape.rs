struct Parser;

impl Parser {
    fn poll_events(&mut self) -> Vec<()> {
        Vec::new()
    }
}

struct TerminalState {
    terminal: Parser,
}

fn parser(state: &mut TerminalState) -> Result<&mut Parser, ()> {
    Ok(&mut state.terminal)
}

fn drain(state: &mut TerminalState) -> Result<(), ()> {
    let _events = parser(state)?.poll_events();
    Ok(())
}
