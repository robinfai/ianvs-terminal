use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicUsize, Ordering};

static LAST_LEN: AtomicUsize = AtomicUsize::new(0);

#[unsafe(no_mangle)]
pub extern "C" fn ianvs_alloc(len: u32) -> u32 {
    allocate(len as usize)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ianvs_free(ptr: u32, len: u32) {
    if ptr == 0 || len == 0 {
        return;
    }
    unsafe {
        drop(Vec::from_raw_parts(ptr as *mut u8, 0, len as usize));
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ianvs_complete(ptr: u32, len: u32) -> u32 {
    if ptr == 0 || len == 0 {
        return write_output(br#"{"items":[]}"#);
    }
    let input = unsafe { std::slice::from_raw_parts(ptr as *const u8, len as usize) };
    let output = complete_json(input);
    write_output(output.as_bytes())
}

#[unsafe(no_mangle)]
pub extern "C" fn ianvs_last_len() -> u32 {
    LAST_LEN.load(Ordering::SeqCst) as u32
}

pub fn complete_json(input: &[u8]) -> String {
    match serde_json::from_slice::<CompletionRequest>(input) {
        Ok(request) => serde_json::to_string(&complete(request))
            .unwrap_or_else(|_| r#"{"items":[]}"#.to_owned()),
        Err(_) => r#"{"items":[]}"#.to_owned(),
    }
}

fn allocate(len: usize) -> u32 {
    if len == 0 {
        return 0;
    }
    let mut buffer = Vec::<u8>::with_capacity(len);
    let ptr = buffer.as_mut_ptr();
    std::mem::forget(buffer);
    ptr as u32
}

fn write_output(output: &[u8]) -> u32 {
    LAST_LEN.store(output.len(), Ordering::SeqCst);
    let ptr = allocate(output.len());
    if ptr != 0 {
        unsafe {
            std::ptr::copy_nonoverlapping(output.as_ptr(), ptr as *mut u8, output.len());
        }
    }
    ptr
}

#[derive(Debug, Deserialize, Default)]
#[serde(default, rename_all = "camelCase")]
struct CompletionRequest {
    text: String,
    cursor_offset: Option<usize>,
    recent_commands: Vec<String>,
    specs: SpecCatalog,
    host_templates: HashMap<String, Vec<HostSuggestion>>,
    limit: Option<usize>,
}

#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum SpecCatalog {
    List(Vec<CommandSpec>),
    Map(HashMap<String, CommandSpec>),
}

impl Default for SpecCatalog {
    fn default() -> Self {
        Self::List(Vec::new())
    }
}

impl SpecCatalog {
    fn values(&self) -> Vec<&CommandSpec> {
        match self {
            Self::List(items) => items.iter().collect(),
            Self::Map(items) => items.values().collect(),
        }
    }
}

#[derive(Debug, Deserialize, Clone, Default)]
#[serde(default, rename_all = "camelCase")]
struct CommandSpec {
    name: Option<StringOrVec>,
    display_name: Option<String>,
    description: Option<String>,
    options: Option<OneOrVec<OptionSpec>>,
    subcommands: Option<OneOrVec<Box<CommandSpec>>>,
    args: Option<OneOrVec<ArgSpec>>,
    template: Option<StringOrVec>,
    priority: Option<i32>,
    is_dangerous: bool,
}

#[derive(Debug, Deserialize, Clone, Default)]
#[serde(default, rename_all = "camelCase")]
struct OptionSpec {
    name: Option<StringOrVec>,
    description: Option<String>,
    args: Option<OneOrVec<ArgSpec>>,
    priority: Option<i32>,
    is_persistent: bool,
    is_dangerous: bool,
}

#[derive(Debug, Deserialize, Clone, Default)]
#[serde(default, rename_all = "camelCase")]
struct ArgSpec {
    name: Option<StringOrVec>,
    description: Option<String>,
    template: Option<StringOrVec>,
    suggestions: Option<OneOrVec<StaticSuggestion>>,
    #[serde(rename = "type")]
    kind: Option<String>,
    priority: Option<i32>,
    is_variadic: bool,
    is_dangerous: bool,
}

#[derive(Debug, Deserialize, Clone)]
#[serde(untagged)]
enum OneOrVec<T> {
    One(T),
    Vec(Vec<T>),
}

#[derive(Debug, Deserialize, Clone)]
#[serde(untagged)]
enum StringOrVec {
    String(String),
    Vec(Vec<String>),
}

impl StringOrVec {
    fn names(&self) -> Vec<&str> {
        match self {
            Self::String(value) => {
                if value.is_empty() {
                    Vec::new()
                } else {
                    vec![value.as_str()]
                }
            }
            Self::Vec(values) => values
                .iter()
                .filter(|value| !value.is_empty())
                .map(String::as_str)
                .collect(),
        }
    }

    fn first(&self) -> Option<&str> {
        self.names().into_iter().next()
    }
}

#[derive(Debug, Deserialize, Clone)]
#[serde(untagged)]
enum StaticSuggestion {
    Text(String),
    Object(StaticSuggestionObject),
}

#[derive(Debug, Deserialize, Clone, Default)]
#[serde(default, rename_all = "camelCase")]
struct StaticSuggestionObject {
    name: Option<StringOrVec>,
    display_name: Option<String>,
    description: Option<String>,
    #[serde(rename = "type")]
    kind: Option<String>,
    priority: Option<i32>,
    is_dangerous: bool,
}

#[derive(Debug, Deserialize, Clone, Default)]
#[serde(default, rename_all = "camelCase")]
struct HostSuggestion {
    name: String,
    insert_text: Option<String>,
    display_name: Option<String>,
    description: Option<String>,
    #[serde(rename = "type")]
    kind: Option<String>,
    source: Option<String>,
    priority: Option<i32>,
    is_dangerous: bool,
}

#[derive(Debug, Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct CompletionResponse {
    items: Vec<Suggestion>,
}

#[derive(Debug, Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct Suggestion {
    name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    display_name: Option<String>,
    insert_text: String,
    replace_start: usize,
    replace_end: usize,
    cursor_offset: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    description: Option<String>,
    #[serde(rename = "type", skip_serializing_if = "Option::is_none")]
    kind: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    source: Option<String>,
    priority: i32,
    is_dangerous: bool,
}

#[derive(Debug, Clone)]
struct Token {
    value: String,
    start: usize,
    end: usize,
}

#[derive(Debug)]
struct ParsedCommandLine {
    context_tokens: Vec<Token>,
    current_token: Token,
}

fn complete(request: CompletionRequest) -> CompletionResponse {
    let text_len = utf16_len(&request.text);
    let cursor_offset = request.cursor_offset.unwrap_or(text_len).min(text_len);
    let parsed = parse_command_line(&request.text, cursor_offset);
    let current_value = parsed.current_token.value.as_str();

    if parsed.context_tokens.is_empty() {
        return response_for_suggestions(
            command_suggestions(
                current_value,
                &parsed.current_token,
                &request.recent_commands,
                &request.specs,
            ),
            request.limit,
        );
    }

    let command_name = parsed.context_tokens[0].value.as_str();
    let Some(root_spec) = find_spec(command_name, &request.specs) else {
        return response_for_suggestions(
            recent_command_suggestions(
                current_value,
                &parsed.current_token,
                &request.recent_commands,
            ),
            request.limit,
        );
    };

    let trailing_tokens = &parsed.context_tokens[1..];
    let resolved = resolve_node(root_spec, trailing_tokens);
    let suggestions = if let Some(active_arg) =
        option_expecting_argument(root_spec, resolved.node, trailing_tokens)
    {
        suggestions_for_arg(
            active_arg,
            current_value,
            &parsed.current_token,
            &request.recent_commands,
            &request.host_templates,
            first_name(&root_spec.name),
            &[],
        )
    } else if current_value.starts_with('-') {
        option_suggestions(
            root_spec,
            resolved.node,
            current_value,
            &parsed.current_token,
        )
    } else {
        let mut items = subcommand_suggestions(
            resolved.node,
            current_value,
            &parsed.current_token,
            first_name(&root_spec.name),
        );
        items.extend(argument_suggestions(
            resolved.node,
            current_value,
            &parsed.current_token,
            &request.recent_commands,
            &request.host_templates,
            resolved.argument_tokens.len(),
            first_name(&root_spec.name),
            &resolved.argument_tokens,
        ));
        items
    };

    response_for_suggestions(suggestions, request.limit)
}

fn parse_command_line(text: &str, cursor_offset: usize) -> ParsedCommandLine {
    let end = byte_index_for_utf16_offset(text, cursor_offset);
    let before_cursor = &text[..end];
    let mut tokens = Vec::new();
    let mut token: Option<Token> = None;
    let mut quote: Option<char> = None;
    let mut escaped = false;
    let mut unit_index = 0;

    for char_value in before_cursor.chars() {
        let next_unit_index = unit_index + char_value.len_utf16();
        if token.is_none() {
            if char_value.is_whitespace() {
                unit_index = next_unit_index;
                continue;
            }
            token = Some(Token {
                value: String::new(),
                start: unit_index,
                end: unit_index,
            });
        }

        let current = token.as_mut().expect("token exists after initialization");
        if escaped {
            current.value.push(char_value);
            current.end = next_unit_index;
            escaped = false;
            unit_index = next_unit_index;
            continue;
        }
        if char_value == '\\' && quote != Some('\'') {
            current.end = next_unit_index;
            escaped = true;
            unit_index = next_unit_index;
            continue;
        }
        if let Some(quote_char) = quote {
            if char_value == quote_char {
                quote = None;
            } else {
                current.value.push(char_value);
            }
            current.end = next_unit_index;
            unit_index = next_unit_index;
            continue;
        }
        if char_value == '"' || char_value == '\'' {
            quote = Some(char_value);
            current.end = next_unit_index;
            unit_index = next_unit_index;
            continue;
        }
        if char_value.is_whitespace() {
            if let Some(finished) = token.take() {
                tokens.push(finished);
            }
            unit_index = next_unit_index;
            continue;
        }
        current.value.push(char_value);
        current.end = next_unit_index;
        unit_index = next_unit_index;
    }

    if let Some(current) = token {
        return ParsedCommandLine {
            context_tokens: tokens,
            current_token: current,
        };
    }

    ParsedCommandLine {
        context_tokens: tokens,
        current_token: Token {
            value: String::new(),
            start: cursor_offset,
            end: cursor_offset,
        },
    }
}

fn command_suggestions(
    prefix: &str,
    current_token: &Token,
    recent_commands: &[String],
    specs: &SpecCatalog,
) -> Vec<Suggestion> {
    let normalized_prefix = prefix.to_lowercase();
    let mut suggestions = Vec::new();
    for spec in specs.values() {
        let Some(name) = first_name(&spec.name) else {
            continue;
        };
        if !matches_prefix(name, &normalized_prefix) {
            continue;
        }
        suggestions.push(make_suggestion(SuggestionParts {
            name,
            insert_text: None,
            display_name: None,
            description: spec.description.clone(),
            kind: Some("subcommand".to_owned()),
            source: Some("fig:root".to_owned()),
            current_token,
            priority: 80,
            is_dangerous: spec.is_dangerous,
        }));
    }
    suggestions.extend(recent_command_suggestions(
        prefix,
        current_token,
        recent_commands,
    ));
    suggestions
}

fn recent_command_suggestions(
    prefix: &str,
    current_token: &Token,
    recent_commands: &[String],
) -> Vec<Suggestion> {
    let normalized_prefix = prefix.to_lowercase();
    let mut seen = HashSet::new();
    let mut suggestions = Vec::new();
    for command in recent_commands {
        let first = command.split_whitespace().next().unwrap_or("");
        if first.is_empty() {
            continue;
        }
        let command_key = command.to_lowercase();
        if seen.contains(&command_key) {
            continue;
        }
        if !normalized_prefix.is_empty() && !command_key.starts_with(&normalized_prefix) {
            continue;
        }
        seen.insert(command_key);
        suggestions.push(make_suggestion(SuggestionParts {
            name: command.as_str(),
            insert_text: None,
            display_name: None,
            description: Some("Recent command".to_owned()),
            kind: Some("history".to_owned()),
            source: Some("fig:history".to_owned()),
            current_token,
            priority: 30,
            is_dangerous: false,
        }));
        if suggestions.len() >= 6 {
            break;
        }
    }
    suggestions
}

fn option_suggestions(
    root_spec: &CommandSpec,
    node: &CommandSpec,
    prefix: &str,
    current_token: &Token,
) -> Vec<Suggestion> {
    let normalized_prefix = prefix.to_lowercase();
    let root_name = first_name(&root_spec.name).unwrap_or("command");
    let mut options: Vec<&OptionSpec> = refs(root_spec.options.as_ref())
        .into_iter()
        .filter(|option| option.is_persistent)
        .collect();
    options.extend(refs(node.options.as_ref()));

    let mut suggestions = Vec::new();
    for option in options {
        for name in names_of(&option.name) {
            if !matches_prefix(name, &normalized_prefix) {
                continue;
            }
            suggestions.push(make_suggestion(SuggestionParts {
                name,
                insert_text: None,
                display_name: None,
                description: option.description.clone(),
                kind: Some("option".to_owned()),
                source: Some(format!("fig:{root_name}")),
                current_token,
                priority: option.priority.unwrap_or(70),
                is_dangerous: option.is_dangerous,
            }));
        }
    }
    suggestions
}

fn subcommand_suggestions(
    node: &CommandSpec,
    prefix: &str,
    current_token: &Token,
    root_name: Option<&str>,
) -> Vec<Suggestion> {
    let normalized_prefix = prefix.to_lowercase();
    let source_name = root_name.unwrap_or("command");
    let mut suggestions = Vec::new();
    for subcommand in command_refs(node.subcommands.as_ref()) {
        for name in names_of(&subcommand.name) {
            if !matches_prefix(name, &normalized_prefix) {
                continue;
            }
            suggestions.push(make_suggestion(SuggestionParts {
                name,
                insert_text: None,
                display_name: subcommand.display_name.clone(),
                description: subcommand.description.clone(),
                kind: Some("subcommand".to_owned()),
                source: Some(format!("fig:{source_name}")),
                current_token,
                priority: subcommand.priority.unwrap_or(75),
                is_dangerous: subcommand.is_dangerous,
            }));
        }
    }
    suggestions
}

fn argument_suggestions(
    node: &CommandSpec,
    prefix: &str,
    current_token: &Token,
    recent_commands: &[String],
    host_templates: &HashMap<String, Vec<HostSuggestion>>,
    argument_index: usize,
    root_name: Option<&str>,
    argument_tokens: &[Token],
) -> Vec<Suggestion> {
    let effective_root_name = first_name(&node.name).or(root_name);
    let mut suggestions = Vec::new();
    for arg in arg_specs_for_index(node.args.as_ref(), argument_index) {
        suggestions.extend(suggestions_for_arg(
            arg,
            prefix,
            current_token,
            recent_commands,
            host_templates,
            effective_root_name,
            argument_tokens,
        ));
    }
    if node.args.is_none() {
        suggestions.extend(template_suggestions(
            node.template.as_ref(),
            prefix,
            current_token,
            recent_commands,
            host_templates,
            argument_tokens,
        ));
    }
    suggestions
}

fn suggestions_for_arg(
    arg: &ArgSpec,
    prefix: &str,
    current_token: &Token,
    recent_commands: &[String],
    host_templates: &HashMap<String, Vec<HostSuggestion>>,
    root_name: Option<&str>,
    argument_tokens: &[Token],
) -> Vec<Suggestion> {
    let mut suggestions = static_arg_suggestions(arg, prefix, current_token, root_name);
    suggestions.extend(template_suggestions(
        arg.template.as_ref(),
        prefix,
        current_token,
        recent_commands,
        host_templates,
        argument_tokens,
    ));
    suggestions
}

fn arg_specs_for_index(args: Option<&OneOrVec<ArgSpec>>, argument_index: usize) -> Vec<&ArgSpec> {
    let specs = refs(args);
    if specs.len() <= 1 {
        return specs;
    }
    if argument_index < specs.len() {
        return vec![specs[argument_index]];
    }
    specs
        .last()
        .copied()
        .filter(|last| last.is_variadic)
        .into_iter()
        .collect()
}

fn static_arg_suggestions(
    arg: &ArgSpec,
    prefix: &str,
    current_token: &Token,
    root_name: Option<&str>,
) -> Vec<Suggestion> {
    let normalized_prefix = prefix.to_lowercase();
    let source_name = root_name.unwrap_or("command");
    let mut suggestions = Vec::new();
    for suggestion in refs(arg.suggestions.as_ref()) {
        match suggestion {
            StaticSuggestion::Text(name) => {
                if matches_prefix(name, &normalized_prefix) {
                    suggestions.push(make_suggestion(SuggestionParts {
                        name,
                        insert_text: None,
                        display_name: None,
                        description: arg.description.clone(),
                        kind: Some(arg.kind.clone().unwrap_or_else(|| "arg".to_owned())),
                        source: Some(format!("fig:{source_name}")),
                        current_token,
                        priority: arg.priority.unwrap_or(55),
                        is_dangerous: arg.is_dangerous,
                    }));
                }
            }
            StaticSuggestion::Object(object) => {
                for name in names_of(&object.name) {
                    if !matches_prefix(name, &normalized_prefix) {
                        continue;
                    }
                    suggestions.push(make_suggestion(SuggestionParts {
                        name,
                        insert_text: None,
                        display_name: object.display_name.clone(),
                        description: object
                            .description
                            .clone()
                            .or_else(|| arg.description.clone()),
                        kind: object
                            .kind
                            .clone()
                            .or_else(|| arg.kind.clone())
                            .or_else(|| Some("arg".to_owned())),
                        source: Some(format!("fig:{source_name}")),
                        current_token,
                        priority: object.priority.or(arg.priority).unwrap_or(55),
                        is_dangerous: object.is_dangerous || arg.is_dangerous,
                    }));
                }
            }
        }
    }
    suggestions
}

fn template_suggestions(
    template: Option<&StringOrVec>,
    prefix: &str,
    current_token: &Token,
    recent_commands: &[String],
    host_templates: &HashMap<String, Vec<HostSuggestion>>,
    argument_tokens: &[Token],
) -> Vec<Suggestion> {
    let normalized_prefix = prefix.to_lowercase();
    let mut suggestions = Vec::new();
    for template_name in names_of_template(template) {
        if template_name == "history" {
            suggestions.extend(recent_command_suggestions(
                prefix,
                current_token,
                recent_commands,
            ));
            continue;
        }
        let Some(host_items) = host_templates.get(template_name) else {
            continue;
        };
        for item in host_items {
            if !matches_prefix(&item.name, &normalized_prefix) {
                continue;
            }
            suggestions.push(make_suggestion(SuggestionParts {
                name: item.name.as_str(),
                insert_text: item.insert_text.clone(),
                display_name: item.display_name.clone(),
                description: item.description.clone(),
                kind: item.kind.clone(),
                source: item.source.clone(),
                current_token,
                priority: item.priority.unwrap_or(50),
                is_dangerous: item.is_dangerous,
            }));
        }
    }
    let _ = argument_tokens;
    suggestions
}

struct ResolvedNode<'a> {
    node: &'a CommandSpec,
    argument_tokens: Vec<Token>,
}

fn resolve_node<'a>(root_spec: &'a CommandSpec, tokens: &[Token]) -> ResolvedNode<'a> {
    let mut node = root_spec;
    let mut argument_tokens = Vec::new();
    let mut index = 0;
    while index < tokens.len() {
        let token = &tokens[index];
        if token.value.is_empty() || token.value.starts_with('-') {
            let option = find_option(root_spec, node, &token.value);
            if option_takes_separate_argument(option, &token.value) && index + 1 < tokens.len() {
                index += 2;
            } else {
                index += 1;
            }
            continue;
        }

        let next = command_refs(node.subcommands.as_ref())
            .into_iter()
            .find(|candidate| names_of(&candidate.name).contains(&token.value.as_str()));
        if let Some(next_node) = next {
            node = next_node;
        } else {
            argument_tokens.push(token.clone());
        }
        index += 1;
    }
    ResolvedNode {
        node,
        argument_tokens,
    }
}

