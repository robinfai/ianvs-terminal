use crate::model::{
    MAX_SCROLLBACK_LINES, TerminalConnectionType, TerminalProfile, TerminalProfileAppearance,
    TerminalProfileConnection, TerminalProfileInteraction, TerminalProfileLaunch,
    TerminalProfileTerminal, TerminalShellIntegration, TerminalSshPortForwardKind,
};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

pub const SESSION_CONFIG_SCHEMA_VERSION: u32 = 1;
pub const SESSION_CONFIG_CONTRACT: &str = "ianvs-session-config-v1";
pub const MAX_SESSION_CONFIG_BYTES: usize = 1024 * 1024;

const MAX_SESSION_ID_BYTES: usize = 128;
const MAX_DISPLAY_NAME_BYTES: usize = 256;
const MAX_PATH_BYTES: usize = 4096;
const MAX_ARGUMENTS: usize = 128;
const MAX_ENVIRONMENT_ENTRIES: usize = 256;
const MAX_STRING_BYTES: usize = 64 * 1024;
const MAX_FONT_FALLBACKS: usize = 32;
const MAX_GRAPHICS_BYTES: usize = 1024 * 1024 * 1024;
const MAX_FONT_SIZE: f64 = 512.0;
const MAX_LINE_HEIGHT: f64 = 10.0;

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct SessionConfigV1 {
    pub schema_version: u32,
    pub contract: String,
    pub session_id: String,
    pub display_name: String,
    #[serde(rename = "client_capabilities")]
    pub client_capabilities: SessionClientCapabilitiesV1,
    pub config: SessionConfigV1Payload,
}

/// Capabilities explicitly enabled by the client that created the session.
///
/// New native libraries can be loaded by older Dart packages, so every
/// additive capability is fail-closed by default. In particular, an older
/// client must continue to receive raw ZMODEM bytes instead of having them
/// intercepted by a protocol UI it does not know how to drive.
#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct SessionClientCapabilitiesV1 {
    pub zmodem: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct SessionConfigV1Payload {
    pub launch: TerminalProfileLaunch,
    pub connection: TerminalProfileConnection,
    pub terminal: TerminalProfileTerminal,
    #[serde(rename = "shellIntegration")]
    pub shell_integration: TerminalShellIntegration,
    pub appearance: TerminalProfileAppearance,
    pub interaction: TerminalProfileInteraction,
}

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum SessionConfigError {
    #[error("encoded SessionConfig exceeds {MAX_SESSION_CONFIG_BYTES} bytes")]
    EncodedConfigTooLarge,
    #[error("invalid SessionConfig JSON: {0}")]
    InvalidJson(String),
    #[error("unsupported SessionConfig schema version {0}")]
    UnsupportedSchema(u32),
    #[error("unsupported SessionConfig contract {0}")]
    UnsupportedContract(String),
    #[error("invalid session_id")]
    InvalidSessionId,
    #[error("invalid display_name")]
    InvalidDisplayName,
    #[error("invalid launch program")]
    InvalidLaunchProgram,
    #[error("invalid SSH connection")]
    InvalidSshConnection,
    #[error("invalid launch arguments")]
    InvalidLaunchArguments,
    #[error("invalid launch environment")]
    InvalidLaunchEnvironment,
    #[error("invalid launch cwd")]
    InvalidLaunchCwd,
    #[error("invalid terminal graphics limits")]
    InvalidGraphicsLimits,
    #[error("invalid terminal font settings")]
    InvalidFontSettings,
}

