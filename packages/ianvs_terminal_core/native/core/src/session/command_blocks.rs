//! Read-only command/output projection. Native grid coordinates remain the
//! source of truth; filters, folding, bookmarks and selection never edit it.
use super::*;
use par_term_emu_core_rust::zone::{Zone, ZoneType};
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

fn identity(zone: &Zone) -> String {
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
        cursor_row.max(zone.abs_row_start)
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
    let start = zone.abs_row_start.max(floor);
    let exclusive_end = if end_col == 0 && zone.is_closed() {
        end
    } else {
        end.saturating_add(1)
    };
    let count = exclusive_end.saturating_sub(start);
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
        let abs = start + line;
        let (cells, wrapped) = row_cells_for_visible_index(terminal, abs - floor);
        let cells = cells.unwrap_or_default();
        let from = if abs == zone.abs_row_start {
            zone.start_col.min(cells.len())
        } else {
            0
        };
        let to = if abs == end {
            end_col.min(cells.len())
        } else {
            cells.len()
        };
        let extracted = extract_row(cells.get(from..to.max(from)), wrapped && abs < end, &theme);
        (
            extracted,
            abs,
            extract_hyperlinks_for_row(terminal, cells.get(from..to.max(from)), line),
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
    let offset = if preview || request["tail"] == true {
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
        rows.push(json!({"index": line, "text": text, "wrapped": row.wrapped,
            "source_row": abs, "source_end_row": abs, "style_runs": row.style_runs}));
    }
    Ok(
        json!({"id": identity(zone), "command": zone.command, "cwd": zone.cwd,
        "startedAt": zone.timestamp, "finishedAt": zone.finished_at,
        "exitCode": zone.exit_code, "running": zone.is_open(),
        "totalLines": count, "matchingLines": total, "offset": offset,
        "commandMatch": regex.as_ref().is_some_and(|re| re.is_match(zone.command.as_deref().unwrap_or(""))),
        "nextOffset": (offset + rows.len() < total).then_some(offset + rows.len()),
        "evicted": zone.abs_row_start < floor, "columns": grid.cols(),
        "cursorLine": if zone.is_open() {cursor_row.saturating_sub(start)} else {0}, "cursorColumn": if zone.is_open() {terminal.cursor().col} else {0},
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
