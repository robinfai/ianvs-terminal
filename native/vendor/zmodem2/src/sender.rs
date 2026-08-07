// SPDX-License-Identifier: MIT OR Apache-2.0
// Copyright (c) 2017-2020 Alexey Arbuzov
// Copyright (c) 2023-2026 Jarkko Sakkinen

//! ZMODEM sender state machine.

use crate::XON;
use crate::api::{Action, Event, FileInfo, Position};
use crate::buffer::Buffer;
use crate::error::Error;
use crate::file::write_zfile_with_escape_options;
use crate::header::{
    Encoding, EscapeOptions, Frame, Header, ZACK_HEADER, ZFIN_HEADER, ZNAK_HEADER, ZRQINIT_HEADER,
    Zrinit,
};
use crate::io::Write;
use crate::session::{FileRequest, HexTrailerPhase, SenderEvent, SenderPhase};
use crate::string::String;
use crate::wire::{
    BufferWriter, CancelDetector, HeaderReader, SUBPACKET_MAX_SIZE, SUBPACKET_PER_ACK, SliceReader,
    SubpacketType, WIRE_BUF_SIZE, write_subpacket_with_escape_options,
};
use core::cmp::{Ordering, min};

/// ZMODEM sender state machine.
// The sender carries a handful of independent flags (has-file,
// frame-needs-header, finish-requested, receiver-nonstop) that read more
// clearly as bools than as a single packed enum.
#[allow(clippy::struct_excessive_bools)]
pub struct Sender {
    state: SenderPhase,
    file_name: String,
    file_size: u32,
    file_modification_time: Option<u64>,
    has_file: bool,
    pending_request: Option<FileRequest>,
    frame_remaining: usize,
    frame_needs_header: bool,
    max_subpacket_size: usize,
    max_subpackets_per_ack: usize,
    buf: Buffer<SUBPACKET_MAX_SIZE>,
    outgoing: Buffer<WIRE_BUF_SIZE>,
    outgoing_offset: usize,
    header_reader: HeaderReader,
    pending_event: Option<SenderEvent>,
    finish_requested: bool,
    streaming_window: usize,
    rx_nonstop: bool,
    escape_ctrl: bool,
    escape_8bit: bool,
    data_encoding: Encoding,
    frame_start: u32,
    znak_retries: u8,
    timeout_retries: u8,
    cancel_detector: CancelDetector,
    zfin_hex_trailer_phase: Option<HexTrailerPhase>,
    zfin_hex_optional_xon: bool,
    peer_progress_epoch: u64,
}

/// Consecutive `ZNAK` responses accepted before the peer is considered
/// unable to recover the current protocol phase.
pub(crate) const MAX_ZNAK_RETRIES: u8 = 3;
/// Consecutive response timeouts tolerated without peer-confirmed progress.
pub(crate) const MAX_TIMEOUT_RETRIES: u8 = 3;

impl Sender {
    /// Create a new sender instance.
    ///
    /// # Errors
    ///
    /// * [`OutOfMemory`](crate::Error::OutOfMemory) when the outgoing buffer cannot hold the handshake
    pub fn new() -> Result<Self, Error> {
        let mut sender = Self {
            state: SenderPhase::WaitReceiverInit,
            file_name: String::new(),
            file_size: 0,
            file_modification_time: None,
            has_file: false,
            pending_request: None,
            frame_remaining: 0,
            frame_needs_header: false,
            max_subpacket_size: SUBPACKET_MAX_SIZE,
            max_subpackets_per_ack: SUBPACKET_PER_ACK,
            buf: Buffer::<SUBPACKET_MAX_SIZE>::new(),
            outgoing: Buffer::<WIRE_BUF_SIZE>::new(),
            outgoing_offset: 0,
            header_reader: HeaderReader::new(),
            pending_event: None,
            finish_requested: false,
            streaming_window: SUBPACKET_PER_ACK,
            rx_nonstop: false,
            escape_ctrl: false,
            escape_8bit: false,
            data_encoding: Encoding::ZBIN,
            frame_start: 0,
            znak_retries: 0,
            timeout_retries: 0,
            cancel_detector: CancelDetector::new(),
            zfin_hex_trailer_phase: None,
            zfin_hex_optional_xon: false,
            peer_progress_epoch: 0,
        };
        sender.queue_zrqinit()?;
        Ok(sender)
    }

