use crate::session;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::time::{SystemTime, UNIX_EPOCH};

pub const SESSION_REQUEST_SCHEMA_VERSION: u32 = 1;
pub const SESSION_REQUEST_CONTRACT: &str = "ianvs-session-request-v1";
pub const SESSION_RESPONSE_CONTRACT: &str = "ianvs-session-response-v1";
pub const MAX_SESSION_REQUEST_BYTES: usize = 1024 * 1024;
pub const MAX_SESSION_RESPONSE_BYTES: usize = 16 * 1024 * 1024;

const MAX_CORRELATION_BYTES: usize = 128;

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct SessionRequestV1 {
    pub schema_version: u32,
    pub contract: String,
    pub request_id: String,
    pub session_id: String,
    pub operation: String,
    pub payload: Value,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct SessionResponseErrorV1 {
    pub code: String,
    pub message: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct SessionResponseV1 {
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
    pub error: Option<SessionResponseErrorV1>,
}

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum SessionRequestError {
    #[error("encoded request exceeds 1 MiB")]
    EncodedRequestTooLarge,
    #[error("invalid request JSON")]
    InvalidJson,
    #[error("unsupported request schema")]
    UnsupportedSchema,
    #[error("unsupported request contract")]
    UnsupportedContract,
    #[error("invalid request id")]
    InvalidRequestId,
    #[error("invalid session id")]
    InvalidSessionId,
    #[error("invalid operation")]
    InvalidOperation,
    #[error("invalid request payload")]
    InvalidPayload,
}

impl SessionRequestError {
    fn code(&self) -> &'static str {
        match self {
            Self::EncodedRequestTooLarge => "encoded_request_too_large",
            Self::InvalidJson => "invalid_json",
            Self::UnsupportedSchema => "unsupported_schema",
            Self::UnsupportedContract => "unsupported_contract",
            Self::InvalidRequestId => "invalid_request_id",
            Self::InvalidSessionId => "invalid_session_id",
            Self::InvalidOperation => "invalid_operation",
            Self::InvalidPayload => "invalid_payload",
        }
    }
}

impl SessionRequestV1 {
    pub fn decode_json(raw: &str, expected_session_id: u64) -> Result<Self, SessionRequestError> {
        if raw.len() > MAX_SESSION_REQUEST_BYTES {
            return Err(SessionRequestError::EncodedRequestTooLarge);
        }
        let request: Self =
            serde_json::from_str(raw).map_err(|_| SessionRequestError::InvalidJson)?;
        if request.schema_version != SESSION_REQUEST_SCHEMA_VERSION {
            return Err(SessionRequestError::UnsupportedSchema);
        }
        if request.contract != SESSION_REQUEST_CONTRACT {
            return Err(SessionRequestError::UnsupportedContract);
        }
        if !valid_request_id(&request.request_id) {
            return Err(SessionRequestError::InvalidRequestId);
        }
        if request.session_id != expected_session_id.to_string() {
            return Err(SessionRequestError::InvalidSessionId);
        }
        if !valid_operation(&request.operation) {
            return Err(SessionRequestError::InvalidOperation);
        }
        if !request.payload.is_object() {
            return Err(SessionRequestError::InvalidPayload);
        }
        Ok(request)
    }

    fn legacy_request_json(&self) -> Result<String, serde_json::Error> {
        let mut payload = self.payload.as_object().cloned().unwrap_or_default();
        payload.insert("kind".to_string(), Value::String(self.operation.clone()));
        serde_json::to_string(&Value::Object(payload))
    }
}

impl SessionResponseV1 {
    fn success(request: &SessionRequestV1, payload: Value) -> Self {
        Self {
            schema_version: SESSION_REQUEST_SCHEMA_VERSION,
            contract: SESSION_RESPONSE_CONTRACT.to_string(),
            request_id: request.request_id.clone(),
            session_id: request.session_id.clone(),
            operation: request.operation.clone(),
            ok: true,
            timestamp_micros: timestamp_micros(),
            payload: Some(payload),
            error: None,
        }
    }

    fn failure(
        request_id: String,
        session_id: String,
        operation: String,
        code: &str,
        message: &str,
    ) -> Self {
        Self {
            schema_version: SESSION_REQUEST_SCHEMA_VERSION,
            contract: SESSION_RESPONSE_CONTRACT.to_string(),
            request_id,
            session_id,
            operation,
            ok: false,
            timestamp_micros: timestamp_micros(),
            payload: None,
            error: Some(SessionResponseErrorV1 {
                code: code.to_string(),
                message: message.to_string(),
            }),
        }
    }
}

pub fn request_session_v1_json(session_id: u64, raw: &str) -> Result<String, serde_json::Error> {
    let response = match SessionRequestV1::decode_json(raw, session_id) {
        Ok(request) => dispatch_request(session_id, &request),
        Err(error) => {
            let (request_id, operation) = correlation_from_raw(raw);
            SessionResponseV1::failure(
                request_id,
                session_id.to_string(),
                operation,
                error.code(),
                &error.to_string(),
            )
        }
    };
    encode_bounded(response)
}

fn dispatch_request(session_id: u64, request: &SessionRequestV1) -> SessionResponseV1 {
    if !supported_operation(&request.operation) {
        return SessionResponseV1::failure(
            request.request_id.clone(),
            request.session_id.clone(),
            request.operation.clone(),
            "unsupported_operation",
            "the requested operation is not supported",
        );
    }
    let legacy_json = match request.legacy_request_json() {
        Ok(json) => json,
        Err(_) => {
            return SessionResponseV1::failure(
                request.request_id.clone(),
                request.session_id.clone(),
                request.operation.clone(),
                "invalid_payload",
                "the request payload could not be encoded",
            );
        }
    };
    match session::request_session_json(session_id, &legacy_json) {
        Ok(Some(raw_payload)) => match serde_json::from_str::<Value>(&raw_payload) {
            Ok(payload) if payload.is_object() => SessionResponseV1::success(request, payload),
            _ => SessionResponseV1::failure(
                request.request_id.clone(),
                request.session_id.clone(),
                request.operation.clone(),
                "invalid_runtime_response",
                "the runtime returned an invalid response payload",
            ),
        },
        Ok(None) => SessionResponseV1::failure(
            request.request_id.clone(),
            request.session_id.clone(),
            request.operation.clone(),
            "invalid_operation_payload",
            "the operation payload is invalid",
        ),
        Err(error) => {
            let (code, message) = public_runtime_error(&error);
            SessionResponseV1::failure(
                request.request_id.clone(),
                request.session_id.clone(),
                request.operation.clone(),
                code,
                message,
            )
        }
    }
}

fn public_runtime_error(error: &session::SessionError) -> (&'static str, &'static str) {
    match error {
        session::SessionError::Zmodem(reason) if reason == "unsupported_platform" => (
            "unsupported_platform",
            "ZMODEM file transfer is unsupported on this platform",
        ),
        _ => ("runtime_error", "the session request failed"),
    }
}

fn encode_bounded(response: SessionResponseV1) -> Result<String, serde_json::Error> {
    let encoded = serde_json::to_string(&response)?;
    if encoded.len() <= MAX_SESSION_RESPONSE_BYTES {
        return Ok(encoded);
    }
    serde_json::to_string(&SessionResponseV1::failure(
        response.request_id,
        response.session_id,
        response.operation,
        "response_too_large",
        "the session response exceeds 16 MiB",
    ))
}

fn correlation_from_raw(raw: &str) -> (String, String) {
    if raw.len() > MAX_SESSION_REQUEST_BYTES {
        return (
            "invalid-request".to_string(),
            "invalid.operation".to_string(),
        );
    }
    let value = serde_json::from_str::<Value>(raw).unwrap_or(Value::Null);
    let request_id = value
        .get("request_id")
        .and_then(Value::as_str)
        .filter(|value| valid_request_id(value))
        .unwrap_or("invalid-request")
        .to_string();
    let operation = value
        .get("operation")
        .and_then(Value::as_str)
        .filter(|value| valid_operation(value))
        .unwrap_or("invalid.operation")
        .to_string();
    (request_id, operation)
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

fn supported_operation(value: &str) -> bool {
    matches!(
        value,
        "ssh.auth_response"
            | "terminal.recording_start"
            | "terminal.recording_stop"
            | "terminal.recording_cancel"
            | "terminal.search_text"
            | "terminal.selection_text"
            | "terminal.clear_scrollback"
            | "terminal.clear_buffer"
            | "terminal.dismiss_osc99_notification"
            | "terminal.set_block_folded"
            | "terminal.set_block_rendered"
            | "terminal.activate_iterm_button"
            | "terminal.export_scrollback"
            | "terminal.export_diagnostics"
            | "terminal.zmodem.accept_receive"
            | "terminal.zmodem.accept_send"
            | "terminal.zmodem.resolve_recovery"
            | "terminal.zmodem.consume_recovery"
            | "terminal.zmodem.dismiss_recovery"
            | "terminal.zmodem.cancel"
            | "terminal.zmodem.cancel_active"
            | "terminal.session.close_readiness"
    )
}

fn timestamp_micros() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_micros()
        .min(u128::from(u64::MAX)) as u64
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decode_rejects_cross_session_identity() {
        let raw = serde_json::json!({
            "schema_version": 1,
            "contract": SESSION_REQUEST_CONTRACT,
            "request_id": "rust-1",
            "session_id": "8",
            "operation": "terminal.search_text",
            "payload": {}
        })
        .to_string();

        assert_eq!(
            SessionRequestV1::decode_json(&raw, 7).unwrap_err(),
            SessionRequestError::InvalidSessionId
        );
    }

    #[test]
    fn decode_rejects_an_operation_that_starts_with_a_digit() {
        let raw = serde_json::json!({
            "schema_version": 1,
            "contract": SESSION_REQUEST_CONTRACT,
            "request_id": "rust-1",
            "session_id": "7",
            "operation": "1terminal.search_text",
            "payload": {}
        })
        .to_string();

        assert_eq!(
            SessionRequestV1::decode_json(&raw, 7).unwrap_err(),
            SessionRequestError::InvalidOperation
        );
    }

    #[test]
    fn malformed_request_returns_a_bounded_structured_response() {
        let response = request_session_v1_json(7, "{").unwrap();
        let decoded: SessionResponseV1 = serde_json::from_str(&response).unwrap();

        assert!(!decoded.ok);
        assert_eq!(decoded.session_id, "7");
        assert_eq!(decoded.error.unwrap().code, "invalid_json");
        assert!(response.len() < MAX_SESSION_RESPONSE_BYTES);
    }

    #[test]
    fn operation_inventory_is_explicit() {
        assert!(supported_operation("ssh.auth_response"));
        assert!(supported_operation("terminal.search_text"));
        assert!(supported_operation("terminal.zmodem.resolve_recovery"));
        assert!(supported_operation("terminal.zmodem.dismiss_recovery"));
        assert!(supported_operation("terminal.zmodem.cancel_active"));
        assert!(supported_operation("terminal.session.close_readiness"));
        assert!(!supported_operation("terminal.future_operation"));
    }

    #[test]
    fn unsupported_platform_zmodem_error_survives_the_public_contract() {
        assert_eq!(
            public_runtime_error(&session::SessionError::Zmodem(
                "unsupported_platform".to_string()
            )),
            (
                "unsupported_platform",
                "ZMODEM file transfer is unsupported on this platform"
            )
        );
        assert_eq!(
            public_runtime_error(&session::SessionError::Zmodem("invalid state".to_string())),
            ("runtime_error", "the session request failed")
        );
    }
}