fn option_expecting_argument<'a>(
    root_spec: &'a CommandSpec,
    node: &'a CommandSpec,
    tokens: &[Token],
) -> Option<&'a ArgSpec> {
    let previous = tokens.last()?;
    if previous.value.contains('=') {
        return None;
    }
    let option = find_option(root_spec, node, &previous.value)?;
    if option_takes_separate_argument(Some(option), &previous.value) {
        refs(option.args.as_ref()).into_iter().next()
    } else {
        None
    }
}

fn find_option<'a>(
    root_spec: &'a CommandSpec,
    node: &'a CommandSpec,
    value: &str,
) -> Option<&'a OptionSpec> {
    let option_name = value.split_once('=').map_or(value, |(name, _)| name);
    for option in refs(root_spec.options.as_ref())
        .into_iter()
        .filter(|option| option.is_persistent)
        .chain(refs(node.options.as_ref()))
    {
        if names_of(&option.name).contains(&option_name) {
            return Some(option);
        }
    }
    None
}

fn option_takes_separate_argument(option: Option<&OptionSpec>, value: &str) -> bool {
    option.and_then(|item| item.args.as_ref()).is_some() && !value.contains('=')
}

fn find_spec<'a>(name: &str, specs: &'a SpecCatalog) -> Option<&'a CommandSpec> {
    specs
        .values()
        .into_iter()
        .find(|spec| names_of(&spec.name).contains(&name))
}

