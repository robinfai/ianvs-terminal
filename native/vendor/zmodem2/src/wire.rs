// SPDX-License-Identifier: MIT OR Apache-2.0
// Copyright (c) 2017-2020 Alexey Arbuzov
// Copyright (c) 2023-2026 Jarkko Sakkinen

//! Incremental ZMODEM wire codec helpers.

use crate::buffer::Buffer;
use crate::crc;
use crate::error::Error;
use crate::header::{
    Encoding, Frame, HEADER_PAYLOAD_SIZE, HEADER_SIZE, Header, Zrinit,
    write_slice_escaped_with_escape_options,
};
use crate::io::{Read, Write};
use crate::zdle;
use crate::{XOFF, XON, ZDLE, ZPAD};

/// Maximum unescaped subpacket payload emitted by this implementation.
pub(crate) const SUBPACKET_MAX_SIZE: usize = 1024;
/// Maximum unescaped subpacket payload accepted from a peer. GNU lrzsz can
/// deliberately start with 4 KiB or 8 KiB subpackets even though the original
/// specification recommends 1024 bytes.
pub(crate) const RECEIVE_SUBPACKET_MAX_SIZE: usize = 8 * 1024;
#[cfg(test)]
pub(crate) const MAX_RECEIVE_SUBPACKET_ESCAPED: usize = RECEIVE_SUBPACKET_MAX_SIZE * 2 + 2 + 8;
pub(crate) const SUBPACKET_PER_ACK: usize = 10;
pub(crate) const MAX_HEADER_ESCAPED: usize = 128;
pub(crate) const MAX_SUBPACKET_ESCAPED: usize = SUBPACKET_MAX_SIZE * 2 + 2 + 8;
pub(crate) const WIRE_BUF_SIZE: usize = MAX_HEADER_ESCAPED + MAX_SUBPACKET_ESCAPED;

const fn is_raw_flow_control(byte: u8) -> bool {
    matches!(byte & 0x7f, XON | XOFF)
}

/// ZMODEM sends eight raw CAN bytes (usually followed by eight backspaces)
/// and requires receivers to abort after five. Framed CAN data is ZDLE
/// escaped, so five consecutive *raw* bytes cannot occur in a valid header or
/// data subpacket.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub(crate) struct CancelDetector {
    run: u8,
}

impl CancelDetector {
    pub(crate) const fn new() -> Self {
        Self { run: 0 }
    }

    pub(crate) fn observe(&mut self, byte: u8) -> Result<(), Error> {
        if byte == ZDLE {
            self.run = self.run.saturating_add(1);
            if self.run >= 5 {
                return Err(Error::Cancelled);
            }
        } else {
            self.run = 0;
        }
        Ok(())
    }
}

pub(crate) fn read_byte_detecting_cancel<P>(
    port: &mut P,
    cancel: &mut CancelDetector,
) -> Result<Option<u8>, Error>
where
    P: Read + ?Sized,
{
    let Some(byte) = port.read_byte()? else {
        return Ok(None);
    };
    cancel.observe(byte)?;
    Ok(Some(byte))
}

/// The ZMODEM protocol subpacket type.
#[repr(u8)]
#[allow(clippy::upper_case_acronyms)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum SubpacketType {
    ZCRCE = 0x68,
    ZCRCG = 0x69,
    ZCRCQ = 0x6a,
    ZCRCW = 0x6b,
}

impl TryFrom<u8> for SubpacketType {
    type Error = Error;