    /// Sets the number of subpackets sent per acknowledgement wait when
    /// the receiver has advertised nonstop I/O (a zero buffer length)
    /// together with `CANOVIO`.
    ///
    /// Defaults to a conservative window of 10. On reliable transports
    /// (TCP, SSH, a pipe) each wait costs a full round trip, so raising
    /// the window, or passing `usize::MAX` for fully nonstop streaming,
    /// removes the dominant latency cost of large transfers. Values
    /// below 1 are clamped to 1. Has no effect when the receiver
    /// advertised a bounded buffer, whose pacing is honored as before.
    pub fn set_streaming_window(&mut self, subpackets: usize) {
        self.streaming_window = subpackets.max(1);
        // ZRINIT may already have been negotiated, in which case
        // max_subpackets_per_ack was fixed from the previous window.
        // Recompute it now so a window set after the handshake still
        // takes effect; it only applies when the receiver advertised
        // nonstop I/O (see update_receiver_caps).
        if self.rx_nonstop {
            self.max_subpackets_per_ack = self.streaming_window;
        }
    }

    /// Monotonic marker advanced after a CRC-valid peer header is accepted.
    /// Embedders can use it to distinguish protocol activity from raw noise.
    #[must_use]
    pub fn peer_progress_epoch(&self) -> u64 {
        self.peer_progress_epoch
    }

    /// Starts sending a file with the provided metadata.
    ///
    /// The file size must be known; [`FileInfo`] with no size is rejected with
    /// [`UnsupportedFeature`](crate::Error::UnsupportedFeature).
    ///
    /// # Errors
    ///
    /// * [`UnsupportedFeature`](crate::Error::UnsupportedFeature) when the size is unknown
    /// * [`Backpressure`](crate::Error::Backpressure) when outgoing bytes are still pending
    /// * [`InvalidState`](crate::Error::InvalidState) when a transfer is already in progress
    pub fn start_file(&mut self, info: FileInfo) -> Result<(), Error> {
        let Some(size) = info.size else {
            return Err(Error::UnsupportedFeature);
        };
        let file_name = info.name;
        let file_size = size.get();
        if !matches!(
            self.state,
            SenderPhase::WaitReceiverInit | SenderPhase::ReadyForFile
        ) {
            return Err(Error::InvalidState);
        }

        self.file_name.clear();
        self.file_name
            .extend_from_slice(file_name)
            .map_err(|_| Error::OutOfMemory)?;
        self.file_size = file_size;
        self.file_modification_time = info.modification_time;
        self.has_file = true;
        self.pending_request = None;
        self.frame_remaining = 0;
        self.frame_needs_header = false;
        self.timeout_retries = 0;

        if self.state == SenderPhase::ReadyForFile {
            if self.outgoing() {
                return Err(Error::Backpressure);
            }
            self.queue_zfile()?;
            self.state = SenderPhase::WaitFilePos;
        }
        Ok(())
    }

    /// Requests to finish the session after the current file completes.
    ///
    /// # Errors
    ///
    /// * [`Backpressure`](crate::Error::Backpressure) when outgoing bytes are still pending
    pub fn finish(&mut self) -> Result<(), Error> {
        self.finish_requested = true;
        if self.state == SenderPhase::ReadyForFile {
            if self.outgoing() {
                return Err(Error::Backpressure);
            }
            self.queue_zfin()?;
            self.state = SenderPhase::WaitFinish;
        }
        Ok(())
    }

