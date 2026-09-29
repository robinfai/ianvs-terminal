//! Pure, bounded Fig-style completion. No host IO or exported pointer ABI.
include!("legacy.rs");

use std::sync::LazyLock;
use unicode_segmentation::UnicodeSegmentation;

pub const CATALOG_REVISION: &str = "ianvs-20260929-v1";
pub const MAX_TEXT_BYTES: usize = 65_536;
static CATALOG: LazyLock<SpecCatalog> = LazyLock::new(|| {
    serde_json::from_str(include_str!("catalog.json")).expect("reviewed bundled catalog")
});

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CompletionQuery {
    pub schema_version: u32,
    pub session_epoch: u64,
    pub target_id: String,
    pub context_revision: u64,
    pub editor_revision: u64,
    pub selection_revision: u64,
    pub catalog_revision: String,
    pub policy_revision: u64,
    pub text: String,
    pub cursor_utf16: usize,
    pub dialect: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CompletionBatch {
    pub schema_version: u32,
    pub query: CompletionQuery,
    pub status: &'static str,
    pub items: Vec<CompletionEdit>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CompletionEdit {
    pub item_id: String,
    pub label: String,
    pub detail: String,
    pub kind: String,
    pub source: String,
    pub replace_start_utf16: usize,
    pub replace_end_utf16: usize,
    pub new_text: String,
    pub final_cursor_utf16: usize,
    pub risk_hint: bool,
}

/// Reject offsets inside surrogate pairs and extended grapheme clusters.
pub fn is_boundary(text: &str, offset: usize) -> bool {
    let mut units = 0;
    for grapheme in text.graphemes(true) {
        if units == offset {
            return true;
        }
        units += grapheme.encode_utf16().count();
    }
    units == offset
}

impl CompletionQuery {
    pub fn validate(&self) -> Result<(), &'static str> {
        if self.schema_version != 1 || self.catalog_revision != CATALOG_REVISION {
            return Err("unsupported_version");
        }
        if self.target_id.is_empty()
            || self.target_id.len() > 256
            || self.target_id.chars().any(char::is_control)
            || self.text.len() > MAX_TEXT_BYTES
            || !is_boundary(&self.text, self.cursor_utf16)
            || !matches!(self.dialect.as_str(), "zsh" | "bash" | "fish" | "generic")
            || self
                .text
                .chars()
                .any(|c| c.is_control() && c != '\n' && c != '\t')
        {
            return Err("invalid_query");
        }
        Ok(())
    }
}

struct CompletionContext {
    parsed: ParsedCommandLine,
    start: usize,
    end: usize,
    quoted: bool,
}

fn context(query: &CompletionQuery) -> Option<CompletionContext> {
    let cursor_byte = byte_index_for_utf16_offset(&query.text, query.cursor_utf16);
    let before = &query.text[..cursor_byte];
    // Nested expansions and redirections need a fuller parser. Fail closed.
    if query.text.contains(['`', '$', '(', ')', '<', '>']) {
        return None;
    }
    let mut segment_start = 0;
    let mut quote = None;
    let mut escaped = false;
    for (index, ch) in before.char_indices() {
        if escaped {
            escaped = false;
            continue;
        }
        if ch == '\\' && quote != Some('\'') {
            escaped = true;
            continue;
        }
        if let Some(q) = quote {
            if q == ch {
                quote = None;
            }
        } else if ch == '\'' || ch == '"' {
            quote = Some(ch);
        } else if matches!(ch, '|' | ';' | '&' | '\n') {
            segment_start = index + ch.len_utf8();
        }
    }
    let segment = &before[segment_start..];
    let mut parsed = parse_command_line(segment, utf16_len(segment));
    while parsed.context_tokens.first().is_some_and(|token| {
        token.value.split_once('=').is_some_and(|(name, _)| {
            !name.is_empty()
                && name.chars().enumerate().all(|(i, c)| {
                    c == '_' || c.is_ascii_alphabetic() || (i > 0 && c.is_ascii_digit())
                })
        })
    }) {
        parsed.context_tokens.remove(0);
    }
    let start = utf16_len(&before[..segment_start]) + parsed.current_token.start;
    let mut end = query.cursor_utf16;
    let mut suffix_quote = quote;
    let mut suffix_escaped = escaped;
    for ch in query.text[cursor_byte..].chars() {
        if !suffix_escaped && suffix_quote.is_none() && (ch.is_whitespace() || "|;&".contains(ch)) {
            break;
        }
        end += ch.len_utf16();
        if suffix_escaped {
            suffix_escaped = false;
            continue;
        }
        if ch == '\\' && suffix_quote != Some('\'') {
            suffix_escaped = true;
        } else if suffix_quote == Some(ch) {
            suffix_quote = None;
        } else if suffix_quote.is_none() && (ch == '\'' || ch == '"') {
            suffix_quote = Some(ch);
        }
    }
    let raw_start = byte_index_for_utf16_offset(&query.text, start);
    let quoted = query.text[raw_start..].starts_with(['\'', '"']);
    Some(CompletionContext {
        parsed,
        start,
        end,
        quoted,
    })
}

/// Pure plan for the host's optional local provider. It contains no cwd or IO.
pub struct LocalContext {
    pub templates: Vec<String>,
    pub prefix: String,
    pub start: usize,
    pub end: usize,
    pub quoted: bool,
}

pub fn local_context(query: &CompletionQuery) -> Option<LocalContext> {
    query.validate().ok()?;
    if query.dialect != "zsh" || query.text.contains([';', '|', '&', '\n']) {
        return None;
    }
    let ctx = context(query)?;
    if ctx.parsed.context_tokens.iter().any(|t| {
        matches!(t.value.as_str(), "-C" | "--cwd" | "--prefix")
            || t.value.starts_with("--cwd=")
            || t.value.starts_with("--prefix=")
    }) {
        return None;
    }
    let root = find_spec(&ctx.parsed.context_tokens.first()?.value, &CATALOG)?;
    let trailing = &ctx.parsed.context_tokens[1..];
    let resolved = resolve_node(root, trailing);
    let mut templates = vec![];
    if let Some(arg) = option_expecting_argument(root, resolved.node, trailing) {
        templates.extend(names_of_template(arg.template.as_ref()));
    } else if !ctx.parsed.current_token.value.starts_with('-')
        || trailing.iter().any(|t| t.value == "--")
    {
        for arg in arg_specs_for_index(resolved.node.args.as_ref(), resolved.argument_tokens.len())
        {
            templates.extend(names_of_template(arg.template.as_ref()));
        }
        if resolved.node.args.is_none() {
            templates.extend(names_of_template(resolved.node.template.as_ref()));
        }
    }
    templates.retain(|t| matches!(*t, "files" | "filepaths" | "folders" | "packageScripts"));
    if templates.is_empty() {
        return None;
    }
    Some(LocalContext {
        templates: templates.into_iter().map(str::to_owned).collect(),
        prefix: ctx.parsed.current_token.value,
        start: ctx.start,
        end: ctx.end,
        quoted: ctx.quoted,
    })
}

/// Quote a literal token; never evaluate a host-provided filename or script.
pub fn quote_literal(value: &str, force: bool) -> String {
    if !force
        && !value.is_empty()
        && value
            .chars()
            .all(|c| c.is_alphanumeric() || "_./-".contains(c))
    {
        value.into()
    } else {
        format!("'{}'", value.replace('\'', "'\\''"))
    }
}

/// Query only the reviewed static catalog. Templates never cause host IO.
pub fn query(query: CompletionQuery) -> Result<CompletionBatch, &'static str> {
    query_with_aliases(query, &[])
}

