use crate::model::{
    TerminalProfile, TerminalProfileAppearance, TerminalProfileInteraction, TerminalProfileLaunch,
    TerminalProfileTerminal, TerminalShellIntegration, normalize_scrollback_lines,
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
    pub config: SessionConfigV1Payload,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct SessionConfigV1Payload {
    pub launch: TerminalProfileLaunch,
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
        if launch.program.trim().is_empty()
            || launch.program.len() > MAX_PATH_BYTES
            || launch.program.contains('\0')
        {
            return Err(SessionConfigError::InvalidLaunchProgram);
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
    }
}