    /// Provides a chunk of file data for the current [`Action::ReadFile`] request.
    ///
    /// # Errors
    ///
    /// * [`InvalidState`](crate::Error::InvalidState) when no read request is pending
    /// * [`UnexpectedEof`](crate::Error::UnexpectedEof) when the chunk is empty or too large
    /// * [`Backpressure`](crate::Error::Backpressure) when outgoing bytes are still pending
    pub fn submit_file(&mut self, data: &[u8]) -> Result<(), Error> {
        if self.state != SenderPhase::NeedFileData {
            return Err(Error::InvalidState);
        }
        let Some(request) = self.pending_request else {
            return Err(Error::InvalidState);
        };

        if data.is_empty() {
            return Err(Error::UnexpectedEof);
        }
        if data.len() > request.len {
            return Err(Error::UnexpectedEof);
        }
        let remaining = self.file_size.saturating_sub(request.offset) as usize;
        if data.len() > remaining {
            return Err(Error::UnexpectedEof);
        }
        if self.outgoing() {
            return Err(Error::Backpressure);
        }

        let offset = request.offset;
        let next_offset = offset
            .checked_add(u32::try_from(data.len()).map_err(|_| Error::OutOfMemory)?)
            .ok_or(Error::OutOfMemory)?;
        let remaining_after = self.file_size.saturating_sub(next_offset);
        let max_len = min(self.max_subpacket_size, remaining_after as usize);
        let is_last_in_frame =
            self.frame_remaining <= 1 || data.len() < request.len || remaining_after == 0;
        let kind = if is_last_in_frame {
            SubpacketType::ZCRCW
        } else {
            SubpacketType::ZCRCG
        };

        self.queue_zdata(offset, data, kind, self.frame_needs_header)?;
        self.frame_needs_header = false;

        if self.frame_remaining > 0 {
            self.frame_remaining -= 1;
        }

        if is_last_in_frame {
            self.pending_request = None;
            self.state = SenderPhase::WaitFileAck;
            self.frame_remaining = 0;
        } else {
            self.pending_request = Some(FileRequest {
                offset: next_offset,
                len: max_len,
            });
        }
        Ok(())
    }

    /// Submits incoming wire data into the state machine.
    ///
    /// Returns the number of bytes consumed.
    ///
    /// # Errors
    ///
    /// * [`UnexpectedCrc16`](crate::Error::UnexpectedCrc16) or
    ///   [`UnexpectedCrc32`](crate::Error::UnexpectedCrc32) when corrupted data has been detected
    pub fn submit_wire(&mut self, input: &[u8]) -> Result<usize, Error> {
        let mut reader = SliceReader::new(input);

        loop {
            if self.outgoing() {
                break;
            }

            let before = reader.consumed();

            if self.zfin_hex_trailer_phase.is_some() {
                if !self.consume_zfin_hex_trailer(&mut reader)? {
                    break;
                }
                self.on_zfin()?;
                if reader.consumed() == before || self.outgoing() {
                    break;
                }
                continue;
            }

            if self.state == SenderPhase::Done {
                if self.zfin_hex_optional_xon {
                    let Some(byte) = reader.peek() else {
                        break;
                    };
                    self.zfin_hex_optional_xon = false;
                    if byte & 0x7f == XON {
                        reader.advance(1);
                    }
                }
                break;
            }

            let header = match self
                .header_reader
                .read(&mut reader, &mut self.cancel_detector)
            {
                Ok(Some(header)) => header,
                Ok(None) => break,
                Err(Error::Cancelled) => {
                    self.on_abort();
                    break;
                }
                Err(_) => {
                    // Header corruption is recoverable in ZMODEM. Preserve
                    // the bytes consumed from this submission, ask the peer
                    // to retransmit, and scan for a fresh header after the
                    // queued ZNAK has been drained.
                    self.header_reader.enter_resync();
                    self.queue_nak()?;
                    break;
                }
            };

            if self.state == SenderPhase::WaitFinish
                && header.frame() == Frame::ZFIN
                && header.encoding() == Encoding::ZHEX
            {
                self.zfin_hex_trailer_phase = Some(HexTrailerPhase::LineStart);
                self.zfin_hex_optional_xon = false;
            } else {
                self.handle_header(header)?;
            }
            self.peer_progress_epoch = self.peer_progress_epoch.saturating_add(1);

            if reader.consumed() == before || reader.consumed() == input.len() {
                break;
            }
        }

        Ok(reader.consumed())
    }