    fn try_from(value: u8) -> Result<Self, Self::Error> {
        match value {
            0x68 => Ok(SubpacketType::ZCRCE),
            0x69 => Ok(SubpacketType::ZCRCG),
            0x6a => Ok(SubpacketType::ZCRCQ),
            0x6b => Ok(SubpacketType::ZCRCW),
            _ => Err(Error::MalformedPacket(value)),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum ZpadState {
    Idle,
    Zpad,
    ZpadZpad,
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum HeaderReadState {
    SeekingZpad,
    ReadingEncoding,
    ReadingData,
}

/// Incremental reader for ZMODEM headers.
pub(crate) struct HeaderReader {
    state: HeaderReadState,
    zpad_state: ZpadState,
    buf: Buffer<HEADER_SIZE>,
    candidate_raw: Buffer<MAX_HEADER_ESCAPED>,
    replay: Buffer<MAX_HEADER_ESCAPED>,
    replay_offset: usize,
    encoding: Option<Encoding>,
    expected_len: usize,
    escape_pending: bool,
    resyncing: bool,
}

impl HeaderReader {
    pub(crate) const fn new() -> Self {
        Self {
            state: HeaderReadState::SeekingZpad,
            zpad_state: ZpadState::Idle,
            buf: Buffer::<HEADER_SIZE>::new(),
            candidate_raw: Buffer::<MAX_HEADER_ESCAPED>::new(),
            replay: Buffer::<MAX_HEADER_ESCAPED>::new(),
            replay_offset: 0,
            encoding: None,
            expected_len: 0,
            escape_pending: false,
            resyncing: false,
        }
    }

    /// Enter resynchronisation mode: malformed framing is treated as
    /// garbage to skip past rather than a fatal error, until the next
    /// well-formed header is decoded. The receiver arms this after a
    /// corrupt data subpacket, when the sender is still transmitting the
    /// tail of the aborted window (arbitrary bytes, some of which look
    /// like a header start) before it honours the ZRPOS and rewinds.
    pub(crate) fn enter_resync(&mut self) {
        self.resyncing = true;
    }

    /// Resets the framing scan without leaving resync mode (so a garbage
    /// byte that faked a header start does not clear the tolerance).
    fn reset(&mut self) {
        self.state = HeaderReadState::SeekingZpad;
        self.zpad_state = ZpadState::Idle;
        self.encoding = None;
        self.expected_len = 0;
        self.escape_pending = false;
        self.buf.clear();
        self.candidate_raw.clear();
    }

    /// Reads a raw byte, preferring bytes retained from a failed overlapping
    /// candidate. Replayed bytes have already passed through the cancel
    /// detector when they were first read from the transport.
    fn read_raw<P>(
        &mut self,
        port: &mut P,
        cancel_detector: &mut CancelDetector,
    ) -> Result<Option<u8>, Error>
    where
        P: Read + ?Sized,
    {
        if let Some(byte) = self.replay.get(self.replay_offset).copied() {
            self.replay_offset += 1;
            return Ok(Some(byte));
        }
        self.replay.clear();
        self.replay_offset = 0;
        read_byte_detecting_cancel(port, cancel_detector)
    }

    /// Retains every raw byte after the failed candidate's encoding byte.
    /// This is the header-scanner equivalent of a one-byte sliding window:
    /// a genuine `ZPAD ZDLE ...` sequence embedded in a false candidate is
    /// reconsidered instead of being lost with the failed CRC body.
    fn replay_candidate_tail(&mut self) -> Result<(), Error> {
        let mut replay = Buffer::<MAX_HEADER_ESCAPED>::new();
        if let Some(tail) = self.candidate_raw.get(1..) {
            replay
                .extend_from_slice(tail)
                .map_err(|_| Error::OutOfMemory)?;
        }
        replay
            .extend_from_slice(&self.replay[self.replay_offset..])
            .map_err(|_| Error::OutOfMemory)?;
        self.replay = replay;
        self.replay_offset = 0;
        Ok(())
    }

    fn read_header_data_byte<P>(
        &mut self,
        port: &mut P,
        cancel_detector: &mut CancelDetector,
    ) -> Result<Option<u8>, Error>
    where
        P: Read + ?Sized,
    {
        if self.encoding == Some(Encoding::ZHEX) {
            loop {
                let Some(byte) = self.read_raw(port, cancel_detector)? else {
                    return Ok(None);
                };
                self.candidate_raw
                    .push(byte)
                    .map_err(|_| Error::OutOfMemory)?;
                if !is_raw_flow_control(byte) {
                    return Ok(Some(byte & 0x7f));
                }
            }
        }

        if self.escape_pending {
            let Some(byte) = self.read_header_escape_followup(port, cancel_detector)? else {
                return Ok(None);
            };
            self.escape_pending = false;
            return Ok(Some(zdle::UNZDLE_TABLE[byte as usize]));
        }

        loop {
            let Some(byte) = self.read_raw(port, cancel_detector)? else {
                return Ok(None);
            };
            self.candidate_raw
                .push(byte)
                .map_err(|_| Error::OutOfMemory)?;
            if is_raw_flow_control(byte) {
                continue;
            }
            if byte != ZDLE {
                return Ok(Some(byte));
            }

            let Some(next) = self.read_header_escape_followup(port, cancel_detector)? else {
                self.escape_pending = true;
                return Ok(None);
            };
            return Ok(Some(zdle::UNZDLE_TABLE[next as usize]));
        }
    }

    /// Reads the encoded byte after `ZDLE`, ignoring raw software-flow-control
    /// characters before retaining the real continuation for candidate replay.
    /// A quoted XON/XOFF is encoded as `ZDLE Q/S`, so a raw 0x11/0x13 (with
    /// either parity) in this position is unambiguously out-of-band noise.
    fn read_header_escape_followup<P>(
        &mut self,
        port: &mut P,
        cancel_detector: &mut CancelDetector,
    ) -> Result<Option<u8>, Error>
    where
        P: Read + ?Sized,
    {
        loop {
            let Some(byte) = self.read_raw(port, cancel_detector)? else {
                return Ok(None);
            };
            if is_raw_flow_control(byte) {
                continue;
            }
            self.candidate_raw
                .push(byte)
                .map_err(|_| Error::OutOfMemory)?;
            return Ok(Some(byte));
        }
    }

    fn advance_zpad_state(&mut self, byte: u8) -> bool {
        // The ZMODEM specification requires the hex-header receive path to
        // ignore parity. We do not know the encoding until after this prefix,
        // so accept parity on the ASCII framing bytes; binary header bodies
        // remain byte-exact below.
        let byte = byte & 0x7f;
        match self.zpad_state {
            ZpadState::Idle => {
                if byte == ZPAD {
                    self.zpad_state = ZpadState::Zpad;
                }
            }
            ZpadState::Zpad | ZpadState::ZpadZpad => {
                if byte == ZDLE {
                    self.zpad_state = ZpadState::Idle;
                    return true;
                }
                if byte == ZPAD {
                    self.zpad_state = ZpadState::ZpadZpad;
                } else {
                    self.zpad_state = ZpadState::Idle;
                }
            }
        }
        false
    }

    pub(crate) fn read<P>(
        &mut self,
        port: &mut P,
        cancel_detector: &mut CancelDetector,
    ) -> Result<Option<Header>, Error>
    where
        P: Read + ?Sized,
    {
        loop {
            match self.state {
                HeaderReadState::SeekingZpad => {
                    let Some(byte) = self.read_raw(port, cancel_detector)? else {
                        return Ok(None);
                    };
                    if is_raw_flow_control(byte) {
                        continue;
                    }
                    if self.advance_zpad_state(byte) {
                        self.state = HeaderReadState::ReadingEncoding;
                    }
                }
                HeaderReadState::ReadingEncoding => {
                    let Some(byte) = self.read_raw(port, cancel_detector)? else {
                        return Ok(None);
                    };
                    if is_raw_flow_control(byte) {
                        continue;
                    }
                    let encoding = match if byte & 0x7f == Encoding::ZHEX as u8 {
                        Ok(Encoding::ZHEX)
                    } else {
                        Encoding::try_from(byte)
                    } {
                        Ok(encoding) => encoding,
                        Err(e) => {
                            self.reset();
                            // The invalid encoding byte may itself be the
                            // first ZPAD of an overlapping header.
                            self.advance_zpad_state(byte);
                            // A `ZPAD ZDLE` in mid-window garbage is not
                            // a real header: keep scanning instead of
                            // aborting the transfer.
                            if self.resyncing {
                                continue;
                            }
                            return Err(e);
                        }
                    };
                    self.expected_len = Header::read_size(encoding);
                    self.encoding = Some(encoding);
                    self.escape_pending = false;
                    self.buf.clear();
                    self.candidate_raw.clear();
                    self.candidate_raw
                        .push(byte)
                        .map_err(|_| Error::OutOfMemory)?;
                    self.state = HeaderReadState::ReadingData;
                }
                HeaderReadState::ReadingData => {
                    while self.buf.len() < self.expected_len {
                        let Some(byte) = self.read_header_data_byte(port, cancel_detector)? else {
                            return Ok(None);
                        };
                        self.buf.push(byte).map_err(|_| Error::OutOfMemory)?;
                    }

                    let Some(encoding) = self.encoding else {
                        self.reset();
                        if self.resyncing {
                            continue;
                        }
                        return Err(Error::MalformedHeader);
                    };

                    let header = match decode_header(encoding, &self.buf) {
                        Ok(header) => header,
                        Err(e) => {
                            self.replay_candidate_tail()?;
                            self.reset();
                            // Garbage that passed the encoding byte by
                            // chance still fails the header CRC; during
                            // resync that is one more byte to skip, not a
                            // fatal error.
                            if self.resyncing {
                                continue;
                            }
                            return Err(e);
                        }
                    };
                    // A well-formed header ends the resync: the stream is
                    // realigned, fatal-on-garbage semantics resume.
                    self.resyncing = false;
                    self.reset();
                    return Ok(Some(header));
                }
            }
        }
    }
}

pub(crate) struct SliceReader<'a> {
    buf: &'a [u8],
    pos: usize,
}

impl<'a> SliceReader<'a> {
    pub(crate) const fn new(buf: &'a [u8]) -> Self {
        Self { buf, pos: 0 }
    }

    pub(crate) const fn consumed(&self) -> usize {
        self.pos
    }

    pub(crate) fn peek(&self) -> Option<u8> {
        self.buf.get(self.pos).copied()
    }

    pub(crate) fn remaining(&self) -> &[u8] {
        &self.buf[self.pos..]
    }

    pub(crate) fn advance(&mut self, n: usize) {
        self.pos = self.pos.saturating_add(n).min(self.buf.len());
    }
}

impl Read for SliceReader<'_> {
    fn read_byte(&mut self) -> Result<Option<u8>, Error> {
        if let Some(byte) = self.buf.get(self.pos) {
            self.pos += 1;
            Ok(Some(*byte))
        } else {
            Ok(None)
        }
    }
}

pub(crate) struct BufferWriter<'a, const N: usize> {
    buf: &'a mut Buffer<N>,
}

impl<'a, const N: usize> BufferWriter<'a, N> {
    pub(crate) fn new(buf: &'a mut Buffer<N>) -> Self {
        Self { buf }
    }
}

impl<const N: usize> Write for BufferWriter<'_, N> {
    fn write_all(&mut self, buf: &[u8]) -> Result<Option<()>, Error> {
        if self.buf.len() + buf.len() > self.buf.capacity() {
            return Ok(None);
        }
        self.buf
            .extend_from_slice(buf)
            .map_err(|_| Error::OutOfMemory)?;
        Ok(Some(()))
    }

