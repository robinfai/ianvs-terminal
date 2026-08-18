use super::*;
use std::path::Path;

const MAX_SFTP_PATH_BYTES: usize = 4096;
const MAX_LOCAL_TRANSFER_PATH_BYTES: usize = 4096;

pub(super) fn valid_sftp_path(path: &str) -> bool {
    !path.is_empty()
        && path.len() <= MAX_SFTP_PATH_BYTES
        && path.starts_with('/')
        && !path.contains('\0')
}

fn valid_local_transfer_path(path: &str) -> bool {
    !path.is_empty()
        && path.len() <= MAX_LOCAL_TRANSFER_PATH_BYTES
        && !path.contains('\0')
        && Path::new(path).is_absolute()
}

pub fn request_session(
    session_id: u64,
    operation: &str,
    request: &serde_json::Value,
) -> Result<Option<String>, SessionError> {
    if !request.is_object() {
        return Ok(None);
    }

    match operation {
        "ssh.sftp.list_directory_start" => {
            let Some(path) = request
                .get("path")
                .and_then(serde_json::Value::as_str)
                .filter(|path| valid_sftp_path(path))
            else {
                return Ok(None);
            };
            let job_id = STORE
                .get(session_id)?
                .start_sftp_directory_listing(path.to_string())?;
            request_json_response(serde_json::json!({
                "jobId": job_id.to_string(),
            }))
        }
        "ssh.sftp.list_directory_poll" => {
            let Some(job_id) = request
                .get("jobId")
                .and_then(serde_json::Value::as_str)
                .filter(|value| !value.is_empty() && value.len() <= 20)
                .and_then(|value| value.parse::<u64>().ok())
                .filter(|value| *value > 0)
            else {
                return Ok(None);
            };
            let response = STORE.get(session_id)?.poll_sftp_directory_listing(job_id)?;
            request_json_response(response)
        }
        "ssh.sftp.list_directory_cancel" => {
            let Some(job_id) = request
                .get("jobId")
                .and_then(serde_json::Value::as_str)
                .filter(|value| !value.is_empty() && value.len() <= 20)
                .and_then(|value| value.parse::<u64>().ok())
                .filter(|value| *value > 0)
            else {
                return Ok(None);
            };
            let cancelled = STORE.get(session_id)?.cancel_sftp_directory_listing(job_id);
            request_json_response(serde_json::json!({ "cancelled": cancelled }))
        }
        "ssh.sftp.operation_start" => {
            let action = request.get("action").and_then(serde_json::Value::as_str);
            let remote_path = request
                .get("remotePath")
                .and_then(serde_json::Value::as_str)
                .filter(|path| valid_sftp_path(path));
            let operation = match (action, remote_path) {
                (Some("download_file"), Some(remote_path)) => {
                    let Some(local_path) = request
                        .get("localPath")
                        .and_then(serde_json::Value::as_str)
                        .filter(|path| valid_local_transfer_path(path))
                    else {
                        return Ok(None);
                    };
                    crate::ssh::SftpOperation::DownloadFile {
                        remote_path: remote_path.to_string(),
                        local_path: local_path.to_string(),
                    }
                }
                (Some("upload_file"), Some(remote_path)) => {
                    let Some(local_path) = request
                        .get("localPath")
                        .and_then(serde_json::Value::as_str)
                        .filter(|path| valid_local_transfer_path(path))
                    else {
                        return Ok(None);
                    };
                    crate::ssh::SftpOperation::UploadFile {
                        local_path: local_path.to_string(),
                        remote_path: remote_path.to_string(),
                    }
                }
                (Some("create_directory"), Some(path)) => {
                    crate::ssh::SftpOperation::CreateDirectory {
                        path: path.to_string(),
                    }
                }
                (Some("delete_entry"), Some(path)) => {
                    let Some(is_directory) = request
                        .get("isDirectory")
                        .and_then(serde_json::Value::as_bool)
                    else {
                        return Ok(None);
                    };
                    crate::ssh::SftpOperation::DeleteEntry {
                        path: path.to_string(),
                        is_directory,
                    }
                }
                _ => return Ok(None),
            };
            let job_id = STORE.get(session_id)?.start_sftp_operation(operation)?;
            request_json_response(serde_json::json!({ "jobId": job_id.to_string() }))
        }
        "ssh.sftp.operation_poll" => {
            let Some(job_id) = request
                .get("jobId")
                .and_then(serde_json::Value::as_str)
                .filter(|value| !value.is_empty() && value.len() <= 20)
                .and_then(|value| value.parse::<u64>().ok())
                .filter(|value| *value > 0)
            else {
                return Ok(None);
            };
            let response = STORE.get(session_id)?.poll_sftp_operation(job_id)?;
            request_json_response(response)
        }
        "ssh.sftp.operation_cancel" => {
            let Some(job_id) = request
                .get("jobId")
                .and_then(serde_json::Value::as_str)
                .filter(|value| !value.is_empty() && value.len() <= 20)
                .and_then(|value| value.parse::<u64>().ok())
                .filter(|value| *value > 0)
            else {
                return Ok(None);
            };
            let cancelled = STORE.get(session_id)?.cancel_sftp_operation(job_id);
            request_json_response(serde_json::json!({ "cancelled": cancelled }))
        }
        "ssh.auth_response" => {
            let challenge_id = request
                .get("challengeId")
                .and_then(serde_json::Value::as_u64)
                .or_else(|| {
                    request
                        .get("challengeId")
                        .and_then(serde_json::Value::as_str)
                        .and_then(|value| value.parse().ok())
                });
            let cancel = request
                .get("cancel")
                .and_then(serde_json::Value::as_bool)
                .unwrap_or(false);
            let responses = request
                .get("responses")
                .and_then(serde_json::Value::as_array)
                .filter(|responses| responses.len() <= 32)
                .and_then(|responses| {
                    responses
                        .iter()
                        .map(|response| {
                            response
                                .as_str()
                                .filter(|response| {
                                    response.len() <= 64 * 1024 && !response.contains('\0')
                                })
                                .map(str::to_string)
                        })
                        .collect::<Option<Vec<_>>>()
                });
            let Some(challenge_id) = challenge_id else {
                return Ok(None);
            };
            let session = STORE.get(session_id)?;
            let accepted = if cancel {
                session.cancel_ssh_auth(challenge_id)
            } else if let Some(responses) = responses {
                session.respond_ssh_auth(challenge_id, responses)
            } else {
                return Ok(None);
            };
            request_json_response(serde_json::json!({ "accepted": accepted }))
        }
        "ssh.host_key_response" => {
            let challenge_id = request
                .get("challengeId")
                .and_then(serde_json::Value::as_u64);
            let accept = request.get("accept").and_then(serde_json::Value::as_bool);
            let (Some(challenge_id), Some(accept)) = (challenge_id, accept) else {
                return Ok(None);
            };
            let session = STORE.get(session_id)?;
            let accepted = session.respond_ssh_host_key(challenge_id, accept);
            request_json_response(serde_json::json!({ "accepted": accepted }))
        }
        "terminal.recording_start" => {
            if request
                .get("schema_version")
                .and_then(serde_json::Value::as_u64)
                != Some(recording::RECORDING_SCHEMA_VERSION.into())
            {
                return invalid_recording_request("schema_version must be 1");
            }
            let Some(created_at_utc) = request
                .get("created_at_utc")
                .and_then(serde_json::Value::as_str)
                .filter(|value| !value.is_empty() && value.ends_with('Z'))
            else {
                return invalid_recording_request(
                    "created_at_utc must be a non-empty UTC timestamp",
                );
            };
            let Some(input_policy) = request
                .get("input_policy")
                .and_then(serde_json::Value::as_str)
                .and_then(RecordingInputPolicy::parse)
            else {
                return invalid_recording_request("input_policy must be record or redact");
            };
            let session = STORE.get(session_id)?;
            let mut recording = session.recording.lock();
            let state = session.state.lock();
            let (cols, rows) = state.terminal.size();
            let terminal_emulation = match session.emulation {
                TerminalEmulation::Xterm256 => "xterm256",
                TerminalEmulation::Vt220 => "vt220",
            };
            let initial_screen = recording_initial_screen(&state.terminal);
            let result = recording.start(
                session_id,
                created_at_utc.to_string(),
                input_policy,
                terminal_emulation,
                cols as u16,
                rows as u16,
                initial_screen,
            );
            drop(state);
            match result {
                Ok(started) => request_json_response(serde_json::json!({
                    "ok": true,
                    "max_events": started.max_events,
                    "max_payload_bytes": started.max_payload_bytes,
                })),
                Err(error) => recording_error_response(error),
            }
        }
        "terminal.recording_stop" => {
            let session = STORE.get(session_id)?;
            session.observe_child_exit()?;
            match session.recording.lock().stop() {
                Ok(recording_ndjson) => request_json_response(serde_json::json!({
                    "ok": true,
                    "recording_ndjson": recording_ndjson,
                })),
                Err(error) => recording_error_response(error),
            }
        }
        "terminal.recording_stop_prepare" => {
            let Some(handoff_directory) = request
                .get("handoff_directory")
                .and_then(serde_json::Value::as_str)
                .filter(|value| !value.is_empty() && value.len() <= 4096 && !value.contains('\0'))
            else {
                return invalid_recording_request(
                    "handoff_directory must be a bounded absolute path",
                );
            };
            let requested_job_id = match request.get("job_id") {
                Some(serde_json::Value::String(value))
                    if value.len() == 32
                        && value
                            .bytes()
                            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte)) =>
                {
                    Some(value.as_str())
                }
                Some(_) => {
                    return invalid_recording_request(
                        "job_id must be 32 lowercase hexadecimal characters",
                    );
                }
                None => None,
            };
            let session = STORE.get(session_id)?;
            session.observe_child_exit()?;
            match session
                .recording
                .lock()
                .prepare_finalize(std::path::Path::new(handoff_directory), requested_job_id)
            {
                Ok(job) => request_json_response(serde_json::json!({
                    "ok": true,
                    "job_id": job.job_id,
                    "handoff_path": job.handoff_path,
                    "error_path": job.error_path,
                })),
                Err(error) => recording_error_response(error),
            }
        }
        "terminal.recording_finalize_status" => {
            let Some(job_id) = request
                .get("job_id")
                .and_then(serde_json::Value::as_str)
                .filter(|job_id| recording::valid_recording_finalize_job_id(job_id))
            else {
                return invalid_recording_request(
                    "job_id must be 32 lowercase hexadecimal characters",
                );
            };
            let Some(consume_terminal) = request
                .get("consume_terminal")
                .and_then(serde_json::Value::as_bool)
            else {
                return invalid_recording_request("consume_terminal must be a boolean");
            };
            let status = recording::recording_finalize_status(job_id, consume_terminal);
            let mut response = serde_json::json!({
                "ok": true,
                "state": match status {
                    RecordingFinalizeStatus::Running => "running",
                    RecordingFinalizeStatus::Ready => "ready",
                    RecordingFinalizeStatus::Failed(_) => "failed",
                    RecordingFinalizeStatus::Unknown => "unknown",
                },
            });
            if let RecordingFinalizeStatus::Failed(error) = status {
                response["error"] = serde_json::json!({
                    "code": error.code,
                    "message": error.message,
                });
            }
            request_json_response(response)
        }
        "terminal.recording_cancel" => {
            let session = STORE.get(session_id)?;
            match session.recording.lock().cancel() {
                Ok(()) => request_json_response(serde_json::json!({ "ok": true })),
                Err(error) => recording_error_response(error),
            }
        }
        "terminal.search_text" => {
            let query = request
                .get("query")
                .and_then(serde_json::Value::as_str)
                .unwrap_or_default();
            let mode = request.get("mode").and_then(serde_json::Value::as_str);
            search_session_with_mode(session_id, query, mode).map(Some)
        }
        "terminal.selection_text" => {
            let Some(selection) = request.get("selection") else {
                return Ok(None);
            };
            let mut selection = selection.clone();
            let serde_json::Value::Object(selection) = &mut selection else {
                return Ok(None);
            };
            selection.insert(
                "block".to_string(),
                serde_json::Value::Bool(
                    request
                        .get("block")
                        .and_then(serde_json::Value::as_bool)
                        .unwrap_or(false),
                ),
            );
            let request_json = serde_json::to_string(&selection)
                .map_err(|error| SessionError::Serialize(error.to_string()))?;
            let text = selection_text_session(session_id, &request_json)?;
            serde_json::to_string(&serde_json::json!({ "text": text }))
                .map(Some)
                .map_err(|error| SessionError::Serialize(error.to_string()))
        }
        "terminal.clear_scrollback" => clear_scrollback_session(session_id).map(Some),
        "terminal.clear_buffer" => clear_buffer_session(session_id).map(Some),
        "terminal.dismiss_osc99_notification" => {
            let Some(identifier) = request.get("id").and_then(serde_json::Value::as_str) else {
                return Ok(None);
            };
            let dismissed = STORE
                .get(session_id)?
                .dismiss_osc99_notification(identifier);
            serde_json::to_string(&serde_json::json!({ "dismissed": dismissed }))
                .map(Some)
                .map_err(|error| SessionError::Serialize(error.to_string()))
        }
        "terminal.set_block_folded" => {
            let Some(id) = request.get("id").and_then(serde_json::Value::as_str) else {
                return Ok(None);
            };
            let Some(folded) = request.get("folded").and_then(serde_json::Value::as_bool) else {
                return Ok(None);
            };
            let updated = STORE.get(session_id)?.set_block_folded(id, folded);
            serde_json::to_string(&serde_json::json!({ "updated": updated }))
                .map(Some)
                .map_err(|error| SessionError::Serialize(error.to_string()))
        }
        "terminal.set_block_rendered" => {
            let Some(id) = request.get("id").and_then(serde_json::Value::as_str) else {
                return Ok(None);
            };
            let Some(rendered) = request.get("rendered").and_then(serde_json::Value::as_bool)
            else {
                return Ok(None);
            };
            let updated = STORE.get(session_id)?.set_block_rendered(id, rendered);
            serde_json::to_string(&serde_json::json!({ "updated": updated }))
                .map(Some)
                .map_err(|error| SessionError::Serialize(error.to_string()))
        }
        "terminal.activate_iterm_button" => {
            let Some(id) = request.get("id").and_then(serde_json::Value::as_u64) else {
                return Ok(None);
            };
            let response = STORE.get(session_id)?.activate_iterm_button(id)?;
            serde_json::to_string(&response)
                .map(Some)
                .map_err(|error| SessionError::Serialize(error.to_string()))
        }
        "terminal.export_scrollback" => {
            let max_lines = scrollback_export_max_lines_from_request(request);
            export_scrollback_session(session_id, max_lines).map(Some)
        }
        "terminal.export_diagnostics" => {
            let max_samples = request
                .get("maxSamples")
                .or_else(|| request.get("max_samples"))
                .and_then(serde_json::Value::as_u64)
                .and_then(|value| usize::try_from(value).ok())
                .unwrap_or(RESOURCE_SAMPLE_CAPACITY)
                .min(RESOURCE_SAMPLE_CAPACITY);
            let include_content = request
                .get("includeContent")
                .or_else(|| request.get("include_content"))
                .and_then(serde_json::Value::as_bool)
                .unwrap_or(false);
            let redaction_mode = request
                .get("redactionMode")
                .or_else(|| request.get("redaction_mode"))
                .and_then(serde_json::Value::as_str)
                .unwrap_or("basic")
                .to_string();
            export_diagnostics_session(
                session_id,
                TerminalDiagnosticsRequest {
                    max_samples,
                    include_content,
                    redaction_mode,
                },
            )
            .map(Some)
        }
        "terminal.zmodem.accept_receive" => {
            let Some(transfer_id) = zmodem_transfer_id_from_request(request) else {
                return Ok(None);
            };
            let Some(destination) = request
                .get("destination")
                .and_then(serde_json::Value::as_str)
                .filter(|value| !value.is_empty() && value.len() <= 4096 && !value.contains('\0'))
            else {
                return Ok(None);
            };
            STORE
                .get(session_id)?
                .accept_zmodem_receive(transfer_id, std::path::Path::new(destination))?;
            request_json_response(serde_json::json!({ "accepted": true }))
        }
        "terminal.zmodem.accept_send" => {
            let Some(transfer_id) = zmodem_transfer_id_from_request(request) else {
                return Ok(None);
            };
            let Some(files) = request
                .get("files")
                .and_then(serde_json::Value::as_array)
                .filter(|files| !files.is_empty() && files.len() <= 256)
            else {
                return Ok(None);
            };
            let mut paths = Vec::with_capacity(files.len());
            for file in files {
                let Some(path) = file.as_str().filter(|value| {
                    !value.is_empty() && value.len() <= 4096 && !value.contains('\0')
                }) else {
                    return Ok(None);
                };
                paths.push(std::path::PathBuf::from(path));
            }
            STORE
                .get(session_id)?
                .accept_zmodem_send(transfer_id, &paths)?;
            request_json_response(serde_json::json!({ "accepted": true }))
        }
        "terminal.zmodem.resolve_recovery" => {
            let Some(token) = request
                .get("recoveryToken")
                .and_then(serde_json::Value::as_str)
                .filter(|value| {
                    value.len() == 32 && value.bytes().all(|byte| byte.is_ascii_hexdigit())
                })
            else {
                return Ok(None);
            };
            let path = match STORE.get(session_id) {
                Ok(session) => session.resolve_zmodem_recovery(token),
                Err(SessionError::MissingSession(_)) => {
                    crate::zmodem::resolve_tombstoned_recovery(token, session_id)
                }
                Err(error) => return Err(error),
            };
            match path {
                Some(path) => request_json_response(serde_json::json!({
                    "available": true,
                    "path": path.to_string_lossy(),
                })),
                None => request_json_response(serde_json::json!({
                    "available": false,
                })),
            }
        }
        "terminal.zmodem.consume_recovery" => {
            let Some(token) = request
                .get("recoveryToken")
                .and_then(serde_json::Value::as_str)
                .filter(|value| {
                    value.len() == 32 && value.bytes().all(|byte| byte.is_ascii_hexdigit())
                })
            else {
                return Ok(None);
            };
            request_json_response(serde_json::json!({
                "consumed": crate::zmodem::consume_recovery(token, session_id),
            }))
        }
        "terminal.zmodem.dismiss_recovery" => {
            let Some(token) = request
                .get("recoveryToken")
                .and_then(serde_json::Value::as_str)
                .filter(|value| {
                    value.len() == 32 && value.bytes().all(|byte| byte.is_ascii_hexdigit())
                })
            else {
                return Ok(None);
            };
            request_json_response(serde_json::json!({
                "dismissed": crate::zmodem::dismiss_recovery(token, session_id),
            }))
        }
        "terminal.zmodem.cancel" => {
            let Some(transfer_id) = zmodem_transfer_id_from_request(request) else {
                return Ok(None);
            };
            STORE.get(session_id)?.cancel_zmodem(transfer_id)?;
            request_json_response(serde_json::json!({ "cancelled": true }))
        }
        "terminal.zmodem.cancel_active" => {
            let outcome = STORE.get(session_id)?.cancel_active_zmodem()?;
            request_json_response(serde_json::json!({
                "reconciled": true,
                "outcome": outcome.as_str(),
            }))
        }
        "terminal.session.close_readiness" => {
            let (ready, reason) = STORE.get(session_id)?.close_readiness();
            request_json_response(serde_json::json!({
                "ready": ready,
                "reason": reason,
            }))
        }
        _ => Ok(None),
    }
}
