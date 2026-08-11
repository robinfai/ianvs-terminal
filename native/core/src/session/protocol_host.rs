use super::protocol_callbacks::{
    ProtocolCallbackBatch, ProtocolCallbackPolicy, ProtocolCompletedTransfer, ProtocolEventControl,
    ProtocolHostContext, ProtocolTransferControl, callback_events_from_parser_events,
};
use super::{TerminalState, retained_row_for_abs_row, selection_text_for_terminal};
use crate::model::TerminalSelectionRequest;
use par_term_emu_core_rust::terminal::{Terminal, TerminalEvent as ParserTerminalEvent};

pub(super) fn drain_protocol_callback_batch(
    state: &mut TerminalState,
    policy: ProtocolCallbackPolicy,
) -> ProtocolCallbackBatch {
    let parser_events = state.terminal.poll_events();
    callback_events_from_parser_events(state, parser_events, policy)
}

impl ProtocolTransferControl for TerminalState {
    fn take_completed_protocol_transfer(&mut self, id: u64) -> Option<ProtocolCompletedTransfer> {
        take_completed_protocol_transfer(&mut self.terminal, id)
    }

    fn cancel_protocol_upload(&mut self) {
        self.terminal.cancel_upload();
    }
}

impl ProtocolHostContext for TerminalState {
    fn resolve_report_variable(&self, name: &str) -> Option<String> {
        let terminal = &self.terminal;
        let variables = terminal.session_variables();
        match name {
            "session.name" => variables
                .session_name
                .clone()
                .or_else(|| (!terminal.title().is_empty()).then(|| terminal.title().to_string())),
            "session.columns" => Some(terminal.size().0.to_string()),
            "session.rows" => Some(terminal.size().1.to_string()),
            "session.hostname" => variables.hostname.clone(),
            "session.username" => variables.username.clone(),
            "session.path" => variables
                .path
                .clone()
                .or_else(|| terminal.current_directory().map(str::to_string)),
            _ => name
                .strip_prefix("user.")
                .and_then(|user_name| terminal.get_user_var(user_name))
                .map(str::to_string),
        }
    }

    fn resolve_annotation_selection(
        &self,
        start_abs_row: usize,
        start_col: usize,
        end_abs_row: usize,
        end_col: usize,
    ) -> Option<(usize, usize, String)> {
        let start_row = retained_row_for_abs_row(&self.terminal, start_abs_row)?;
        let end_row = retained_row_for_abs_row(&self.terminal, end_abs_row)?;
        let selected_text = selection_text_for_terminal(
            &self.terminal,
            TerminalSelectionRequest {
                start_row,
                start_col,
                end_row,
                end_col,
                block: false,
            },
        );
        Some((start_row, end_row, selected_text))
    }

    fn retain_protocol_download(
        &mut self,
        filename: String,
        data: Vec<u8>,
    ) -> Result<(u64, String, usize), String> {
        self.retain_file_download(filename, data)
    }
}

impl ProtocolTransferControl for Terminal {
    fn take_completed_protocol_transfer(&mut self, id: u64) -> Option<ProtocolCompletedTransfer> {
        take_completed_protocol_transfer(self, id)
    }

    fn cancel_protocol_upload(&mut self) {
        self.cancel_upload();
    }
}

impl ProtocolEventControl for Terminal {
    fn poll_protocol_events(&mut self) -> Vec<ParserTerminalEvent> {
        self.poll_events()
    }
}

fn take_completed_protocol_transfer(
    terminal: &mut Terminal,
    id: u64,
) -> Option<ProtocolCompletedTransfer> {
    terminal
        .take_completed_transfer(id)
        .map(|transfer| ProtocolCompletedTransfer {
            direction: transfer.direction,
            status: transfer.status,
            filename: transfer.filename,
            data: transfer.data,
        })
}
