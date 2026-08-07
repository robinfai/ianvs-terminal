// SPDX-License-Identifier: MIT OR Apache-2.0
// Copyright (c) 2017-2020 Alexey Arbuzov
// Copyright (c) 2023-2026 Jarkko Sakkinen

//! ZMODEM file metadata helpers.

use crate::buffer::Buffer;
use crate::error::Error;
use crate::header::{Encoding, EscapeOptions, Frame, Header};
use crate::io::Write;
use crate::wire::{SUBPACKET_MAX_SIZE, SubpacketType, write_subpacket_with_escape_options};
use core::fmt::Write as _;

/// Parses a u32 from a slice of ASCII decimal bytes.
pub(crate) fn parse_file_size(bytes: &[u8]) -> Result<Option<u32>, Error> {
    if bytes.is_empty() {
        return Ok(None);
    }

    let mut result: u32 = 0;
    for &byte in bytes {
        let digit = match byte {
            b'0'..=b'9' => u32::from(byte - b'0'),
            _ => return Err(Error::MalformedFileSize),
        };
        result = result
            .checked_mul(10)
            .and_then(|r| r.checked_add(digit))
            .ok_or(Error::MalformedFileSize)?;
    }
    Ok(Some(result))
}

/// Parses the optional octal Unix modification time from ZFILE metadata.
pub(crate) fn parse_file_modification_time(bytes: &[u8]) -> Result<Option<u64>, Error> {
    if bytes.is_empty() {
        return Ok(None);
    }

    let mut result = 0_u64;
    for &byte in bytes {
        let digit = match byte {
            b'0'..=b'7' => u64::from(byte - b'0'),
            _ => return Err(Error::MalformedFileModificationTime),
        };
        result = result
            .checked_mul(8)
            .and_then(|value| value.checked_add(digit))
            .ok_or(Error::MalformedFileModificationTime)?;
    }

    // ZMODEM uses zero to mean that the sender did not provide a timestamp.
    Ok((result != 0).then_some(result))
}

pub(crate) fn write_zfile_with_escape_options<P>(
    port: &mut P,
    buf: &mut Buffer<SUBPACKET_MAX_SIZE>,
    name: &[u8],
    size: u32,
    modification_time: Option<u64>,
    encoding: Encoding,
    escape: EscapeOptions,
) -> Result<Option<()>, Error>
where
    P: Write + ?Sized,
{
    buf.clear();
    buf.extend_from_slice(name)
        .map_err(|_| Error::OutOfMemory)?;
    buf.push(b'\0').map_err(|_| Error::OutOfMemory)?;

    // GNU lrzsz parses the first three fields unconditionally once metadata is
    // present. Always include an explicit mode field so absent optional values
    // cannot leave the receiver with uninitialized timestamp/mode data.
    write!(
        buf,
        "{size} {:o} 0\0",
        modification_time.unwrap_or_default()
    )
    .map_err(|_| Error::OutOfMemory)?;

    if Header::new(encoding, Frame::ZFILE, [0; 4])
        .write_with_escape_options(port, escape.ctrl, escape.bit8)?
        .is_none()
    {
        return Ok(None);
    }
    write_subpacket_with_escape_options(
        port,
        encoding,
        SubpacketType::ZCRCW,
        buf,
        escape.ctrl,
        escape.bit8,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_empty_file_size_as_unknown() {
        assert_eq!(parse_file_size(b""), Ok(None));
        assert_eq!(parse_file_size(b"0"), Ok(Some(0)));
    }

    #[test]
    fn reject_bad_file_size() {
        assert_eq!(parse_file_size(b"12x"), Err(Error::MalformedFileSize));
    }

    #[test]
    fn parse_octal_file_modification_time() {
        assert_eq!(
            parse_file_modification_time(b"14524770400"),
            Ok(Some(1_700_000_000))
        );
        assert_eq!(parse_file_modification_time(b"0"), Ok(None));
        assert_eq!(parse_file_modification_time(b""), Ok(None));
    }

    #[test]
    fn reject_bad_file_modification_time() {
        assert_eq!(
            parse_file_modification_time(b"128"),
            Err(Error::MalformedFileModificationTime)
        );
    }
}
