use crate::model::{
    TerminalConnectionType, TerminalProfile, TerminalProfileAppearance, TerminalProfileConnection,
    TerminalProfileInteraction, TerminalProfileLaunch, TerminalProfileTerminal,
    TerminalShellIntegration, TerminalSshPortForwardKind, normalize_scrollback_lines,
};
use serde::{Deserialize, Serialize};

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

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct SessionConfigV1 {
    pub schema_version: u32,
    pub contract: String,
    pub session_id: String,
    pub display_name: String,
    #[serde(rename = "client_capabilities", default)]
    pub client_capabilities: SessionClientCapabilitiesV1,
    pub config: SessionConfigV1Payload,
}

/// Capabilities explicitly enabled by the client that created the session.
///
/// New native libraries can be loaded by older Dart packages, so every
/// additive capability is fail-closed by default. In particular, an older
/// client must continue to receive raw ZMODEM bytes instead of having them
/// intercepted by a protocol UI it does not know how to drive.
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct SessionClientCapabilitiesV1 {
    #[serde(default)]
    pub zmodem: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct SessionConfigV1Payload {
    pub launch: TerminalProfileLaunch,
    #[serde(default)]
    pub connection: TerminalProfileConnection,
    #[serde(default)]
    pub terminal: TerminalProfileTerminal,
    #[serde(rename = "shellIntegration", default)]
    pub shell_integration: TerminalShellIntegration,
    #[serde(default)]
    pub appearance: TerminalProfileAppearance,
    #[serde(default)]
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
        let mut value: Self = serde_json::from_str(raw)
            .map_err(|error| SessionConfigError::InvalidJson(error.to_string()))?;
        value.validate()?;
        value.config.terminal.scrollback_lines =
            normalize_scrollback_lines(value.config.terminal.scrollback_lines);
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
        if self.config.connection.connection_type == TerminalConnectionType::Local
            && (launch.program.trim().is_empty()
                || launch.program.len() > MAX_PATH_BYTES
                || launch.program.contains('\0'))
        {
            return Err(SessionConfigError::InvalidLaunchProgram);
        }
        let connection = &self.config.connection;
        if connection.connection_type == TerminalConnectionType::Ssh
            && (invalid_identity_text(&connection.host, MAX_PATH_BYTES)
                || invalid_identity_text(&connection.user, MAX_DISPLAY_NAME_BYTES)
                || connection.port == 0
                || connection.private_keys.len() > MAX_ARGUMENTS
                || connection.private_keys.iter().any(|path| {
                    path.is_empty() || path.len() > MAX_PATH_BYTES || path.contains('\0')
                })
                || connection
                    .known_hosts_file
                    .as_ref()
                    .is_some_and(|path| path.len() > MAX_PATH_BYTES || path.contains('\0'))
                || connection.proxy_command.as_ref().is_some_and(|command| {
                    command.len() > MAX_STRING_BYTES || command.contains('\0')
                })
                || connection
                    .proxy_jump
                    .as_ref()
                    .is_some_and(|jump| jump.len() > MAX_PATH_BYTES || jump.contains('\0'))
                || connection.proxy_jump_profiles.len() > MAX_ARGUMENTS
                || connection.proxy_jump_profiles.iter().any(|jump| {
                    (!jump.host.is_empty() && invalid_identity_text(&jump.host, MAX_PATH_BYTES))
                        || (!jump.user.is_empty()
                            && invalid_identity_text(&jump.user, MAX_DISPLAY_NAME_BYTES))
                        || jump.password.as_ref().is_some_and(|password| {
                            password.len() > MAX_STRING_BYTES || password.contains('\0')
                        })
                        || jump
                            .private_key_passphrase
                            .as_ref()
                            .is_some_and(|passphrase| {
                                passphrase.len() > MAX_STRING_BYTES || passphrase.contains('\0')
                            })
                        || jump.private_keys.len() > MAX_ARGUMENTS
                        || jump.private_keys.iter().any(|path| {
                            path.is_empty() || path.len() > MAX_PATH_BYTES || path.contains('\0')
                        })
                        || jump
                            .known_hosts_file
                            .as_ref()
                            .is_some_and(|path| path.len() > MAX_PATH_BYTES || path.contains('\0'))
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
                || connection.agent_socket.as_ref().is_some_and(|path| {
                    path.is_empty() || path.len() > MAX_PATH_BYTES || path.contains('\0')
                })
                || connection
                    .x11_target_host
                    .as_ref()
                    .is_some_and(|host| invalid_identity_text(host, MAX_PATH_BYTES))
                || connection.x11_auth_protocol.len() > 128
                || connection.x11_auth_protocol.chars().any(char::is_control)
                || connection.x11_auth_cookie.as_ref().is_some_and(|cookie| {
                    cookie.len() > 4096 || cookie.chars().any(char::is_control)
                })
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
                    || key.contains('\0')
                    || value.contains('\0')
            })
        {
            return Err(SessionConfigError::InvalidLaunchEnvironment);
        }
        if launch
            .cwd
            .as_ref()
            .is_some_and(|cwd| cwd.len() > MAX_PATH_BYTES || cwd.contains('\0'))
        {
            return Err(SessionConfigError::InvalidLaunchCwd);
        }
        let graphics = &self.config.terminal.graphics;
        if graphics.max_image_bytes == 0
            || graphics.max_total_bytes == 0
            || graphics.max_image_bytes > graphics.max_total_bytes
        {
            return Err(SessionConfigError::InvalidGraphicsLimits);
        }
        let font = &self.config.appearance.font;
        if font.family.len() > MAX_STRING_BYTES
            || font.fallback.len() > MAX_FONT_FALLBACKS
            || font
                .fallback
                .iter()
                .any(|family| family.len() > MAX_STRING_BYTES)
            || !font.size.is_finite()
            || font.size <= 0.0
            || !font.line_height.is_finite()
            || font.line_height <= 0.0
        {
            return Err(SessionConfigError::InvalidFontSettings);
        }
        Ok(())
    }
}

fn invalid_identity_text(value: &str, maximum: usize) -> bool {
    value.trim().is_empty()
        || value.len() > maximum
        || value.chars().any(|character| character.is_control())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::TerminalSshAuthMethod;

    #[test]
    fn rejects_unknown_schema_before_runtime_creation() {
        let raw = serde_json::json!({
            "schema_version": 2,
            "contract": SESSION_CONFIG_CONTRACT,
            "session_id": "runtime-1",
            "display_name": "shell",
            "config": {"launch": {"program": "/bin/sh"}}
        })
        .to_string();

        assert_eq!(
            SessionConfigV1::decode_json(&raw).unwrap_err(),
            SessionConfigError::UnsupportedSchema(2)
        );
    }

    #[test]
    fn ignores_additive_fields_and_normalizes_scrollback() {
        let raw = serde_json::json!({
            "schema_version": 1,
            "contract": SESSION_CONFIG_CONTRACT,
            "session_id": "runtime-1",
            "display_name": "shell",
            "config": {
                "launch": {"program": "/bin/sh"},
                "terminal": {"scrollbackLines": 0},
                "future": true
            },
            "future": true
        })
        .to_string();

        let decoded = SessionConfigV1::decode_json(&raw).unwrap();
        assert_eq!(decoded.config.terminal.scrollback_lines, 1);
        assert!(!decoded.client_capabilities.zmodem);
    }

    #[test]
    fn decodes_explicit_zmodem_client_opt_in() {
        let raw = serde_json::json!({
            "schema_version": 1,
            "contract": SESSION_CONFIG_CONTRACT,
            "session_id": "runtime-1",
            "display_name": "shell",
            "client_capabilities": {"zmodem": true},
            "config": {"launch": {"program": "/bin/sh"}}
        })
        .to_string();

        let decoded = SessionConfigV1::decode_json(&raw).unwrap();
        assert!(decoded.client_capabilities.zmodem);
    }

    #[test]
    fn decodes_ssh_connection_without_a_local_launch_program() {
        let raw = serde_json::json!({
            "schema_version": 1,
            "contract": SESSION_CONFIG_CONTRACT,
            "session_id": "ssh-runtime-1",
            "display_name": "production",
            "config": {
                "launch": {"program": ""},
                "connection": {
                    "type": "ssh",
                    "host": "ssh.example.test",
                    "user": "operator",
                    "port": 2222,
                    "auth": "password",
                    "password": "transient-secret"
                }
            }
        })
        .to_string();

        let decoded = SessionConfigV1::decode_json(&raw).unwrap();
        assert_eq!(decoded.config.connection.host, "ssh.example.test");
        assert_eq!(decoded.config.connection.port, 2222);
        assert_eq!(
            decoded.config.connection.password.as_deref(),
            Some("transient-secret")
        );
    }

    #[test]
    fn rejects_incomplete_ssh_connection() {
        let raw = serde_json::json!({
            "schema_version": 1,
            "contract": SESSION_CONFIG_CONTRACT,
            "session_id": "ssh-runtime-1",
            "display_name": "production",
            "config": {
                "launch": {"program": ""},
                "connection": {"type": "ssh", "host": "", "user": "operator"}
            }
        })
        .to_string();

        assert_eq!(
            SessionConfigV1::decode_json(&raw).unwrap_err(),
            SessionConfigError::InvalidSshConnection
        );
    }

    #[test]
    fn decodes_advanced_ssh_forwarding_configuration() {
        let raw = serde_json::json!({
            "schema_version": 1,
            "contract": SESSION_CONFIG_CONTRACT,
            "session_id": "ssh-runtime-advanced",
            "display_name": "forwarding",
            "config": {
                "launch": {"program": ""},
                "connection": {
                    "type": "ssh",
                    "host": "ssh.example.test",
                    "user": "operator",
                    "auth": "keyboard_interactive",
                    "proxyJump": "jump-a,jump-b:2222",
                    "portForwards": [
                        {
                            "type": "local",
                            "bindHost": "127.0.0.1",
                            "bindPort": 8080,
                            "targetHost": "app.internal",
                            "targetPort": 80
                        },
                        {
                            "type": "dynamic",
                            "bindHost": "127.0.0.1",
                            "bindPort": 1080
                        }
                    ],
                    "agentForwarding": true,
                    "agentSocket": "/tmp/agent.sock",
                    "x11Forwarding": true,
                    "x11TargetHost": "127.0.0.1",
                    "x11TargetPort": 6000,
                    "x11AuthCookie": "00112233445566778899aabbccddeeff"
                }
            }
        })
        .to_string();

        let decoded = SessionConfigV1::decode_json(&raw).unwrap();
        let connection = decoded.config.connection;
        assert_eq!(connection.auth, TerminalSshAuthMethod::KeyboardInteractive);
        assert_eq!(connection.proxy_jump.as_deref(), Some("jump-a,jump-b:2222"));
        assert_eq!(connection.port_forwards.len(), 2);
        assert_eq!(
            connection.port_forwards[1].kind,
            TerminalSshPortForwardKind::Dynamic
        );
        assert!(connection.agent_forwarding);
        assert!(connection.x11_forwarding);
        assert_eq!(connection.x11_target_port, 6000);
    }

    #[test]
    fn decodes_independent_proxy_jump_profiles() {
        let raw = serde_json::json!({
            "schema_version": 1,
            "contract": SESSION_CONFIG_CONTRACT,
            "session_id": "ssh-runtime-jump",
            "display_name": "jump",
            "config": {
                "launch": {},
                "connection": {
                    "type": "ssh",
                    "host": "target.internal",
                    "user": "target-user",
                    "auth": "password",
                    "password": "target-secret",
                    "proxyJump": "jump-user@jump-alias",
                    "proxyJumpProfiles": [{
                        "host": "jump.internal",
                        "user": "jump-user",
                        "auth": "password",
                        "password": "jump-secret",
                        "hostKeyPolicy": "strict"
                    }]
                }
            }
        })
        .to_string();

        let decoded = SessionConfigV1::decode_json(&raw).expect("jump config");
        let connection = decoded.config.connection;
        assert_eq!(connection.proxy_jump_profiles.len(), 1);
        let jump = &connection.proxy_jump_profiles[0];
        assert_eq!(jump.host, "jump.internal");
        assert_eq!(jump.password.as_deref(), Some("jump-secret"));
        assert_ne!(jump.password, connection.password);
    }

    #[test]
    fn rejects_invalid_dynamic_and_incomplete_x11_forwards() {
        for connection in [
            serde_json::json!({
                "type": "ssh",
                "host": "ssh.example.test",
                "user": "operator",
                "portForwards": [{
                    "type": "dynamic",
                    "bindHost": "127.0.0.1",
                    "bindPort": 1080,
                    "targetHost": "must-be-empty",
                    "targetPort": 22
                }]
            }),
            serde_json::json!({
                "type": "ssh",
                "host": "ssh.example.test",
                "user": "operator",
                "x11Forwarding": true,
                "x11TargetHost": "127.0.0.1"
            }),
        ] {
            let raw = serde_json::json!({
                "schema_version": 1,
                "contract": SESSION_CONFIG_CONTRACT,
                "session_id": "ssh-runtime-invalid",
                "display_name": "invalid",
                "config": {"launch": {"program": ""}, "connection": connection}
            })
            .to_string();
            assert_eq!(
                SessionConfigV1::decode_json(&raw).unwrap_err(),
                SessionConfigError::InvalidSshConnection
            );
        }
    }
}
