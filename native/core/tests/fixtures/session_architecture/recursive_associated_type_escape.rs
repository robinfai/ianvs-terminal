struct TerminalState;

trait ProtocolHostContext {
    type Context: Into<TerminalState>;
}
