use anyhow::{Context, Result};
use glob::{Pattern, glob};
use serde::Serialize;
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

const IMPORT_CONTRACT: &str = "ianvs-openssh-profiles-v1";

#[derive(Clone, Debug)]
struct Directive {
    key: String,
    values: Vec<String>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportedSshPortForward {
    #[serde(rename = "type")]
    pub forward_type: String,
    pub bind_host: String,
    pub bind_port: u16,
    pub target_host: String,
    pub target_port: u16,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportedSshJumpProfile {
    pub host: String,
    pub user: String,
    pub port: u16,
    pub auth: String,
    pub private_keys: Vec<String>,
    pub host_key_policy: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub known_hosts_file: Option<String>,
    pub connect_timeout_seconds: u64,
    pub keepalive_seconds: u64,
    pub keepalive_count_max: usize,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportedSshProfile {
    pub id: String,
    pub name: String,
    pub group: String,
    pub source: String,
    pub alias: String,
    pub host: String,
    pub user: String,
    pub port: u16,
    pub auth: String,
    pub private_keys: Vec<String>,
    pub host_key_policy: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub known_hosts_file: Option<String>,
    pub connect_timeout_seconds: u64,
    pub keepalive_seconds: u64,
    pub keepalive_count_max: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub proxy_command: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub proxy_jump: Option<String>,
    pub proxy_jump_profiles: Vec<ImportedSshJumpProfile>,
    pub port_forwards: Vec<ImportedSshPortForward>,
    pub agent_forwarding: bool,
    pub x11_forwarding: bool,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SshConfigImportWarning {
    pub path: String,
    pub message: String,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportedSshProfilesDocument {
    pub schema_version: u32,
    pub contract: &'static str,
    pub source_path: String,
    pub source_mtime_micros: u64,
    pub profiles: Vec<ImportedSshProfile>,
    pub warnings: Vec<SshConfigImportWarning>,
}

pub fn import_profiles_json(config_path: Option<&str>) -> Result<String> {
    serde_json::to_string(&import_profiles(config_path)?).context("could not encode SSH profiles")
}

pub fn import_profiles(config_path: Option<&str>) -> Result<ImportedSshProfilesDocument> {
    let path = config_path
        .filter(|path| !path.trim().is_empty())
        .map(expand_home)
        .unwrap_or_else(default_config_path);
    let mut visited = HashSet::new();
    let mut newest_mtime_micros = 0;
    let mut warnings = Vec::new();
    let directives =
        read_config_recursive(&path, &mut visited, &mut newest_mtime_micros, &mut warnings);
    let unsupported_matches = directives
        .iter()
        .filter(|directive| directive.key == "match")
        .count();
    if unsupported_matches != 0 {
        warnings.push(SshConfigImportWarning {
            path: path.to_string_lossy().into_owned(),
            message: format!(
                "ignored {unsupported_matches} unsupported Match block(s); directives in those blocks were skipped to preserve OpenSSH conditions"
            ),
        });
    }
    let aliases = concrete_aliases(&directives);
    let mut profiles = Vec::new();
    for alias in aliases {
        let settings = compute_settings(&directives, &alias);
        let Some(host) = first_setting(&settings, "hostname") else {
            // Match Tabby's importer: wildcard-only or alias-only blocks remain
            // valid OpenSSH config but do not become launcher profiles.
            continue;
        };
        profiles.push(profile_from_settings(alias, host, &settings, &directives));
    }
    profiles.sort_by(|left, right| left.alias.cmp(&right.alias));
    Ok(ImportedSshProfilesDocument {
        schema_version: 1,
        contract: IMPORT_CONTRACT,
        source_path: path.to_string_lossy().into_owned(),
        source_mtime_micros: newest_mtime_micros,
        profiles,
        warnings,
    })
}

fn read_config_recursive(
    path: &Path,
    visited: &mut HashSet<PathBuf>,
    newest_mtime_micros: &mut u64,
    warnings: &mut Vec<SshConfigImportWarning>,
) -> Vec<Directive> {
    let identity = fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    if !visited.insert(identity) {
        return Vec::new();
    }
    let contents = match fs::read_to_string(path) {
        Ok(contents) => contents,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Vec::new(),
        Err(error) => {
            warnings.push(SshConfigImportWarning {
                path: path.to_string_lossy().into_owned(),
                message: error.to_string(),
            });
            return Vec::new();
        }
    };
    if let Ok(modified) = fs::metadata(path).and_then(|metadata| metadata.modified())
        && let Ok(duration) = modified.duration_since(UNIX_EPOCH)
    {
        *newest_mtime_micros = (*newest_mtime_micros).max(duration.as_micros() as u64);
    }

    let mut merged = Vec::new();
    for logical_line in logical_lines(&contents) {
        let Some(directive) = parse_directive(&logical_line) else {
            continue;
        };
        if directive.key == "include" {
            for include in directive.values {
                let include_path = resolve_include_path(&include);
                let pattern = include_path.to_string_lossy();
                let mut matches = match glob(&pattern) {
                    Ok(paths) => paths.filter_map(Result::ok).collect::<Vec<_>>(),
                    Err(error) => {
                        warnings.push(SshConfigImportWarning {
                            path: path.to_string_lossy().into_owned(),
                            message: format!("invalid Include pattern {include}: {error}"),
                        });
                        Vec::new()
                    }
                };
                matches.sort();
                for matched in matches {
                    if matched.is_file() {
                        merged.extend(read_config_recursive(
                            &matched,
                            visited,
                            newest_mtime_micros,
                            warnings,
                        ));
                    }
                }
            }
        } else {
            merged.push(directive);
        }
    }
    merged
}

fn logical_lines(contents: &str) -> Vec<String> {
    let mut lines = Vec::new();
    let mut pending = String::new();
    for line in contents.lines() {
        let trimmed = line.trim_end();
        if let Some(prefix) = trimmed.strip_suffix('\\') {
            pending.push_str(prefix);
            pending.push(' ');
            continue;
        }
        pending.push_str(trimmed);
        lines.push(std::mem::take(&mut pending));
    }
    if !pending.trim().is_empty() {
        lines.push(pending);
    }
    lines
}

fn parse_directive(line: &str) -> Option<Directive> {
    let without_comment = strip_comment(line).trim();
    if without_comment.is_empty() {
        return None;
    }
    let mut tokens = shell_words::split(without_comment).ok()?;
    if tokens.is_empty() {
        return None;
    }
    if let Some((key, value)) = tokens[0].split_once('=') {
        let key = key.to_string();
        let value = value.to_string();
        tokens[0] = key;
        if !value.is_empty() {
            tokens.insert(1, value);
        }
    }
    let key = tokens.remove(0).to_ascii_lowercase();
    if tokens.is_empty() {
        return None;
    }
    Some(Directive {
        key,
        values: tokens,
    })
}

fn strip_comment(line: &str) -> &str {
    let mut quote = None;
    let mut escaped = false;
    for (index, character) in line.char_indices() {
        if escaped {
            escaped = false;
            continue;
        }
        if character == '\\' {
            escaped = true;
            continue;
        }
        if matches!(character, '\'' | '"') {
            if quote == Some(character) {
                quote = None;
            } else if quote.is_none() {
                quote = Some(character);
            }
            continue;
        }
        if character == '#' && quote.is_none() {
            return &line[..index];
        }
    }
    line
}

fn concrete_aliases(directives: &[Directive]) -> BTreeSet<String> {
    directives
        .iter()
        .filter(|directive| directive.key == "host")
        .flat_map(|directive| directive.values.iter())
        .filter(|value| !value.starts_with('!') && !value.contains('*') && !value.contains('?'))
        .cloned()
        .collect()
}

fn compute_settings(directives: &[Directive], alias: &str) -> BTreeMap<String, Vec<String>> {
    let mut applies = true;
    let mut settings = BTreeMap::<String, Vec<String>>::new();
    for directive in directives {
        if directive.key == "host" {
            applies = patterns_match(&directive.values, alias);
            continue;
        }
        if directive.key == "match" {
            // Match supports runtime predicates such as `exec`, `localnetwork`,
            // and canonicalization state. Applying its body without evaluating
            // the predicate can execute ProxyCommand or expose an agent outside
            // the scope intended by the user. Skip until the next Host block.
            applies = false;
            continue;
        }
        if !applies {
            continue;
        }
        let value = directive.values.join(" ");
        if is_multi_value(&directive.key) {
            settings
                .entry(directive.key.clone())
                .or_default()
                .push(value);
        } else {
            settings
                .entry(directive.key.clone())
                .or_insert_with(|| vec![value]);
        }
    }
    settings
}

fn patterns_match(patterns: &[String], alias: &str) -> bool {
    let mut positive_match = false;
    for raw in patterns {
        let (negated, pattern) = raw
            .strip_prefix('!')
            .map_or((false, raw.as_str()), |pattern| (true, pattern));
        let matches = Pattern::new(pattern)
            .map(|pattern| pattern.matches(alias))
            .unwrap_or(false);
        if matches && negated {
            return false;
        }
        positive_match |= matches;
    }
    positive_match
}

fn is_multi_value(key: &str) -> bool {
    matches!(
        key,
        "identityfile" | "localforward" | "remoteforward" | "dynamicforward"
    )
}

fn profile_from_settings(
    alias: String,
    host: String,
    settings: &BTreeMap<String, Vec<String>>,
    directives: &[Directive],
) -> ImportedSshProfile {
    let user = first_setting(settings, "user").unwrap_or_else(default_user);
    let port = first_setting(settings, "port")
        .and_then(|value| value.parse::<u16>().ok())
        .filter(|port| *port != 0)
        .unwrap_or(22);
    let strict_host_key = first_setting(settings, "stricthostkeychecking")
        .unwrap_or_else(|| "yes".to_string())
        .to_ascii_lowercase();
    let host_key_policy = match strict_host_key.as_str() {
        "no" | "off" | "false" => "insecure",
        "accept-new" => "accept_new",
        _ => "strict",
    };
    let private_keys = settings
        .get("identityfile")
        .into_iter()
        .flatten()
        .map(|path| expand_home(path).to_string_lossy().into_owned())
        .collect();
    let port_forwards = imported_port_forwards(settings);
    let proxy_jump =
        first_setting(settings, "proxyjump").filter(|jump| !jump.eq_ignore_ascii_case("none"));
    let proxy_jump_profiles = proxy_jump
        .as_deref()
        .map(|jump| imported_proxy_jump_profiles(jump, directives))
        .unwrap_or_default();
    ImportedSshProfile {
        id: format!("openssh-config:{}", stable_profile_hash(&alias)),
        name: alias.clone(),
        group: "Imported from .ssh/config".to_string(),
        source: "openssh_config".to_string(),
        alias: alias.clone(),
        host,
        user,
        port,
        auth: "auto".to_string(),
        private_keys,
        host_key_policy: host_key_policy.to_string(),
        known_hosts_file: first_setting(settings, "userknownhostsfile")
            .map(|path| expand_home(&path).to_string_lossy().into_owned()),
        connect_timeout_seconds: parsed_u64(settings, "connecttimeout", 10),
        keepalive_seconds: parsed_u64(settings, "serveraliveinterval", 0),
        keepalive_count_max: parsed_u64(settings, "serveralivecountmax", 3) as usize,
        proxy_command: first_setting(settings, "proxycommand")
            .filter(|command| !command.eq_ignore_ascii_case("none")),
        proxy_jump,
        proxy_jump_profiles,
        port_forwards,
        agent_forwarding: enabled_setting(settings, "forwardagent"),
        x11_forwarding: enabled_setting(settings, "forwardx11"),
    }
}

fn imported_proxy_jump_profiles(
    proxy_jump: &str,
    directives: &[Directive],
) -> Vec<ImportedSshJumpProfile> {
    proxy_jump
        .split(',')
        .filter_map(|hop| imported_proxy_jump_profile(hop.trim(), directives))
        .collect()
}

fn imported_proxy_jump_profile(
    hop: &str,
    directives: &[Directive],
) -> Option<ImportedSshJumpProfile> {
    let url = url::Url::parse(&format!("ssh://{hop}")).ok()?;
    if url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
        || !matches!(url.path(), "" | "/")
    {
        return None;
    }
    let alias = url.host_str()?.trim_matches(['[', ']']);
    if alias.is_empty() {
        return None;
    }
    let settings = compute_settings(directives, alias);
    let host = first_setting(&settings, "hostname").unwrap_or_else(|| alias.to_string());
    let user = (!url.username().is_empty())
        .then(|| url.username().to_string())
        .or_else(|| first_setting(&settings, "user"))
        .unwrap_or_else(default_user);
    let port = url
        .port()
        .or_else(|| first_setting(&settings, "port").and_then(|port| port.parse::<u16>().ok()))
        .filter(|port| *port != 0)
        .unwrap_or(22);
    let private_keys = settings
        .get("identityfile")
        .into_iter()
        .flatten()
        .map(|path| expand_home(path).to_string_lossy().into_owned())
        .collect();
    let strict_host_key = first_setting(&settings, "stricthostkeychecking")
        .unwrap_or_else(|| "yes".to_string())
        .to_ascii_lowercase();
    let host_key_policy = match strict_host_key.as_str() {
        "no" | "off" | "false" => "insecure",
        "accept-new" => "accept_new",
        _ => "strict",
    };
    Some(ImportedSshJumpProfile {
        host,
        user,
        port,
        auth: "auto".to_string(),
        private_keys,
        host_key_policy: host_key_policy.to_string(),
        known_hosts_file: first_setting(&settings, "userknownhostsfile")
            .map(|path| expand_home(&path).to_string_lossy().into_owned()),
        connect_timeout_seconds: parsed_u64(&settings, "connecttimeout", 10),
        keepalive_seconds: parsed_u64(&settings, "serveraliveinterval", 0),
        keepalive_count_max: parsed_u64(&settings, "serveralivecountmax", 3) as usize,
    })
}

fn imported_port_forwards(settings: &BTreeMap<String, Vec<String>>) -> Vec<ImportedSshPortForward> {
    let mut forwards = Vec::new();
    for (key, kind) in [
        ("localforward", "local"),
        ("remoteforward", "remote"),
        ("dynamicforward", "dynamic"),
    ] {
        for value in settings.get(key).into_iter().flatten() {
            let parts = shell_words::split(value).unwrap_or_default();
            let expected_parts = if kind == "dynamic" { 1 } else { 2 };
            if parts.len() != expected_parts {
                continue;
            }
            let Some((bind_host, bind_port)) = parse_forward_endpoint(&parts[0], true) else {
                continue;
            };
            let (target_host, target_port) = if kind == "dynamic" {
                (String::new(), 0)
            } else {
                let Some(target) = parse_forward_endpoint(&parts[1], false) else {
                    continue;
                };
                target
            };
            forwards.push(ImportedSshPortForward {
                forward_type: kind.to_string(),
                bind_host,
                bind_port,
                target_host,
                target_port,
            });
        }
    }
    forwards
}

fn parse_forward_endpoint(value: &str, bind: bool) -> Option<(String, u16)> {
    let (host, port) = if let Some(bracketed) = value.strip_prefix('[') {
        let (host, port) = bracketed.rsplit_once("]:")?;
        (host.to_string(), port)
    } else if bind && let Ok(port) = value.parse::<u16>() {
        return (port != 0).then(|| ("127.0.0.1".to_string(), port));
    } else {
        let (host, port) = value.rsplit_once(':')?;
        (host.to_string(), port)
    };
    let port = port.parse::<u16>().ok().filter(|port| *port != 0)?;
    let host = match host.as_str() {
        "" if bind => "127.0.0.1".to_string(),
        "*" if bind => "0.0.0.0".to_string(),
        "" => return None,
        _ => host,
    };
    Some((host, port))
}

fn enabled_setting(settings: &BTreeMap<String, Vec<String>>, key: &str) -> bool {
    first_setting(settings, key)
        .is_some_and(|value| matches!(value.to_ascii_lowercase().as_str(), "yes" | "on" | "true"))
}

fn first_setting(settings: &BTreeMap<String, Vec<String>>, key: &str) -> Option<String> {
    settings.get(key).and_then(|values| values.first()).cloned()
}

fn parsed_u64(settings: &BTreeMap<String, Vec<String>>, key: &str, fallback: u64) -> u64 {
    first_setting(settings, key)
        .and_then(|value| value.parse().ok())
        .unwrap_or(fallback)
}

fn stable_profile_hash(alias: &str) -> String {
    let digest = Sha256::digest(alias.as_bytes());
    digest.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn default_user() -> String {
    std::env::var("USER")
        .or_else(|_| std::env::var("USERNAME"))
        .unwrap_or_else(|_| "root".to_string())
}

fn default_config_path() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("~"))
        .join(".ssh")
        .join("config")
}

fn resolve_include_path(value: &str) -> PathBuf {
    let expanded = expand_home(value);
    if expanded.is_absolute() || value.starts_with('~') {
        return expanded;
    }
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("~"))
        .join(".ssh")
        .join(expanded)
}

fn expand_home(value: &str) -> PathBuf {
    if value == "~" {
        return std::env::var_os("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("~"));
    }
    if let Some(relative) = value.strip_prefix("~/")
        && let Some(home) = std::env::var_os("HOME")
    {
        return PathBuf::from(home).join(relative);
    }
    PathBuf::from(value)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    #[test]
    fn imports_includes_and_computes_wildcard_defaults() {
        let directory = tempfile::tempdir().expect("tempdir");
        let included = directory.path().join("hosts.conf");
        let mut included_file = fs::File::create(&included).expect("included");
        writeln!(
            included_file,
            "Host work\n  HostName 10.0.0.7\n  User deploy\n  IdentityFile ~/.ssh/work_key\n  ForwardAgent yes\n  ForwardX11 yes\n  LocalForward 127.0.0.1:8080 app.internal:80\n  RemoteForward [::1]:9000 localhost:9001\n  DynamicForward 1080"
        )
        .expect("write included");
        let config = directory.path().join("config");
        let mut config_file = fs::File::create(&config).expect("config");
        writeln!(
            config_file,
            "Include {}\nHost *\n  Port 2200\n  ServerAliveInterval 15",
            included.display()
        )
        .expect("write config");

        let document = import_profiles(config.to_str()).expect("import");
        assert_eq!(document.profiles.len(), 1);
        let profile = &document.profiles[0];
        assert_eq!(profile.alias, "work");
        assert_eq!(profile.host, "10.0.0.7");
        assert_eq!(profile.user, "deploy");
        assert_eq!(profile.port, 2200);
        assert_eq!(profile.keepalive_seconds, 15);
        assert_eq!(profile.private_keys.len(), 1);
        assert!(profile.agent_forwarding);
        assert!(profile.x11_forwarding);
        assert_eq!(profile.port_forwards.len(), 3);
        assert_eq!(profile.port_forwards[0].forward_type, "local");
        assert_eq!(profile.port_forwards[0].target_host, "app.internal");
        assert_eq!(profile.port_forwards[1].bind_host, "::1");
        assert_eq!(profile.port_forwards[2].forward_type, "dynamic");
        assert_eq!(profile.port_forwards[2].bind_host, "127.0.0.1");
        assert_eq!(profile.port_forwards[2].bind_port, 1080);
        let encoded = serde_json::to_value(&document).expect("serialize import contract");
        assert_eq!(encoded["profiles"][0]["portForwards"][0]["type"], "local");
        assert_eq!(encoded["profiles"][0]["agentForwarding"], true);
        assert_eq!(encoded["profiles"][0]["x11Forwarding"], true);
    }

    #[test]
    fn include_cycles_are_bounded() {
        let directory = tempfile::tempdir().expect("tempdir");
        let first = directory.path().join("first");
        let second = directory.path().join("second");
        fs::write(
            &first,
            format!(
                "Include {}\nHost cycle\n HostName example.test",
                second.display()
            ),
        )
        .expect("first");
        fs::write(&second, format!("Include {}", first.display())).expect("second");
        let document = import_profiles(first.to_str()).expect("import");
        assert_eq!(document.profiles.len(), 1);
    }

    #[test]
    fn negated_patterns_do_not_apply() {
        let directives = vec![
            Directive {
                key: "host".to_string(),
                values: vec!["*".to_string(), "!blocked".to_string()],
            },
            Directive {
                key: "user".to_string(),
                values: vec!["allowed".to_string()],
            },
        ];
        assert!(compute_settings(&directives, "blocked").is_empty());
        assert_eq!(
            first_setting(&compute_settings(&directives, "other"), "user"),
            Some("allowed".to_string())
        );
    }

    #[test]
    fn unsupported_match_blocks_fail_closed_and_emit_a_warning() {
        let directory = tempfile::tempdir().expect("tempdir");
        let config = directory.path().join("config");
        fs::write(
            &config,
            "Host production\n  HostName prod.example.test\n  User deploy\nMatch user root\n  ProxyCommand should-not-run %h %p\n  ForwardAgent yes\n",
        )
        .expect("config");

        let document = import_profiles(config.to_str()).expect("import");
        let profile = document.profiles.first().expect("production profile");
        assert!(profile.proxy_command.is_none());
        assert!(!profile.agent_forwarding);
        assert!(
            document
                .warnings
                .iter()
                .any(|warning| warning.message.contains("unsupported Match"))
        );
    }

    #[test]
    fn imports_independent_settings_for_every_proxy_jump_hop() {
        let directory = tempfile::tempdir().expect("tempdir");
        let config = directory.path().join("config");
        fs::write(
            &config,
            format!(
                "Host destination\n  HostName target.internal\n  User target-user\n  IdentityFile {0}/target-key\n  ProxyJump jump-user@jump-alias:2200\nHost jump-alias\n  HostName jump.internal\n  User ignored-by-explicit-user\n  Port 2222\n  IdentityFile {0}/jump-key\n  StrictHostKeyChecking accept-new\n  UserKnownHostsFile {0}/jump-known-hosts\n  ConnectTimeout 7\n",
                directory.path().display()
            ),
        )
        .expect("config");

        let document = import_profiles(config.to_str()).expect("import");
        let destination = document
            .profiles
            .iter()
            .find(|profile| profile.alias == "destination")
            .expect("destination profile");
        let jump = destination
            .proxy_jump_profiles
            .first()
            .expect("independent jump profile");
        assert_eq!(jump.host, "jump.internal");
        assert_eq!(jump.user, "jump-user");
        assert_eq!(jump.port, 2200);
        assert_eq!(jump.auth, "auto");
        assert_eq!(
            jump.private_keys,
            vec![
                directory
                    .path()
                    .join("jump-key")
                    .to_string_lossy()
                    .into_owned()
            ]
        );
        assert_eq!(jump.host_key_policy, "accept_new");
        assert_eq!(
            jump.known_hosts_file.as_deref(),
            Some(
                directory
                    .path()
                    .join("jump-known-hosts")
                    .to_string_lossy()
                    .as_ref()
            )
        );
        assert_eq!(jump.connect_timeout_seconds, 7);
        let encoded = serde_json::to_value(destination).expect("serialize jump profile");
        assert_eq!(encoded["proxyJumpProfiles"][0]["host"], "jump.internal");
        assert_eq!(
            encoded["proxyJumpProfiles"][0]["privateKeys"][0],
            directory.path().join("jump-key").to_string_lossy().as_ref()
        );
    }
}