impl SessionConfigV1 {
    pub fn decode_json(raw: &str) -> Result<Self, SessionConfigError> {
        if raw.len() > MAX_SESSION_CONFIG_BYTES {
            return Err(SessionConfigError::EncodedConfigTooLarge);
        }
        let raw_value: Value = serde_json::from_str(raw)
            .map_err(|error| SessionConfigError::InvalidJson(error.to_string()))?;
        if let Some(schema_version) = raw_value
            .as_object()
            .and_then(|object| object.get("schema_version"))
            .and_then(Value::as_u64)
            && schema_version != u64::from(SESSION_CONFIG_SCHEMA_VERSION)
        {
            return Err(SessionConfigError::UnsupportedSchema(
                schema_version.try_into().unwrap_or(u32::MAX),
            ));
        }
        if let Some(contract) = raw_value
            .as_object()
            .and_then(|object| object.get("contract"))
            .and_then(Value::as_str)
            && contract != SESSION_CONFIG_CONTRACT
        {
            return Err(SessionConfigError::UnsupportedContract(
                contract.to_string(),
            ));
        }
        validate_exact_session_config_shape(&raw_value).map_err(SessionConfigError::InvalidJson)?;
        let value: Self = serde_json::from_value(raw_value)
            .map_err(|error| SessionConfigError::InvalidJson(error.to_string()))?;
        value.validate()?;
        Ok(value)
    }

    pub fn into_terminal_profile(self) -> TerminalProfile {
        TerminalProfile {
            id: self.session_id,
            name: self.display_name,
            launch: self.config.launch,
            connection: self.config.connection,
            terminal: self.config.terminal,
            shell_integration: self.config.shell_integration,
            appearance: self.config.appearance,
            interaction: self.config.interaction,
        }
    }

