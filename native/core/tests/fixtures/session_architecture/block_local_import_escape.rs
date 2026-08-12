struct TerminalState;

mod callbacks {
    fn escape() {
        use super::TerminalState as Hidden;

        let _state: Option<&Hidden> = None;
    }
}
