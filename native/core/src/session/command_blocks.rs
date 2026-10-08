//! Read-only command/output projection. Native grid coordinates remain the
//! source of truth; filters, folding, bookmarks and selection never edit it.
use super::*;
use par_term_emu_core_rust::zone::{Zone, ZoneOutputSlice, ZoneType};
use serde_json::{Value, json};

const MAX_BLOCKS: usize = 128;
const PREVIEW_LINES: usize = 48;
const MAX_PAGE_LINES: usize = 2048;

pub(super) fn snapshot(terminal: &Terminal, request: &Value) -> Value {
    if terminal.is_alt_screen_active() {
        return json!({"blocks": [], "alternateScreen": true});
    }
    let id = request["id"].as_str();
    let zones = terminal
        .get_zones()
        .iter()
        .filter(|z| z.zone_type == ZoneType::Output);
    if let Some(id) = id {
        let Some(zone) = zones.into_iter().find(|z| identity(z) == id) else {
            return json!({"missing": true});
        };
        return match read_block(terminal, zone, request, false) {
            Ok(block) => json!({"block": block}),
            Err(error) => json!({"error": error}),
        };
    }
    let mut zones: Vec<_> = zones.collect();
    let omitted = zones.len().saturating_sub(MAX_BLOCKS);
    zones.drain(..omitted);
    // Bound the aggregate response as well as individual pages. Preserve the
    // newest previews; older metadata still exposes paged output on demand.
    let mut budget = 6 * 1024 * 1024usize;
    let mut blocks = Vec::new();
    for zone in zones.into_iter().rev() {
        if let Ok(mut block) = read_block(terminal, zone, request, true) {
            let size = serde_json::to_vec(&block).map_or(budget + 1, |b| b.len());
            if size > budget {
                block["lines"] = json!([]);
                block["hyperlinks"] = json!([]);
                block["offset"] = json!(0);
                block["nextOffset"] = if block["totalLines"].as_u64().unwrap_or(0) > 0 {
                    json!(0)
                } else {
                    Value::Null
                };
            } else {
                budget -= size;
            }
            blocks.push(block);
        }
    }
    blocks.reverse();
    json!({"blocks": blocks, "omittedBlocks": omitted, "alternateScreen": false})
}

pub(super) fn identity(zone: &Zone) -> String {
    format!("{}-{}", zone.timestamp.unwrap_or_default(), zone.id)
}