    fn validate(&self) -> Result<(), SessionConfigError> {
        if self.schema_version != SESSION_CONFIG_SCHEMA_VERSION {
            return Err(SessionConfigError::UnsupportedSchema(self.schema_version));
        }
        if self.contract != SESSION_CONFIG_CONTRACT {
            return Err(SessionConfigError::UnsupportedContract(
                self.contract.clone(),
            ));
        }
        if self.session_id.is_empty()
            || self.session_id.len() > MAX_SESSION_ID_BYTES
            || !self.session_id.bytes().enumerate().all(|(index, byte)| {
                byte.is_ascii_alphanumeric()
                    || (index > 0 && matches!(byte, b'.' | b'_' | b':' | b'-'))
            })
        {
            return Err(SessionConfigError::InvalidSessionId);
        }
        if invalid_identity_text(&self.display_name, MAX_DISPLAY_NAME_BYTES) {
            return Err(SessionConfigError::InvalidDisplayName);
        }
        let launch = &self.config.launch;
        if launch.program.len() > MAX_PATH_BYTES
            || launch.program.chars().any(char::is_control)
            || (self.config.connection.connection_type == TerminalConnectionType::Local
                && launch.program.trim().is_empty())
        {
            return Err(SessionConfigError::InvalidLaunchProgram);
        }
        let connection = &self.config.connection;
        if connection.connection_type == TerminalConnectionType::Ssh
            && (invalid_identity_text(&connection.host, MAX_PATH_BYTES)
                || invalid_identity_text(&connection.user, MAX_DISPLAY_NAME_BYTES)
                || connection.port == 0
                || connection.private_keys.len() > MAX_ARGUMENTS
                || connection
                    .private_keys
                    .iter()
                    .any(|path| invalid_identity_text(path, MAX_PATH_BYTES))
                || invalid_optional_text(connection.password.as_deref(), MAX_STRING_BYTES)
                || invalid_optional_text(
                    connection.private_key_passphrase.as_deref(),
                    MAX_STRING_BYTES,
                )
                || connection
                    .known_hosts_file
                    .as_ref()
                    .is_some_and(|path| invalid_identity_text(path, MAX_PATH_BYTES))
                || connection
                    .proxy_command
                    .as_ref()
                    .is_some_and(|command| invalid_identity_text(command, MAX_PATH_BYTES))
                || connection
                    .proxy_jump
                    .as_ref()
                    .is_some_and(|jump| invalid_identity_text(jump, MAX_PATH_BYTES))
                || connection.proxy_jump_profiles.len() > MAX_ARGUMENTS
                || connection.proxy_jump_profiles.iter().any(|jump| {
                    invalid_identity_text(&jump.host, MAX_PATH_BYTES)
                        || invalid_identity_text(&jump.user, MAX_DISPLAY_NAME_BYTES)
                        || jump.port == 0
                        || invalid_optional_text(jump.password.as_deref(), MAX_STRING_BYTES)
                        || invalid_optional_text(
                            jump.private_key_passphrase.as_deref(),
                            MAX_STRING_BYTES,
                        )
                        || jump.private_keys.len() > MAX_ARGUMENTS
                        || jump
                            .private_keys
                            .iter()
                            .any(|path| invalid_identity_text(path, MAX_PATH_BYTES))
                        || jump
                            .known_hosts_file
                            .as_ref()
                            .is_some_and(|path| invalid_identity_text(path, MAX_PATH_BYTES))
                        || !(1..=120).contains(&jump.connect_timeout_seconds)
                        || jump.keepalive_seconds > 86_400
                        || !(1..=100).contains(&jump.keepalive_count_max)
                })
                || connection.port_forwards.len() > MAX_ARGUMENTS
                || connection.port_forwards.iter().any(|forward| {
                    invalid_identity_text(&forward.bind_host, MAX_PATH_BYTES)
                        || forward.bind_port == 0
                        || match forward.kind {
                            TerminalSshPortForwardKind::Local
                            | TerminalSshPortForwardKind::Remote => {
                                invalid_identity_text(&forward.target_host, MAX_PATH_BYTES)
                                    || forward.target_port == 0
                            }
                            TerminalSshPortForwardKind::Dynamic => {
                                !forward.target_host.is_empty() || forward.target_port != 0
                            }
                        }
                })
                || connection
                    .agent_socket
                    .as_ref()
                    .is_some_and(|path| invalid_identity_text(path, MAX_PATH_BYTES))
                || connection
                    .x11_target_host
                    .as_ref()
                    .is_some_and(|host| invalid_identity_text(host, MAX_PATH_BYTES))
                || connection.x11_auth_protocol.len() > 128
                || invalid_identity_text(&connection.x11_auth_protocol, 128)
                || connection.x11_auth_cookie.as_ref().is_some_and(|cookie| {
                    cookie.len() != 32 || !cookie.bytes().all(|byte| byte.is_ascii_hexdigit())
                })
                || connection.x11_screen_number > u32::from(u16::MAX)
                || !(1..=120).contains(&connection.connect_timeout_seconds)
                || connection.keepalive_seconds > 86_400
                || !(1..=100).contains(&connection.keepalive_count_max)
                || (connection.x11_forwarding
                    && (connection.x11_auth_protocol != "MIT-MAGIC-COOKIE-1"
                        || !connection.x11_auth_cookie.as_ref().is_some_and(|cookie| {
                            cookie.len() == 32
                                && cookie.bytes().all(|byte| byte.is_ascii_hexdigit())
                        })
                        || match (
                            connection.x11_target_host.as_deref(),
                            connection.x11_target_port,
                        ) {
                            (None, 0) => false,
                            (Some(_), port) if port != 0 => false,
                            _ => true,
                        })))
        {
            return Err(SessionConfigError::InvalidSshConnection);
        }
        if launch.args.len() > MAX_ARGUMENTS
            || launch
                .args
                .iter()
                .any(|argument| argument.len() > MAX_STRING_BYTES || argument.contains('\0'))
        {
            return Err(SessionConfigError::InvalidLaunchArguments);
        }
        if launch.env.len() > MAX_ENVIRONMENT_ENTRIES
            || launch.env.iter().any(|(key, value)| {
                key.is_empty()
                    || key.len() > MAX_STRING_BYTES
                    || value.len() > MAX_STRING_BYTES
                    || key.contains('=')
                    || key.trim() != key
                    || key.contains('\0')
                    || value.contains('\0')
            })
        {
            return Err(SessionConfigError::InvalidLaunchEnvironment);
        }
        if launch
            .cwd
            .as_ref()
            .is_some_and(|cwd| invalid_identity_text(cwd, MAX_PATH_BYTES))
        {
            return Err(SessionConfigError::InvalidLaunchCwd);
        }
        let graphics = &self.config.terminal.graphics;
        if self.config.terminal.scrollback_lines == 0
            || self.config.terminal.scrollback_lines > MAX_SCROLLBACK_LINES
            || !matches!(graphics.advertise.as_str(), "auto" | "kitty" | "none")
            || graphics.max_image_bytes == 0
            || graphics.max_total_bytes == 0
            || graphics.max_image_bytes > MAX_GRAPHICS_BYTES
            || graphics.max_total_bytes > MAX_GRAPHICS_BYTES
            || graphics.max_image_bytes > graphics.max_total_bytes
        {
            return Err(SessionConfigError::InvalidGraphicsLimits);
        }
        let font = &self.config.appearance.font;
        if invalid_identity_text(&font.family, MAX_STRING_BYTES)
            || font.fallback.len() > MAX_FONT_FALLBACKS
            || font
                .fallback
                .iter()
                .any(|family| invalid_identity_text(family, MAX_STRING_BYTES))
            || !font.size.is_finite()
            || font.size <= 0.0
            || font.size > MAX_FONT_SIZE
            || !font.line_height.is_finite()
            || font.line_height <= 0.0
            || font.line_height > MAX_LINE_HEIGHT
        {
            return Err(SessionConfigError::InvalidFontSettings);
        }
        let colors = &self.config.appearance.colors;
        if [
            colors.special.foreground.as_deref(),
            colors.special.background.as_deref(),
            colors.special.cursor.as_deref(),
            colors.special.selection.as_deref(),
            colors.special.tab.as_deref(),
            colors.normal.black.as_deref(),
            colors.normal.red.as_deref(),
            colors.normal.green.as_deref(),
            colors.normal.yellow.as_deref(),
            colors.normal.blue.as_deref(),
            colors.normal.magenta.as_deref(),
            colors.normal.cyan.as_deref(),
            colors.normal.white.as_deref(),
            colors.bright.black.as_deref(),
            colors.bright.red.as_deref(),
            colors.bright.green.as_deref(),
            colors.bright.yellow.as_deref(),
            colors.bright.blue.as_deref(),
            colors.bright.magenta.as_deref(),
            colors.bright.cyan.as_deref(),
            colors.bright.white.as_deref(),
        ]
        .into_iter()
        .flatten()
        .any(|color| !valid_hex_color(color))
        {
            return Err(SessionConfigError::InvalidFontSettings);
        }
        Ok(())
    }
}

