use crate::{runtime_contract, session, session_request};
use libc::{c_char, c_int};
use std::ffi::{CStr, CString};

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct IanvsGraphicAssetMeta {
    pub width: u32,
    pub height: u32,
    pub rgba_len: usize,
    pub version: u64,
}

#[unsafe(no_mangle)]
pub extern "C" fn ianvs_ping() -> c_int {
    session::ping()
}

#[unsafe(no_mangle)]
pub extern "C" fn ianvs_runtime_capabilities_json() -> *mut c_char {
    runtime_contract::runtime_capabilities_json()
        .ok()
        .and_then(|json| CString::new(json).ok())
        .map(CString::into_raw)
        .unwrap_or(std::ptr::null_mut())
}

#[unsafe(no_mangle)]
/// # Safety
///
/// `profile_json` must be a valid, NUL-terminated UTF-8 string pointer that
/// remains alive for the duration of this call.
pub unsafe extern "C" fn ianvs_session_create(profile_json: *const c_char) -> u64 {
    if profile_json.is_null() {
        return 0;
    }

    let profile_json = unsafe { CStr::from_ptr(profile_json) };
    profile_json
        .to_str()
        .ok()
        .and_then(|json| session::create_session(json).ok())
        .unwrap_or_default()
}

#[unsafe(no_mangle)]
/// Creates a live session from the product-neutral SessionConfig v1 contract.
///
/// # Safety
///
/// `session_config_json` must be a valid, NUL-terminated UTF-8 string pointer
/// that remains alive for the duration of this call.
pub unsafe extern "C" fn ianvs_session_create_v1(session_config_json: *const c_char) -> u64 {
    if session_config_json.is_null() {
        return 0;
    }

    let session_config_json = unsafe { CStr::from_ptr(session_config_json) };
    session_config_json
        .to_str()
        .ok()
        .and_then(|json| session::create_session_v1(json).ok())
        .unwrap_or_default()
}

#[unsafe(no_mangle)]
/// # Safety
///
/// `profile_json` must be a valid, NUL-terminated UTF-8 string pointer that
/// remains alive for the duration of this call.
pub unsafe extern "C" fn ianvs_replay_session_create(profile_json: *const c_char) -> u64 {
    if profile_json.is_null() {
        return 0;
    }

    let profile_json = unsafe { CStr::from_ptr(profile_json) };
    profile_json
        .to_str()
        .ok()
        .and_then(|json| session::create_replay_session(json).ok())
        .unwrap_or_default()
}

#[unsafe(no_mangle)]
/// Creates a deterministic replay session from SessionConfig v1.
///
/// # Safety
///
/// `session_config_json` must be a valid, NUL-terminated UTF-8 string pointer
/// that remains alive for the duration of this call.
pub unsafe extern "C" fn ianvs_replay_session_create_v1(session_config_json: *const c_char) -> u64 {
    if session_config_json.is_null() {
        return 0;
    }

    let session_config_json = unsafe { CStr::from_ptr(session_config_json) };
    session_config_json
        .to_str()
        .ok()
        .and_then(|json| session::create_replay_session_v1(json).ok())
        .unwrap_or_default()
}

