use base64::{Engine as _, engine::general_purpose::STANDARD};
use serde::{Deserialize, Serialize};
use serde_json::Value;

pub const HOST_REQUEST_SCHEMA_VERSION: u32 = 1;
pub const HOST_REQUEST_CONTRACT: &str = "ianvs-host-request-v1";
pub const HOST_RESPONSE_CONTRACT: &str = "ianvs-host-response-v1";
pub const HOST_REQUEST_EVENT_NAME: &str = "host_request";
pub const MAX_HOST_REQUEST_BYTES: usize = 64 * 1024;
pub const MAX_HOST_RESPONSE_BYTES: usize = 6 * 1024 * 1024;

const CLIPBOARD_READ_OPERATION: &str = "clipboard.read_text";
const MAX_CLIPBOARD_BYTES: usize = 4 * 1024 * 1024;
const MAX_CORRELATION_BYTES: usize = 128;
const MAX_ERROR_MESSAGE_BYTES: usize = 1024;
const MAX_JSON_SAFE_INTEGER: u64 = 9_007_199_254_740_991;

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub struct HostRequestV1 {
    pub schema_version: u32,
    pub contract: String,
    pub request_id: String,
    pub session_id: String,
    pub operation: String,
    pub sequence: u64,
    pub timestamp_micros: u64,
    pub payload: Value,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub struct HostResponseErrorV1 {
    pub code: String,
    pub message: String,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub struct HostResponseV1 {
    pub schema_version: u32,
    pub contract: String,
    pub request_id: String,
    pub session_id: String,
    pub operation: String,
    pub ok: bool,
    pub timestamp_micros: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub payload: Option<Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<HostResponseErrorV1>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct PendingHostRequestV1 {
    pub request_id: String,
    pub session_id: String,
    pub operation: String,
    pub selection: String,
}

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum HostResponseError {
    #[error("encoded Host Response exceeds 6 MiB")]
    EncodedResponseTooLarge,
    #[error("invalid Host Response JSON")]
    InvalidJson,
    #[error("unsupported Host Response schema")]
    UnsupportedSchema,
    #[error("unsupported Host Response contract")]
    UnsupportedContract,
    #[error("invalid Host Response request id")]
    InvalidRequestId,
    #[error("invalid Host Response session id")]
    InvalidSessionId,
    #[error("invalid Host Response operation")]
    InvalidOperation,
    #[error("invalid Host Response timestamp")]
    InvalidTimestamp,
    #[error("invalid Host Response state")]
    InvalidResponseState,
    #[error("invalid Host Response error")]
    InvalidError,
    #[error("Host Response correlation mismatch")]
    CorrelationMismatch,
    #[error("unsupported Host Response operation")]
    UnsupportedOperation,
    #[error("invalid Host Response payload")]
    InvalidPayload,
}

pub fn host_request_v1_from_event(
    session_id: u64,
    sequence: u64,
    timestamp_micros: u64,
    kind: &str,
    payload: Option<Value>,
) -> Option<HostRequestV1> {
    if kind != "clipboard_paste_request"
        || sequence > MAX_JSON_SAFE_INTEGER
        || timestamp_micros > MAX_JSON_SAFE_INTEGER
    {
        return None;
    }
    let selection = payload
        .as_ref()
        .and_then(Value::as_object)
        .and_then(|value| value.get("selection"))
        .and_then(Value::as_str)
        .unwrap_or("c");
    if !valid_selection(selection) {
        return None;
    }
    let request = HostRequestV1 {
        schema_version: HOST_REQUEST_SCHEMA_VERSION,
        contract: HOST_REQUEST_CONTRACT.to_string(),
        request_id: format!("host:{session_id}:{sequence}"),
        session_id: session_id.to_string(),
        operation: CLIPBOARD_READ_OPERATION.to_string(),
        sequence,
        timestamp_micros,
        payload: serde_json::json!({"selection": selection}),
    };
    let encoded = serde_json::to_vec(&request).ok()?;
    (encoded.len() <= MAX_HOST_REQUEST_BYTES).then_some(request)
}

impl HostResponseV1 {
    pub fn decode_json(raw: &str, expected_session_id: u64) -> Result<Self, HostResponseError> {
        if raw.len() > MAX_HOST_RESPONSE_BYTES {
            return Err(HostResponseError::EncodedResponseTooLarge);
        }
        let response: Self =
            serde_json::from_str(raw).map_err(|_| HostResponseError::InvalidJson)?;
        if response.schema_version != HOST_REQUEST_SCHEMA_VERSION {
            return Err(HostResponseError::UnsupportedSchema);
        }
        if response.contract != HOST_RESPONSE_CONTRACT {
            return Err(HostResponseError::UnsupportedContract);
        }
        if !valid_request_id(&response.request_id) {
            return Err(HostResponseError::InvalidRequestId);
        }
        if response.session_id != expected_session_id.to_string() {
            return Err(HostResponseError::InvalidSessionId);
        }
        if !valid_operation(&response.operation) {
            return Err(HostResponseError::InvalidOperation);
        }
        if response.timestamp_micros > MAX_JSON_SAFE_INTEGER {
            return Err(HostResponseError::InvalidTimestamp);
        }
        match (response.ok, &response.payload, &response.error) {
            (true, Some(payload), None) if payload.is_object() => {}
            (false, None, Some(error)) if valid_error(error) => {}
            (false, None, Some(_)) => return Err(HostResponseError::InvalidError),
            _ => return Err(HostResponseError::InvalidResponseState),
        }
        Ok(response)
    }
}

pub(crate) fn pending_host_request(request: &HostRequestV1) -> Option<PendingHostRequestV1> {
    let selection = request.payload.get("selection")?.as_str()?;
    valid_selection(selection).then(|| PendingHostRequestV1 {
        request_id: request.request_id.clone(),
        session_id: request.session_id.clone(),
        operation: request.operation.clone(),
        selection: selection.to_string(),
    })
}

pub(crate) fn resolve_host_response(
    response: &HostResponseV1,
    pending: &PendingHostRequestV1,
) -> Result<Option<Vec<u8>>, HostResponseError> {
    if response.request_id != pending.request_id
        || response.session_id != pending.session_id
        || response.operation != pending.operation
    {
        return Err(HostResponseError::CorrelationMismatch);
    }
    if response.operation != CLIPBOARD_READ_OPERATION {
        return Err(HostResponseError::UnsupportedOperation);
    }
    if !response.ok {
        return Ok(None);
    }
    let encoded = response
        .payload
        .as_ref()
        .and_then(Value::as_object)
        .and_then(|payload| payload.get("data_base64"))
        .and_then(Value::as_str)
        .ok_or(HostResponseError::InvalidPayload)?;
    let decoded = STANDARD
        .decode(encoded)
        .map_err(|_| HostResponseError::InvalidPayload)?;
    if decoded.len() > MAX_CLIPBOARD_BYTES
        || std::str::from_utf8(&decoded).is_err()
        || STANDARD.encode(&decoded) != encoded
    {
        return Err(HostResponseError::InvalidPayload);
    }
    Ok(Some(
        format!("\u{1b}]52;{};{}\u{7}", pending.selection, encoded).into_bytes(),
    ))
}

fn valid_request_id(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= MAX_CORRELATION_BYTES
        && value.bytes().enumerate().all(|(index, byte)| {
            byte.is_ascii_alphanumeric() || (index > 0 && matches!(byte, b'.' | b'_' | b':' | b'-'))
        })
}

fn valid_operation(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= MAX_CORRELATION_BYTES
        && value.bytes().enumerate().all(|(index, byte)| {
            (index == 0 && byte.is_ascii_lowercase())
                || (index > 0
                    && (byte.is_ascii_lowercase()
                        || byte.is_ascii_digit()
                        || matches!(byte, b'.' | b'_' | b'-')))
        })
}

fn valid_selection(value: &str) -> bool {
    !value.is_empty() && value.len() <= 16 && value.bytes().all(|byte| byte.is_ascii_alphanumeric())
}

fn valid_error(error: &HostResponseErrorV1) -> bool {
    valid_operation(&error.code)
        && !error.message.is_empty()
        && error.message.len() <= MAX_ERROR_MESSAGE_BYTES
        && !error
            .message
            .chars()
            .any(|character| character.is_control())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clipboard_response_requires_canonical_bounded_utf8_base64() {
        let request = host_request_v1_from_event(
            7,
            3,
            1_200,
            "clipboard_paste_request",
            Some(serde_json::json!({"selection": "c"})),
        )
        .unwrap();
        let pending = pending_host_request(&request).unwrap();
        let response = HostResponseV1 {
            schema_version: 1,
            contract: HOST_RESPONSE_CONTRACT.to_string(),
            request_id: request.request_id,
            session_id: request.session_id,
            operation: request.operation,
            ok: true,
            timestamp_micros: 1_300,
            payload: Some(serde_json::json!({"data_base64": "aGVsbG8="})),
            error: None,
        };

        assert_eq!(
            resolve_host_response(&response, &pending).unwrap(),
            Some(b"\x1b]52;c;aGVsbG8=\x07".to_vec())
        );
    }
}
