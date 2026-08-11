struct TerminalState;

type HiddenHostAlias = TerminalState;

trait ProtocolHostContext {
    fn hidden(&self) -> HiddenHostAlias;
}
