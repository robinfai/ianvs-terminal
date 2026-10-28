//! Same-lock provenance for the complete displayed viewport. This is separate
//! from command preview pagination and never looks up a later terminal state.
use super::frame::DisplayProjectionRow;
use super::*;
use crate::model::{TerminalSemanticBlock, TerminalSemanticRowContext};
use par_term_emu_core_rust::zone::{Zone, ZoneOutputSlice, ZoneType};

const MAX_ROWS: usize = 512;
const MAX_BLOCKS: usize = 128;
const MAX_BYTES: usize = 256 * 1024;
const MAX_FIELD_BYTES: usize = 4096;
const MAX_OWNERSHIP_WORK: usize = 1_000_000;

type Snapshot = (Vec<TerminalSemanticBlock>, Vec<TerminalSemanticRowContext>);

pub(super) fn capture(
    terminal: &Terminal,
    projection: &DisplayProjection,
    viewport_start: usize,
    viewport_rows: usize,
    replay: bool,
) -> Snapshot {
    if replay || terminal.is_alt_screen_active() || viewport_rows > MAX_ROWS {
        return (Vec::new(), Vec::new());
    }
    let grid = terminal.grid();
    let floor = grid
        .total_lines_scrolled()
        .saturating_sub(grid.scrollback_len());
    let cursor_row = grid
        .total_lines_scrolled()
        .saturating_add(terminal.cursor().row);
    let mut blocks = Vec::new();
    let mut rows = Vec::new();
    let mut ids = std::collections::HashSet::new();
    let mut work = 0usize;
    for viewport_row in 0..viewport_rows {
        let Some(DisplayProjectionRow::Source(source)) =
            projection.rows.get(viewport_start + viewport_row)
        else {
            continue; // Fold summaries and padding never have output provenance.
        };
        let Some(cells) = row_cells_for_visible_index(terminal, *source).0 else {
            continue;
        };
        work = work.saturating_add(cells.len().saturating_mul(2));
        if work > MAX_OWNERSHIP_WORK {
            return (Vec::new(), Vec::new());
        }
        let Some(first) = cells.iter().position(|cell| {
            cell.c != ' ' || cell.flags.wide_char_spacer() || cell.flags.hyperlink_id.is_some()
        }) else {
            continue;
        };
        let last = cells
            .iter()
            .rposition(|cell| {
                cell.c != ' ' || cell.flags.wide_char_spacer() || cell.flags.hyperlink_id.is_some()
            })
            .unwrap();
        let absolute = floor.saturating_add(*source);
        let mut owner = None;
        let mut ambiguous = false;
        for zone in terminal
            .get_zones()
            .iter()
            .filter(|zone| zone.zone_type == ZoneType::Output)
        {
            work += 1;
            if work > MAX_OWNERSHIP_WORK {
                return (Vec::new(), Vec::new());
            }
            let end = if zone.is_open() {
                cursor_row.max(zone.abs_row_end)
            } else {
                zone.abs_row_end
            };
            if absolute < zone.abs_row_start || absolute > end {
                continue;
            }
            let mut any_owned = false;
            let mut all_owned = true;
            for col in first..=last {
                work += zone.output_slices.len() + 1;
                if work > MAX_OWNERSHIP_WORK {
                    return (Vec::new(), Vec::new());
                }
                let owned = owns_column(
                    zone,
                    absolute,
                    col,
                    cursor_row,
                    terminal.cursor().col.max(last + 1),
                    grid.cols(),
                );
                any_owned |= owned;
                all_owned &= owned;
            }
            if !any_owned {
                continue;
            }
            if owner.is_some() || !all_owned {
                ambiguous = true;
                break;
            }
            owner = Some(zone);
        }
        let Some(zone) = owner.filter(|_| !ambiguous) else {
            continue;
        };
        if zone.semantic_invalidated {
            continue;
        }
        let Some(cwd) = zone.cwd.as_ref().filter(|cwd| !cwd.is_empty()) else {
            continue;
        };
        if !valid_field(cwd, MAX_FIELD_BYTES)
            || zone
                .context_id
                .as_ref()
                .is_some_and(|value| !valid_field(value, 128))
            || zone
                .shell_hostname
                .as_ref()
                .is_some_and(|value| !valid_field(value, 255))
            || zone
                .shell_username
                .as_ref()
                .is_some_and(|value| !valid_field(value, 255))
        {
            continue;
        }
        let id = command_blocks::identity(zone);
        if ids.insert(id.clone()) {
            blocks.push(TerminalSemanticBlock {
                id: id.clone(),
                cwd: cwd.clone(),
                context_id: zone.context_id.clone(),
                shell_hostname: zone.shell_hostname.clone(),
                shell_username: zone.shell_username.clone(),
                sftp_context_id: zone.sftp_context_id.clone(),
            });
        }
        rows.push(TerminalSemanticRowContext {
            viewport_row,
            block_id: id,
        });
        if blocks.len() > MAX_BLOCKS {
            return (Vec::new(), Vec::new());
        }
    }
    // Count escaped wire bytes, not just UTF-8 length (control chars expand).
    if serde_json::to_vec(&(&blocks, &rows)).map_or(true, |bytes| bytes.len() > MAX_BYTES) {
        return (Vec::new(), Vec::new());
    }
    (blocks, rows)
}

