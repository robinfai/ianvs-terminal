use serde::Serialize;
use serde_json::{Value, json};
use std::collections::HashMap;
use std::fs::{self, File, OpenOptions};
use std::hash::{Hash, Hasher};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{
    LazyLock, Mutex,
    atomic::{AtomicU64, Ordering},
};
use std::thread;
use std::time::{Duration, Instant};

const SPECS_JSON: &str = include_str!("fig_specs.json");
const KUBECTL_FAST_TIMEOUT: Duration = Duration::from_millis(450);
const KUBECTL_SLOW_TIMEOUT: Duration = Duration::from_millis(500);
const KUBECTL_CONTEXT_TTL: Duration = Duration::from_secs(30);
const KUBECTL_NAMESPACE_TTL: Duration = Duration::from_secs(15);
const KUBECTL_RESOURCE_TYPE_TTL: Duration = Duration::from_secs(60);
const KUBECTL_RESOURCE_NAME_TTL: Duration = Duration::from_secs(5);
const FALLBACK_KUBE_RESOURCES: &[&str] = &[
    "pods",
    "deployments",
    "services",
    "namespaces",
    "nodes",
    "configmaps",
    "secrets",
    "ingresses",
    "jobs",
    "cronjobs",
    "statefulsets",
    "daemonsets",
];
static KUBECTL_OUTPUT_CACHE: LazyLock<Mutex<HashMap<String, CachedKubectlOutput>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
static KUBECTL_OUTPUT_FILE_COUNTER: AtomicU64 = AtomicU64::new(0);
#[cfg(test)]
static TEST_KUBECTL_PATH: LazyLock<Mutex<Option<PathBuf>>> = LazyLock::new(|| Mutex::new(None));
#[cfg(test)]
static TEST_KUBECTL_LOCK: LazyLock<Mutex<()>> = LazyLock::new(|| Mutex::new(()));

pub fn complete_request_json(request_json: &str) -> String {
    let mut request = serde_json::from_str::<Value>(request_json).unwrap_or_else(|_| json!({}));
    if !request.is_object() {
        request = json!({});
    }
    request["specs"] = serde_json::from_str(SPECS_JSON).unwrap_or_else(|_| json!([]));
    request["hostTemplates"] =
        serde_json::to_value(collect_host_templates(&request)).unwrap_or_else(|_| json!({}));

    ianvs_fig_completion_wasm::complete_json(request.to_string().as_bytes())
}

#[derive(Debug, Clone)]
struct Token {
    value: String,
}

#[derive(Debug, Clone)]
struct ParsedCommandLine {
    context_tokens: Vec<Token>,
    current_value: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct HostSuggestion {
    name: String,
    #[serde(rename = "insertText", skip_serializing_if = "Option::is_none")]
    insert_text: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    description: Option<String>,
    #[serde(rename = "type", skip_serializing_if = "Option::is_none")]
    kind: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    source: Option<String>,
    priority: i32,
}

#[derive(Debug)]
struct PathEntrySuggestion {
    name: String,
    is_dir: bool,
    hidden: bool,
}

#[derive(Debug, Clone, Copy)]
enum PathTemplateKind {
    Filepaths,
    Folders,
    Files,
}

#[derive(Debug, Clone, Default)]
struct KubectlTemplateNeeds {
    contexts: bool,
    namespaces: bool,
    resource_types: bool,
    resource_names_for: Option<String>,
    inline_resource_name_prefix: Option<String>,
    pod_names: bool,
    namespace: Option<String>,
    context: Option<String>,
    all_namespaces: bool,
}

#[derive(Debug, Clone)]
struct CachedKubectlOutput {
    value: String,
    expires_at: Instant,
}

#[derive(Debug, Clone)]
struct KubectlExecutionContext {
    cwd: PathBuf,
    environment: Vec<(String, String)>,
}

#[derive(Debug, Clone, Copy)]
struct KubectlLineSuggestionStyle {
    description: &'static str,
    kind: &'static str,
    source: &'static str,
    priority: i32,
}

#[derive(Debug, Clone, Copy)]
struct KubectlJsonSuggestionStyle<'a> {
    kind: &'a str,
    priority: i32,
    insert_prefix: Option<&'a str>,
}

#[derive(Debug, Clone)]
struct KubectlQuery<'a> {
    args: Vec<String>,
    timeout: Duration,
    ttl: Duration,
    context: &'a KubectlExecutionContext,
}

fn kubectl_query<'a>(
    args: Vec<String>,
    timeout: Duration,
    ttl: Duration,
    context: &'a KubectlExecutionContext,
) -> KubectlQuery<'a> {
    KubectlQuery {
        args,
        timeout,
        ttl,
        context,
    }
}