fn read_block(
    terminal: &Terminal,
    zone: &Zone,
    request: &Value,
    preview: bool,
) -> Result<Value, String> {
    let grid = terminal.grid();
    let floor = grid
        .total_lines_scrolled()
        .saturating_sub(grid.scrollback_len());
    let cursor_row = grid
        .total_lines_scrolled()
        .saturating_add(terminal.cursor().row);
    let end = if zone.is_open() {
        cursor_row
    } else {
        zone.abs_row_end
    };
    let end_col = if zone.is_open() {
        let content_end = grid
            .row(terminal.cursor().row)
            .and_then(|cells| {
                cells
                    .iter()
                    .rposition(|cell| cell.c != ' ' || cell.flags.wide_char_spacer())
            })
            .map_or(0, |col| col + 1);
        terminal.cursor().col.max(content_end)
    } else {
        zone.end_col.unwrap_or(grid.cols())
    };
    let source_base = zone.abs_row_start.max(floor);
    let (active_row, active_col) = zone
        .output_start
        .unwrap_or((zone.abs_row_start, zone.start_col));
    let active = ZoneOutputSlice {
        start_row: active_row,
        start_col: active_col,
        end_row: end,
        end_col,
    };
    // A suspended parent stays running, but its child's rows must never be
    // exposed by parent pagination, filtering, copy or evidence references.
    let mut slices = Vec::new();
    let mut ranges = Vec::new();
    for slice in zone
        .output_slices
        .iter()
        .chain((!zone.suspended).then_some(&active))
    {
        let live = std::ptr::eq(slice, &active) && zone.is_open();
        if !live && (slice.end_row, slice.end_col) <= (slice.start_row, slice.start_col) {
            continue;
        }
        let start = slice.start_row.max(source_base);
        let empty_boundary = zone
            .output_boundary_rows
            .get(&slice.end_row)
            .is_some_and(|owned| !owned.iter().any(|owned| *owned));
        let exclusive_end = if (slice.end_col == 0 || empty_boundary) && !live {
            slice.end_row
        } else {
            slice.end_row.saturating_add(1)
        };
        let length = exclusive_end.saturating_sub(start);
        if length > 0 {
            slices.push(slice);
            ranges.push((start, exclusive_end));
        }
    }
    // Source indices address physical rows; paging offsets address only this
    // command's retained output. Merge overlapping row ranges so two portions
    // on one physical row never produce duplicate source indices.
    ranges.sort_unstable();
    let mut spans: Vec<(usize, usize, usize)> = Vec::new();
    let mut count = 0;
    for (start, end) in ranges {
        if let Some((_, _, previous_end)) = spans.last_mut()
            && start <= *previous_end
        {
            count += end.saturating_sub(*previous_end);
            *previous_end = (*previous_end).max(end);
        } else {
            spans.push((count, start, end));
            count += end - start;
        }
    }
    let source_count = spans.last().map_or(0, |(_, _, end)| end - source_base);
    let query = request["query"].as_str().unwrap_or("");
    if query.len() > 4096 {
        return Err("Query is too long".into());
    }
    let regex = if query.is_empty() {
        None
    } else {
        let pattern = if request["regex"] == true {
            query.to_owned()
        } else {
            regex::escape(query)
        };
        Some(
            RegexBuilder::new(&pattern)
                .case_insensitive(request["caseSensitive"] != true)
                .size_limit(1024 * 1024)
                .build()
                .map_err(|_| "Invalid regular expression".to_owned())?,
        )
    };
    let context = request["contextLines"].as_u64().unwrap_or(0).min(20) as usize;
    let inverted = request["invert"] == true;
    let mut selected = Vec::new();
    let theme = terminal_theme_snapshot(terminal);
    let row_at = |line: usize| {
        let (base, start, _) = spans
            .iter()
            .rev()
            .find(|(base, _, _)| *base <= line)
            .unwrap();
        let abs = start + line - base;
        let (cells, wrapped) = row_cells_for_visible_index(terminal, abs - floor);
        let cells = cells.unwrap_or_default();
        let mut columns = Vec::new();
        let mut continued = false;
        for slice in &slices {
            if abs < slice.start_row || abs > slice.end_row {
                continue;
            }
            let from = if abs == slice.start_row {
                slice.start_col.min(cells.len())
            } else {
                0
            };
            let to = if abs == slice.end_row {
                slice.end_col.min(cells.len())
            } else {
                cells.len()
            };
            if to > from {
                columns.push((from, to));
                continued |= abs < slice.end_row;
            }
        }
        columns.sort_unstable();
        let mut owned_cells = Vec::new();
        let mut copied_to = 0;
        let ownership = zone.output_boundary_rows.get(&abs);
        for (from, to) in columns {
            let from = from.max(copied_to);
            if to > from {
                owned_cells.extend(cells[from..to].iter().enumerate().filter_map(
                    |(index, cell)| {
                        ownership
                            .is_none_or(|owned| owned.get(from + index) == Some(&true))
                            .then(|| cell.clone())
                    },
                ));
                copied_to = to;
            }
        }
        let extracted = extract_row(Some(&owned_cells), wrapped && continued, &theme);
        (
            extracted,
            abs,
            extract_hyperlinks_for_row(terminal, Some(&owned_cells), line),
        )
    };
    if let Some(regex) = &regex {
        // Rust regex is linear-time. Untrusted terminal text and user patterns
        // never run a backtracking expression on Flutter's UI thread.
        let mut included = vec![false; count];
        for line in 0..count {
            let (row, _, _) = row_at(line);
            if regex.is_match(&row.text) != inverted {
                for include in
                    &mut included[line.saturating_sub(context)..=(line + context).min(count - 1)]
                {
                    *include = true;
                }
            }
        }
        selected.extend(
            included
                .iter()
                .enumerate()
                .filter_map(|(i, &yes)| yes.then_some(i)),
        );
    }
    let total = if regex.is_some() {
        selected.len()
    } else {
        count
    };
    let limit = if preview {
        PREVIEW_LINES
    } else {
        request["limit"]
            .as_u64()
            .unwrap_or(MAX_PAGE_LINES as u64)
            .clamp(1, MAX_PAGE_LINES as u64) as usize
    };
    let offset = if !preview && !request["sourceLine"].is_null() {
        let source = request["sourceLine"]
            .as_u64()
            .and_then(|line| usize::try_from(line).ok())
            .and_then(|line| source_base.checked_add(line))
            .ok_or("Invalid source line")?;
        let ordinal = spans
            .iter()
            .find_map(|(base, start, end)| {
                (*start <= source && source < *end).then(|| base + source - start)
            })
            .ok_or("Source line is no longer available")?;
        if regex.is_some() {
            selected
                .iter()
                .position(|line| *line == ordinal)
                .ok_or("Source line is not present in filtered output")?
        } else {
            ordinal
        }
    } else if preview || request["tail"] == true {
        total.saturating_sub(limit)
    } else {
        request["offset"].as_u64().unwrap_or(0).min(total as u64) as usize
    };
    let mut bytes = 0;
    let mut rows = Vec::new();
    let mut hyperlinks = Vec::new();
    let indices: Box<dyn Iterator<Item = usize>> = if regex.is_some() {
        Box::new(selected.into_iter().skip(offset).take(limit))
    } else {
        Box::new((offset..count).take(limit))
    };
    for line in indices {
        let (row, abs, links) = row_at(line);
        let text = if row.wrapped {
            row.text.clone()
        } else {
            row.text.trim_end().to_owned()
        };
        bytes += text.len()
            + row.style_runs.len() * 180
            + links.iter().map(|link| link.uri.len() + 128).sum::<usize>();
        if bytes > 512 * 1024 {
            if rows.is_empty() {
                return Err("A terminal row exceeds the output page limit".into());
            }
            break;
        }
        hyperlinks.extend(links.into_iter().map(|mut link| {
            link.row = rows.len();
            link
        }));
        rows.push(
            json!({"index": abs - source_base, "text": text, "wrapped": row.wrapped,
            "source_row": abs, "source_end_row": abs, "style_runs": row.style_runs}),
        );
    }
    Ok(
        json!({"id": identity(zone), "command": zone.command, "cwd": zone.cwd,
        "submissionId": zone.submission_id, "contextId": zone.context_id,
        "startedAt": zone.timestamp, "finishedAt": zone.finished_at,
        "exitCode": zone.exit_code, "running": zone.is_open(),
        "suspended": zone.suspended,
        "totalLines": count, "matchingLines": total, "offset": offset,
        "sourceLineCount": source_count, "segmented": zone.suspended || zone.output_start.is_some(),
        "commandMatch": regex.as_ref().is_some_and(|re| re.is_match(zone.command.as_deref().unwrap_or(""))),
        "nextOffset": (offset + rows.len() < total).then_some(offset + rows.len()),
        "evicted": zone.output_truncated || zone.abs_row_start < floor, "columns": grid.cols(),
        "cursorLine": if zone.suspended {source_count} else if zone.is_open() {cursor_row.saturating_sub(source_base)} else {0}, "cursorColumn": if zone.is_open() && !zone.suspended {terminal.cursor().col} else {0},
        "lines": rows, "hyperlinks": hyperlinks}),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    fn hook(term: &mut Terminal, value: Value) {
        let hex = value
            .to_string()
            .bytes()
            .map(|b| format!("{b:02x}"))
            .collect::<String>();
        term.process(format!("\x1bPhook;{hex}\x1b\\").as_bytes());
    }
    fn command(term: &mut Terminal, text: &str, output: &[u8], code: i32) {
        hook(term, json!({"hook":"precmd"}));
        hook(term, json!({"hook":"precmd.pwd", "pwd":"/project"}));
        term.process(b"prompt> command\r\n");
        hook(term, json!({"hook":"preexec", "command":text}));
        term.process(output);
        hook(term, json!({"hook":"command_finished", "exit_code":code}));
        hook(term, json!({"hook":"precmd"}));
        term.process(b"next prompt> ");
    }
    fn context_command(term: &mut Terminal, context: &str, command: &str, osc_first: bool) {
        hook(term, json!({"hook":"precmd", "context_id":context}));
        term.process(b"prompt> command\r\n");
        if osc_first {
            term.process(b"\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C\x07");
        }
        hook(
            term,
            json!({"hook":"preexec", "context_id":context,
            "submission_id":command, "command":command}),
        );
        if !osc_first {
            term.process(b"\x1b]133;B\x07\x1b]133;C\x07");
        }
    }

    #[test]
    fn child_context_restores_parent_output_exit_codes_and_sparse_source_indices() {
        for osc_first in [false, true] {
            let mut term = Terminal::new(80, 24);
            hook(
                &mut term,
                json!({"hook":"bootstrap.checking", "context_id":"root"}),
            );
            hook(
                &mut term,
                json!({"hook":"precmd.pwd", "context_id":"root", "pwd":"/parent"}),
            );
            context_command(&mut term, "root", "parent", osc_first);
            term.process(b"BEFORE\r\n");
            let parent_id = snapshot(&term, &json!({}))["blocks"][0]["id"].clone();
            hook(
                &mut term,
                json!({"hook":"bootstrap.checking", "context_id":"child", "parent_context_id":"root"}),
            );
            // Repeated init for the same context must not suspend it again.
            hook(
                &mut term,
                json!({"hook":"bootstrap.checking", "context_id":"child", "parent_context_id":"root"}),
            );
            hook(
                &mut term,
                json!({"hook":"precmd.pwd", "context_id":"child", "pwd":"/child"}),
            );
            context_command(&mut term, "child", "child-command", osc_first);
            term.process(b"CHILD\r\n");
            if osc_first {
                term.process(b"\x1b]133;D;0\x07");
            }
            hook(
                &mut term,
                json!({"hook":"command_finished", "context_id":"child", "exit_code":0}),
            );
            if !osc_first {
                term.process(b"\x1b]133;D;0\x07");
            }
            let paused = snapshot(&term, &json!({"id":parent_id}));
            assert_eq!(paused["block"]["running"], true);
            assert_eq!(paused["block"]["suspended"], true);
            assert_eq!(paused["block"]["exitCode"], Value::Null);
            assert_eq!(paused["block"]["lines"].as_array().unwrap().len(), 1);
            assert_eq!(paused["block"]["lines"][0]["text"], "BEFORE");
            context_command(&mut term, "child", "exit-child", osc_first);
            // Resize/session restoration must preserve both context lifecycles.
            let saved = term.capture_snapshot();
            term = Terminal::new(80, 24);
            term.restore_from_snapshot(saved);
            hook(
                &mut term,
                json!({"hook":"bootstrap.resume", "context_id":"root", "retired_contexts":["child"], "exit_code":7}),
            );
            term.process(b"AFTER\r\n");
            hook(
                &mut term,
                json!({"hook":"command_finished", "context_id":"child", "exit_code":99}),
            );
            assert_eq!(
                snapshot(&term, &json!({"id":parent_id}))["block"]["running"],
                true
            );
            if osc_first {
                term.process(b"\x1b]133;D;0\x07");
            }
            hook(
                &mut term,
                json!({"hook":"command_finished", "context_id":"root", "exit_code":0}),
            );
            if !osc_first {
                term.process(b"\x1b]133;D;0\x07");
            }
            let all = snapshot(&term, &json!({}));
            let blocks = all["blocks"].as_array().unwrap();
            assert_eq!(blocks.len(), 3, "{all}");
            let parent = &blocks[0];
            assert_eq!(parent["id"], parent_id);
            assert_eq!(parent["cwd"], "/parent");
            assert_eq!(parent["exitCode"], 0);
            assert_eq!(parent["running"], false);
            assert_eq!(parent["suspended"], false);
            assert_eq!(parent["segmented"], true);
            assert_eq!(parent["totalLines"], 2);
            assert_eq!(blocks[1]["cwd"], "/child");
            assert_eq!(blocks[1]["exitCode"], 0);
            assert_eq!(blocks[2]["exitCode"], 7);
            assert_eq!(blocks[2]["lines"], json!([]));
            let rows = parent["lines"].as_array().unwrap();
            assert_eq!(rows[0]["text"], "BEFORE");
            assert_eq!(rows[1]["text"], "AFTER");
            let source = rows[1]["index"].as_u64().unwrap();
            assert!(source > 1);
            assert_eq!(
                rows[0]["source_row"].as_u64().unwrap() - rows[0]["index"].as_u64().unwrap(),
                rows[1]["source_row"].as_u64().unwrap() - source
            );
            assert_eq!(parent["sourceLineCount"], source + 1);
            let first = snapshot(&term, &json!({"id":parent_id,"offset":0,"limit":1}));
            assert_eq!(first["block"]["nextOffset"], 1);
            let last = snapshot(
                &term,
                &json!({"id":parent_id,"sourceLine":source,"limit":1}),
            );
            assert_eq!(last["block"]["offset"], 1);
            assert_eq!(last["block"]["lines"][0], rows[1]);
            assert_eq!(last["block"]["nextOffset"], Value::Null);
            assert!(snapshot(&term, &json!({"id":parent_id,"sourceLine":1}))["error"].is_string());
            let filtered = snapshot(
                &term,
                &json!({"id":parent_id,"sourceLine":source,"query":"AFTER"}),
            );
            assert_eq!(filtered["block"]["offset"], 0);
            assert_eq!(filtered["block"]["matchingLines"], 1);
            assert_eq!(filtered["block"]["lines"][0], rows[1]);
            assert!(
                snapshot(
                    &term,
                    &json!({"id":parent_id,"sourceLine":0,"query":"AFTER"})
                )["error"]
                    .is_string()
            );
            let context = snapshot(
                &term,
                &json!({"id":parent_id,"query":"AFTER","contextLines":1}),
            );
            assert_eq!(context["block"]["lines"], parent["lines"]);
        }
    }

    #[test]
    fn parent_segments_on_one_physical_row_merge_without_child_cells() {
        let mut term = Terminal::new(80, 24);
        hook(
            &mut term,
            json!({"hook":"preexec","context_id":"root","command":"parent"}),
        );
        term.process(b"\x1b[31mLEFT\x1b[0m");
        hook(
            &mut term,
            json!({"hook":"bootstrap.checking","context_id":"child","parent_context_id":"root"}),
        );
        hook(&mut term, json!({"hook":"precmd","context_id":"child"}));
        term.process(b"secret-child");
        hook(
            &mut term,
            json!({"hook":"bootstrap.resume","context_id":"root","retired_contexts":["child"],"exit_code":0}),
        );
        term.process(b"\x1b]8;;https://example.org\x1b\\RIGHT\x1b]8;;\x1b\\");
        hook(
            &mut term,
            json!({"hook":"command_finished","context_id":"root","exit_code":0}),
        );
        let snap = snapshot(&term, &json!({}));
        let block = &snap["blocks"][0];
        assert_eq!(block["totalLines"], 1);
        assert_eq!(block["sourceLineCount"], 1);
        assert_eq!(block["lines"].as_array().unwrap().len(), 1);
        assert_eq!(block["lines"][0]["text"], "LEFTRIGHT");
        assert_eq!(block["lines"][0]["index"], 0);
        assert_eq!(block["hyperlinks"][0]["start_col"], 4);
        assert_eq!(block["hyperlinks"][0]["end_col"], 9);
        assert_eq!(block["lines"][0]["style_runs"][0]["end"], 4);
    }

    #[test]
    fn resumed_parent_cr_keeps_its_own_tail_but_not_child_residue() {
        for (child_output, parent_output, expected) in [
            ("SECRET-CHILD\r", "OK", "OK"),
            ("SECRET-CHILD", "\rOK", "OK"),
            ("SECRET-CHILD\r", "abcdef\rOK", "OKcdef"),
            ("SECRET-CHILD\r", "中文\rOK", "OK文"),
            ("SECRET-CHILD\r", "e\u{301}", "é"),
            ("SECRET-CHILD\r", "🇨🇳", "🇨🇳"),
        ] {
            let mut term = Terminal::new(80, 24);
            hook(
                &mut term,
                json!({"hook":"preexec","context_id":"root","command":"parent"}),
            );
            hook(
                &mut term,
                json!({"hook":"bootstrap.checking","context_id":"child","parent_context_id":"root"}),
            );
            hook(&mut term, json!({"hook":"precmd","context_id":"child"}));
            term.process(child_output.as_bytes());
            hook(
                &mut term,
                json!({"hook":"bootstrap.resume","context_id":"root","retired_contexts":["child"],"exit_code":0}),
            );
            term.process(parent_output.as_bytes());
            hook(
                &mut term,
                json!({"hook":"command_finished","context_id":"root","exit_code":0}),
            );
            let snap = snapshot(&term, &json!({}));
            let rows = snap["blocks"][0]["lines"].as_array().unwrap();
            assert_eq!(rows.len(), 1, "{snap}");
            assert_eq!(
                rows[0]["text"], expected,
                "child={child_output:?}, parent={parent_output:?}"
            );
        }
    }

    #[test]
    fn ancestor_resume_only_assigns_known_direct_child_exit_code() {
        let mut term = Terminal::new(80, 24);
        context_command(&mut term, "root", "parent", false);
        hook(
            &mut term,
            json!({"hook":"bootstrap.checking","context_id":"child","parent_context_id":"root"}),
        );
        context_command(&mut term, "child", "inner-parent", false);
        hook(
            &mut term,
            json!({"hook":"bootstrap.checking","context_id":"deep","parent_context_id":"child"}),
        );
        context_command(&mut term, "deep", "unknown-child", false);
        term.process(b"CHILD\r\n");
        hook(
            &mut term,
            json!({"hook":"bootstrap.resume","context_id":"root","retired_contexts":["deep","child"],"exit_code":7}),
        );
        term.process(b"PARENT\r\n");
        hook(
            &mut term,
            json!({"hook":"command_finished","context_id":"root","exit_code":0}),
        );
        let snap = snapshot(&term, &json!({}));
        let blocks = snap["blocks"].as_array().unwrap();
        assert_eq!(blocks.len(), 3);
        assert_eq!(blocks[0]["exitCode"], 0);
        assert_eq!(blocks[0]["lines"][0]["text"], "PARENT");
        assert_eq!(blocks[1]["exitCode"], 7);
        assert_eq!(blocks[1]["lines"], json!([]));
        assert_eq!(blocks[2]["exitCode"], Value::Null);
        assert_eq!(blocks[2]["running"], false);
        assert_eq!(blocks[2]["lines"][0]["text"], "CHILD");
    }

    #[test]
    fn repeated_child_launches_bound_segments_and_shared_row_ownership() {
        let mut term = Terminal::with_scrollback(80, 24, 1000);
        hook(
            &mut term,
            json!({"hook":"preexec","context_id":"root","command":"parent"}),
        );
        let id = snapshot(&term, &json!({}))["blocks"][0]["id"].clone();
        for _ in 0..140 {
            term.process(b"PARENT\r\n");
            hook(
                &mut term,
                json!({"hook":"bootstrap.checking","context_id":"child","parent_context_id":"root"}),
            );
            hook(&mut term, json!({"hook":"precmd","context_id":"child"}));
            term.process(b"CHILD\r\n");
            hook(
                &mut term,
                json!({"hook":"bootstrap.resume","context_id":"root","retired_contexts":["child"],"exit_code":0}),
            );
        }
        hook(
            &mut term,
            json!({"hook":"command_finished","context_id":"root","exit_code":0}),
        );
        let output = term
            .get_zones()
            .iter()
            .find(|zone| {
                zone.command.as_deref() == Some("parent") && zone.zone_type == ZoneType::Output
            })
            .unwrap();
        assert_eq!(output.output_slices.len(), 128);
        assert!(output.output_boundary_rows.len() <= 258);
        let snap = snapshot(&term, &json!({"id":id}));
        assert_eq!(snap["block"]["evicted"], true);
        assert_eq!(snap["block"]["totalLines"], 128);
        assert!(
            snap["block"]["lines"]
                .as_array()
                .unwrap()
                .iter()
                .all(|line| line["text"] == "PARENT")
        );
    }

    #[test]
    fn overwritten_parent_boundary_is_evicted_instead_of_becoming_child_output() {
        let mut term = Terminal::new(80, 24);
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
        term.process(b"\rSECRET-CHILD\r");
        hook(
            &mut term,
            json!({"hook":"bootstrap.resume","context_id":"root","retired_contexts":["child"],"exit_code":0}),
        );
        hook(
            &mut term,
            json!({"hook":"command_finished","context_id":"root","exit_code":0}),
        );
        let snap = snapshot(&term, &json!({}));
        assert_eq!(snap["blocks"][0]["evicted"], true);
        assert_eq!(snap["blocks"][0]["totalLines"], 0);
        assert_eq!(snap["blocks"][0]["lines"], json!([]));
    }

    #[test]
    fn failed_child_bootstrap_diagnostics_remain_in_parent_command() {
        let mut term = Terminal::new(80, 24);
        context_command(&mut term, "root", "parent", false);
        term.process(b"BEFORE\r\n");
        hook(
            &mut term,
            json!({"hook":"bootstrap.checking","context_id":"failed-child","parent_context_id":"root"}),
        );
        term.process(b"shell: program not found\r\n");
        hook(
            &mut term,
            json!({"hook":"bootstrap.resume","context_id":"root","retired_contexts":["failed-child"],"exit_code":127}),
        );
        hook(
            &mut term,
            json!({"hook":"command_finished","context_id":"root","exit_code":127}),
        );
        let snap = snapshot(&term, &json!({}));
        let blocks = snap["blocks"].as_array().unwrap();
        assert_eq!(blocks.len(), 1);
        assert_eq!(blocks[0]["exitCode"], 127);
        assert_eq!(blocks[0]["running"], false);
        assert_eq!(blocks[0]["suspended"], false);
        assert_eq!(blocks[0]["lines"][0]["text"], "BEFORE");
        assert_eq!(blocks[0]["lines"][1]["text"], "shell: program not found");
    }

    #[test]
    fn confirmed_child_bootstrap_discards_installation_prompts_at_original_boundary() {
        let mut term = Terminal::new(80, 24);
        context_command(&mut term, "root", "parent", false);
        term.process(b"BEFORE\r\n");
        hook(
            &mut term,
            json!({"hook":"bootstrap.checking","context_id":"child","parent_context_id":"root"}),
        );
        term.process(b"bootstrap prompt> installation\r\ncontinuation>\r\n");
        hook(&mut term, json!({"hook":"precmd","context_id":"child"}));
        hook(
            &mut term,
            json!({"hook":"bootstrap.resume","context_id":"root","retired_contexts":["child"],"exit_code":0}),
        );
        term.process(b"AFTER\r\n");
        hook(
            &mut term,
            json!({"hook":"command_finished","context_id":"root","exit_code":0}),
        );
        let snap = snapshot(&term, &json!({}));
        let lines = snap["blocks"][0]["lines"].as_array().unwrap();
        assert_eq!(lines.len(), 2);
        assert_eq!(lines[0]["text"], "BEFORE");
        assert_eq!(lines[1]["text"], "AFTER");
    }

    #[test]
    fn repeated_failed_bootstrap_does_not_retain_temporary_boundary_rows() {
        let mut term = Terminal::with_scrollback(80, 24, 1000);
        hook(
            &mut term,
            json!({"hook":"preexec","context_id":"root","command":"parent"}),
        );
        for _ in 0..300 {
            hook(
                &mut term,
                json!({"hook":"bootstrap.checking","context_id":"child","parent_context_id":"root"}),
            );
            term.process(b"shell not found\r\n");
            hook(
                &mut term,
                json!({"hook":"bootstrap.resume","context_id":"root","retired_contexts":["child"],"exit_code":127}),
            );
        }
        let parent = term
            .get_zones()
            .iter()
            .find(|zone| zone.zone_type == ZoneType::Output)
            .unwrap();
        assert!(parent.output_boundary_rows.is_empty());
        let id = identity(parent);
        hook(
            &mut term,
            json!({"hook":"command_finished","context_id":"root","exit_code":127}),
        );
        let snap = snapshot(&term, &json!({"id":id}));
        assert_eq!(snap["block"]["totalLines"], 300);
        assert!(
            snap["block"]["lines"]
                .as_array()
                .unwrap()
                .iter()
                .all(|line| line["text"] == "shell not found")
        );
    }

    #[test]
    fn child_cursor_rewind_never_references_rows_before_parent_source_base() {
        let mut term = Terminal::new(80, 24);
        term.process(b"old command\r\n\r\n\r\n");
        hook(
            &mut term,
            json!({"hook":"preexec","context_id":"root","command":"parent"}),
        );
        term.process(b"BEFORE");
        hook(
            &mut term,
            json!({"hook":"bootstrap.checking","context_id":"child","parent_context_id":"root"}),
        );
        hook(&mut term, json!({"hook":"precmd","context_id":"child"}));
        term.process(b"\x1b[HCHILD");
        hook(
            &mut term,
            json!({"hook":"bootstrap.resume","context_id":"root","retired_contexts":["child"],"exit_code":0}),
        );
        term.process(b"AFTER");
        let running = snapshot(&term, &json!({}));
        assert_eq!(running["blocks"][0]["evicted"], true);
        hook(
            &mut term,
            json!({"hook":"command_finished","context_id":"root","exit_code":0}),
        );
        let snap = snapshot(&term, &json!({}));
        assert_eq!(snap["blocks"][0]["lines"].as_array().unwrap().len(), 1);
        assert_eq!(snap["blocks"][0]["lines"][0]["text"], "BEFORE");
        assert_eq!(snap["blocks"][0]["lines"][0]["index"], 0);
        assert_eq!(snap["blocks"][0]["lines"][0]["source_row"], 3);
    }

    #[test]
    fn child_repaint_inside_parent_portion_invalidates_that_portion() {
        for direct_fill in [false, true] {
            let mut term = Terminal::new(80, 24);
            hook(
                &mut term,
                json!({"hook":"preexec","context_id":"root","command":"parent"}),
            );
            term.process(b"PARENT-A\r\nPARENT-B\r\n");
            hook(
                &mut term,
                json!({"hook":"bootstrap.checking","context_id":"child","parent_context_id":"root"}),
            );
            hook(&mut term, json!({"hook":"precmd","context_id":"child"}));
            if direct_fill {
                term.fill_rectangle(0, 0, 0, 5, 'E');
            } else {
                term.process(b"\x1b[HCHILD");
            }
            term.process(b"\x1b[4;1H");
            hook(
                &mut term,
                json!({"hook":"bootstrap.resume","context_id":"root","retired_contexts":["child"],"exit_code":0}),
            );
            term.process(b"AFTER\r\n");
            hook(
                &mut term,
                json!({"hook":"command_finished","context_id":"root","exit_code":0}),
            );
            let snap = snapshot(&term, &json!({}));
            assert_eq!(snap["blocks"][0]["evicted"], true);
            assert_eq!(snap["blocks"][0]["lines"].as_array().unwrap().len(), 1);
            assert_eq!(snap["blocks"][0]["lines"][0]["text"], "AFTER");
        }
    }

    #[test]
    fn partial_top_scroll_invalidates_parent_below_the_scroll_region() {
        let mut term = Terminal::new(80, 24);
        term.process(b"\x1b[6;1H");
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
        term.process(b"\x1b[5;1HCHILD\x1b[1;3r\x1b[S\x1b[8;1H");
        hook(
            &mut term,
            json!({"hook":"bootstrap.resume","context_id":"root","retired_contexts":["child"],"exit_code":0}),
        );
        hook(
            &mut term,
            json!({"hook":"command_finished","context_id":"root","exit_code":0}),
        );
        let snap = snapshot(&term, &json!({}));
        assert_eq!(snap["blocks"][0]["lines"], json!([]), "{snap}");
        assert_eq!(snap["blocks"][0]["evicted"], true);
    }

    #[test]
    fn child_cell_moves_invalidate_parent_fragments_instead_of_leaking_child_text() {
        for edit in [
            "\r\x1b[6P",              // DCH
            "\r\x1b[6@",              // ICH
            "\r\x1b[4hX\x1b[4l",      // IRM
            "\x1b[1;1H\x1b[L",        // IL
            "\x1b[1;1H\x1b[M",        // DL
            "\x1b[T",                 // downward scroll
            "\x1b[1;3r\x1b[S",        // partial-region upward scroll
            "\x1b[1;1;1;6;1;1;7;1$v", // DECCRA
            "\x1b[88;1;1;1;6$x",      // DECFRA
        ] {
            let mut term = Terminal::new(80, 24);
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
            term.process(b"CHILD");
            term.process(edit.as_bytes());
            hook(
                &mut term,
                json!({"hook":"bootstrap.resume","context_id":"root","retired_contexts":["child"],"exit_code":0}),
            );
            hook(
                &mut term,
                json!({"hook":"command_finished","context_id":"root","exit_code":0}),
            );
            let snap = snapshot(&term, &json!({}));
            assert_eq!(snap["blocks"][0]["evicted"], true, "edit={edit:?}: {snap}");
            assert_eq!(
                snap["blocks"][0]["lines"],
                json!([]),
                "edit={edit:?}: {snap}"
            );
        }
    }

    #[test]
    fn segmented_output_paging_survives_child_scrollback_eviction() {
        let mut term = Terminal::with_scrollback(80, 4, 8);
        hook(
            &mut term,
            json!({"hook":"preexec","context_id":"root","command":"parent"}),
        );
        term.process(b"BEFORE\r\n");
        let id = snapshot(&term, &json!({}))["blocks"][0]["id"].clone();
        hook(
            &mut term,
            json!({"hook":"bootstrap.checking","context_id":"child","parent_context_id":"root"}),
        );
        context_command(&mut term, "child", "child", false);
        for _ in 0..30 {
            term.process(b"CHILD\r\n");
        }
        hook(
            &mut term,
            json!({"hook":"bootstrap.resume","context_id":"root","retired_contexts":["child"],"exit_code":7}),
        );
        term.process(b"AFTER-1\r\nAFTER-2\r\n");
        hook(
            &mut term,
            json!({"hook":"command_finished","context_id":"root","exit_code":0}),
        );
        let page = snapshot(&term, &json!({"id":id,"offset":0,"limit":1}));
        assert_eq!(page["block"]["evicted"], true);
        assert_eq!(page["block"]["totalLines"], 2);
        assert_eq!(page["block"]["lines"][0]["text"], "AFTER-1");
        assert_eq!(page["block"]["nextOffset"], 1);
        let next = snapshot(&term, &json!({"id":id,"offset":1,"limit":1}));
        let first = &page["block"]["lines"][0];
        let last = &next["block"]["lines"][0];
        assert_eq!(last["text"], "AFTER-2");
        assert_eq!(
            first["source_row"].as_u64().unwrap() - first["index"].as_u64().unwrap(),
            last["source_row"].as_u64().unwrap() - last["index"].as_u64().unwrap()
        );
        assert_eq!(
            snapshot(
                &term,
                &json!({"id":id,"sourceLine":last["index"],"query":"AFTER"})
            )["block"]["offset"],
            1
        );
        assert!(snapshot(&term, &json!({"id":id,"sourceLine":0}))["error"].is_string());
        assert_eq!(
            snapshot(&term, &json!({"id":id,"query":"CHILD"}))["block"]["matchingLines"],
            0
        );
    }
    #[test]
    fn boundaries_exclude_prompt_and_preserve_unterminated_output() {
        let mut term = Terminal::with_scrollback(80, 24, 100);
        command(&mut term, "printf hello", b"hello", 7);
        let snap = snapshot(&term, &json!({}));
        let block = &snap["blocks"][0];
        assert_eq!(block["command"], "printf hello");
        assert_eq!(block["lines"][0]["text"], "hello");
        assert_eq!(block["exitCode"], 7);
        assert_eq!(block["cwd"], "/project");
        assert_eq!(block["running"], false);
    }
    #[test]
    fn empty_output_and_multiline_command_are_not_guessed_from_screen() {
        let mut term = Terminal::new(80, 24);
        command(&mut term, "true\ntrue", b"", 0);
        let snap = snapshot(&term, &json!({}));
        assert_eq!(snap["blocks"][0]["command"], "true\ntrue");
        assert_eq!(snap["blocks"][0]["lines"], json!([]));
    }
    #[test]
    fn composer_limit_preserves_literal_command_after_json_and_hex_encoding() {
        let mut term = Terminal::new(80, 24);
        let text = format!("printf '%s' '{}'; true", "\\\"\t\n".repeat(16_379));
        let text = format!("{text}{}", " ".repeat(65_536 - text.len()));
        assert_eq!(text.len(), 65_536);
        hook(&mut term, json!({"hook":"precmd"}));
        hook(
            &mut term,
            json!({"hook":"preexec", "command":text,
            "submission_id":"compound-limit", "context_id":"ssh-context"}),
        );
        term.process(b"done\r\n");
        hook(&mut term, json!({"hook":"command_finished", "exit_code":0}));
        let snap = snapshot(&term, &json!({}));
        assert_eq!(snap["blocks"].as_array().unwrap().len(), 1);
        assert_eq!(snap["blocks"][0]["command"], text);
        assert_eq!(snap["blocks"][0]["submissionId"], "compound-limit");
        let page = snapshot(&term, &json!({"id":snap["blocks"][0]["id"]}));
        assert_eq!(page["block"]["command"], text);
        assert_eq!(page["block"]["lines"][0]["text"], "done");
    }
    #[test]
    fn oversized_command_and_hook_are_rejected_without_poisoning_next_block() {
        let mut term = Terminal::new(80, 24);
        for text in ["x".repeat(65_537), "\\".repeat(100_000)] {
            hook(&mut term, json!({"hook":"preexec", "command":text}));
            assert_eq!(snapshot(&term, &json!({}))["blocks"], json!([]));
        }
        command(&mut term, "printf recovered", b"recovered", 0);
        let snap = snapshot(&term, &json!({}));
        assert_eq!(snap["blocks"].as_array().unwrap().len(), 1);
        assert_eq!(snap["blocks"][0]["command"], "printf recovered");
    }
    #[test]
    fn filtering_is_reversible_with_context_and_invalid_regex() {
        let mut term = Terminal::new(80, 24);
        command(
            &mut term,
            "build",
            b"one\r\nERROR two\r\nthree\r\nfour\r\n",
            1,
        );
        let snap = snapshot(&term, &json!({}));
        let id = snap["blocks"][0]["id"].clone();
        let result = snapshot(&term, &json!({"id":id,"query":"error","contextLines":1}));
        assert_eq!(result["block"]["lines"].as_array().unwrap().len(), 3);
        assert_eq!(
            snapshot(&term, &json!({"id":id,"query":"[","regex":true}))["error"],
            "Invalid regular expression"
        );
        assert_eq!(snapshot(&term, &json!({"id":id}))["block"]["totalLines"], 4);
    }
    #[test]
    fn split_hook_and_alternate_screen_are_safe() {
        let mut term = Terminal::new(80, 24);
        let wire = format!(
            "\x1bPhook;{}\x1b\\",
            json!({"hook":"precmd"})
                .to_string()
                .bytes()
                .map(|b| format!("{b:02x}"))
                .collect::<String>()
        );
        for byte in wire.bytes() {
            term.process(&[byte]);
        }
        hook(&mut term, json!({"hook":"preexec","command":"sleep 1"}));
        assert_eq!(snapshot(&term, &json!({}))["blocks"][0]["running"], true);
        term.process(b"\x1b[?1049h");
        assert_eq!(snapshot(&term, &json!({}))["alternateScreen"], true);
    }

    #[test]
    fn main_screen_tui_clear_preserves_completed_blocks_without_repeating_history() {
        let mut term = Terminal::with_scrollback(80, 24, 100);
        command(&mut term, "ls", b"first\r\n", 0);
        command(&mut term, "ls", b"second\r\n", 0);
        let before = snapshot(&term, &json!({}))["blocks"].clone();
        hook(&mut term, json!({"hook":"preexec", "command":"top"}));
        term.process(b"\x1b[H\x1b[2JTasks: initial");
        let after = snapshot(&term, &json!({}));
        assert_eq!(
            &after["blocks"].as_array().unwrap()[..2],
            before.as_array().unwrap()
        );
        let retained = term.grid().scrollback_len();
        let absolute = term.grid().total_lines_scrolled();
        for _ in 0..5 {
            term.process(b"\x1b[H\x1b[2JTasks: redraw");
            assert_eq!(term.grid().scrollback_len(), retained);
            assert_eq!(term.grid().total_lines_scrolled(), absolute);
            let current = snapshot(&term, &json!({}));
            assert_eq!(
                &current["blocks"].as_array().unwrap()[..2],
                before.as_array().unwrap()
            );
        }
        hook(&mut term, json!({"hook":"command_finished", "exit_code":0}));
        term.process(b"\x1b[?1049h\x1b[2Jvim\x1b[?1049l");
        let returned = snapshot(&term, &json!({}));
        assert_eq!(
            &returned["blocks"].as_array().unwrap()[..2],
            before.as_array().unwrap()
        );
        assert_eq!(returned["blocks"][2]["command"], "top");
        assert_eq!(returned["blocks"][2]["exitCode"], 0);
    }

    #[test]
    fn display_clear_retention_obeys_history_limit_and_explicit_history_clear() {
        let mut term = Terminal::with_scrollback(80, 6, 8);
        for index in 0..8 {
            command(&mut term, &format!("printf {index}"), b"output\r\n", 0);
            term.process(b"\x1b[H\x1b[2J");
            assert!(term.grid().scrollback_len() <= 8);
            let floor = term.grid().total_lines_scrolled() - term.grid().scrollback_len();
            assert!(
                term.get_zones()
                    .iter()
                    .all(|z| z.is_open() || z.abs_row_end >= floor)
            );
        }
        term.process(b"\x1b[3J");
        assert_eq!(snapshot(&term, &json!({}))["blocks"], json!([]));

        let mut raw = Terminal::with_scrollback(80, 24, 100);
        raw.process(b"plain output\x1b[2J");
        assert_eq!(raw.grid().scrollback_len(), 0);
        let mut no_history = Terminal::with_scrollback(80, 24, 0);
        command(&mut no_history, "ls", b"no retained output\r\n", 0);
        no_history.process(b"\x1b[2J");
        assert_eq!(no_history.grid().scrollback_len(), 0);
        assert_eq!(snapshot(&no_history, &json!({}))["blocks"], json!([]));
    }

    #[test]
    fn wrapping_carriage_return_ansi_and_links_preserve_terminal_cells() {
        let mut term = Terminal::new(8, 24);
        command(
            &mut term,
            "print",
            b"hello   world\r\n\x1b[31mabcdefgh\x1b[0m",
            0,
        );
        let snap = snapshot(&term, &json!({}));
        let rows = snap["blocks"][0]["lines"].as_array().unwrap();
        assert_eq!(rows[0]["text"], "hello   ");
        assert_eq!(rows[0]["wrapped"], true);
        assert_eq!(rows[1]["text"], "world");
        assert_eq!(rows[2]["text"], "abcdefgh");
        assert!(rows[2]["style_runs"][0]["foreground"].is_string());

        let mut term = Terminal::new(80, 24);
        command(
            &mut term,
            "progress",
            b"abcdef\rOK\r\n\x1b]8;;https://example.org\x1b\\link\x1b]8;;\x1b\\",
            0,
        );
        let snap = snapshot(&term, &json!({}));
        assert_eq!(snap["blocks"][0]["lines"][0]["text"], "OKcdef");
        assert_eq!(
            snap["blocks"][0]["hyperlinks"][0]["uri"],
            "https://example.org"
        );
    }

    #[test]
    fn pages_search_and_eviction_report_the_retained_source() {
        let mut term = Terminal::with_scrollback(80, 8, 80);
        let output = (0..160)
            .map(|i| format!("line {i}\r\n"))
            .collect::<String>();
        command(&mut term, "print many", output.as_bytes(), 0);
        let snap = snapshot(&term, &json!({}));
        let id = snap["blocks"][0]["id"].clone();
        assert_eq!(snap["blocks"][0]["evicted"], true);
        let page = snapshot(&term, &json!({"id":id,"limit":3}));
        assert_eq!(page["block"]["lines"].as_array().unwrap().len(), 3);
        assert_eq!(page["block"]["nextOffset"], 3);
        let tail = snapshot(
            &term,
            &json!({"id":id,"query":"line","tail":true,"limit":1}),
        );
        assert_eq!(tail["block"]["lines"][0]["text"], "line 159");
        assert_eq!(
            snapshot(&term, &json!({"id":id,"query":"print many"}))["block"]["commandMatch"],
            true
        );
    }

    #[test]
    fn replay_preserves_execution_identity_and_elapsed_metadata() {
        let mut original = Terminal::new(80, 24);
        command(&mut original, "printf hello", b"hello", 0);
        let before = snapshot(&original, &json!({}));
        let mut replay = Terminal::new(40, 24);
        command(&mut replay, "printf hello", b"hello", 0);
        replay.restore_zone_metadata(original.get_zones());
        let after = snapshot(&replay, &json!({}));
        for key in ["id", "startedAt", "finishedAt", "cwd"] {
            assert_eq!(before["blocks"][0][key], after["blocks"][0][key]);
        }
        assert_eq!(after["blocks"][0]["columns"], 40);
    }
}