fn response_for_suggestions(
    suggestions: Vec<Suggestion>,
    limit: Option<usize>,
) -> CompletionResponse {
    let mut items: Vec<Suggestion> = suggestions
        .into_iter()
        .filter(|item| !has_unsafe_insert_text(&item.insert_text))
        .collect();
    items.sort_by(|left, right| right.priority.cmp(&left.priority));

    let mut seen = HashSet::new();
    let mut deduped = Vec::new();
    for item in items {
        let key = item.insert_text.clone();
        if seen.insert(key) {
            deduped.push(item);
        }
        if deduped.len() >= limit.unwrap_or(12) {
            break;
        }
    }
    CompletionResponse { items: deduped }
}

struct SuggestionParts<'a> {
    name: &'a str,
    insert_text: Option<String>,
    display_name: Option<String>,
    description: Option<String>,
    kind: Option<String>,
    source: Option<String>,
    current_token: &'a Token,
    priority: i32,
    is_dangerous: bool,
}

fn make_suggestion(parts: SuggestionParts<'_>) -> Suggestion {
    let insert_text = parts.insert_text.unwrap_or_else(|| parts.name.to_owned());
    Suggestion {
        name: parts.name.to_owned(),
        display_name: parts.display_name,
        insert_text: insert_text.clone(),
        replace_start: parts.current_token.start,
        replace_end: parts.current_token.end,
        cursor_offset: parts.current_token.start + utf16_len(&insert_text),
        description: parts.description,
        kind: parts.kind,
        source: parts.source,
        priority: parts.priority,
        is_dangerous: parts.is_dangerous,
    }
}