/// Alias names are inserted literally. Their descriptions are display data,
/// never parsed, evaluated, or used to infer an effective working directory.
pub fn query_with_aliases(
    query: CompletionQuery,
    aliases: &[(String, String)],
) -> Result<CompletionBatch, &'static str> {
    query.validate()?;
    let Some(CompletionContext {
        parsed,
        start,
        end,
        quoted,
    }) = context(&query)
    else {
        return Ok(CompletionBatch {
            schema_version: 1,
            query,
            status: "unsupported_context",
            items: vec![],
        });
    };
    // Reuse the migrated matcher with normalized context but map its edit back
    // to the exact original span, preserving everything right of the token.
    let mut normalized = parsed
        .context_tokens
        .iter()
        .map(|t| quote_literal(&t.value, true))
        .collect::<Vec<_>>()
        .join(" ");
    if !normalized.is_empty() {
        normalized.push(' ');
    }
    normalized.push_str(&quote_literal(&parsed.current_token.value, true));
    let after_double_dash = parsed.context_tokens.iter().any(|t| t.value == "--");
    let response = complete_with_catalog(
        CompletionRequest {
            cursor_offset: Some(utf16_len(&normalized)),
            text: normalized,
            limit: Some(100),
            ..Default::default()
        },
        &CATALOG,
    );
    let mut items = vec![];
    if is_boundary(&query.text, start) && is_boundary(&query.text, end) {
        if parsed.context_tokens.is_empty() && query.dialect == "zsh" {
            for (name, value) in aliases.iter().take(64) {
                if !name.starts_with(&parsed.current_token.value)
                    || name.is_empty()
                    || name.len() > 128
                    || value.len() > 1024
                    || !name
                        .chars()
                        .all(|c| c.is_alphanumeric() || "_-".contains(c))
                    || value.chars().any(char::is_control)
                {
                    continue;
                }
                let new_text = quote_literal(name, quoted);
                items.push(CompletionEdit {
                    item_id: format!("shell:zsh:{start}:{end}:{name}"),
                    label: name.clone(),
                    detail: value.clone(),
                    kind: "alias".into(),
                    source: "shell:zsh".into(),
                    replace_start_utf16: start,
                    replace_end_utf16: end,
                    final_cursor_utf16: start + utf16_len(&new_text),
                    new_text,
                    risk_hint: false,
                });
            }
        }
        for item in response.items {
            if items.len() >= 100 {
                break;
            }
            if items.iter().any(|existing| existing.label == item.name) {
                continue;
            }
            if after_double_dash && item.kind.as_deref() == Some("option") {
                continue;
            }
            let new_text = if quoted {
                format!("'{}'", item.insert_text.replace('\'', "'\\''"))
            } else {
                item.insert_text
            };
            if new_text.chars().any(char::is_control) {
                continue;
            }
            let source = item.source.unwrap_or_else(|| "fig:static".into());
            items.push(CompletionEdit {
                item_id: format!("{source}:{start}:{end}:{new_text}"),
                label: item.display_name.unwrap_or(item.name),
                detail: item.description.unwrap_or_default(),
                kind: item.kind.unwrap_or_else(|| "argument".into()),
                source,
                replace_start_utf16: start,
                replace_end_utf16: end,
                final_cursor_utf16: start + utf16_len(&new_text),
                new_text,
                risk_hint: item.is_dangerous,
            });
        }
    }
    Ok(CompletionBatch {
        schema_version: 1,
        query,
        status: "ok",
        items,
    })
}