const TOP_LEVEL_KEYS: &[&str] = &[
    "schema_version",
    "contract",
    "session_id",
    "display_name",
    "client_capabilities",
    "config",
];
const CONFIG_KEYS: &[&str] = &[
    "launch",
    "connection",
    "terminal",
    "shellIntegration",
    "appearance",
    "interaction",
];
const SSH_CONNECTION_KEYS: &[&str] = &[
    "type",
    "host",
    "user",
    "port",
    "auth",
    "password",
    "privateKeys",
    "privateKeyPassphrase",
    "hostKeyPolicy",
    "knownHostsFile",
    "connectTimeoutSeconds",
    "keepaliveSeconds",
    "keepaliveCountMax",
    "proxyCommand",
    "proxyJump",
    "proxyJumpProfiles",
    "portForwards",
    "agentForwarding",
    "agentSocket",
    "x11Forwarding",
    "x11TargetHost",
    "x11TargetPort",
    "x11AuthProtocol",
    "x11AuthCookie",
    "x11ScreenNumber",
];
const SSH_JUMP_KEYS: &[&str] = &[
    "host",
    "user",
    "port",
    "auth",
    "password",
    "privateKeys",
    "privateKeyPassphrase",
    "hostKeyPolicy",
    "knownHostsFile",
    "connectTimeoutSeconds",
    "keepaliveSeconds",
    "keepaliveCountMax",
];
const ANSI_COLOR_KEYS: &[&str] = &[
    "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
];