    fn write_byte(&mut self, value: u8) -> Result<Option<()>, Error> {
        if self.buf.len() == self.buf.capacity() {
            return Ok(None);
        }
        self.buf.push(value).map_err(|_| Error::OutOfMemory)?;
        Ok(Some(()))
    }
}

pub(crate) struct RxCrc {
    calc16: crc::Crc16,
    calc32: crc::Crc32,
    buf: [u8; 4],
    bytes_read: u8,
    escape_pending: bool,
}

impl RxCrc {
    pub(crate) fn new() -> Self {
        Self {
            calc16: crc::Crc16::new(),
            calc32: crc::Crc32::new(),
            buf: [0; 4],
            bytes_read: 0,
            escape_pending: false,
        }
    }

    pub(crate) fn reset(&mut self) {
        self.calc16 = crc::Crc16::new();
        self.calc32 = crc::Crc32::new();
        self.bytes_read = 0;
        self.escape_pending = false;
    }

    pub(crate) fn update(&mut self, byte: u8, encoding: Encoding) {
        if encoding == Encoding::ZBIN32 {
            self.calc32.update_byte(byte);
        } else {
            self.calc16.update_byte(byte);
        }
    }

    pub(crate) fn process<P: Read + ?Sized>(
        &mut self,
        port: &mut P,
        encoding: Encoding,
        cancel: &mut CancelDetector,
    ) -> Result<Option<()>, Error> {
        let crc_len = if encoding == Encoding::ZBIN32 { 4 } else { 2 };
        let Some(byte) = read_byte_unescaped_stateful(port, &mut self.escape_pending, cancel)?
        else {
            return Ok(None);
        };
        self.buf[self.bytes_read as usize] = byte;
        self.bytes_read += 1;

        if self.bytes_read < crc_len {
            return Ok(None);
        }

        if encoding == Encoding::ZBIN32 {
            let expected = self.calc32.finalize().to_le_bytes();
            if expected != self.buf {
                return Err(Error::UnexpectedCrc32);
            }
        } else {
            let expected = self.calc16.finalize().to_be_bytes();
            if expected != [self.buf[0], self.buf[1]] {
                return Err(Error::UnexpectedCrc16);
            }
        }
        Ok(Some(()))
    }
}