fn collect_host_templates(request: &Value) -> Value {
    let text = request
        .get("text")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let cursor_offset = request
        .get("cursorOffset")
        .and_then(Value::as_u64)
        .map(|value| value as usize)
        .unwrap_or_else(|| text.encode_utf16().count());
    let cwd = request
        .get("cwd")
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")));
    let kubectl_context = KubectlExecutionContext {
        cwd: cwd.clone(),
        environment: environment_variables(request),
    };
    let parsed = parse_command_line(text, cursor_offset.min(text.encode_utf16().count()));
    let prefix = parsed.current_value.as_str();

    let mut host_templates = json!({
        "filepaths": path_template_suggestions(&cwd, prefix, PathTemplateKind::Filepaths),
        "folders": path_template_suggestions(&cwd, prefix, PathTemplateKind::Folders),
        "files": path_template_suggestions(&cwd, prefix, PathTemplateKind::Files),
    });

    let root_command = parsed
        .context_tokens
        .first()
        .map(|token| token.value.as_str());
    if matches!(root_command, Some("npm" | "pnpm" | "yarn")) {
        host_templates["packageScripts"] = json!(package_script_suggestions(&cwd, prefix));
    }
    if matches!(root_command, Some("kubectl" | "k")) {
        let needs = kubectl_template_needs(&parsed);
        if needs.contexts {
            host_templates["kubeContexts"] = kubectl_line_suggestions(
                kubectl_query(
                    kubectl_args(&needs, &["config", "get-contexts", "-o", "name"], false),
                    KUBECTL_FAST_TIMEOUT,
                    KUBECTL_CONTEXT_TTL,
                    &kubectl_context,
                ),
                prefix,
                KubectlLineSuggestionStyle {
                    description: "Kubernetes context",
                    kind: "context",
                    source: "fig:kubectl",
                    priority: 66,
                },
            );
        }
        if needs.namespaces {
            host_templates["kubeNamespaces"] = kubectl_json_item_suggestions(
                kubectl_query(
                    kubectl_args(&needs, &["get", "namespaces", "-o", "json"], false),
                    KUBECTL_SLOW_TIMEOUT,
                    KUBECTL_NAMESPACE_TTL,
                    &kubectl_context,
                ),
                prefix,
                KubectlJsonSuggestionStyle {
                    kind: "namespace",
                    priority: 66,
                    insert_prefix: None,
                },
                |_, _| "Kubernetes namespace".to_owned(),
            );
        }
        if needs.resource_types {
            let inline_resource_names = if let Some(resource) = needs.resource_names_for.as_deref()
                && let Some(inline_prefix) = needs.inline_resource_name_prefix.as_deref()
            {
                let args = kubectl_args(&needs, &["get", resource, "-o", "json"], true);
                Some(kubectl_json_item_suggestions(
                    kubectl_query(
                        args,
                        KUBECTL_SLOW_TIMEOUT,
                        KUBECTL_RESOURCE_NAME_TTL,
                        &kubectl_context,
                    ),
                    prefix,
                    KubectlJsonSuggestionStyle {
                        kind: "resource",
                        priority: 58,
                        insert_prefix: Some(inline_prefix),
                    },
                    |item, kind| {
                        item.get("metadata")
                            .and_then(|metadata| metadata.get("namespace"))
                            .and_then(Value::as_str)
                            .map(|namespace| format!("{kind} in {namespace}"))
                            .unwrap_or_else(|| kind.to_owned())
                    },
                ))
            } else {
                None
            };
            let mut resource_types = inline_resource_names.unwrap_or_else(|| {
                kubectl_line_suggestions(
                    kubectl_query(
                        kubectl_args(
                            &needs,
                            &["api-resources", "--verbs=list", "-o", "name"],
                            false,
                        ),
                        KUBECTL_FAST_TIMEOUT,
                        KUBECTL_RESOURCE_TYPE_TTL,
                        &kubectl_context,
                    ),
                    prefix,
                    KubectlLineSuggestionStyle {
                        description: "Kubernetes resource type",
                        kind: "resource",
                        source: "fig:kubectl",
                        priority: 64,
                    },
                )
            });
            if resource_types.as_array().is_none_or(Vec::is_empty)
                && needs.inline_resource_name_prefix.is_none()
            {
                let normalized_prefix = prefix.to_lowercase();
                resource_types = json!(
                    FALLBACK_KUBE_RESOURCES
                        .iter()
                        .filter(|name| matches_prefix(name, &normalized_prefix))
                        .map(|name| HostSuggestion {
                            name: (*name).to_owned(),
                            insert_text: None,
                            description: Some("Kubernetes resource type".to_owned()),
                            kind: Some("resource".to_owned()),
                            source: Some("fig:kubectl".to_owned()),
                            priority: 50,
                        })
                        .collect::<Vec<_>>()
                );
            }
            host_templates["kubeResourceTypes"] = resource_types;
        }
        if let Some(resource) = needs.resource_names_for.as_deref() {
            let args = kubectl_args(&needs, &["get", resource, "-o", "json"], true);
            host_templates["kubeResourceNames"] = kubectl_json_item_suggestions(
                kubectl_query(
                    args,
                    KUBECTL_SLOW_TIMEOUT,
                    KUBECTL_RESOURCE_NAME_TTL,
                    &kubectl_context,
                ),
                prefix,
                KubectlJsonSuggestionStyle {
                    kind: "resource",
                    priority: 58,
                    insert_prefix: None,
                },
                |item, kind| {
                    item.get("metadata")
                        .and_then(|metadata| metadata.get("namespace"))
                        .and_then(Value::as_str)
                        .map(|namespace| format!("{kind} in {namespace}"))
                        .unwrap_or_else(|| kind.to_owned())
                },
            );
        }
        if needs.pod_names {
            host_templates["kubePodNames"] = kubectl_json_item_suggestions(
                kubectl_query(
                    kubectl_args(&needs, &["get", "pods", "-o", "json"], true),
                    KUBECTL_SLOW_TIMEOUT,
                    KUBECTL_RESOURCE_NAME_TTL,
                    &kubectl_context,
                ),
                prefix,
                KubectlJsonSuggestionStyle {
                    kind: "pod",
                    priority: 62,
                    insert_prefix: None,
                },
                |item, _| {
                    item.get("metadata")
                        .and_then(|metadata| metadata.get("namespace"))
                        .and_then(Value::as_str)
                        .map(|namespace| format!("Pod in {namespace}"))
                        .unwrap_or_else(|| "Kubernetes pod".to_owned())
                },
            );
        }
    }

    host_templates
}

fn parse_command_line(text: &str, cursor_offset: usize) -> ParsedCommandLine {
    let end = byte_index_for_utf16_offset(text, cursor_offset);
    let before_cursor = &text[..end];
    let mut tokens = Vec::new();
    let mut token: Option<String> = None;
    let mut quote: Option<char> = None;
    let mut escaped = false;

    for char_value in before_cursor.chars() {
        if token.is_none() {
            if char_value.is_whitespace() {
                continue;
            }
            token = Some(String::new());
        }

        let current = token.as_mut().expect("token exists after initialization");
        if escaped {
            current.push(char_value);
            escaped = false;
            continue;
        }
        if char_value == '\\' && quote != Some('\'') {
            escaped = true;
            continue;
        }
        if let Some(quote_char) = quote {
            if char_value == quote_char {
                quote = None;
            } else {
                current.push(char_value);
            }
            continue;
        }
        if char_value == '"' || char_value == '\'' {
            quote = Some(char_value);
            continue;
        }
        if char_value.is_whitespace() {
            if let Some(value) = token.take() {
                tokens.push(Token { value });
            }
            continue;
        }
        current.push(char_value);
    }

    if let Some(value) = token {
        ParsedCommandLine {
            context_tokens: tokens,
            current_value: value,
        }
    } else {
        ParsedCommandLine {
            context_tokens: tokens,
            current_value: String::new(),
        }
    }
}