fn owns_column(
    zone: &Zone,
    row: usize,
    col: usize,
    cursor_row: usize,
    cursor_col: usize,
    columns: usize,
) -> bool {
    if zone
        .output_boundary_rows
        .get(&row)
        .is_some_and(|owned| owned.get(col) != Some(&true))
    {
        return false;
    }
    let (start_row, start_col) = zone
        .output_start
        .unwrap_or((zone.abs_row_start, zone.start_col));
    let active = ZoneOutputSlice {
        start_row,
        start_col,
        end_row: if zone.is_open() {
            cursor_row
        } else {
            zone.abs_row_end
        },
        end_col: if zone.is_open() {
            cursor_col
        } else {
            zone.end_col.unwrap_or(columns)
        },
    };
    zone.output_slices
        .iter()
        .chain((!zone.suspended).then_some(&active))
        .any(|slice| {
            (row, col) >= (slice.start_row, slice.start_col)
                && (row, col) < (slice.end_row, slice.end_col)
        })
}

fn valid_field(value: &str, limit: usize) -> bool {
    !value.is_empty() && value.len() <= limit && !value.chars().any(char::is_control)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn hook(term: &mut Terminal, value: serde_json::Value) {
        let hex: String = value
            .to_string()
            .bytes()
            .map(|byte| format!("{byte:02x}"))
            .collect();
        term.process(format!("\x1bPhook;{hex}\x1b\\").as_bytes());
    }
    fn start(term: &mut Terminal, context: &str, cwd: &str) {
        hook(term, json!({"hook":"precmd", "context_id":context}));
        hook(
            term,
            json!({"hook":"precmd.pwd", "context_id":context, "pwd":cwd}),
        );
        term.process(b"prompt> command\r\n");
        hook(
            term,
            json!({"hook":"preexec", "context_id":context,"command":"cat file"}),
        );
    }
    fn snapshot(term: &Terminal) -> Snapshot {
        let projection = display_projection_for_terminal(term);
        capture(term, &projection, 0, term.size().1, false)
    }
    #[test]
    fn freezes_historical_context_without_preview_or_current_cwd() {
        let mut term = Terminal::with_scrollback(30, 80, 100);
        start(&mut term, "root", "/old");
        for _ in 0..70 {
            term.process(b"src/file.rs:12:3\r\n");
        }
        let (blocks, rows) = snapshot(&term);
        assert_eq!(blocks.len(), 1);
        assert_eq!(rows.len(), 70);
        assert_eq!(rows[0].viewport_row, 1); // Outside the 48-row preview.
        hook(
            &mut term,
            json!({"hook":"command_finished", "context_id":"root","exit_code":0}),
        );
        hook(
            &mut term,
            json!({"hook":"precmd.pwd", "context_id":"root","pwd":"/later"}),
        );
        assert_eq!(blocks[0].cwd, "/old");
        assert_eq!(snapshot(&term).0[0].cwd, "/old");
    }
    #[test]
    fn refuses_shared_nested_rows_and_preserves_separate_child_rows() {
        let mut term = Terminal::new(80, 12);
        hook(
            &mut term,
            json!({"hook":"bootstrap.checking", "context_id":"parent"}),
        );
        start(&mut term, "parent", "/parent");
        term.process(b"parent.txt ");
        hook(
            &mut term,
            json!({"hook":"bootstrap.checking", "context_id":"child", "parent_context_id":"parent"}),
        );
        start(&mut term, "child", "/child");
        term.process(b"child.txt\r\n");
        let (blocks, rows) = snapshot(&term);
        assert!(!rows.iter().any(|row| row.viewport_row == 1));
        assert!(blocks.iter().any(|block| block.cwd == "/child"));
    }
    #[test]
    fn alternate_replay_and_oversized_viewport_have_no_authority() {
        let mut term = Terminal::new(30, 8);
        start(&mut term, "root", "/old");
        term.process(b"file.txt\r\n");
        assert!(!snapshot(&term).0.is_empty());
        let projection = display_projection_for_terminal(&term);
        assert!(capture(&term, &projection, 0, 8, true).0.is_empty());
        assert!(
            capture(&term, &projection, 0, MAX_ROWS + 1, false)
                .0
                .is_empty()
        );
        term.process(b"\x1b[?1049hfile.txt");
        assert!(snapshot(&term).0.is_empty());
        term.process(b"\x1b[?1049l");
        assert!(!snapshot(&term).0.is_empty());
    }
    #[test]
    fn scrollback_floor_maps_retained_rows_to_absolute_zone_coordinates() {
        let mut term = Terminal::with_scrollback(30, 4, 5);
        start(&mut term, "root", "/old");
        for _ in 0..20 {
            term.process(b"file.txt\r\n");
        }
        let (blocks, rows) = snapshot(&term);
        assert_eq!(blocks.len(), 1);
        assert_eq!(rows.len(), 4);
        assert_eq!(rows[0].viewport_row, 0);
    }
    #[test]
    fn completed_output_repaint_cannot_reuse_old_cwd() {
        let mut term = Terminal::new(30, 8);
        start(&mut term, "root", "/old");
        term.process(b"old.txt\r\n");
        hook(
            &mut term,
            json!({"hook":"command_finished", "context_id":"root","exit_code":0}),
        );
        hook(&mut term, json!({"hook":"precmd", "context_id":"root"}));
        term.process(b"prompt> ");
        term.process(b"\x1b[2;1Hnew.txt");
        assert!(!snapshot(&term).1.iter().any(|row| row.viewport_row == 1));
    }
    fn session(replay: bool) -> Arc<TerminalSession> {
        let profile: TerminalProfile =
            serde_json::from_value(json!({"id":"semantic", "name":"semantic", "launch":{}}))
                .unwrap();
        let mut session = TerminalSession::spawn_replay(99, profile).unwrap();
        Arc::get_mut(&mut session).unwrap().is_replay = replay;
        session.state.lock().terminal = Terminal::with_scrollback(30, 8, 40);
        session
    }

    #[test]
    fn published_frame_token_delta_protobuf_resize_and_frozen_context() {
        let session = session(false);
        {
            let mut state = session.state.lock();
            start(&mut state.terminal, "root", "/old");
            state.terminal.process(b"src/file.rs:12\r\n");
        }
        let first = session.take_frame_diff().unwrap().unwrap();
        assert_eq!(first.semantic_snapshot_token.as_deref(), Some("1"));
        assert_eq!(first.semantic_blocks[0].cwd, "/old");
        assert!(session.take_frame_diff().unwrap().is_none());
        assert_eq!(
            session.semantic_snapshot_sequence.load(Ordering::Relaxed),
            1
        );
        session.ingest_pty_output(b"next.txt", false);
        let delta = session.take_frame_diff().unwrap().unwrap();
        assert_eq!(delta.frame_kind, TerminalFrameKind::Delta);
        assert_eq!(delta.semantic_snapshot_token.as_deref(), Some("2"));
        assert!(
            delta
                .semantic_row_contexts
                .iter()
                .any(|row| row.viewport_row == 1)
        );
        assert!(
            delta
                .semantic_row_contexts
                .iter()
                .any(|row| row.viewport_row == 2)
        );
        let encoded = frame_diff_proto::encode_frame_diff(&delta).unwrap();
        let decoded = frame_diff_proto::decode_frame_diff_for_test(&encoded).unwrap();
        assert_eq!(
            decoded.semantic_snapshot_token,
            delta.semantic_snapshot_token
        );
        assert_eq!(decoded.semantic_blocks[0].cwd, "/old");
        assert_eq!(
            decoded.semantic_row_contexts.len(),
            delta.semantic_row_contexts.len()
        );
        {
            let mut state = session.state.lock();
            hook(
                &mut state.terminal,
                json!({"hook":"precmd.pwd","context_id":"root","pwd":"/later"}),
            );
        }
        session.resize(20, 8, 0, 0).unwrap();
        let resized = session.take_frame_diff().unwrap().unwrap();
        assert_ne!(
            resized.semantic_snapshot_token,
            delta.semantic_snapshot_token
        );
        assert_eq!(first.semantic_blocks[0].cwd, "/old");
        assert_eq!(delta.semantic_blocks[0].cwd, "/old");
    }
    #[test]
    fn replay_published_frames_cannot_authorize_paths() {
        let session = session(true);
        {
            let mut state = session.state.lock();
            start(&mut state.terminal, "root", "/old");
            state.terminal.process(b"file.txt");
        }
        let frame = session.take_frame_diff().unwrap().unwrap();
        assert!(frame.semantic_snapshot_token.is_some());
        assert!(frame.semantic_blocks.is_empty());
        assert!(frame.semantic_row_contexts.is_empty());
    }
    #[test]
    fn invalidation_survives_snapshot_restore_and_height_resize() {
        let mut term = Terminal::new(30, 8);
        start(&mut term, "root", "/old");
        term.process(b"old.txt\r\n");
        hook(
            &mut term,
            json!({"hook":"command_finished","context_id":"root","exit_code":0}),
        );
        term.process(b"\x1b[2;1Hnew.txt");
        let frozen = term.capture_snapshot();
        term.restore_from_snapshot(frozen);
        assert!(snapshot(&term).0.is_empty());
        term.resize(30, 10);
        assert!(snapshot(&term).0.is_empty());
        term.resize(20, 10);
        assert!(snapshot(&term).0.is_empty());
    }
    #[test]
    fn wide_softwrap_rows_share_frozen_owner() {
        let mut term = Terminal::new(8, 8);
        // Avoid a wrapping prompt in this fixture.
        hook(&mut term, json!({"hook":"precmd.pwd","pwd":"/project"}));
        hook(&mut term, json!({"hook":"preexec","command":"cat"}));
        term.process("目录/file.dart:12".as_bytes());
        let (blocks, rows) = snapshot(&term);
        assert_eq!(blocks.len(), 1);
        assert!(rows.len() >= 2);
        assert!(rows.iter().all(|row| row.block_id == blocks[0].id));
    }
    #[test]
    fn blank_hyperlink_owned_by_child_never_uses_parent_context() {
        let mut term = Terminal::new(80, 12);
        hook(
            &mut term,
            json!({"hook":"precmd.pwd","context_id":"root","pwd":"/parent"}),
        );
        hook(
            &mut term,
            json!({"hook":"preexec","context_id":"root","command":"parent"}),
        );
        term.process(b"PARENT");
        hook(
            &mut term,
            json!({"hook":"bootstrap.checking","context_id":"child","parent_context_id":"root"}),
        );
        hook(&mut term, json!({"hook":"precmd","context_id":"child"}));
        term.process(b"\x1b]8;;file:child.txt\x07      \x1b]8;;\x07");
        hook(
            &mut term,
            json!({"hook":"bootstrap.resume","context_id":"root","retired_contexts":["child"],"exit_code":0}),
        );
        term.process(b"\rPARENT");
        assert!(snapshot(&term).1.is_empty());
    }
    #[test]
    fn metadata_budget_is_all_or_nothing_and_long_fields_are_untrusted() {
        let mut term = Terminal::new(40, 512);
        for index in 0..129 {
            hook(
                &mut term,
                json!({"hook":"precmd.pwd","pwd":format!("/p{index}")}),
            );
            hook(&mut term, json!({"hook":"preexec","command":"cat"}));
            term.process(b"file.txt\r\n");
            hook(&mut term, json!({"hook":"command_finished","exit_code":0}));
        }
        assert!(snapshot(&term).0.is_empty());
        let mut term = Terminal::new(40, 8);
        start(&mut term, "root", &format!("/{}", "x".repeat(4096)));
        term.process(b"file.txt");
        assert!(snapshot(&term).0.is_empty());
    }
    #[test]
    fn open_output_rectangle_copy_revokes_foreign_row_provenance() {
        let mut term = Terminal::new(40, 12);
        start(&mut term, "root", "/old");
        term.process(b"old.txt\r\n");
        hook(
            &mut term,
            json!({"hook":"command_finished","context_id":"root","exit_code":0}),
        );
        start(&mut term, "root", "/new");
        // Copy a previous command's text beyond the initial row of the open
        // output, then move the cursor beyond it. Range endpoints cannot prove
        // that copied cells belong to the current command.
        term.process(b"\x1b[2;1;2;7;1;6;1;1$v\x1b[7;1H");
        assert!(!snapshot(&term).1.iter().any(|row| row.viewport_row == 5));
    }

    #[test]
    fn session_replay_resize_never_restores_revoked_provenance() {
        let session = session(false);
        session.state.lock().terminal = Terminal::with_scrollback(8, 8, 40);
        let hook_bytes = |value: serde_json::Value| {
            let hex: String = value
                .to_string()
                .bytes()
                .map(|byte| format!("{byte:02x}"))
                .collect();
            format!("\x1bPhook;{hex}\x1b\\").into_bytes()
        };
        session.ingest_pty_output(
            &hook_bytes(json!({"hook":"precmd.pwd","pwd":"/old"})),
            false,
        );
        session.ingest_pty_output(
            &hook_bytes(json!({"hook":"preexec","command":"cat"})),
            false,
        );
        session.ingest_pty_output(b"abcdefgh.txt", false);
        session.ingest_pty_output(
            &hook_bytes(json!({"hook":"command_finished","exit_code":0})),
            false,
        );
        session.ingest_pty_output(b"\x1b[2;1Hoverwrite", false);
        let old = session.take_frame_diff().unwrap().unwrap();
        assert!(old.semantic_blocks.is_empty());
        session.resize(30, 8, 0, 0).unwrap();
        let resized = session.take_frame_diff().unwrap().unwrap();
        assert!(resized.semantic_blocks.is_empty());
    }

    #[test]
    fn state_remains_locked_until_ingress_damage_is_published() {
        use std::sync::{Barrier, mpsc};
        let session = session(false);
        let _ = session.take_frame_diff().unwrap();
        let entered = Arc::new(Barrier::new(2));
        let release = Arc::new(Barrier::new(2));
        let blocker = {
            let session = session.clone();
            let entered = entered.clone();
            let release = release.clone();
            thread::spawn(move || {
                session.pending_frame_signal.mutate(|_| {
                    entered.wait();
                    release.wait();
                })
            })
        };
        entered.wait();
        // Hold the observer so ingress first demonstrably acquires state.
        let observer = session.output_observer.lock();
        let (started, received) = mpsc::channel();
        let writer = {
            let session = session.clone();
            thread::spawn(move || {
                started.send(()).unwrap();
                session.ingest_pty_output(b"changed", true);
            })
        };
        received.recv_timeout(Duration::from_secs(2)).unwrap();
        let deadline = Instant::now() + Duration::from_secs(2);
        while session.state.try_lock().is_some() && Instant::now() < deadline {
            thread::yield_now();
        }
        let ingress_acquired_state = session.state.try_lock().is_none();
        drop(observer);
        // Before the fix ingress released state while waiting on the blocked
        // damage publication. A frame could then observe torn rows/provenance.
        let unpublished_state_visible = session
            .state
            .try_lock_for(Duration::from_millis(100))
            .is_some();
        release.wait();
        blocker.join().unwrap();
        writer.join().unwrap();
        assert!(ingress_acquired_state);
        assert!(!unpublished_state_visible);
        let frame = session.take_frame_diff().unwrap().unwrap();
        assert!(frame.rows.iter().any(|row| row.text.contains("changed")));
    }
    #[test]
    fn route_incarnation_is_frozen_in_blocks_frames_and_metadata_restore() {
        let mut term = Terminal::new(40, 10);
        hook(
            &mut term,
            json!({"hook":"bootstrap.checking","context_id":"root","sftp_context_id":"root"}),
        );
        hook(
            &mut term,
            json!({"hook":"bootstrap.checking","context_id":"child","parent_context_id":"root","sftp_context_id":"child@1"}),
        );
        start(&mut term, "child", "/remote");
        term.process(b"file.txt\r\n");
        let frozen = snapshot(&term);
        assert_eq!(frozen.0[0].sftp_context_id.as_deref(), Some("child@1"));
        let blocks = command_blocks::snapshot(&term, &json!({}));
        assert_eq!(blocks["blocks"][0]["sftpContextId"], "child@1");
        let previous = term.get_zones().to_vec();
        hook(
            &mut term,
            json!({"hook":"bootstrap.checking","context_id":"child","parent_context_id":"root","sftp_context_id":"child@2"}),
        );
        // A metadata update cannot rewrite an already started command.
        assert_eq!(
            snapshot(&term).0[0].sftp_context_id.as_deref(),
            Some("child@1")
        );
        term.restore_zone_metadata(&previous);
        assert_eq!(
            snapshot(&term).0[0].sftp_context_id.as_deref(),
            Some("child@1")
        );
    }
}