pub(crate) fn read_byte_unescaped_stateful<P>(
    port: &mut P,
    pending: &mut bool,
    cancel: &mut CancelDetector,
) -> Result<Option<u8>, Error>
where
    P: Read + ?Sized,
{
    if *pending {
        let Some(b) = read_escape_followup(port, cancel)? else {
            return Ok(None);
        };
        *pending = false;
        return Ok(Some(zdle::UNZDLE_TABLE[b as usize]));
    }

    loop {
        let Some(b) = read_byte_detecting_cancel(port, cancel)? else {
            return Ok(None);
        };
        // Raw software-flow-control bytes are transport noise throughout a
        // binary subpacket, including its CRC. An escaped XON/XOFF takes the
        // `pending`/ZDLE branch and remains an exact protocol byte.
        if is_raw_flow_control(b) {
            continue;
        }
        if b == ZDLE {
            let Some(next) = read_escape_followup(port, cancel)? else {
                *pending = true;
                return Ok(None);
            };
            return Ok(Some(zdle::UNZDLE_TABLE[next as usize]));
        }

        return Ok(Some(b));
    }
}

/// Reads the encoded continuation after `ZDLE`, ignoring raw XON/XOFF and
/// their parity-marked variants even when they arrive in separate submits.
pub(crate) fn read_escape_followup<P>(
    port: &mut P,
    cancel: &mut CancelDetector,
) -> Result<Option<u8>, Error>
where
    P: Read + ?Sized,
{
    loop {
        let Some(byte) = read_byte_detecting_cancel(port, cancel)? else {
            return Ok(None);
        };
        if !is_raw_flow_control(byte) {
            return Ok(Some(byte));
        }
    }
}