    /// Consumes the exact LF or CR/LF after a peer ZHEX ZFIN. The optional
    /// XON is consumed when already available and otherwise remains armed for
    /// the next submission after OO has drained. Bytes that do not belong to
    /// the trailer are never consumed, preserving the following shell text.
    fn consume_zfin_hex_trailer(&mut self, reader: &mut SliceReader<'_>) -> Result<bool, Error> {
        loop {
            let Some(phase) = self.zfin_hex_trailer_phase else {
                break;
            };
            let Some(byte) = reader.peek() else {
                return Ok(false);
            };
            match (phase, byte & 0x7f) {
                (HexTrailerPhase::LineStart, b'\r') => {
                    self.cancel_detector.observe(byte)?;
                    reader.advance(1);
                    self.zfin_hex_trailer_phase = Some(HexTrailerPhase::LineFeed);
                }
                (HexTrailerPhase::LineStart | HexTrailerPhase::LineFeed, b'\n') => {
                    self.cancel_detector.observe(byte)?;
                    reader.advance(1);
                    self.zfin_hex_trailer_phase = None;
                    self.zfin_hex_optional_xon = true;
                }
                _ => {
                    self.zfin_hex_trailer_phase = None;
                }
            }
        }

        if self.zfin_hex_optional_xon {
            if let Some(byte) = reader.peek() {
                self.zfin_hex_optional_xon = false;
                if byte & 0x7f == XON {
                    self.cancel_detector.observe(byte)?;
                    reader.advance(1);
                }
            }
        }
        Ok(true)
    }

    /// Returns pending outgoing bytes.
    fn drain_outgoing(&self) -> &[u8] {
        &self.outgoing[self.outgoing_offset..]
    }

    /// Reports that `n` outgoing bytes from the last [`Action::WriteWire`] were
    /// written to the transport.
    pub fn wire_written(&mut self, n: usize) {
        let remaining = self.outgoing.len().saturating_sub(self.outgoing_offset);
        let n = min(n, remaining);
        self.outgoing_offset += n;
        if self.outgoing_offset >= self.outgoing.len() {
            self.outgoing.clear();
            self.outgoing_offset = 0;
        }
    }

    /// Signals that the protocol response timeout expired.
    ///
    /// Re-queues the protocol unit whose acknowledgement was lost. Retries are
    /// bounded and are replenished only by peer-confirmed forward progress.
    ///
    /// # Errors
    ///
    /// * [`Backpressure`](crate::Error::Backpressure) when outgoing bytes are still pending
    pub fn timeout(&mut self) -> Result<(), Error> {
        if self.outgoing() {
            return Ok(());
        }
        if !matches!(
            self.state,
            SenderPhase::WaitReceiverInit
                | SenderPhase::WaitFilePos
                | SenderPhase::WaitFileAck
                | SenderPhase::WaitFileDone
                | SenderPhase::WaitFinish
        ) {
            return Ok(());
        }

        self.timeout_retries = self.timeout_retries.saturating_add(1);
        if self.timeout_retries > MAX_TIMEOUT_RETRIES {
            self.on_abort();
            return Ok(());
        }

        match self.state {
            SenderPhase::WaitReceiverInit => self.queue_zrqinit(),
            SenderPhase::WaitFilePos => self.queue_zfile(),
            SenderPhase::WaitFileAck => {
                self.retry_current_frame();
                Ok(())
            }
            SenderPhase::WaitFileDone => self.queue_zeof(self.file_size),
            SenderPhase::WaitFinish => self.queue_zfin(),
            _ => Ok(()),
        }
    }

    /// Aborts the current session.
    pub fn abort(&mut self) {
        self.state = SenderPhase::Done;
        self.pending_request = None;
        self.zfin_hex_trailer_phase = None;
        self.zfin_hex_optional_xon = false;
        self.pending_event = Some(SenderEvent::Aborted);
    }

    /// Returns the next action the caller must perform.
    ///
    /// Pending events take priority, followed by outgoing wire bytes, then a
    /// file read request, and finally [`Action::Idle`] when there is no
    /// immediate work.
    pub fn poll(&mut self) -> Action<'_> {
        if let Some(event) = self.pending_event.take() {
            return Action::Event(match event {
                SenderEvent::FileComplete => Event::FileCompleted,
                SenderEvent::FileSkipped => Event::FileSkipped,
                SenderEvent::SessionComplete => Event::SessionCompleted,
                SenderEvent::Aborted => Event::Aborted,
            });
        }