#[cfg(test)]
mod contract_tests {
    use super::*;
    fn q(text: &str, cursor: usize) -> CompletionQuery {
        CompletionQuery {
            schema_version: 1,
            session_epoch: 1,
            target_id: "local".into(),
            context_revision: 1,
            editor_revision: 1,
            selection_revision: 1,
            catalog_revision: CATALOG_REVISION.into(),
            policy_revision: 1,
            text: text.into(),
            cursor_utf16: cursor,
            dialect: "zsh".into(),
        }
    }
    #[test]
    fn edits_middle_without_consuming_suffix() {
        let batch = query(q("git che --help", 7)).unwrap();
        let edit = batch.items.iter().find(|i| i.label == "checkout").unwrap();
        assert_eq!((edit.replace_start_utf16, edit.replace_end_utf16), (4, 7));
    }
    #[test]
    fn aliases_are_literal_command_candidates_with_source_and_description() {
        let aliases = vec![
            ("gc".into(), "git checkout".into()),
            ("git".into(), "git --no-pager".into()),
        ];
        let batch = query_with_aliases(q("g --help", 1), &aliases).unwrap();
        let item = batch.items.iter().find(|i| i.label == "gc").unwrap();
        assert_eq!(
            (&*item.kind, &*item.detail, &*item.new_text),
            ("alias", "git checkout", "gc")
        );
        assert_eq!((item.replace_start_utf16, item.replace_end_utf16), (0, 1));
        assert_eq!(batch.items.iter().filter(|i| i.label == "git").count(), 1);
        let args = query_with_aliases(q("echo g", 6), &aliases).unwrap();
        assert!(!args.items.iter().any(|i| i.kind == "alias"));
        // No alias body expansion or evaluation, including shell expressions.
        let expressions = vec![("go".into(), "$(touch /tmp/never-execute)".into())];
        assert_eq!(
            query_with_aliases(q("go", 2), &expressions).unwrap().items[0].new_text,
            "go"
        );
        assert!(
            query_with_aliases(q("go --", 5), &expressions)
                .unwrap()
                .items
                .is_empty()
        );
    }
    #[test]
    fn completes_inside_token_and_quotes() {
        let batch = query(q("git 'chec' --help", 8)).unwrap();
        let edit = batch.items.iter().find(|i| i.label == "checkout").unwrap();
        assert_eq!(
            (
                edit.replace_start_utf16,
                edit.replace_end_utf16,
                edit.new_text.as_str()
            ),
            (4, 10, "'checkout'")
        );
    }
    #[test]
    fn assignment_and_pipeline_offsets() {
        let text = "echo hi | A=1 git che";
        let batch = query(q(text, text.len())).unwrap();
        assert!(
            batch
                .items
                .iter()
                .any(|i| i.label == "checkout" && i.replace_start_utf16 == 18)
        );
    }
    #[test]
    fn rejects_unicode_splits_and_unknown_fields() {
        assert!(query(q("😀", 1)).is_err());
        assert!(query(q("e\u{301}", 1)).is_err());
        let mut value = serde_json::to_value(q("git ", 4)).unwrap();
        value["unknown"] = true.into();
        assert!(serde_json::from_value::<CompletionQuery>(value).is_err());
    }
    #[test]
    fn never_evaluates_expansions() {
        assert_eq!(
            query(q("echo $(touch secret)", 20)).unwrap().status,
            "unsupported_context"
        );
    }
}