fn validate_exact_session_config_shape(value: &Value) -> Result<(), String> {
    let root = exact_object(value, TOP_LEVEL_KEYS, "$")?;
    exact_object(
        required(root, "client_capabilities", "$"),
        &["zmodem"],
        "$.client_capabilities",
    )?;
    let config = exact_object(required(root, "config", "$"), CONFIG_KEYS, "$.config")?;
    exact_object(
        required(config, "launch", "$.config"),
        &["program", "args", "env", "cwd"],
        "$.config.launch",
    )?;

    let connection = required(config, "connection", "$.config");
    let connection_object = connection
        .as_object()
        .ok_or_else(|| "$.config.connection must be an object".to_string())?;
    match connection_object.get("type").and_then(Value::as_str) {
        Some("local") => {
            exact_object(connection, &["type"], "$.config.connection")?;
        }
        Some("ssh") => {
            let ssh = exact_object(connection, SSH_CONNECTION_KEYS, "$.config.connection")?;
            exact_object_array(
                required(ssh, "proxyJumpProfiles", "$.config.connection"),
                SSH_JUMP_KEYS,
                "$.config.connection.proxyJumpProfiles",
            )?;
            exact_object_array(
                required(ssh, "portForwards", "$.config.connection"),
                &["type", "bindHost", "bindPort", "targetHost", "targetPort"],
                "$.config.connection.portForwards",
            )?;
        }
        _ => return Err("$.config.connection.type must be local or ssh".to_string()),
    }

    let terminal = exact_object(
        required(config, "terminal", "$.config"),
        &[
            "emulation",
            "scrollbackLines",
            "graphics",
            "dragDropEnabled",
        ],
        "$.config.terminal",
    )?;
    exact_object(
        required(terminal, "graphics", "$.config.terminal"),
        &["enabled", "advertise", "maxImageBytes", "maxTotalBytes"],
        "$.config.terminal.graphics",
    )?;
    exact_object(
        required(config, "shellIntegration", "$.config"),
        &["enabled"],
        "$.config.shellIntegration",
    )?;
    let appearance = exact_object(
        required(config, "appearance", "$.config"),
        &["font", "colors", "cursor"],
        "$.config.appearance",
    )?;
    exact_object(
        required(appearance, "font", "$.config.appearance"),
        &["family", "fallback", "size", "lineHeight"],
        "$.config.appearance.font",
    )?;
    let colors = exact_object(
        required(appearance, "colors", "$.config.appearance"),
        &["special", "normal", "bright"],
        "$.config.appearance.colors",
    )?;
    exact_object(
        required(colors, "special", "$.config.appearance.colors"),
        &["foreground", "background", "cursor", "selection", "tab"],
        "$.config.appearance.colors.special",
    )?;
    exact_object(
        required(colors, "normal", "$.config.appearance.colors"),
        ANSI_COLOR_KEYS,
        "$.config.appearance.colors.normal",
    )?;
    exact_object(
        required(colors, "bright", "$.config.appearance.colors"),
        ANSI_COLOR_KEYS,
        "$.config.appearance.colors.bright",
    )?;
    exact_object(
        required(appearance, "cursor", "$.config.appearance"),
        &["shape", "blink"],
        "$.config.appearance.cursor",
    )?;
    exact_object(
        required(config, "interaction", "$.config"),
        &["copyOnSelect", "optionDragMode"],
        "$.config.interaction",
    )?;
    Ok(())
}

fn exact_object<'a>(
    value: &'a Value,
    expected: &[&str],
    path: &str,
) -> Result<&'a Map<String, Value>, String> {
    let object = value
        .as_object()
        .ok_or_else(|| format!("{path} must be an object"))?;
    if let Some(key) = object.keys().find(|key| !expected.contains(&key.as_str())) {
        return Err(format!("{path} contains unknown field {key}"));
    }
    if let Some(key) = expected.iter().find(|key| !object.contains_key(**key)) {
        return Err(format!("{path} is missing field {key}"));
    }
    Ok(object)
}

fn exact_object_array(value: &Value, expected: &[&str], path: &str) -> Result<(), String> {
    let values = value
        .as_array()
        .ok_or_else(|| format!("{path} must be an array"))?;
    for (index, value) in values.iter().enumerate() {
        exact_object(value, expected, &format!("{path}[{index}]"))?;
    }
    Ok(())
}

fn required<'a>(object: &'a Map<String, Value>, key: &str, path: &str) -> &'a Value {
    object
        .get(key)
        .unwrap_or_else(|| unreachable!("{path} exact-shape gate requires {key}"))
}

fn invalid_identity_text(value: &str, maximum: usize) -> bool {
    value.trim().is_empty()
        || value.trim() != value
        || value.len() > maximum
        || value.chars().any(|character| character.is_control())
}