fn environment_variables(request: &Value) -> Vec<(String, String)> {
    let mut variables = request
        .get("environmentVariables")
        .and_then(Value::as_object)
        .into_iter()
        .flat_map(|items| items.iter())
        .filter_map(|(key, value)| {
            let value = value.as_str()?;
            if key.is_empty() || key.contains('\0') || value.contains('\0') {
                return None;
            }
            Some((key.clone(), value.to_owned()))
        })
        .collect::<Vec<_>>();
    variables.sort_by(|left, right| left.0.cmp(&right.0));
    variables
}

fn path_template_suggestions(
    cwd: &Path,
    prefix: &str,
    kind: PathTemplateKind,
) -> Vec<HostSuggestion> {
    let (directory_prefix, base) = split_path_prefix(prefix);
    let directory = cwd.join(if directory_prefix.is_empty() {
        "."
    } else {
        directory_prefix.as_str()
    });
    let normalized_base = base.to_lowercase();
    let mut entries = match fs::read_dir(directory) {
        Ok(entries) => entries
            .filter_map(Result::ok)
            .filter_map(|entry| {
                let name = entry.file_name().to_string_lossy().into_owned();
                let file_type = entry.file_type().ok()?;
                let is_dir = file_type.is_dir();
                let include = match kind {
                    PathTemplateKind::Filepaths => true,
                    PathTemplateKind::Folders => is_dir,
                    PathTemplateKind::Files => true,
                };
                if !include {
                    return None;
                }
                if !normalized_base.is_empty() && !name.to_lowercase().starts_with(&normalized_base)
                {
                    return None;
                }
                Some(PathEntrySuggestion {
                    hidden: name.starts_with('.'),
                    name,
                    is_dir,
                })
            })
            .collect::<Vec<_>>(),
        Err(_) => return Vec::new(),
    };
    entries.sort_by(|left, right| {
        path_entry_rank(kind, left)
            .cmp(&path_entry_rank(kind, right))
            .then_with(|| left.hidden.cmp(&right.hidden))
            .then_with(|| left.name.cmp(&right.name))
    });
    entries
        .into_iter()
        .take(16)
        .map(|entry| {
            let suffix = if entry.is_dir { "/" } else { "" };
            let name = format!("{directory_prefix}{}{suffix}", entry.name);
            let insert_text = shell_escape_unquoted(&name);
            let insert_text = (insert_text != name).then_some(insert_text);
            HostSuggestion {
                name,
                insert_text,
                description: Some(if entry.is_dir { "Folder" } else { "File" }.to_owned()),
                kind: Some(if entry.is_dir { "folder" } else { "file" }.to_owned()),
                source: Some(
                    match kind {
                        PathTemplateKind::Filepaths => "fig:filepaths",
                        PathTemplateKind::Folders => "fig:folders",
                        PathTemplateKind::Files => "fig:files",
                    }
                    .to_owned(),
                ),
                priority: match kind {
                    PathTemplateKind::Filepaths if entry.is_dir => 70,
                    PathTemplateKind::Filepaths => 45,
                    PathTemplateKind::Folders => 70,
                    PathTemplateKind::Files if entry.is_dir => 40,
                    PathTemplateKind::Files => 65,
                },
            }
        })
        .collect()
}

fn path_entry_rank(kind: PathTemplateKind, entry: &PathEntrySuggestion) -> u8 {
    match kind {
        PathTemplateKind::Files if !entry.is_dir => 0,
        PathTemplateKind::Files => 1,
        PathTemplateKind::Filepaths | PathTemplateKind::Folders if entry.is_dir => 0,
        PathTemplateKind::Filepaths | PathTemplateKind::Folders => 1,
    }
}

fn split_path_prefix(prefix: &str) -> (String, String) {
    match prefix.rfind('/') {
        Some(slash) => (prefix[..=slash].to_owned(), prefix[slash + 1..].to_owned()),
        None => (String::new(), prefix.to_owned()),
    }
}

fn package_script_suggestions(cwd: &Path, prefix: &str) -> Vec<HostSuggestion> {
    let Some(package_json) = nearest_package_json(cwd) else {
        return Vec::new();
    };
    let Ok(contents) = fs::read_to_string(package_json) else {
        return Vec::new();
    };
    let Ok(value) = serde_json::from_str::<Value>(&contents) else {
        return Vec::new();
    };
    let Some(scripts) = value.get("scripts").and_then(Value::as_object) else {
        return Vec::new();
    };
    let normalized_prefix = prefix.to_lowercase();
    let mut names = scripts
        .keys()
        .filter(|name| matches_prefix(name, &normalized_prefix))
        .cloned()
        .collect::<Vec<_>>();
    names.sort();
    names
        .into_iter()
        .take(16)
        .map(|name| HostSuggestion {
            insert_text: Some(shell_escape_unquoted(&name)).filter(|value| value != &name),
            name,
            description: Some("package.json script".to_owned()),
            kind: Some("script".to_owned()),
            source: Some("fig:packageScripts".to_owned()),
            priority: 68,
        })
        .collect()
}

fn shell_escape_unquoted(value: &str) -> String {
    let mut escaped = String::with_capacity(value.len());
    for (index, char_value) in value.chars().enumerate() {
        if shell_needs_escape(char_value, index == 0) {
            escaped.push('\\');
        }
        escaped.push(char_value);
    }
    escaped
}

fn shell_needs_escape(value: char, at_start: bool) -> bool {
    value.is_whitespace()
        || matches!(
            value,
            '\\' | '\''
                | '"'
                | '`'
                | '$'
                | '&'
                | '|'
                | ';'
                | '<'
                | '>'
                | '('
                | ')'
                | '['
                | ']'
                | '{'
                | '}'
                | '*'
                | '?'
                | '!'
        )
        || (at_start && matches!(value, '#' | '~'))
}

fn nearest_package_json(cwd: &Path) -> Option<PathBuf> {
    let mut directory = if cwd.is_file() {
        cwd.parent()?.to_path_buf()
    } else {
        cwd.to_path_buf()
    };
    loop {
        let candidate = directory.join("package.json");
        if candidate.is_file() {
            return Some(candidate);
        }
        if is_package_search_boundary(&directory) {
            return None;
        }
        if !directory.pop() {
            return None;
        }
    }
}

fn is_package_search_boundary(directory: &Path) -> bool {
    if directory.join(".git").exists() {
        return true;
    }
    std::env::var_os("HOME").is_some_and(|home| directory == Path::new(&home))
}