#[unsafe(no_mangle)]
/// # Safety
///
/// When `len` is non-zero, `bytes` must point to `len` readable bytes for the
/// duration of this call. When `len` is zero, `bytes` may be null.
pub unsafe extern "C" fn ianvs_replay_session_output(
    session_id: u64,
    bytes: *const u8,
    len: usize,
) -> c_int {
    let bytes = if len == 0 {
        &[]
    } else {
        if bytes.is_null() {
            return -1;
        }
        unsafe { std::slice::from_raw_parts(bytes, len) }
    };
    session::replay_session_output(session_id, bytes)
        .map(|_| 0)
        .unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub extern "C" fn ianvs_replay_session_exit(
    session_id: u64,
    exit_code: c_int,
    has_exit_code: c_int,
) -> c_int {
    let exit_code = (has_exit_code != 0).then_some(exit_code);
    session::replay_session_exit(session_id, exit_code)
        .map(|_| 0)
        .unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub extern "C" fn ianvs_replay_session_checkpoint_capture(session_id: u64) -> u64 {
    session::replay_session_capture_checkpoint(session_id).unwrap_or_default()
}

#[unsafe(no_mangle)]
pub extern "C" fn ianvs_replay_session_checkpoint_restore(
    session_id: u64,
    checkpoint_id: u64,
) -> c_int {
    session::replay_session_restore_checkpoint(session_id, checkpoint_id)
        .map(|_| 0)
        .unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub extern "C" fn ianvs_session_close(session_id: u64) -> c_int {
    session::close_session(session_id).map(|_| 0).unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub extern "C" fn ianvs_session_refresh_hint(session_id: u64) -> u32 {
    session::refresh_hint_flags(session_id).unwrap_or_default()
}

#[unsafe(no_mangle)]
pub extern "C" fn ianvs_session_resize(
    session_id: u64,
    cols: u16,
    rows: u16,
    pixel_width: u16,
    pixel_height: u16,
) -> c_int {
    session::resize_session(session_id, cols, rows, pixel_width, pixel_height)
        .map(|_| 0)
        .unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub extern "C" fn ianvs_session_resize_with_cell_size(
    session_id: u64,
    cols: u16,
    rows: u16,
    pixel_width: u16,
    pixel_height: u16,
    cell_width: u16,
    cell_height: u16,
) -> c_int {
    session::resize_session_with_cell_size(
        session_id,
        cols,
        rows,
        pixel_width,
        pixel_height,
        cell_width,
        cell_height,
    )
    .map(|_| 0)
    .unwrap_or(-1)
}

#[unsafe(no_mangle)]
/// # Safety
///
/// When `len` is non-zero, `bytes` must point to `len` readable bytes for the
/// duration of this call. When `len` is zero, `bytes` may be null.
pub unsafe extern "C" fn ianvs_session_write(
    session_id: u64,
    bytes: *const u8,
    len: usize,
) -> c_int {
    let bytes = if len == 0 {
        &[]
    } else {
        if bytes.is_null() {
            return -1;
        }
        unsafe { std::slice::from_raw_parts(bytes, len) }
    };
    session::write_session(session_id, bytes)
        .map(|_| 0)
        .unwrap_or(-1)
}

#[unsafe(no_mangle)]
/// Consumes one correlated Host Response v1.
///
/// # Safety
///
/// `response_json` must be a valid, NUL-terminated UTF-8 string pointer that
/// remains alive for the duration of this call.
pub unsafe extern "C" fn ianvs_session_host_response_v1_json(
    session_id: u64,
    response_json: *const c_char,
) -> c_int {
    if response_json.is_null() {
        return -1;
    }
    let response_json = unsafe { CStr::from_ptr(response_json) };
    response_json
        .to_str()
        .ok()
        .and_then(|value| session::respond_host_v1_json(session_id, value).ok())
        .map(|_| 0)
        .unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub extern "C" fn ianvs_session_scroll(session_id: u64, delta_lines: i32) -> c_int {
    session::scroll_session(session_id, delta_lines)
        .map(|_| 0)
        .unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub extern "C" fn ianvs_session_scroll_to(session_id: u64, offset: usize) -> c_int {
    session::scroll_to_session(session_id, offset)
        .map(|_| 0)
        .unwrap_or(-1)
}

#[unsafe(no_mangle)]
/// # Safety
///
/// `query` must be a valid, NUL-terminated UTF-8 string pointer that remains
/// alive for the duration of this call.
pub unsafe extern "C" fn ianvs_session_search_json(
    session_id: u64,
    query: *const c_char,
) -> *mut c_char {
    if query.is_null() {
        return std::ptr::null_mut();
    }

    let query = unsafe { CStr::from_ptr(query) };
    match query
        .to_str()
        .ok()
        .and_then(|value| session::search_session(session_id, value).ok())
    {
        Some(json) => CString::new(json)
            .map(CString::into_raw)
            .unwrap_or(std::ptr::null_mut()),
        None => std::ptr::null_mut(),
    }
}

#[unsafe(no_mangle)]
/// # Safety
///
/// `request_json` must be a valid, NUL-terminated UTF-8 string pointer that
/// remains alive for the duration of this call.
pub unsafe extern "C" fn ianvs_session_selection_text(
    session_id: u64,
    request_json: *const c_char,
) -> *mut c_char {
    if request_json.is_null() {
        return std::ptr::null_mut();
    }

    let request_json = unsafe { CStr::from_ptr(request_json) };
    match request_json
        .to_str()
        .ok()
        .and_then(|value| session::selection_text_session(session_id, value).ok())
    {
        Some(text) => CString::new(text)
            .map(CString::into_raw)
            .unwrap_or(std::ptr::null_mut()),
        None => std::ptr::null_mut(),
    }
}

#[unsafe(no_mangle)]
/// # Safety
///
/// `request_json` must be a valid, NUL-terminated UTF-8 string pointer that
/// remains alive for the duration of this call.
pub unsafe extern "C" fn ianvs_session_request_json(
    session_id: u64,
    request_json: *const c_char,
) -> *mut c_char {
    if request_json.is_null() {
        return std::ptr::null_mut();
    }

    let request_json = unsafe { CStr::from_ptr(request_json) };
    match request_json
        .to_str()
        .ok()
        .and_then(|value| session::request_session_json(session_id, value).ok())
        .flatten()
    {
        Some(json) => CString::new(json)
            .map(CString::into_raw)
            .unwrap_or(std::ptr::null_mut()),
        None => std::ptr::null_mut(),
    }
}

#[unsafe(no_mangle)]
/// Executes a correlated Session Request v1 and returns Session Response v1.
///
/// # Safety
///
/// `request_json` must be a valid, NUL-terminated UTF-8 string pointer that
/// remains alive for the duration of this call.
pub unsafe extern "C" fn ianvs_session_request_v1_json(
    session_id: u64,
    request_json: *const c_char,
) -> *mut c_char {
    if request_json.is_null() {
        return std::ptr::null_mut();
    }

    let request_json = unsafe { CStr::from_ptr(request_json) };
    request_json
        .to_str()
        .ok()
        .and_then(|value| session_request::request_session_v1_json(session_id, value).ok())
        .and_then(|json| CString::new(json).ok())
        .map(CString::into_raw)
        .unwrap_or(std::ptr::null_mut())
}

#[unsafe(no_mangle)]
pub extern "C" fn ianvs_session_take_frame_diff_json(session_id: u64) -> *mut c_char {
    match session::take_frame_diff(session_id).ok().flatten() {
        Some(json) => CString::new(json)
            .map(CString::into_raw)
            .unwrap_or(std::ptr::null_mut()),
        None => std::ptr::null_mut(),
    }
}

#[unsafe(no_mangle)]
/// # Safety
///
/// `out_len` must point to writable memory for one `usize`.
pub unsafe extern "C" fn ianvs_session_take_frame_diff_protobuf(
    session_id: u64,
    out_len: *mut usize,
) -> *mut u8 {
    if out_len.is_null() {
        return std::ptr::null_mut();
    }
    unsafe {
        *out_len = 0;
    }

    match session::take_frame_diff_protobuf(session_id).ok().flatten() {
        Some(bytes) => {
            let mut boxed = bytes.into_boxed_slice();
            let len = boxed.len();
            let ptr = boxed.as_mut_ptr();
            unsafe {
                *out_len = len;
            }
            std::mem::forget(boxed);
            ptr
        }
        None => std::ptr::null_mut(),
    }
}

#[unsafe(no_mangle)]
/// Returns one correlated Terminal Frame Packet v1 as owned Protobuf bytes.
///
/// `has_after_sequence` is zero before the first accepted packet and non-zero
/// when `after_sequence` contains the last packet sequence applied by Dart.
/// A stale acknowledgement forces the returned Frame payload to be a Snapshot.
///
/// # Safety
///
/// `out_len` must point to writable memory for one `usize`.
pub unsafe extern "C" fn ianvs_session_take_frame_packet_v1_protobuf(
    session_id: u64,
    after_sequence: u64,
    has_after_sequence: u8,
    out_len: *mut usize,
) -> *mut u8 {
    if out_len.is_null() {
        return std::ptr::null_mut();
    }
    unsafe {
        *out_len = 0;
    }

    let after_sequence = (has_after_sequence != 0).then_some(after_sequence);
    match session::take_frame_packet_v1_protobuf(session_id, after_sequence)
        .ok()
        .flatten()
    {
        Some(bytes) => {
            let mut boxed = bytes.into_boxed_slice();
            let len = boxed.len();
            let ptr = boxed.as_mut_ptr();
            unsafe {
                *out_len = len;
            }
            std::mem::forget(boxed);
            ptr
        }
        None => std::ptr::null_mut(),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn ianvs_session_take_frame_debug_stats_json(session_id: u64) -> *mut c_char {
    match session::take_frame_debug_stats_json(session_id)
        .ok()
        .flatten()
    {
        Some(json) => CString::new(json)
            .map(CString::into_raw)
            .unwrap_or(std::ptr::null_mut()),
        None => std::ptr::null_mut(),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn ianvs_session_take_session_debug_stats_json(session_id: u64) -> *mut c_char {
    match session::take_session_debug_stats_json(session_id)
        .ok()
        .flatten()
    {
        Some(json) => CString::new(json)
            .map(CString::into_raw)
            .unwrap_or(std::ptr::null_mut()),
        None => std::ptr::null_mut(),
    }
}

#[unsafe(no_mangle)]
/// Returns a Diagnostic Event v1 Runtime Envelope for a supported diagnostic.
///
/// # Safety
///
/// `diagnostic_name` must be a valid, NUL-terminated UTF-8 string pointer that
/// remains alive for the duration of this call.
pub unsafe extern "C" fn ianvs_session_take_diagnostic_event_v1_json(
    session_id: u64,
    diagnostic_name: *const c_char,
) -> *mut c_char {
    if diagnostic_name.is_null() {
        return std::ptr::null_mut();
    }
    let diagnostic_name = unsafe { CStr::from_ptr(diagnostic_name) };
    diagnostic_name
        .to_str()
        .ok()
        .and_then(|name| session::take_diagnostic_event_v1_json(session_id, name).ok())
        .flatten()
        .and_then(|json| CString::new(json).ok())
        .map(CString::into_raw)
        .unwrap_or(std::ptr::null_mut())
}

#[unsafe(no_mangle)]
pub extern "C" fn ianvs_session_poll_events_json(session_id: u64) -> *mut c_char {
    match session::take_events(session_id) {
        Ok(events) if events.is_empty() => std::ptr::null_mut(),
        Ok(events) => serde_json::to_string(&events)
            .ok()
            .and_then(|json| CString::new(json).ok())
            .map(CString::into_raw)
            .unwrap_or(std::ptr::null_mut()),
        Err(_) => std::ptr::null_mut(),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn ianvs_session_poll_event_envelopes_json(session_id: u64) -> *mut c_char {
    match session::poll_event_envelopes(session_id) {
        Ok(Some(json)) => CString::new(json)
            .map(CString::into_raw)
            .unwrap_or(std::ptr::null_mut()),
        Ok(None) | Err(_) => std::ptr::null_mut(),
    }
}

#[unsafe(no_mangle)]
/// # Safety
///
/// `out_meta` must point to writable memory for an `IanvsGraphicAssetMeta`.
pub unsafe extern "C" fn ianvs_session_graphic_asset_meta(
    session_id: u64,
    asset_id: u64,
    asset_version: u64,
    out_meta: *mut IanvsGraphicAssetMeta,
) -> c_int {
    if out_meta.is_null() {
        return -1;
    }
    match session::graphic_asset_meta(session_id, asset_id, asset_version) {
        Ok(meta) => {
            unsafe {
                *out_meta = IanvsGraphicAssetMeta {
                    width: meta.width,
                    height: meta.height,
                    rgba_len: meta.rgba_len,
                    version: meta.version,
                };
            }
            0
        }
        Err(_) => -1,
    }
}

#[unsafe(no_mangle)]
/// Returns one Graphic Asset Packet v1 as owned Protobuf bytes.
///
/// # Safety
///
/// `out_len` must point to writable memory for one `usize`.
pub unsafe extern "C" fn ianvs_session_graphic_asset_packet_v1_protobuf(
    session_id: u64,
    asset_id: u64,
    asset_version: u64,
    out_len: *mut usize,
) -> *mut u8 {
    if out_len.is_null() {
        return std::ptr::null_mut();
    }
    unsafe {
        *out_len = 0;
    }
    match session::graphic_asset_packet_v1_protobuf(session_id, asset_id, asset_version) {
        Ok(bytes) => {
            let mut boxed = bytes.into_boxed_slice();
            let len = boxed.len();
            let pointer = boxed.as_mut_ptr();
            unsafe {
                *out_len = len;
            }
            std::mem::forget(boxed);
            pointer
        }
        Err(_) => std::ptr::null_mut(),
    }
}

#[unsafe(no_mangle)]
/// # Safety
///
/// `dst` must point to `len` writable bytes for the duration of this call.
pub unsafe extern "C" fn ianvs_session_graphic_asset_rgba_copy(
    session_id: u64,
    asset_id: u64,
    asset_version: u64,
    dst: *mut u8,
    len: usize,
) -> isize {
    if dst.is_null() {
        return -1;
    }
    let dst = unsafe { std::slice::from_raw_parts_mut(dst, len) };
    session::copy_graphic_asset_rgba(session_id, asset_id, asset_version, dst)
        .map(|copied| copied as isize)
        .unwrap_or(-1)
}

#[unsafe(no_mangle)]
/// Atomically copies and consumes one completed OSC 1337 download.
///
/// # Safety
///
/// When `len` is non-zero, `dst` must point to `len` writable bytes for the
/// duration of this call. When `len` is zero, `dst` may be null.
pub unsafe extern "C" fn ianvs_session_file_download_take(
    session_id: u64,
    download_id: u64,
    dst: *mut u8,
    len: usize,
) -> isize {
    let dst = if len == 0 {
        &mut []
    } else {
        if dst.is_null() {
            return -1;
        }
        unsafe { std::slice::from_raw_parts_mut(dst, len) }
    };
    session::take_file_download(session_id, download_id, dst)
        .map(|copied| copied as isize)
        .unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub extern "C" fn ianvs_session_file_download_discard(session_id: u64, download_id: u64) -> c_int {
    session::discard_file_download(session_id, download_id)
        .map(|_| 0)
        .unwrap_or(-1)
}

#[unsafe(no_mangle)]
/// # Safety
///
/// `value` must be a pointer previously returned by this library via
/// `CString::into_raw`, and it must not be freed more than once.
pub unsafe extern "C" fn ianvs_string_free(value: *mut c_char) {
    if value.is_null() {
        return;
    }
    unsafe {
        let _ = CString::from_raw(value);
    }
}

#[unsafe(no_mangle)]
/// # Safety
///
/// `ptr` must be a pointer returned by one of this library's owned Protobuf
/// Frame byte entrypoints with the same `len`.
pub unsafe extern "C" fn ianvs_bytes_free(ptr: *mut u8, len: usize) {
    if ptr.is_null() {
        return;
    }
    let slice = std::ptr::slice_from_raw_parts_mut(ptr, len);
    unsafe {
        drop(Box::from_raw(slice));
    }
}