fn refs<T>(value: Option<&OneOrVec<T>>) -> Vec<&T> {
    match value {
        Some(OneOrVec::One(item)) => vec![item],
        Some(OneOrVec::Vec(items)) => items.iter().collect(),
        None => Vec::new(),
    }
}

fn command_refs(value: Option<&OneOrVec<Box<CommandSpec>>>) -> Vec<&CommandSpec> {
    match value {
        Some(OneOrVec::One(item)) => vec![item.as_ref()],
        Some(OneOrVec::Vec(items)) => items.iter().map(Box::as_ref).collect(),
        None => Vec::new(),
    }
}

fn names_of(value: &Option<StringOrVec>) -> Vec<&str> {
    value.as_ref().map(StringOrVec::names).unwrap_or_default()
}

fn names_of_template(value: Option<&StringOrVec>) -> Vec<&str> {
    value.map(StringOrVec::names).unwrap_or_default()
}

fn first_name(value: &Option<StringOrVec>) -> Option<&str> {
    value.as_ref().and_then(StringOrVec::first)
}

fn matches_prefix(name: &str, normalized_prefix: &str) -> bool {
    normalized_prefix.is_empty() || name.to_lowercase().starts_with(normalized_prefix)
}

fn has_unsafe_insert_text(value: &str) -> bool {
    value
        .chars()
        .any(|item| item == '\u{8}' || item == '\r' || item == '\n')
}