fn kubectl_template_needs(parsed: &ParsedCommandLine) -> KubectlTemplateNeeds {
    let mut needs = KubectlTemplateNeeds::default();
    apply_kubectl_scope(&mut needs, &parsed.context_tokens[1..]);
    if parsed.current_value.starts_with('-') {
        return needs;
    }

    if let Some(option) = parsed
        .context_tokens
        .last()
        .and_then(|token| kubectl_option_template(token.value.as_str()))
    {
        match option {
            "kubeContexts" => needs.contexts = true,
            "kubeNamespaces" => needs.namespaces = true,
            _ => {}
        }
        return needs;
    }

    let command_tokens = kubectl_non_option_tokens(&parsed.context_tokens[1..]);
    match command_tokens.as_slice() {
        [] => {}
        ["get" | "describe" | "delete" | "scale"] => {
            needs.resource_types = true;
            if let Some(resource) = normalize_kubectl_resource(parsed.current_value.as_str()) {
                needs.resource_names_for = Some(resource.to_owned());
                needs.inline_resource_name_prefix = Some(parsed.current_value.clone());
            }
        }
        ["get" | "describe" | "delete" | "scale", resource, ..] => {
            if let Some(resource) = normalize_kubectl_resource(resource) {
                needs.resource_names_for = Some(resource.to_owned());
            }
        }
        ["explain"] => needs.resource_types = true,
        ["logs" | "exec" | "port-forward", ..] => needs.pod_names = true,
        ["config", "use-context" | "set-context"] => needs.contexts = true,
        _ => {}
    }
    needs
}

fn apply_kubectl_scope(needs: &mut KubectlTemplateNeeds, tokens: &[Token]) {
    let mut index = 0;
    while index < tokens.len() {
        let value = tokens[index].value.as_str();
        if value == "-A" || value == "--all-namespaces" {
            needs.all_namespaces = true;
            index += 1;
            continue;
        }
        if let Some(namespace) = value.strip_prefix("--namespace=") {
            if !namespace.is_empty() {
                needs.namespace = Some(namespace.to_owned());
            }
            index += 1;
            continue;
        }
        if let Some(context) = value.strip_prefix("--context=") {
            if !context.is_empty() {
                needs.context = Some(context.to_owned());
            }
            index += 1;
            continue;
        }
        if matches!(value, "-n" | "--namespace") && index + 1 < tokens.len() {
            needs.namespace = Some(tokens[index + 1].value.clone());
            index += 2;
            continue;
        }
        if value == "--context" && index + 1 < tokens.len() {
            needs.context = Some(tokens[index + 1].value.clone());
            index += 2;
            continue;
        }
        index += 1;
    }
}

fn kubectl_args(
    needs: &KubectlTemplateNeeds,
    tail: &[&str],
    include_namespace: bool,
) -> Vec<String> {
    let mut args = Vec::new();
    if let Some(context) = needs.context.as_deref().filter(|value| !value.is_empty()) {
        args.push("--context".to_owned());
        args.push(context.to_owned());
    }
    args.extend(tail.iter().map(|value| (*value).to_owned()));
    if include_namespace {
        if needs.all_namespaces {
            args.push("-A".to_owned());
        } else if let Some(namespace) = needs
            .namespace
            .as_deref()
            .filter(|value| !value.trim().is_empty())
        {
            args.push("-n".to_owned());
            args.push(namespace.to_owned());
        }
    }
    args
}

fn normalize_kubectl_resource(value: &str) -> Option<&'static str> {
    match value {
        "po" | "pod" | "pods" => Some("pods"),
        "deploy" | "deployment" | "deployments" | "deployments.apps" => Some("deployments"),
        "svc" | "service" | "services" => Some("services"),
        "ns" | "namespace" | "namespaces" => Some("namespaces"),
        "cm" | "configmap" | "configmaps" => Some("configmaps"),
        "secret" | "secrets" => Some("secrets"),
        "ing" | "ingress" | "ingresses" => Some("ingresses"),
        "job" | "jobs" => Some("jobs"),
        "cronjob" | "cronjobs" => Some("cronjobs"),
        "sts" | "statefulset" | "statefulsets" => Some("statefulsets"),
        "ds" | "daemonset" | "daemonsets" => Some("daemonsets"),
        "node" | "nodes" | "no" => Some("nodes"),
        _ => None,
    }
}

fn kubectl_non_option_tokens(tokens: &[Token]) -> Vec<&str> {
    let mut values = Vec::new();
    let mut index = 0;
    while index < tokens.len() {
        let value = tokens[index].value.as_str();
        if value.starts_with('-') {
            index += if kubectl_option_takes_value(value) && index + 1 < tokens.len() {
                2
            } else {
                1
            };
            continue;
        }
        values.push(value);
        index += 1;
    }
    values
}

fn kubectl_option_template(value: &str) -> Option<&'static str> {
    let option_name = value.split_once('=').map_or(value, |(name, _)| name);
    match option_name {
        "-n" | "--namespace" => Some("kubeNamespaces"),
        "--context" => Some("kubeContexts"),
        _ => None,
    }
}

fn kubectl_option_takes_value(value: &str) -> bool {
    let option_name = value.split_once('=').map_or(value, |(name, _)| name);
    matches!(
        option_name,
        "-n" | "--namespace" | "--context" | "--kubeconfig" | "-o" | "--output"
    )
}