pub(crate) fn decode_header(encoding: Encoding, data: &[u8]) -> Result<Header, Error> {
    let mut out: Buffer<HEADER_SIZE> = Buffer::new();
    if encoding == Encoding::ZHEX {
        if data.len() % 2 != 0 {
            return Err(Error::MalformedHeader);
        }
        let mut out_bytes = [0u8; HEADER_SIZE / 2];
        let out_len = data.len() / 2;
        let out_buf = out_bytes.get_mut(..out_len).ok_or(Error::UnexpectedEof)?;
        hex::decode_to_slice(data, out_buf).map_err(|_| Error::MalformedHeader)?;
        out.extend_from_slice(out_buf)
            .map_err(|_| Error::OutOfMemory)?;
    } else {
        out.extend_from_slice(data)
            .map_err(|_| Error::OutOfMemory)?;
    }

    let crc_len = if encoding == Encoding::ZBIN32 { 4 } else { 2 };
    if out.len() < HEADER_PAYLOAD_SIZE + crc_len {
        return Err(Error::MalformedHeader);
    }
    let (payload, crc_bytes) = out.split_at(HEADER_PAYLOAD_SIZE);
    if encoding == Encoding::ZBIN32 {
        let expected_crc = crc::crc32_iso_hdlc(payload).to_le_bytes();
        if crc_bytes != &expected_crc[..crc_len] {
            return Err(Error::UnexpectedCrc32);
        }
    } else {
        let expected_crc = crc::crc16_xmodem(payload).to_be_bytes();
        if crc_bytes != &expected_crc[..crc_len] {
            return Err(Error::UnexpectedCrc16);
        }
    }

    let frame = Frame::try_from(payload[0])?;
    let mut flags = [0u8; 4];
    flags.copy_from_slice(&payload[1..=4]);
    Ok(Header::new(encoding, frame, flags))
}