fn utf16_len(value: &str) -> usize {
    value.encode_utf16().count()
}

fn byte_index_for_utf16_offset(value: &str, offset: usize) -> usize {
    let mut units = 0;
    for (byte_index, char_value) in value.char_indices() {
        let next_units = units + char_value.len_utf16();
        if next_units > offset {
            return byte_index;
        }
        if next_units == offset {
            return byte_index + char_value.len_utf8();
        }
        units = next_units;
    }
    value.len()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;

    #[test]
    fn suggests_static_subcommands() {
        let output = complete_json(
            br#"{
              "text":"git che",
              "cursorOffset":7,
              "specs":[
                {
                  "name":"git",
                  "subcommands":[
                    {"name":"checkout","description":"Switch branches"},
                    {"name":"cherry-pick","description":"Apply commits"}
                  ]
                }
              ]
            }"#,
        );
        let value: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(value["items"][0]["name"], "checkout");
        assert_eq!(value["items"][0]["replaceStart"], 4);
        assert_eq!(value["items"][0]["replaceEnd"], 7);
    }

    #[test]
    fn uses_host_template_suggestions() {
        let output = complete_json(
            br#"{
              "text":"ls ./",
              "cursorOffset":5,
              "specs":[{"name":"ls","args":{"template":["filepaths","folders"]}}],
              "hostTemplates":{
                "filepaths":[{"name":"./alpha/","type":"folder","source":"fig:filepaths","priority":70}],
                "folders":[{"name":"./alpha/","type":"folder","source":"fig:folders","priority":70}]
              }
            }"#,
        );
        let value: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(value["items"][0]["name"], "./alpha/");
        assert_eq!(value["items"].as_array().unwrap().len(), 1);
    }

    #[test]
    fn dedupes_static_and_template_suggestions_by_insert_text() {
        let output = complete_json(
            br#"{
              "text":"npm run te",
              "cursorOffset":10,
              "specs":[{"name":"npm","subcommands":[{"name":"run","args":{"template":"packageScripts","suggestions":["test"]}}]}],
              "hostTemplates":{
                "packageScripts":[{"name":"test","type":"script","source":"fig:packageScripts","priority":68}]
              }
            }"#,
        );
        let value: Value = serde_json::from_str(&output).unwrap();
        let items = value["items"].as_array().unwrap();
        assert_eq!(items.len(), 1);
        assert_eq!(items[0]["name"], "test");
        assert_eq!(items[0]["type"], "script");
    }

    #[test]
    fn host_template_can_match_raw_name_and_insert_escaped_text() {
        let output = complete_json(
            br#"{
              "text":"cat ./My\\ ",
              "cursorOffset":10,
              "specs":[{"name":"cat","args":{"template":"files"}}],
              "hostTemplates":{
                "files":[{"name":"./My File.txt","insertText":"./My\\ File.txt","type":"file","source":"fig:files","priority":65}]
              }
            }"#,
        );
        let value: Value = serde_json::from_str(&output).unwrap();
        let items = value["items"].as_array().unwrap();
        assert_eq!(items.len(), 1);
        assert_eq!(items[0]["name"], "./My File.txt");
        assert_eq!(items[0]["insertText"], "./My\\ File.txt");
        assert_eq!(items[0]["replaceStart"], 4);
        assert_eq!(items[0]["replaceEnd"], 10);
    }
}
