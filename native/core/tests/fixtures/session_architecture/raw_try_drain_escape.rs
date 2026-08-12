struct Parser;

impl Parser {
    fn poll_events(&mut self) -> Vec<()> {
        Vec::new()
    }
}

struct SessionState {
    terminal: Parser,
}

fn drain(state: &mut SessionState) -> Result<(), ()> {
    let _events = Ok::<_, ()>(&mut state.terminal)?.poll_events();
    Ok(())
}
