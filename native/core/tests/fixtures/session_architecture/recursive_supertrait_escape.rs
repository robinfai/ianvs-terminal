struct TerminalState;

trait HiddenHostPort {
    fn hidden(&self) -> TerminalState;
}

trait ProtocolHostContext: HiddenHostPort {}