fn invalid_optional_text(value: Option<&str>, maximum: usize) -> bool {
    value.is_some_and(|value| invalid_identity_text(value, maximum))
}

fn valid_hex_color(value: &str) -> bool {
    value.len() == 7
        && value.starts_with('#')
        && value[1..].bytes().all(|byte| byte.is_ascii_hexdigit())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{TerminalSshAuthMethod, TerminalSshPortForwardKind};

    const SHAPE_CORPUS: &str =
        include_str!("../tests/fixtures/session_config/session_config_v1_shape_corpus.json");

    fn corpus() -> Value {
        serde_json::from_str(SHAPE_CORPUS).expect("SessionConfig shape corpus")
    }

    fn valid(name: &str) -> Value {
        corpus()[name].clone()
    }

    fn object_at_mut<'a>(root: &'a mut Value, pointer: &str) -> &'a mut Map<String, Value> {
        let mut value = root;
        for segment in pointer
            .split('/')
            .skip(1)
            .filter(|segment| !segment.is_empty())
        {
            value = match value {
                Value::Object(object) => object.get_mut(segment).expect("object path segment"),
                Value::Array(values) => &mut values[segment.parse::<usize>().expect("array index")],
                _ => panic!("invalid corpus pointer {pointer}"),
            };
        }
        value.as_object_mut().expect("closed object path")
    }

    fn value_at<'a>(root: &'a Value, pointer: &str) -> &'a Value {
        pointer
            .split('/')
            .skip(1)
            .filter(|segment| !segment.is_empty())
            .fold(root, |value, segment| match value {
                Value::Object(object) => object.get(segment).expect("object path segment"),
                Value::Array(values) => &values[segment.parse::<usize>().expect("array index")],
                _ => panic!("invalid corpus pointer {pointer}"),
            })
    }

    fn replace_at(root: &mut Value, pointer: &str, replacement: Value) {
        let mut segments = pointer
            .split('/')
            .skip(1)
            .filter(|segment| !segment.is_empty())
            .collect::<Vec<_>>();
        let last = segments.pop().expect("non-root mutation path");
        let mut parent = root;
        for segment in segments {
            parent = match parent {
                Value::Object(object) => object.get_mut(segment).expect("object path segment"),
                Value::Array(values) => &mut values[segment.parse::<usize>().expect("array index")],
                _ => panic!("invalid corpus pointer {pointer}"),
            };
        }
        match parent {
            Value::Object(object) => {
                object.insert(last.to_string(), replacement);
            }
            Value::Array(values) => {
                values[last.parse::<usize>().expect("array index")] = replacement;
            }
            _ => panic!("invalid corpus pointer {pointer}"),
        }
    }

    fn materialize_mutation(specification: &Value, current: Option<&Value>) -> Value {
        let Some(object) = specification.as_object() else {
            return match specification {
                Value::Array(values) => Value::Array(
                    values
                        .iter()
                        .map(|value| materialize_mutation(value, None))
                        .collect(),
                ),
                _ => specification.clone(),
            };
        };
        let Some(operation) = object.get("op").and_then(Value::as_str) else {
            return Value::Object(
                object
                    .iter()
                    .map(|(key, value)| (key.clone(), materialize_mutation(value, None)))
                    .collect(),
            );
        };
        let count = object["count"].as_u64().expect("mutation count") as usize;
        match operation {
            "repeat_string" => Value::String(
                object["value"]
                    .as_str()
                    .expect("repeat string value")
                    .repeat(count),
            ),
            "repeat_array" => Value::Array(
                (0..count)
                    .map(|_| materialize_mutation(&object["value"], None))
                    .collect(),
            ),
            "repeat_current_array_item" => {
                let first = current
                    .and_then(Value::as_array)
                    .and_then(|values| values.first())
                    .expect("current array item");
                Value::Array((0..count).map(|_| first.clone()).collect())
            }
            "oversized_string_map" => Value::Object(
                (0..count)
                    .map(|index| (format!("KEY_{index}"), Value::String("value".into())))
                    .collect(),
            ),
            _ => panic!("unknown corpus mutation operation {operation}"),
        }
    }

    fn case_alias(key: &str) -> String {
        let mut chars = key.chars();
        let first = chars.next().expect("non-empty JSON key");
        let alias = if first.is_ascii_uppercase() {
            first.to_ascii_lowercase()
        } else {
            first.to_ascii_uppercase()
        };
        format!("{alias}{}", chars.as_str())
    }

    #[test]
    fn rejects_unknown_schema_before_runtime_creation() {
        let mut value = valid("valid_local");
        value["schema_version"] = Value::from(2);

        assert_eq!(
            SessionConfigV1::decode_json(&value.to_string()).unwrap_err(),
            SessionConfigError::UnsupportedSchema(2)
        );
    }

    #[test]
    fn rejects_every_shared_missing_unknown_and_case_shape_mutation() {
        let corpus = corpus();
        let valid_ssh = corpus["valid_ssh"].clone();
        let paths = corpus["closed_object_paths"]
            .as_array()
            .expect("closed paths");

        SessionConfigV1::decode_json(&corpus["valid_local"].to_string())
            .expect("valid local corpus");
        SessionConfigV1::decode_json(&valid_ssh.to_string()).expect("valid SSH corpus");

        for path in paths {
            let path = path.as_str().expect("string path");
            let keys = {
                let mut source = valid_ssh.clone();
                object_at_mut(&mut source, path)
                    .keys()
                    .cloned()
                    .collect::<Vec<_>>()
            };
            for key in keys {
                let mut missing = valid_ssh.clone();
                object_at_mut(&mut missing, path).remove(&key);
                assert!(
                    matches!(
                        SessionConfigV1::decode_json(&missing.to_string()),
                        Err(SessionConfigError::InvalidJson(_))
                    ),
                    "missing {path}/{key}"
                );

                let mut case_variant = valid_ssh.clone();
                let object = object_at_mut(&mut case_variant, path);
                let value = object.remove(&key).expect("existing key");
                object.insert(case_alias(&key), value);
                assert!(
                    matches!(
                        SessionConfigV1::decode_json(&case_variant.to_string()),
                        Err(SessionConfigError::InvalidJson(_))
                    ),
                    "case alias {path}/{key}"
                );
            }

            let mut unknown = valid_ssh.clone();
            object_at_mut(&mut unknown, path).insert("future_field".into(), Value::Bool(true));
            assert!(
                matches!(
                    SessionConfigV1::decode_json(&unknown.to_string()),
                    Err(SessionConfigError::InvalidJson(_))
                ),
                "unknown field at {path}"
            );
        }

        for mutation in ["missing", "case", "unknown"] {
            let mut local = corpus["valid_local"].clone();
            let connection = object_at_mut(&mut local, "/config/connection");
            match mutation {
                "missing" => {
                    connection.remove("type");
                }
                "case" => {
                    let value = connection.remove("type").expect("type");
                    connection.insert("Type".into(), value);
                }
                "unknown" => {
                    connection.insert("future_field".into(), Value::Bool(true));
                }
                _ => unreachable!(),
            }
            assert!(matches!(
                SessionConfigV1::decode_json(&local.to_string()),
                Err(SessionConfigError::InvalidJson(_))
            ));
        }
    }

    #[test]
    fn rejects_every_shared_invalid_value_without_normalization() {
        let corpus = corpus();
        let groups = corpus["value_mutation_groups"]
            .as_array()
            .expect("value mutation groups");
        for group in groups {
            let id = group["id"].as_str().expect("group id");
            let base = group["base"].as_str().expect("group base");
            for path in group["paths"].as_array().expect("mutation paths") {
                let path = path.as_str().expect("mutation path");
                for (index, specification) in group["invalid_values"]
                    .as_array()
                    .expect("invalid values")
                    .iter()
                    .enumerate()
                {
                    let mut invalid = corpus[base].clone();
                    let current = value_at(&invalid, path).clone();
                    let replacement = materialize_mutation(specification, Some(&current));
                    replace_at(&mut invalid, path, replacement);
                    assert!(
                        SessionConfigV1::decode_json(&invalid.to_string()).is_err(),
                        "accepted {id} {path} mutation {index}"
                    );
                }
            }
        }
    }

    #[test]
    fn rejects_zero_scrollback_instead_of_normalizing_it() {
        let mut value = valid("valid_local");
        value["config"]["terminal"]["scrollbackLines"] = Value::from(0);
        assert_eq!(
            SessionConfigV1::decode_json(&value.to_string()).unwrap_err(),
            SessionConfigError::InvalidGraphicsLimits
        );
    }

    #[test]
    fn decodes_explicit_zmodem_client_opt_in() {
        let decoded = SessionConfigV1::decode_json(&valid("valid_ssh").to_string()).unwrap();
        assert!(decoded.client_capabilities.zmodem);
    }

    #[test]
    fn decodes_ssh_connection_without_a_local_launch_program() {
        let decoded = SessionConfigV1::decode_json(&valid("valid_ssh").to_string()).unwrap();
        assert_eq!(decoded.config.connection.host, "target.example.test");
        assert_eq!(decoded.config.connection.port, 22);
        assert_eq!(
            decoded.config.connection.auth,
            TerminalSshAuthMethod::PublicKey
        );
    }

    #[test]
    fn decodes_advanced_ssh_forwarding_configuration() {
        let mut value = valid("valid_ssh");
        value["config"]["connection"]["auth"] = Value::from("keyboard_interactive");
        value["config"]["connection"]["agentForwarding"] = Value::Bool(true);
        value["config"]["connection"]["agentSocket"] = Value::from("/tmp/agent.sock");
        value["config"]["connection"]["x11Forwarding"] = Value::Bool(true);
        value["config"]["connection"]["x11TargetHost"] = Value::from("127.0.0.1");
        value["config"]["connection"]["x11TargetPort"] = Value::from(6000);
        value["config"]["connection"]["x11AuthCookie"] =
            Value::from("00112233445566778899aabbccddeeff");
        let decoded = SessionConfigV1::decode_json(&value.to_string()).unwrap();
        let connection = decoded.config.connection;
        assert_eq!(connection.auth, TerminalSshAuthMethod::KeyboardInteractive);
        assert_eq!(
            connection.proxy_jump.as_deref(),
            Some("jump-user@jump.example.test")
        );
        assert_eq!(connection.port_forwards.len(), 1);
        assert_eq!(
            connection.port_forwards[0].kind,
            TerminalSshPortForwardKind::Local
        );
        assert!(connection.agent_forwarding);
        assert!(connection.x11_forwarding);
        assert_eq!(connection.x11_target_port, 6000);
    }

    #[test]
    fn decodes_independent_proxy_jump_profiles() {
        let mut value = valid("valid_ssh");
        value["config"]["connection"]["password"] = Value::from("target-secret");
        value["config"]["connection"]["proxyJumpProfiles"][0]["password"] =
            Value::from("jump-secret");
        let decoded = SessionConfigV1::decode_json(&value.to_string()).expect("jump config");
        let connection = decoded.config.connection;
        assert_eq!(connection.proxy_jump_profiles.len(), 1);
        let jump = &connection.proxy_jump_profiles[0];
        assert_eq!(jump.host, "jump.example.test");
        assert_eq!(jump.password.as_deref(), Some("jump-secret"));
        assert_ne!(jump.password, connection.password);
    }

    #[test]
    fn rejects_invalid_dynamic_and_incomplete_x11_forwards() {
        let mut dynamic = valid("valid_ssh");
        dynamic["config"]["connection"]["portForwards"][0]["type"] = Value::from("dynamic");
        dynamic["config"]["connection"]["portForwards"][0]["targetHost"] =
            Value::from("must-be-empty");
        dynamic["config"]["connection"]["portForwards"][0]["targetPort"] = Value::from(22);
        let mut x11 = valid("valid_ssh");
        x11["config"]["connection"]["x11Forwarding"] = Value::Bool(true);
        x11["config"]["connection"]["x11TargetHost"] = Value::from("127.0.0.1");
        for value in [dynamic, x11] {
            assert_eq!(
                SessionConfigV1::decode_json(&value.to_string()).unwrap_err(),
                SessionConfigError::InvalidSshConnection
            );
        }
    }
}