/// Writes ZRINIT. `buffer_len` is the advertised receiver buffer
/// length in bytes, where zero means nonstop I/O (the sender may
/// stream without waiting for acknowledgement); `overlapped_io` adds
/// `CANOVIO` (storage is written while receiving).
pub(crate) fn write_zrinit<P>(
    port: &mut P,
    buffer_len: u16,
    overlapped_io: bool,
) -> Result<Option<()>, Error>
where
    P: Write + ?Sized,
{
    let mut zrinit = Zrinit::CANFDX | Zrinit::CANFC32;
    if overlapped_io {
        zrinit |= Zrinit::CANOVIO;
    }
    let buffer_size = buffer_len.to_le_bytes();
    Header::new(
        Encoding::ZHEX,
        Frame::ZRINIT,
        [buffer_size[0], buffer_size[1], 0, zrinit.bits()],
    )
    .write(port)
}

/// Writes a subpacket.
///
/// # Errors
///
/// This function returns `Error::OutOfMemory` if the sink is full, or
/// `Error::UnsupportedFeature` if `ZHEX` encoding is requested.
pub(crate) fn write_subpacket_with_escape_options<P>(
    port: &mut P,
    encoding: Encoding,
    kind: SubpacketType,
    data: &[u8],
    escape_ctrl: bool,
    escape_8bit: bool,
) -> Result<Option<()>, Error>
where
    P: Write + ?Sized,
{
    let kind = kind as u8;
    if write_slice_escaped_with_escape_options(port, data, escape_ctrl, escape_8bit)?.is_none() {
        return Ok(None);
    }
    if port.write_byte(ZDLE)?.is_none() {
        return Ok(None);
    }
    if port.write_byte(kind)?.is_none() {
        return Ok(None);
    }
    match encoding {
        Encoding::ZBIN32 => {
            let mut crc = crc::Crc32::new();
            crc.update(data);
            crc.update_byte(kind);
            let buf = crc.finalize().to_le_bytes();
            write_slice_escaped_with_escape_options(port, &buf, escape_ctrl, escape_8bit)
        }
        Encoding::ZBIN => {
            let mut crc = crc::Crc16::new();
            crc.update(data);
            crc.update_byte(kind);
            let buf = crc.finalize().to_be_bytes();
            write_slice_escaped_with_escape_options(port, &buf, escape_ctrl, escape_8bit)
        }
        Encoding::ZHEX => Err(Error::UnsupportedFeature),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decode_zbin32_header() {
        let data = [
            Frame::ZRINIT as u8,
            0x0a,
            0x0b,
            0x0c,
            0x0d,
            0x99,
            0xe2,
            0xae,
            0x4a,
        ];
        let header = decode_header(Encoding::ZBIN32, &data).unwrap();

        assert_eq!(header.encoding(), Encoding::ZBIN32);
        assert_eq!(header.frame(), Frame::ZRINIT);
        assert_eq!(header.count(), u32::from_le_bytes([0x0a, 0x0b, 0x0c, 0x0d]));
    }

    #[test]
    fn decode_zbin32_bad_crc() {
        let data = [Frame::ZRINIT as u8, 0x0a, 0x0b, 0x0c, 0x0d, 0, 0, 0, 0];

        assert!(matches!(
            decode_header(Encoding::ZBIN32, &data),
            Err(Error::UnexpectedCrc32)
        ));
    }
}