fn kubectl_line_suggestions(
    query: KubectlQuery<'_>,
    prefix: &str,
    style: KubectlLineSuggestionStyle,
) -> Value {
    let normalized_prefix = prefix.to_lowercase();
    json!(
        exec_kubectl(&query.args, query.timeout, query.ttl, query.context)
            .map(|output| {
                output
                    .lines()
                    .map(str::trim)
                    .filter(|line| !line.is_empty())
                    .filter(|line| matches_prefix(line, &normalized_prefix))
                    .take(24)
                    .map(|name| HostSuggestion {
                        name: name.to_owned(),
                        insert_text: None,
                        description: Some(style.description.to_owned()),
                        kind: Some(style.kind.to_owned()),
                        source: Some(style.source.to_owned()),
                        priority: style.priority,
                    })
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default()
    )
}

fn kubectl_json_item_suggestions<F>(
    query: KubectlQuery<'_>,
    prefix: &str,
    style: KubectlJsonSuggestionStyle<'_>,
    description_for: F,
) -> Value
where
    F: Fn(&Value, &str) -> String,
{
    let normalized_prefix = prefix.to_lowercase();
    let items = exec_kubectl(&query.args, query.timeout, query.ttl, query.context)
        .ok()
        .and_then(|output| serde_json::from_str::<Value>(&output).ok())
        .and_then(|payload| payload.get("items").and_then(Value::as_array).cloned())
        .unwrap_or_default();

    json!(
        items
            .iter()
            .filter_map(|item| {
                let name = item
                    .get("metadata")
                    .and_then(|metadata| metadata.get("name"))
                    .and_then(Value::as_str)?;
                let insert_name = style
                    .insert_prefix
                    .map(|prefix| format!("{prefix} {name}"))
                    .unwrap_or_else(|| name.to_owned());
                if !matches_prefix(&insert_name, &normalized_prefix) {
                    return None;
                }
                Some(HostSuggestion {
                    name: insert_name,
                    insert_text: None,
                    description: Some(description_for(item, style.kind)),
                    kind: Some(style.kind.to_owned()),
                    source: Some("fig:kubectl".to_owned()),
                    priority: style.priority,
                })
            })
            .take(24)
            .collect::<Vec<_>>()
    )
}

fn exec_kubectl(
    args: &[String],
    timeout: Duration,
    ttl: Duration,
    context: &KubectlExecutionContext,
) -> anyhow::Result<String> {
    let program = kubectl_program();
    let cache_key = kubectl_cache_key(&program, args, context);
    let now = Instant::now();
    if let Ok(cache) = KUBECTL_OUTPUT_CACHE.lock()
        && let Some(cached) = cache.get(&cache_key)
        && cached.expires_at > now
    {
        return Ok(cached.value.clone());
    }

    let (stdout_path, stdout_file) = kubectl_stdout_file()?;
    let mut child = Command::new(&program)
        .args(kubectl_command_args(args, timeout))
        .current_dir(&context.cwd)
        .envs(context.environment.iter().map(|(key, value)| (key, value)))
        .stdout(Stdio::from(stdout_file))
        .stderr(Stdio::null())
        .spawn()?;
    let deadline = Instant::now() + kubectl_wall_timeout(timeout);
    loop {
        if let Some(status) = child.try_wait()? {
            if !status.success() {
                let _ = fs::remove_file(&stdout_path);
                anyhow::bail!("kubectl failed");
            }
            break;
        }
        if Instant::now() >= deadline {
            let _ = child.kill();
            let _ = child.wait();
            let _ = fs::remove_file(&stdout_path);
            anyhow::bail!("kubectl timed out");
        }
        thread::sleep(Duration::from_millis(10));
    }
    let output = fs::read_to_string(&stdout_path);
    let _ = fs::remove_file(&stdout_path);
    let output = output?;
    if let Ok(mut cache) = KUBECTL_OUTPUT_CACHE.lock() {
        cache.insert(
            cache_key,
            CachedKubectlOutput {
                value: output.clone(),
                expires_at: Instant::now() + ttl,
            },
        );
    }
    Ok(output)
}

fn kubectl_stdout_file() -> anyhow::Result<(PathBuf, File)> {
    for _ in 0..16 {
        let counter = KUBECTL_OUTPUT_FILE_COUNTER.fetch_add(1, Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!(
            "ianvs-kubectl-{}-{counter}.stdout",
            std::process::id()
        ));
        match OpenOptions::new().write(true).create_new(true).open(&path) {
            Ok(file) => return Ok((path, file)),
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(error.into()),
        }
    }
    anyhow::bail!("failed to create kubectl stdout file")
}

fn kubectl_wall_timeout(timeout: Duration) -> Duration {
    timeout + Duration::from_millis(150)
}

fn kubectl_command_args(args: &[String], timeout: Duration) -> Vec<String> {
    #[cfg(test)]
    {
        let _ = timeout;
        args.to_vec()
    }

    #[cfg(not(test))]
    {
        let millis = timeout.as_millis().max(1);
        let mut command_args = Vec::with_capacity(args.len() + 1);
        command_args.push(format!("--request-timeout={millis}ms"));
        command_args.extend(args.iter().cloned());
        command_args
    }
}

fn kubectl_cache_key(program: &Path, args: &[String], context: &KubectlExecutionContext) -> String {
    let mut key = program.display().to_string();
    key.push('\u{1f}');
    key.push_str(&context.cwd.display().to_string());
    key.push('\u{1f}');
    key.push_str(&kubectl_environment_hash(&context.environment).to_string());
    for arg in args {
        key.push('\u{1f}');
        key.push_str(arg);
    }
    key
}

fn kubectl_environment_hash(environment: &[(String, String)]) -> u64 {
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    environment.hash(&mut hasher);
    hasher.finish()
}

fn kubectl_program() -> PathBuf {
    #[cfg(test)]
    {
        if let Some(path) = TEST_KUBECTL_PATH
            .lock()
            .ok()
            .and_then(|value| value.clone())
        {
            return path;
        }
    }
    PathBuf::from("kubectl")
}

#[cfg(test)]
fn clear_kubectl_cache() {
    if let Ok(mut cache) = KUBECTL_OUTPUT_CACHE.lock() {
        cache.clear();
    }
}

#[cfg(test)]
fn set_test_kubectl_path(path: Option<PathBuf>) {
    clear_kubectl_cache();
    TEST_KUBECTL_PATH
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .clone_from(&path);
}

fn matches_prefix(name: &str, normalized_prefix: &str) -> bool {
    normalized_prefix.is_empty() || name.to_lowercase().starts_with(normalized_prefix)
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
    use std::io::Write;

    #[test]
    fn completes_git_subcommands_via_shared_core() {
        let response = complete_request_json(r#"{"text":"git che","cursorOffset":7}"#);
        let value: Value = serde_json::from_str(&response).unwrap();
        let names = item_names(&value);
        assert_eq!(&names[..2], ["checkout", "cherry-pick"]);
    }

    #[test]
    fn completes_common_developer_tools_via_specs() {
        for (text, expected) in [
            ("docker co", "compose"),
            ("brew ser", "services"),
            ("cargo cl", "clippy"),
            ("pnpm ru", "run"),
            ("yarn wor", "workspace"),
            ("gh pr che", "checkout"),
        ] {
            let request = json!({
                "text": text,
                "cursorOffset": text.encode_utf16().count(),
            });
            let response = complete_request_json(&request.to_string());
            let value: Value = serde_json::from_str(&response).unwrap();
            let names = item_names(&value);
            assert!(
                names.contains(&expected.to_owned()),
                "expected {expected:?} for {text:?}, got {names:?}"
            );
        }

        let response = complete_request_json(r#"{"text":"yarn wor","cursorOffset":8}"#);
        let value: Value = serde_json::from_str(&response).unwrap();
        let names = item_names(&value);
        assert!(names.contains(&"workspace".to_owned()));
        assert!(names.contains(&"workspaces".to_owned()));
    }

    #[test]
    fn completes_package_json_scripts_for_node_package_managers() {
        let temp = tempfile::tempdir().unwrap();
        fs::write(
            temp.path().join("package.json"),
            r#"{"scripts":{"dev":"vite","test":"vitest","typecheck":"tsc --noEmit","test:unit":"vitest"}}"#,
        )
        .unwrap();

        for text in ["npm run t", "pnpm run t", "yarn run t"] {
            let request = json!({
                "text": text,
                "cursorOffset": text.encode_utf16().count(),
                "cwd": temp.path(),
            });
            let response = complete_request_json(&request.to_string());
            let value: Value = serde_json::from_str(&response).unwrap();
            let names = item_names(&value);
            assert!(
                names.contains(&"typecheck".to_owned()),
                "expected typecheck for {text:?}, got {names:?}"
            );
            assert!(
                names.contains(&"test:unit".to_owned()),
                "expected test:unit for {text:?}, got {names:?}"
            );
            assert_eq!(
                names.iter().filter(|name| name.as_str() == "test").count(),
                1,
                "expected one test suggestion for {text:?}, got {names:?}"
            );
        }
    }

    #[test]
    fn completes_package_json_scripts_from_ancestor_directory() {
        let temp = tempfile::tempdir().unwrap();
        let src = temp.path().join("src");
        fs::create_dir(&src).unwrap();
        fs::write(
            temp.path().join("package.json"),
            r#"{"scripts":{"typecheck":"tsc --noEmit","test:unit":"vitest"}}"#,
        )
        .unwrap();

        let text = "npm run t";
        let request = json!({
            "text": text,
            "cursorOffset": text.encode_utf16().count(),
            "cwd": src,
        });
        let response = complete_request_json(&request.to_string());
        let value: Value = serde_json::from_str(&response).unwrap();
        let names = item_names(&value);

        assert!(names.contains(&"typecheck".to_owned()));
        assert!(names.contains(&"test:unit".to_owned()));
    }

    #[test]
    fn escapes_package_json_scripts_with_shell_spaces() {
        let temp = tempfile::tempdir().unwrap();
        fs::write(
            temp.path().join("package.json"),
            r#"{"scripts":{"build app":"vite build"}}"#,
        )
        .unwrap();

        let text = "npm run build\\ ";
        let request = json!({
            "text": text,
            "cursorOffset": text.encode_utf16().count(),
            "cwd": temp.path(),
        });
        let response = complete_request_json(&request.to_string());
        let value: Value = serde_json::from_str(&response).unwrap();
        let items = value.get("items").and_then(Value::as_array).unwrap();

        assert_eq!(items[0]["name"], "build app");
        assert_eq!(items[0]["insertText"], "build\\ app");
    }

    #[test]
    fn package_json_script_lookup_stops_at_git_boundary() {
        let temp = tempfile::tempdir().unwrap();
        fs::write(
            temp.path().join("package.json"),
            r#"{"scripts":{"typecheck":"tsc --noEmit"}}"#,
        )
        .unwrap();
        let repo = temp.path().join("nested-repo");
        let src = repo.join("src");
        fs::create_dir_all(repo.join(".git")).unwrap();
        fs::create_dir(&src).unwrap();

        let text = "npm run ty";
        let request = json!({
            "text": text,
            "cursorOffset": text.encode_utf16().count(),
            "cwd": src,
        });
        let response = complete_request_json(&request.to_string());
        let value: Value = serde_json::from_str(&response).unwrap();
        let names = item_names(&value);

        assert!(!names.contains(&"typecheck".to_owned()), "{names:?}");
    }

    #[test]
    fn completes_ls_current_directory_children() {
        let temp = tempfile::tempdir().unwrap();
        fs::create_dir(temp.path().join("alpha-dir")).unwrap();
        fs::create_dir(temp.path().join("beta-dir")).unwrap();
        fs::write(temp.path().join("z-file.txt"), "file").unwrap();

        let request = json!({
            "text": "ls ./",
            "cursorOffset": 5,
            "cwd": temp.path(),
        });
        let response = complete_request_json(&request.to_string());
        let value: Value = serde_json::from_str(&response).unwrap();
        let names = item_names(&value);

        assert!(names.contains(&"./alpha-dir/".to_owned()));
        assert!(names.contains(&"./beta-dir/".to_owned()));
        assert!(
            names.iter().position(|name| name == "./z-file.txt")
                > names.iter().position(|name| name == "./beta-dir/")
        );
    }

    #[test]
    fn applies_file_and_path_templates_to_command_options() {
        let temp = tempfile::tempdir().unwrap();
        fs::create_dir(temp.path().join("src")).unwrap();
        fs::write(temp.path().join("compose.yaml"), "services: {}\n").unwrap();
        fs::write(temp.path().join("Dockerfile"), "FROM scratch\n").unwrap();

        let file_request = json!({
            "text": "docker compose -f ./",
            "cursorOffset": "docker compose -f ./".encode_utf16().count(),
            "cwd": temp.path(),
        });
        let file_response = complete_request_json(&file_request.to_string());
        let file_value: Value = serde_json::from_str(&file_response).unwrap();
        let file_names = item_names(&file_value);
        assert!(file_names.contains(&"./compose.yaml".to_owned()));
        assert!(file_names.contains(&"./Dockerfile".to_owned()));
        assert!(file_names.contains(&"./src/".to_owned()));
        assert!(
            file_names.iter().position(|name| name == "./compose.yaml")
                < file_names.iter().position(|name| name == "./src/")
        );

        let volume_request = json!({
            "text": "docker run -v ./",
            "cursorOffset": "docker run -v ./".encode_utf16().count(),
            "cwd": temp.path(),
        });
        let volume_response = complete_request_json(&volume_request.to_string());
        let volume_value: Value = serde_json::from_str(&volume_response).unwrap();
        let volume_names = item_names(&volume_value);
        assert!(volume_names.contains(&"./src/".to_owned()));
        assert!(volume_names.contains(&"./compose.yaml".to_owned()));

        let cargo_new_request = json!({
            "text": "cargo new ",
            "cursorOffset": "cargo new ".encode_utf16().count(),
            "cwd": temp.path(),
        });
        let cargo_new_response = complete_request_json(&cargo_new_request.to_string());
        let cargo_new_value: Value = serde_json::from_str(&cargo_new_response).unwrap();
        let cargo_new_names = item_names(&cargo_new_value);
        assert!(!cargo_new_names.contains(&"src/".to_owned()));
    }

    #[test]
    fn escapes_path_template_insert_text_for_shell_tokens() {
        let temp = tempfile::tempdir().unwrap();
        fs::write(temp.path().join("My File.txt"), "file").unwrap();

        for text in ["cat ./M", "cat ./My\\ "] {
            let request = json!({
                "text": text,
                "cursorOffset": text.encode_utf16().count(),
                "cwd": temp.path(),
            });
            let response = complete_request_json(&request.to_string());
            let value: Value = serde_json::from_str(&response).unwrap();
            let items = value.get("items").and_then(Value::as_array).unwrap();

            assert_eq!(items[0]["name"], "./My File.txt");
            assert_eq!(items[0]["insertText"], "./My\\ File.txt");
        }
    }

    #[test]
    fn files_template_keeps_files_when_many_directories_match() {
        let temp = tempfile::tempdir().unwrap();
        for index in 0..20 {
            fs::create_dir(temp.path().join(format!("dir-{index:02}"))).unwrap();
        }
        fs::write(temp.path().join("compose.yaml"), "services: {}\n").unwrap();

        let text = "docker compose -f ./";
        let request = json!({
            "text": text,
            "cursorOffset": text.encode_utf16().count(),
            "cwd": temp.path(),
        });
        let response = complete_request_json(&request.to_string());
        let value: Value = serde_json::from_str(&response).unwrap();
        let names = item_names(&value);

        assert!(names.contains(&"./compose.yaml".to_owned()), "{names:?}");
        assert!(
            names.iter().position(|name| name == "./compose.yaml")
                < names.iter().position(|name| name == "./dir-00/")
        );
    }

    #[test]
    fn completes_kubectl_resource_types_from_host_provider() {
        let _guard = TEST_KUBECTL_LOCK
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let temp = tempfile::tempdir().unwrap();
        let bin = temp.path().join("bin");
        fs::create_dir(&bin).unwrap();
        let kubectl = bin.join("kubectl");
        let call_log = temp.path().join("kubectl-calls.log");
        let mut file = fs::File::create(&kubectl).unwrap();
        writeln!(
            file,
            r#"#!/bin/sh
printf '%s\n' "$*" >> "{}"
case "$*" in
  "api-resources --verbs=list -o name")
    printf '%s\n' pods deployments.apps services namespaces nodes
    ;;
  *)
    exit 1
    ;;
esac
"#,
            call_log.display()
        )
        .unwrap();
        drop(file);
        make_executable(&kubectl);

        set_test_kubectl_path(Some(kubectl));
        let response = complete_request_json(r#"{"text":"kubectl get ","cursorOffset":12}"#);
        set_test_kubectl_path(None);

        let value: Value = serde_json::from_str(&response).unwrap();
        let names = item_names(&value);
        assert!(names.contains(&"pods".to_owned()));
        assert!(names.contains(&"deployments.apps".to_owned()));
        let calls = fs::read_to_string(call_log).unwrap();
        assert_eq!(
            calls.lines().collect::<Vec<_>>(),
            ["api-resources --verbs=list -o name"]
        );
    }

    #[test]
    fn completes_k_alias_resource_types_from_host_provider() {
        let _guard = TEST_KUBECTL_LOCK
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let temp = tempfile::tempdir().unwrap();
        let kubectl = write_kubectl_mock(
            temp.path(),
            r#"case "$*" in
  "api-resources --verbs=list -o name")
    printf '%s\n' pods deployments.apps services namespaces nodes
    ;;
  *)
    exit 1
    ;;
esac
"#,
        );

        set_test_kubectl_path(Some(kubectl.path));
        let response = complete_request_json(r#"{"text":"k get ","cursorOffset":6}"#);
        set_test_kubectl_path(None);

        let value: Value = serde_json::from_str(&response).unwrap();
        let names = item_names(&value);
        assert!(names.contains(&"pods".to_owned()));
        assert!(names.contains(&"deployments.apps".to_owned()));
        let calls = fs::read_to_string(kubectl.call_log).unwrap();
        assert_eq!(
            calls.lines().collect::<Vec<_>>(),
            ["api-resources --verbs=list -o name"]
        );
    }

    #[test]
    fn passes_kubectl_environment_and_cwd_to_host_provider() {
        let _guard = TEST_KUBECTL_LOCK
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let temp = tempfile::tempdir().unwrap();
        let workdir = temp.path().join("workspace");
        fs::create_dir(&workdir).unwrap();
        let kubectl = write_kubectl_mock(
            temp.path(),
            r#"printf 'pwd=%s\n' "$(pwd)" >> "$IANVS_KUBECTL_LOG"
printf 'kubeconfig=%s\n' "$KUBECONFIG" >> "$IANVS_KUBECTL_LOG"
case "$*" in
  "api-resources --verbs=list -o name")
    printf '%s\n' pods
    ;;
  *)
    exit 1
    ;;
esac
"#,
        );

        set_test_kubectl_path(Some(kubectl.path));
        let text = "kubectl get ";
        let request = json!({
            "text": text,
            "cursorOffset": text.encode_utf16().count(),
            "cwd": workdir,
            "environmentVariables": {
                "KUBECONFIG": "relative-kubeconfig",
                "IANVS_KUBECTL_LOG": kubectl.call_log,
            },
        });
        let response = complete_request_json(&request.to_string());
        set_test_kubectl_path(None);

        let value: Value = serde_json::from_str(&response).unwrap();
        let names = item_names(&value);
        assert!(names.contains(&"pods".to_owned()));
        let calls = fs::read_to_string(kubectl.call_log).unwrap();
        let expected_pwd = fs::canonicalize(&workdir).unwrap();
        assert!(
            calls.contains(&format!("pwd={}", expected_pwd.display())),
            "{calls}"
        );
        assert!(calls.contains("kubeconfig=relative-kubeconfig"), "{calls}");
    }

    #[test]
    fn kubectl_host_provider_has_wall_clock_timeout() {
        let _guard = TEST_KUBECTL_LOCK
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let temp = tempfile::tempdir().unwrap();
        let kubectl = write_kubectl_mock(
            temp.path(),
            r#"case "$*" in
  "api-resources --verbs=list -o name")
    sleep 2
    printf '%s\n' pods
    ;;
  *)
    exit 1
    ;;
esac
"#,
        );

        set_test_kubectl_path(Some(kubectl.path));
        let started_at = Instant::now();
        let response = complete_request_json(r#"{"text":"kubectl get ","cursorOffset":12}"#);
        let elapsed = started_at.elapsed();
        set_test_kubectl_path(None);

        let value: Value = serde_json::from_str(&response).unwrap();
        let names = item_names(&value);
        assert!(names.contains(&"pods".to_owned()));
        assert!(elapsed < Duration::from_secs(2), "elapsed: {elapsed:?}");
    }

    #[test]
    fn completes_kubectl_pod_names_for_namespaced_resource_alias() {
        let _guard = TEST_KUBECTL_LOCK
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let temp = tempfile::tempdir().unwrap();
        let kubectl = write_kubectl_mock(
            temp.path(),
            r#"case "$*" in
  "get pods -o json -n kube-system")
    printf '%s\n' '{"items":[{"metadata":{"name":"coredns-abc","namespace":"kube-system"}},{"metadata":{"name":"metrics-server","namespace":"kube-system"}}]}'
    ;;
  *)
    exit 1
    ;;
