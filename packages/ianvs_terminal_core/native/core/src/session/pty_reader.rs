use std::time::Duration;

const POLL_INTERVAL: Duration = Duration::from_millis(50);

pub(super) fn read_error_is_trusted_eof(error: &std::io::Error) -> bool {
    #[cfg(unix)]
    {
        // PTY masters conventionally report EIO, rather than Ok(0), after
        // the slave side closes. Treat that specific transport boundary as
        // EOF so a receiver that already replied to ZFIN can complete even
        // when the final OO is swallowed by the PTY teardown.
        error.raw_os_error() == Some(libc::EIO)
    }
    #[cfg(not(unix))]
    {
        let _ = error;
        false
    }
}

/// Wait until a Unix PTY master is readable without committing the reader
/// thread to an unbounded `read`. A timeout after the child-exit flag is
/// visible is an ordered drain barrier: all bytes written before that exit
/// have either been routed by the sole reader or are reported readable by the
/// second poll iteration.
pub(super) fn wait_until_readable(poll_handle: Option<&std::fs::File>) -> std::io::Result<bool> {
    #[cfg(unix)]
    if let Some(poll_handle) = poll_handle {
        use std::os::fd::AsRawFd as _;
        let mut descriptor = libc::pollfd {
            fd: poll_handle.as_raw_fd(),
            events: libc::POLLIN,
            revents: 0,
        };
        let timeout_millis = i32::try_from(POLL_INTERVAL.as_millis()).unwrap_or(i32::MAX);
        let result = unsafe { libc::poll(&mut descriptor, 1, timeout_millis) };
        if result < 0 {
            return Err(std::io::Error::last_os_error());
        }
        return Ok(result > 0);
    }

    let _ = poll_handle;
    Ok(true)
}