        if self.outgoing() {
            return Action::WriteWire(self.drain_outgoing());
        }

        if let Some(request) = self.pending_request {
            return Action::ReadFile {
                offset: Position::new(request.offset),
                max_len: request.len,
            };
        }

        Action::Idle
    }

    fn outgoing(&self) -> bool {
        self.outgoing_offset < self.outgoing.len()
    }

    fn queue_writer(&mut self) -> Result<BufferWriter<'_, WIRE_BUF_SIZE>, Error> {
        if self.outgoing() {
            return Err(Error::Backpressure);
        }
        Ok(BufferWriter::new(&mut self.outgoing))
    }

    fn queue_header(&mut self, header: Header) -> Result<(), Error> {
        let escape_ctrl = self.escape_ctrl;
        let escape_8bit = self.escape_8bit;
        let mut writer = self.queue_writer()?;
        if header
            .write_with_escape_options(&mut writer, escape_ctrl, escape_8bit)?
            .is_none()
        {
            return Err(Error::OutOfMemory);
        }
        Ok(())
    }

    fn queue_zrqinit(&mut self) -> Result<(), Error> {
        self.queue_header(ZRQINIT_HEADER)
    }

    fn queue_zfile(&mut self) -> Result<(), Error> {
        let file_size = self.file_size;
        let file_modification_time = self.file_modification_time;
        let data_encoding = self.data_encoding;
        let file_name = &self.file_name;
        let mut writer = BufferWriter::new(&mut self.outgoing);
        if write_zfile_with_escape_options(
            &mut writer,
            &mut self.buf,
            file_name,
            file_size,
            file_modification_time,
            data_encoding,
            EscapeOptions::new(self.escape_ctrl, self.escape_8bit),
        )?
        .is_none()
        {
            return Err(Error::OutOfMemory);
        }
        Ok(())
    }

    fn queue_zdata(
        &mut self,
        offset: u32,
        data: &[u8],
        kind: SubpacketType,
        include_header: bool,
    ) -> Result<(), Error> {
        let escape_ctrl = self.escape_ctrl;
        let escape_8bit = self.escape_8bit;
        let data_encoding = self.data_encoding;
        let mut writer = self.queue_writer()?;
        if include_header
            && Header::new(data_encoding, Frame::ZDATA, offset.to_le_bytes())
                .write_with_escape_options(&mut writer, escape_ctrl, escape_8bit)?
                .is_none()
        {
            return Err(Error::OutOfMemory);
        }
        if write_subpacket_with_escape_options(
            &mut writer,
            data_encoding,
            kind,
            data,
            escape_ctrl,
            escape_8bit,
        )?
        .is_none()
        {
            return Err(Error::OutOfMemory);
        }
        Ok(())
    }

    fn queue_zeof(&mut self, offset: u32) -> Result<(), Error> {
        self.queue_header(Header::new(
            self.data_encoding,
            Frame::ZEOF,
            offset.to_le_bytes(),
        ))
    }

    fn queue_zfin(&mut self) -> Result<(), Error> {
        self.queue_header(ZFIN_HEADER)
    }

    fn queue_zack(&mut self, count: u32) -> Result<(), Error> {
        self.queue_header(ZACK_HEADER.with_count(count))
    }

    fn queue_nak(&mut self) -> Result<(), Error> {
        self.queue_header(ZNAK_HEADER)
    }

    fn queue_oo(&mut self) -> Result<(), Error> {
        let mut writer = self.queue_writer()?;
        if writer.write_byte(b'O')?.is_none() {
            return Err(Error::OutOfMemory);
        }
        if writer.write_byte(b'O')?.is_none() {
            return Err(Error::OutOfMemory);
        }
        Ok(())
    }

    fn handle_header(&mut self, header: Header) -> Result<(), Error> {
        if header.frame() == Frame::ZNAK {
            return self.on_znak();
        }
        self.znak_retries = 0;
        match header.frame() {
            Frame::ZCHALLENGE => self.queue_zack(header.count()),
            Frame::ZRINIT => self.on_zrinit(header),
            Frame::ZRPOS | Frame::ZACK => self.on_zrpos(header.count()),
            Frame::ZSKIP => self.on_zskip(),
            Frame::ZABORT | Frame::ZFERR | Frame::ZCAN => {
                self.on_abort();
                Ok(())
            }
            Frame::ZFIN => self.on_zfin(),
            _ => {
                if self.state == SenderPhase::WaitReceiverInit {
                    self.queue_zrqinit()?;
                }
                Ok(())
            }
        }
    }

    fn on_zrinit(&mut self, header: Header) -> Result<(), Error> {
        self.update_receiver_caps(header)?;
        match self.state {
            SenderPhase::WaitReceiverInit => {
                self.timeout_retries = 0;
                if self.has_file {
                    self.queue_zfile()?;
                    self.state = SenderPhase::WaitFilePos;
                } else {
                    self.state = SenderPhase::ReadyForFile;
                    if self.finish_requested {
                        self.queue_zfin()?;
                        self.state = SenderPhase::WaitFinish;
                    }
                }
            }
            SenderPhase::WaitFilePos => {
                // ZRINIT is also the receiver's timeout response while it is
                // waiting for an offer. The previous ZFILE may have vanished.
                self.queue_zfile()?;
            }
            SenderPhase::WaitFileDone => {
                self.timeout_retries = 0;
                self.pending_event = Some(SenderEvent::FileComplete);
                self.has_file = false;
                if self.finish_requested {
                    self.queue_zfin()?;
                    self.state = SenderPhase::WaitFinish;
                } else {
                    self.state = SenderPhase::ReadyForFile;
                }
            }
            SenderPhase::WaitFinish => {
                // ZRINIT acknowledges a completed file, not the session
                // closing handshake. A delayed duplicate can arrive after
                // our ZFIN; retransmit ZFIN and keep waiting for peer ZFIN.
                self.queue_zfin()?;
            }
            _ => {}
        }
        Ok(())
    }

    fn update_receiver_caps(&mut self, header: Header) -> Result<(), Error> {
        let flags = header.count().to_le_bytes();
        let rx_buf_size = u16::from_le_bytes([flags[0], flags[1]]) as usize;
        let caps = flags[3];
        if (caps & Zrinit::ESC8.bits()) != 0 {
            // ZMODEM has no reversible 7-bit ZDLE representation for every
            // possible octet. Refuse a peer that requires ESC8 instead of
            // silently transmitting high printable bytes unchanged.
            return Err(Error::UnsupportedFeature);
        }
        let can_ovio = (caps & Zrinit::CANOVIO.bits()) != 0;
        self.escape_ctrl = (caps & Zrinit::ESCCTL.bits()) != 0;
        self.escape_8bit = false;
        self.data_encoding = if (caps & Zrinit::CANFC32.bits()) != 0 {
            Encoding::ZBIN32
        } else {
            Encoding::ZBIN
        };

        // Remember whether the streaming window governs pacing so a later
        // set_streaming_window() can recompute the cadence.
        self.rx_nonstop = rx_buf_size == 0 && can_ovio;

        if rx_buf_size == 0 {
            self.max_subpacket_size = SUBPACKET_MAX_SIZE;
            self.max_subpackets_per_ack = if can_ovio { self.streaming_window } else { 1 };
            return Ok(());
        }

        self.max_subpacket_size = min(SUBPACKET_MAX_SIZE, rx_buf_size);
        if !can_ovio {
            self.max_subpackets_per_ack = 1;
            return Ok(());
        }

        let subpackets = rx_buf_size / self.max_subpacket_size;
        self.max_subpackets_per_ack = if subpackets == 0 { 1 } else { subpackets };
        Ok(())
    }

    fn on_zrpos(&mut self, offset: u32) -> Result<(), Error> {
        let made_progress = self.state == SenderPhase::WaitFilePos
            || (matches!(
                self.state,
                SenderPhase::WaitFileAck | SenderPhase::NeedFileData
            ) && offset > self.frame_start);
        if made_progress {
            self.timeout_retries = 0;
        }
        match self.state {
            SenderPhase::WaitReceiverInit => {
                self.queue_zrqinit()?;
            }
            SenderPhase::WaitFilePos | SenderPhase::WaitFileAck | SenderPhase::NeedFileData => {
                match offset.cmp(&self.file_size) {
                    Ordering::Equal => {
                        self.queue_zeof(self.file_size)?;
                        self.state = SenderPhase::WaitFileDone;
                        self.pending_request = None;
                    }
                    Ordering::Greater => {
                        // A resume beyond EOF cannot be satisfied. In
                        // particular, never echo the hostile offset in a ZEOF:
                        // that would falsely claim a file larger than offered.
                        self.on_abort();
                    }
                    Ordering::Less => {
                        let remaining = (self.file_size - offset) as usize;
                        let max_subpackets = remaining.div_ceil(self.max_subpacket_size);
                        self.frame_remaining = min(self.max_subpackets_per_ack, max_subpackets);
                        self.frame_start = offset;
                        self.frame_needs_header = true;
                        let len = min(self.max_subpacket_size, remaining);
                        self.pending_request = Some(FileRequest { offset, len });
                        self.state = SenderPhase::NeedFileData;
                    }
                }
            }
            _ => {}
        }
        Ok(())
    }

    fn retry_current_frame(&mut self) {
        let offset = self.frame_start;
        if offset >= self.file_size {
            self.on_abort();
            return;
        }
        let remaining = (self.file_size - offset) as usize;
        let max_subpackets = remaining.div_ceil(self.max_subpacket_size);
        self.frame_remaining = min(self.max_subpackets_per_ack, max_subpackets);
        self.frame_needs_header = true;
        self.pending_request = Some(FileRequest {
            offset,
            len: min(self.max_subpacket_size, remaining),
        });
        self.state = SenderPhase::NeedFileData;
    }

    /// Retransmits the protocol unit appropriate to the current phase.
    /// A bounded retry count prevents a broken peer from pinning the sender
    /// forever in an otherwise idle state.
    fn on_znak(&mut self) -> Result<(), Error> {
        self.znak_retries = self.znak_retries.saturating_add(1);
        if self.znak_retries > MAX_ZNAK_RETRIES {
            self.on_abort();
            return Ok(());
        }

        match self.state {
            SenderPhase::WaitReceiverInit | SenderPhase::ReadyForFile => self.queue_zrqinit(),
            SenderPhase::WaitFilePos => self.queue_zfile(),
            SenderPhase::NeedFileData | SenderPhase::WaitFileAck => {
                self.retry_current_frame();
                Ok(())
            }
            SenderPhase::WaitFileDone => self.queue_zeof(self.file_size),
            SenderPhase::WaitFinish => self.queue_zfin(),
            SenderPhase::Done => Ok(()),
        }
    }

    fn on_zskip(&mut self) -> Result<(), Error> {
        if matches!(
            self.state,
            SenderPhase::WaitFilePos
                | SenderPhase::NeedFileData
                | SenderPhase::WaitFileAck
                | SenderPhase::WaitFileDone
        ) {
            self.timeout_retries = 0;
            self.has_file = false;
            self.pending_request = None;
            self.frame_remaining = 0;
            self.pending_event = Some(SenderEvent::FileSkipped);
            if self.finish_requested {
                self.queue_zfin()?;
                self.state = SenderPhase::WaitFinish;
            } else {
                self.state = SenderPhase::ReadyForFile;
            }
        }
        Ok(())
    }

    fn on_abort(&mut self) {
        self.state = SenderPhase::Done;
        self.pending_request = None;
        self.zfin_hex_trailer_phase = None;
        self.zfin_hex_optional_xon = false;
        self.pending_event = Some(SenderEvent::Aborted);
    }

    fn on_zfin(&mut self) -> Result<(), Error> {
        if self.state == SenderPhase::WaitFinish {
            self.timeout_retries = 0;
            self.queue_oo()?;
            self.state = SenderPhase::Done;
            self.pending_event = Some(SenderEvent::SessionComplete);
        }
        Ok(())
    }
}