esac
"#,
        );
        set_test_kubectl_path(Some(kubectl.path));
        let text = "kubectl -n kube-system get po ";
        let request = json!({
            "text": text,
            "cursorOffset": text.encode_utf16().count(),
        });
        let response = complete_request_json(&request.to_string());
        set_test_kubectl_path(None);

        let value: Value = serde_json::from_str(&response).unwrap();
        let names = item_names(&value);
        assert!(names.contains(&"coredns-abc".to_owned()));
        assert!(names.contains(&"metrics-server".to_owned()));
        let calls = fs::read_to_string(kubectl.call_log).unwrap();
        assert_eq!(
            calls.lines().collect::<Vec<_>>(),
            ["get pods -o json -n kube-system"]
        );
    }

    #[test]
    fn completes_kubectl_pod_names_inline_after_exact_resource_alias() {
        let _guard = TEST_KUBECTL_LOCK
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let temp = tempfile::tempdir().unwrap();
        let kubectl = write_kubectl_mock(
            temp.path(),
            r#"case "$*" in
  "api-resources --verbs=list -o name")
    printf '%s\n' pods deployments.apps services namespaces nodes
    ;;
  "get pods -o json -n kube-system")
    printf '%s\n' '{"items":[{"metadata":{"name":"coredns-abc","namespace":"kube-system"}},{"metadata":{"name":"metrics-server","namespace":"kube-system"}}]}'
    ;;
  *)
    exit 1
    ;;
