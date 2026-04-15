use crate::session;
use libc::{c_char, c_int};
use std::ffi::{CStr, CString};

#[unsafe(no_mangle)]
pub extern "C" fn flutterm_ping() -> c_int {
    session::ping()
}

#[unsafe(no_mangle)]
pub extern "C" fn flutterm_session_create(profile_json: *const c_char) -> u64 {
    if profile_json.is_null() {
        return 0;
    }

    let profile_json = unsafe { CStr::from_ptr(profile_json) };
    match profile_json
        .to_str()
        .ok()
        .and_then(|json| session::create_session(json).ok())
    {
        Some(session_id) => session_id,
        None => 0,
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn flutterm_session_close(session_id: u64) -> c_int {
    session::close_session(session_id).map(|_| 0).unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub extern "C" fn flutterm_session_resize(
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
pub extern "C" fn flutterm_session_write(session_id: u64, bytes: *const u8, len: usize) -> c_int {
    if bytes.is_null() {
        return -1;
    }
    let bytes = unsafe { std::slice::from_raw_parts(bytes, len) };
    session::write_session(session_id, bytes)
        .map(|_| 0)
        .unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub extern "C" fn flutterm_session_scroll(session_id: u64, delta_lines: i32) -> c_int {
    session::scroll_session(session_id, delta_lines)
        .map(|_| 0)
        .unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub extern "C" fn flutterm_session_take_frame_diff_json(session_id: u64) -> *mut c_char {
    match session::take_frame_diff(session_id).ok().flatten() {
        Some(json) => CString::new(json)
            .map(CString::into_raw)
            .unwrap_or(std::ptr::null_mut()),
        None => std::ptr::null_mut(),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn flutterm_session_poll_events_json(session_id: u64) -> *mut c_char {
    match session::poll_events(session_id) {
        Ok(json) => CString::new(json)
            .map(CString::into_raw)
            .unwrap_or(std::ptr::null_mut()),
        Err(_) => std::ptr::null_mut(),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn flutterm_string_free(value: *mut c_char) {
    if value.is_null() {
        return;
    }
    unsafe {
        let _ = CString::from_raw(value);
    }
}
