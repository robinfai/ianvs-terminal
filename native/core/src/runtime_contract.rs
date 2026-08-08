use crate::model::TERMINAL_FRAME_SCHEMA_VERSION;
use serde::{Deserialize, Serialize};
use serde_json::Value;

pub const RUNTIME_CAPABILITIES_SCHEMA_VERSION: u32 = 1;
pub const RUNTIME_CONTRACT: &str = "ianvs-runtime-contract-v1";
pub const RUNTIME_ENVELOPE_SCHEMA_VERSION: u32 = 1;
pub const RUNTIME_ENVELOPE_CONTRACT: &str = "ianvs-runtime-envelope-v1";
pub const RUNTIME_EVENT_BATCH_CONTRACT: &str = "ianvs-runtime-event-batch-v1";
pub const FRAME_PACKET_SCHEMA_VERSION: u32 = 1;
pub const FRAME_PACKET_CONTRACT: &str = "ianvs-terminal-frame-packet-v1";
pub const GRAPHIC_ASSET_PACKET_SCHEMA_VERSION: u32 = 1;
pub const GRAPHIC_ASSET_PACKET_CONTRACT: &str = "ianvs-graphic-asset-packet-v1";
pub const GRAPHIC_ASSET_PACKET_MAX_RGBA_BYTES: usize = 100 * 1024 * 1024;

const RECORDING_SCHEMA_VERSION: u32 = 1;
const FEATURES: &[&str] = &[
    "diagnostic-event.json.v1",
    "diagnostics.json.v1",
    "event-envelope.json.v1",
    "file-download.v1",
    "frame-packet.protobuf.v1",
    "frame.json.v1",
    "frame.protobuf.v1",
    "graphic-asset-packet.protobuf.v1",
    "graphic-asset.rgba.v1",
    "host-request-response.json.v1",
    "refresh-hint.v1",
    "replay-checkpoint.v1",
    "replay-session.v1",
    "session-config.json.v1",
    "session-recording.v1",
    "session-request-envelope.json.v1",
    "session-request.json.v1",
    "ssh-session.v1",
    "zmodem.receive.v1",
    "zmodem.send.v1",
];

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum RuntimeMessageClass {
    Command,
    Event,
    Frame,
    AssetTransfer,
    Diagnostic,
    Error,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub struct RuntimeEnvelopeV1 {
    pub schema_version: u32,
    pub contract: String,
    pub message_class: RuntimeMessageClass,
    pub message_name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub session_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sequence: Option<u64>,
    pub timestamp_micros: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub payload: Option<Value>,
}

impl RuntimeEnvelopeV1 {
    pub fn event(
        session_id: u64,
        sequence: u64,
        timestamp_micros: u64,
        message_name: String,
        payload: Option<Value>,
    ) -> Self {
        Self {
            schema_version: RUNTIME_ENVELOPE_SCHEMA_VERSION,
            contract: RUNTIME_ENVELOPE_CONTRACT.to_owned(),
            message_class: RuntimeMessageClass::Event,
            message_name,
            session_id: Some(session_id.to_string()),
            sequence: Some(sequence),
            timestamp_micros,
            payload,
        }
    }

    pub fn diagnostic(
        session_id: u64,
        sequence: u64,
        timestamp_micros: u64,
        message_name: String,
        payload: Value,
    ) -> Self {
        Self {
            schema_version: RUNTIME_ENVELOPE_SCHEMA_VERSION,
            contract: RUNTIME_ENVELOPE_CONTRACT.to_owned(),
            message_class: RuntimeMessageClass::Diagnostic,
            message_name,
            session_id: Some(session_id.to_string()),
            sequence: Some(sequence),
            timestamp_micros,
            payload: Some(payload),
        }
    }
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub struct RuntimeEventBatchV1 {
    pub schema_version: u32,
    pub contract: String,
    pub message_class: RuntimeMessageClass,
    pub session_id: String,
    pub next_sequence: u64,
    pub dropped_count: u64,
    pub messages: Vec<RuntimeEnvelopeV1>,
}

impl RuntimeEventBatchV1 {
    pub fn new(
        session_id: u64,
        next_sequence: u64,
        dropped_count: u64,
        messages: Vec<RuntimeEnvelopeV1>,
    ) -> Self {
        Self {
            schema_version: RUNTIME_ENVELOPE_SCHEMA_VERSION,
            contract: RUNTIME_EVENT_BATCH_CONTRACT.to_owned(),
            message_class: RuntimeMessageClass::Event,
            session_id: session_id.to_string(),
            next_sequence,
            dropped_count,
            messages,
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct RuntimeCapabilities {
    pub schema_version: u32,
    pub runtime_contract: String,
    pub frame_schema_versions: Vec<String>,
    pub recording_schema_versions: Vec<u32>,
    pub features: Vec<String>,
}

impl RuntimeCapabilities {
    pub fn current() -> Self {
        Self {
            schema_version: RUNTIME_CAPABILITIES_SCHEMA_VERSION,
            runtime_contract: RUNTIME_CONTRACT.to_owned(),
            frame_schema_versions: vec![TERMINAL_FRAME_SCHEMA_VERSION.to_owned()],
            recording_schema_versions: vec![RECORDING_SCHEMA_VERSION],
            features: FEATURES
                .iter()
                .filter(|feature| {
                    cfg!(any(target_os = "macos", target_os = "linux"))
                        || !matches!(**feature, "zmodem.receive.v1" | "zmodem.send.v1")
                })
                .map(|feature| (*feature).to_owned())
                .collect(),
        }
    }
}

pub fn runtime_capabilities_json() -> Result<String, serde_json::Error> {
    serde_json::to_string(&RuntimeCapabilities::current())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn current_features_are_sorted_and_unique() {
        let capabilities = RuntimeCapabilities::current();
        assert!(
            capabilities
                .features
                .windows(2)
                .all(|pair| pair[0] < pair[1])
        );
        assert_eq!(
            capabilities
                .features
                .iter()
                .any(|feature| feature == "zmodem.receive.v1"),
            cfg!(any(target_os = "macos", target_os = "linux"))
        );
        assert_eq!(
            capabilities
                .features
                .iter()
                .any(|feature| feature == "zmodem.send.v1"),
            cfg!(any(target_os = "macos", target_os = "linux"))
        );
    }

    #[test]
    fn runtime_message_class_taxonomy_has_stable_wire_names() {
        let classes = [
            RuntimeMessageClass::Command,
            RuntimeMessageClass::Event,
            RuntimeMessageClass::Frame,
            RuntimeMessageClass::AssetTransfer,
            RuntimeMessageClass::Diagnostic,
            RuntimeMessageClass::Error,
        ];
        let wire_names = classes
            .into_iter()
            .map(|class| serde_json::to_value(class).unwrap())
            .collect::<Vec<_>>();
        assert_eq!(
            wire_names,
            serde_json::json!([
                "command",
                "event",
                "frame",
                "asset_transfer",
                "diagnostic",
                "error"
            ])
            .as_array()
            .unwrap()
            .to_owned()
        );
    }
}