esac
"#,
        );
        set_test_kubectl_path(Some(kubectl.path));
        let text = "kubectl -n kube-system get po";
        let request = json!({
            "text": text,
            "cursorOffset": text.encode_utf16().count(),
        });
        let response = complete_request_json(&request.to_string());
        set_test_kubectl_path(None);

        let value: Value = serde_json::from_str(&response).unwrap();
        let names = item_names(&value);
        assert!(names.contains(&"po coredns-abc".to_owned()));
        assert!(names.contains(&"po metrics-server".to_owned()));
        let calls = fs::read_to_string(kubectl.call_log).unwrap();
        assert_eq!(
            calls.lines().collect::<Vec<_>>(),
            ["get pods -o json -n kube-system"]
        );
    }

    #[test]
    fn leaves_kubectl_inline_resource_names_empty_without_resource_type_fallback() {
        let _guard = TEST_KUBECTL_LOCK
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let temp = tempfile::tempdir().unwrap();
        let kubectl = write_kubectl_mock(
            temp.path(),
            r#"case "$*" in
  "get pods -o json -n kube-system")
    printf '%s\n' '{"items":[]}'
    ;;
  "api-resources --verbs=list -o name")
    printf '%s\n' pods deployments.apps services namespaces nodes
    ;;
  *)
    exit 1
    ;;
esac
"#,
        );
        set_test_kubectl_path(Some(kubectl.path));
        let text = "kubectl -n kube-system get po";
        let request = json!({
            "text": text,
            "cursorOffset": text.encode_utf16().count(),
        });
        let response = complete_request_json(&request.to_string());
        set_test_kubectl_path(None);

        let value: Value = serde_json::from_str(&response).unwrap();
        let names = item_names(&value);
        assert!(names.is_empty(), "{names:?}");
        let calls = fs::read_to_string(kubectl.call_log).unwrap();
        assert_eq!(
            calls.lines().collect::<Vec<_>>(),
            ["get pods -o json -n kube-system"]
        );
    }

    fn item_names(value: &Value) -> Vec<String> {
        value
            .get("items")
            .and_then(Value::as_array)
            .unwrap()
            .iter()
            .filter_map(|item| item.get("name").and_then(Value::as_str))
            .map(str::to_owned)
            .collect()
    }

    struct KubectlMock {
        path: PathBuf,
        call_log: PathBuf,
    }

    fn write_kubectl_mock(temp: &Path, cases: &str) -> KubectlMock {
        let bin = temp.join("bin");
        fs::create_dir(&bin).unwrap();
        let path = bin.join("kubectl");
        let call_log = temp.join("kubectl-calls.log");
        let mut file = fs::File::create(&path).unwrap();
        writeln!(
            file,
            r#"#!/bin/sh
printf '%s\n' "$*" >> "{}"
{}
"#,
            call_log.display(),
            cases
        )
        .unwrap();
        drop(file);
        make_executable(&path);
        KubectlMock { path, call_log }
    }

    #[cfg(unix)]
    fn make_executable(path: &Path) {
        use std::os::unix::fs::PermissionsExt;
        let mut permissions = fs::metadata(path).unwrap().permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(path, permissions).unwrap();
    }

    #[cfg(not(unix))]
    fn make_executable(_path: &Path) {}
}
