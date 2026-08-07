// SPDX-License-Identifier: MIT OR Apache-2.0
// Copyright (c) 2017-2020 Alexey Arbuzov
// Copyright (c) 2023-2026 Jarkko Sakkinen

//! ZMODEM receiver state machine.

use crate::api::{Action, Event, FileInfo, Position};
use crate::buffer::Buffer;
use crate::error::Error;
use crate::file::{parse_file_modification_time, parse_file_size};
use crate::header::{Encoding, Frame, Header, ZACK_HEADER, ZFIN_HEADER, ZNAK_HEADER, ZRPOS_HEADER};
use crate::io::Read;
use crate::session::{HexTrailerPhase, ReceiverEvent, ReceiverPhase, SubpacketPhase};
use crate::string::String;
use crate::wire::{
    BufferWriter, CancelDetector, HeaderReader, RECEIVE_SUBPACKET_MAX_SIZE, RxCrc, SliceReader,
    SubpacketType, WIRE_BUF_SIZE, read_byte_detecting_cancel, read_escape_followup, write_zrinit,
};
use crate::{XOFF, XON, ZDLE, ZPAD, zdle};
use core::cmp::min;

const RECEIVER_EVENT_QUEUE_CAP: usize = 4;
#[derive(Clone, Copy, Debug, PartialEq)]
enum ReceiverReply {
    Zrinit,
    Zrpos(u32),
    Zack(u32),
    Zskip,
    Zfin,
}

/// ZMODEM receiver state machine.
// The receiver tracks several independent one-shot conditions (escape
// continuation, overlapped I/O, manual accept, active file) that don't
// collapse into a single enum without losing clarity.
#[allow(clippy::struct_excessive_bools)]
pub struct Receiver {
    state: ReceiverPhase,
    count: u32,
    file_name: String,
    file_size: Option<u32>,
    file_modification_time: Option<u64>,
    buf: Buffer<RECEIVE_SUBPACKET_MAX_SIZE>,
    buf_write_offset: usize,
    data_encoding: Encoding,
    header_reader: HeaderReader,
    subpacket_state: SubpacketPhase,
    subpacket_optional_xon: bool,
    subpacket_escape_pending: bool,
    crc: RxCrc,
    outgoing: Buffer<WIRE_BUF_SIZE>,
    outgoing_offset: usize,
    pending_events: [Option<ReceiverEvent>; RECEIVER_EVENT_QUEUE_CAP],
    pending_event_head: usize,
    pending_event_len: usize,
    buffer_len: u16,
    overlapped_io: bool,
    manual_accept: bool,
    zrpos_retries: u8,
    timeout_retries: u8,
    file_active: bool,
    cancel_detector: CancelDetector,
    final_hex_trailer_phase: Option<HexTrailerPhase>,
    final_hex_optional_xon: bool,
    zfin_retries: u8,
    last_reply: Option<ReceiverReply>,
    znak_retries: u8,
    metadata_retries: u8,
    metadata_return_state: ReceiverPhase,
    peer_progress_epoch: u64,
}

/// Consecutive corrupt data subpackets, without any forward progress in
/// between, tolerated before the transfer is abandoned. Each one costs a
/// ZRPOS rewind; a link that cannot deliver a single clean subpacket in
/// this many attempts is failing, so surfacing the CRC error is more
/// honest than looping forever. lrzsz's `rz` gives up on a similar
/// garbage/retry threshold.
pub(crate) const MAX_ZRPOS_RETRIES: u8 = 10;
/// Consecutive active-file response timeouts tolerated without persisted data.
pub(crate) const MAX_TIMEOUT_RETRIES: u8 = 3;
/// Number of closing ZFIN retransmissions before a missing final `OO` is
/// treated as successful completion on a reliable transport.
pub(crate) const MAX_ZFIN_RETRIES: u8 = 3;
/// Consecutive peer ZNAKs accepted before the receiver aborts instead of
/// retransmitting the same response forever.
pub(crate) const MAX_RECEIVER_ZNAK_RETRIES: u8 = 3;
/// Consecutive corrupt ZFILE/ZSINIT subpackets accepted before aborting.
pub(crate) const MAX_METADATA_RETRIES: u8 = 3;

fn has_confirmed_header_start(input: &[u8]) -> bool {
    if input.first().map(|byte| byte & 0x7f) != Some(ZPAD) {
        return false;
    }
    let Some(first_non_zpad) = input.iter().position(|byte| byte & 0x7f != ZPAD) else {
        return false;
    };
    input
        .get(first_non_zpad)
        .is_some_and(|byte| byte & 0x7f == ZDLE)
}

impl Receiver {
    /// Create a new receiver instance.
    ///
    /// Advertises a conservative 1024-byte buffer length and no
    /// overlapped I/O: the sender pauses for an acknowledgement after
    /// each buffer's worth of data, which suits constrained targets
    /// that cannot drain the wire while persisting file data. See
    /// [`Receiver::with_flow_control`] to lift that pacing.
    ///
    /// # Errors
    ///
    /// * [`OutOfMemory`](crate::Error::OutOfMemory) when the outgoing buffer cannot hold the handshake
    pub fn new() -> Result<Self, Error> {
        Self::with_flow_control(1024, false)
    }

    /// Create a receiver advertising explicit flow-control
    /// capabilities in its ZRINIT handshake.
    ///
    /// `buffer_len` is the receiver buffer length the sender must
    /// respect: it will not transmit more than this many bytes without
    /// waiting for an acknowledgement. Zero advertises nonstop I/O.
    /// `overlapped_io` advertises `CANOVIO` (storage is written while
    /// data is being received). Senders such as lrzsz's `sz` require
    /// both (a zero buffer length and `CANOVIO`) before they stream
    /// continuously; anything less inserts one round-trip wait per
    /// buffer of data, which dominates transfer time on links with
    /// real latency.
    ///
    /// Callers that pump [`Receiver::submit_wire`] from a reliable,
    /// flow-controlled transport (TCP, SSH, a pipe) and persist file
    /// data promptly should prefer `with_flow_control(0, true)`; the
    /// conservative [`Receiver::new`] default exists for targets where
    /// wire input can genuinely overrun the consumer.
    ///
    /// # Errors
    ///
    /// * [`OutOfMemory`](crate::Error::OutOfMemory) when the outgoing buffer cannot hold the handshake
    pub fn with_flow_control(buffer_len: u16, overlapped_io: bool) -> Result<Self, Error> {
        let mut receiver = Self {
            state: ReceiverPhase::SessionBegin,
            count: 0,
            file_name: String::new(),
            file_size: None,
            file_modification_time: None,
            buf: Buffer::<RECEIVE_SUBPACKET_MAX_SIZE>::new(),
            buf_write_offset: 0,
            data_encoding: Encoding::ZBIN,
            header_reader: HeaderReader::new(),
            subpacket_state: SubpacketPhase::Idle,
            subpacket_optional_xon: false,
            subpacket_escape_pending: false,
            crc: RxCrc::new(),
            outgoing: Buffer::<WIRE_BUF_SIZE>::new(),
            outgoing_offset: 0,
            pending_events: [None; RECEIVER_EVENT_QUEUE_CAP],
            pending_event_head: 0,
            pending_event_len: 0,
            buffer_len,
            overlapped_io,
            manual_accept: false,
            zrpos_retries: 0,
            timeout_retries: 0,
            file_active: false,
            cancel_detector: CancelDetector::new(),
            final_hex_trailer_phase: None,
            final_hex_optional_xon: false,
            zfin_retries: 0,
            last_reply: None,
            znak_retries: 0,
            metadata_retries: 0,
            metadata_return_state: ReceiverPhase::SessionBegin,
            peer_progress_epoch: 0,
        };
        receiver.queue_zrinit()?;
        Ok(receiver)
    }

    /// Enables or disables manual file acceptance.
    ///
    /// In the default automatic mode every announced file is accepted
    /// from offset zero as soon as its ZFILE metadata parses. In
    /// manual mode the receiver instead pauses after emitting
    /// [`Event::FileStarted`] and waits for the caller to decide:
    /// [`Receiver::accept_file_at`] requests the file from a given
    /// offset (resuming an existing partial download), and
    /// [`Receiver::skip_file`] declines it (ZSKIP). While a decision
    /// is pending, [`Receiver::poll`] returns [`Action::Idle`] and no
    /// wire bytes are produced.
    pub fn set_manual_file_accept(&mut self, manual: bool) {
        self.manual_accept = manual;
    }

    /// Monotonic marker advanced after a CRC-valid peer header is accepted.
    /// Embedders can use it to distinguish protocol activity from raw noise.
    #[must_use]
    pub fn peer_progress_epoch(&self) -> u64 {
        self.peer_progress_epoch
    }

    /// Accepts the file announced by the pending [`Event::FileStarted`]
    /// and asks the sender to start at `offset` (ZRPOS).
    ///
    /// Zero requests the whole file; a nonzero offset resumes a
    /// partial transfer, and the caller is responsible for appending
    /// the incoming data to its existing `offset` bytes.
    ///
    /// # Errors
    ///
    /// * [`InvalidState`](crate::Error::InvalidState) when no file is awaiting acceptance
    /// * [`Backpressure`](crate::Error::Backpressure) when outgoing bytes are still
    ///   pending (drain and retry; the acceptance state is unchanged)
    pub fn accept_file_at(&mut self, offset: u32) -> Result<(), Error> {
        if self.state != ReceiverPhase::FileAcceptPending {
            return Err(Error::InvalidState);
        }
        self.queue_zrpos(offset)?;
        self.count = offset;
        self.timeout_retries = 0;
        self.state = ReceiverPhase::FileBegin;
        // The sender's response may be ZDATA (more bytes) or, when the
        // resume offset already sits at EOF, an immediate ZEOF with no
        // data frame. Mark the file active so the ZEOF handler accepts
        // that completion in FileBegin (see handle_header).
        self.file_active = true;
        Ok(())
    }

    /// Declines the file announced by the pending [`Event::FileStarted`]
    /// (ZSKIP); the sender moves on to its next file or finishes.
    ///
    /// # Errors
    ///
    /// * [`InvalidState`](crate::Error::InvalidState) when no file is awaiting acceptance
    /// * [`Backpressure`](crate::Error::Backpressure) when outgoing bytes are still
    ///   pending (drain and retry; the acceptance state is unchanged)
    pub fn skip_file(&mut self) -> Result<(), Error> {
        if self.state != ReceiverPhase::FileAcceptPending {
            return Err(Error::InvalidState);
        }
        self.queue_header(Header::new(Encoding::ZHEX, Frame::ZSKIP, [0; 4]))?;
        self.last_reply = Some(ReceiverReply::Zskip);
        self.state = ReceiverPhase::FileBegin;
        self.file_active = false;
        self.timeout_retries = 0;
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
        // Once the protocol has completed, every following byte belongs to
        // the embedding application (typically a shell). Returning zero is
        // the ownership boundary that lets the caller pass those bytes on.
        if self.state == ReceiverPhase::SessionEnd {
            return Ok(0);
        }

        let mut reader = SliceReader::new(input);

        loop {
            if self.blocked() {
                break;
            }

            let before = reader.consumed();

            if self.state == ReceiverPhase::WaitFinalOo {
                if !self.process_final_handshake(&mut reader)? {
                    break;
                }
                if self.blocked() || self.state == ReceiverPhase::SessionEnd {
                    break;
                }
                continue;
            }

            if matches!(
                self.state,
                ReceiverPhase::FileReadingSubpacket
                    | ReceiverPhase::FileReadingMetadata
                    | ReceiverPhase::FileReadingDuplicateMetadata
                    | ReceiverPhase::SinitReadingData
            ) {
                match self.process_subpacket(&mut reader) {
                    Ok(Some(())) => {
                        if self.blocked() {
                            break;
                        }
                        if reader.consumed() == before {
                            break;
                        }
                        continue;
                    }
                    Ok(None) => break,
                    Err(Error::Cancelled) => {
                        self.on_cancel()?;
                        break;
                    }
                    Err(e) => return Err(e),
                }
            }

            let header = match self
                .header_reader
                .read(&mut reader, &mut self.cancel_detector)
            {
                Ok(Some(header)) => header,
                Ok(None) => break,
                Err(Error::Cancelled) => {
                    self.on_cancel()?;
                    break;
                }
                Err(_) => {
                    // Bad header framing/CRC is recoverable. Report how much
                    // of this submission was consumed, emit ZNAK, and resume
                    // scanning after the caller drains it instead of forcing
                    // the embedding transport to tear down the session.
                    self.header_reader.enter_resync();
                    self.queue_nak()?;
                    break;
                }
            };

            self.handle_header(header)?;
            self.peer_progress_epoch = self.peer_progress_epoch.saturating_add(1);

            if self.pending_events_full() {
                break;
            }

            if reader.consumed() == before || reader.consumed() == input.len() {
                break;
            }
        }

        Ok(reader.consumed())
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

    /// Returns pending file data bytes.
    fn drain_file(&self) -> &[u8] {
        match self.subpacket_state {
            SubpacketPhase::Writing(_) => &self.buf[self.buf_write_offset..],
            _ => &[],
        }
    }

    /// Reports that `n` file bytes from the last [`Action::WriteFile`] were
    /// persisted to storage.
    ///
    /// # Errors
    ///
    /// * [`Backpressure`](crate::Error::Backpressure) when outgoing bytes are still pending
    pub fn file_written(&mut self, n: usize) -> Result<(), Error> {
        let SubpacketPhase::Writing(packet) = self.subpacket_state else {
            return Ok(());
        };

        let remaining = self.buf.len().saturating_sub(self.buf_write_offset);
        let n = min(n, remaining);
        self.buf_write_offset = self
            .buf_write_offset
            .checked_add(n)
            .ok_or(Error::OutOfMemory)?;

        if self.buf_write_offset < self.buf.len() {
            return Ok(());
        }

        self.finish_subpacket(packet)
    }

    /// Signals that the protocol response timeout expired.
    ///
    /// Incomplete metadata is discarded and answered with `ZNAK`; incomplete
    /// file data is discarded and answered with the current `ZRPOS`. While
    /// waiting between files or for the session to begin, this re-queues the
    /// `ZRINIT` handshake. All active-file recovery paths are bounded until
    /// persisted progress replenishes their retry budget.
    ///
    /// # Errors
    ///
    /// * [`Backpressure`](crate::Error::Backpressure) when outgoing bytes are still pending
    pub fn timeout(&mut self) -> Result<(), Error> {
        if matches!(
            self.state,
            ReceiverPhase::FileReadingMetadata
                | ReceiverPhase::FileReadingDuplicateMetadata
                | ReceiverPhase::SinitReadingData
        ) && !self.outgoing()
        {
            let _ = self.recover_corrupt_metadata(Error::UnexpectedEof)?;
        } else if self.state == ReceiverPhase::FileReadingSubpacket
            && matches!(
                self.subpacket_state,
                SubpacketPhase::SkipTrailer(_) | SubpacketPhase::Reading | SubpacketPhase::Crc(_)
            )
            && !self.outgoing()
        {
            self.recover_incomplete_subpacket_timeout()?;
        } else if matches!(
            self.state,
            ReceiverPhase::FileBegin | ReceiverPhase::FileWaitingSubpacket
        ) && self.file_active
            && !self.outgoing()
        {
            self.timeout_retries = self.timeout_retries.saturating_add(1);
            if self.timeout_retries > MAX_TIMEOUT_RETRIES {
                self.on_cancel()?;
            } else {
                self.queue_zrpos(self.count)?;
            }
        } else if matches!(
            self.state,
            ReceiverPhase::SessionBegin | ReceiverPhase::FileBegin
        ) && !self.outgoing()
        {
            self.queue_zrinit()?;
        } else if self.state == ReceiverPhase::WaitFinalOo && !self.outgoing() {
            if self.zfin_retries < MAX_ZFIN_RETRIES {
                self.queue_zfin()?;
                self.zfin_retries += 1;
            } else {
                // The protocol specifies only a brief wait for the optional
                // final `OO`. Once the bounded ZFIN retry budget is exhausted,
                // return ownership of any unconsumed bytes to the embedding
                // application and complete the already-finished batch.
                self.transport_closed()?;
            }
        }
        Ok(())
    }

    /// Reports that the underlying transport reached a trustworthy EOF.
    ///
    /// ZMODEM normally completes the receiver-side closing handshake with the
    /// sender's final `OO`. A reliable byte-stream transport (for example an
    /// OpenSSH channel) may instead close immediately after the receiver has
    /// replied with `ZFIN`. EOF is therefore successful only while waiting for
    /// that final `OO`; an already completed session is accepted idempotently.
    /// EOF in every other active phase aborts the session and returns
    /// [`UnexpectedEof`](crate::Error::UnexpectedEof).
    ///
    /// # Errors
    ///
    /// * [`UnexpectedEof`](crate::Error::UnexpectedEof) when the transport
    ///   closes before the receiver has replied to `ZFIN`
    /// * [`OutOfMemory`](crate::Error::OutOfMemory) when the event queue cannot
    ///   accept the completion or abort event
    pub fn transport_closed(&mut self) -> Result<(), Error> {
        match self.state {
            ReceiverPhase::WaitFinalOo => {
                self.state = ReceiverPhase::SessionEnd;
                self.final_hex_trailer_phase = None;
                self.final_hex_optional_xon = false;
                self.push_event(ReceiverEvent::SessionComplete)
            }
            ReceiverPhase::SessionEnd => Ok(()),
            _ => {
                self.on_cancel()?;
                Err(Error::UnexpectedEof)
            }
        }
    }

    /// Returns whether the receiver has replied to `ZFIN` and is waiting for
    /// the sender's final `OO` (or a trustworthy transport EOF).
    #[must_use]
    pub fn is_waiting_final_oo(&self) -> bool {
        self.state == ReceiverPhase::WaitFinalOo
    }

    /// Aborts the current session.
    ///
    /// # Errors
    ///
    /// * [`OutOfMemory`](crate::Error::OutOfMemory) when the event queue is full
    pub fn abort(&mut self) -> Result<(), Error> {
        self.on_cancel()
    }

    /// Returns the next action the caller must perform.
    ///
    /// Pending events take priority, followed by outgoing wire bytes, then
    /// received file bytes, and finally [`Action::Idle`] when there is no
    /// immediate work.
    pub fn poll(&mut self) -> Action<'_> {
        if let Some(event) = self.pop_event() {
            return Action::Event(match event {
                ReceiverEvent::FileStart => {
                    let mut info =
                        FileInfo::new(&self.file_name, self.file_size.map(Position::new));
                    if let Some(modification_time) = self.file_modification_time {
                        info = info.with_modification_time(modification_time);
                    }
                    Event::FileStarted(info)
                }
                ReceiverEvent::FileComplete => Event::FileCompleted,
                ReceiverEvent::SessionComplete => Event::SessionCompleted,
                ReceiverEvent::Aborted => Event::Aborted,
            });
        }

        if self.outgoing() {
            return Action::WriteWire(self.drain_outgoing());
        }

        if !self.drain_file().is_empty() {
            return Action::WriteFile(self.drain_file());
        }

        Action::Idle
    }

    fn outgoing(&self) -> bool {
        self.outgoing_offset < self.outgoing.len()
    }

    /// Returns `true` when no further wire input can be consumed until the
    /// caller drains outgoing bytes, persists file data, or pops events.
    fn blocked(&self) -> bool {
        self.outgoing() || !self.drain_file().is_empty() || self.pending_events_full()
    }

    fn pending_events_full(&self) -> bool {
        self.pending_event_len >= RECEIVER_EVENT_QUEUE_CAP
    }

    fn push_event(&mut self, event: ReceiverEvent) -> Result<(), Error> {
        if self.pending_events_full() {
            return Err(Error::OutOfMemory);
        }
        let index = (self.pending_event_head + self.pending_event_len) % RECEIVER_EVENT_QUEUE_CAP;
        self.pending_events[index] = Some(event);
        self.pending_event_len += 1;
        Ok(())
    }

    fn pop_event(&mut self) -> Option<ReceiverEvent> {
        if self.pending_event_len == 0 {
            return None;
        }
        let event = self.pending_events[self.pending_event_head].take();
        self.pending_event_head = (self.pending_event_head + 1) % RECEIVER_EVENT_QUEUE_CAP;
        self.pending_event_len -= 1;
        event
    }

    fn queue_writer(&mut self) -> Result<BufferWriter<'_, WIRE_BUF_SIZE>, Error> {
        if self.outgoing() {
            return Err(Error::Backpressure);
        }
        Ok(BufferWriter::new(&mut self.outgoing))
    }

    fn queue_header(&mut self, header: Header) -> Result<(), Error> {
        let mut writer = self.queue_writer()?;
        if header.write(&mut writer)?.is_none() {
            return Err(Error::OutOfMemory);
        }
        Ok(())
    }

    fn queue_zrinit(&mut self) -> Result<(), Error> {
        let (buffer_len, overlapped_io) = (self.buffer_len, self.overlapped_io);
        let mut writer = self.queue_writer()?;
        if write_zrinit(&mut writer, buffer_len, overlapped_io)?.is_none() {
            return Err(Error::OutOfMemory);
        }
        self.last_reply = Some(ReceiverReply::Zrinit);
        Ok(())
    }

    fn queue_zrpos(&mut self, count: u32) -> Result<(), Error> {
        self.queue_header(ZRPOS_HEADER.with_count(count))?;
        self.last_reply = Some(ReceiverReply::Zrpos(count));
        Ok(())
    }

    fn queue_zack(&mut self) -> Result<(), Error> {
        let count = self.count;
        self.queue_zack_count(count)
    }

    fn queue_zack_count(&mut self, count: u32) -> Result<(), Error> {
        self.queue_header(ZACK_HEADER.with_count(count))?;
        self.last_reply = Some(ReceiverReply::Zack(count));
        Ok(())
    }

    fn queue_zfin(&mut self) -> Result<(), Error> {
        self.queue_header(ZFIN_HEADER)?;
        self.last_reply = Some(ReceiverReply::Zfin);
        Ok(())
    }

    fn queue_nak(&mut self) -> Result<(), Error> {
        self.queue_header(ZNAK_HEADER)
    }

    fn resend_last_reply(&mut self) -> Result<(), Error> {
        self.znak_retries = self.znak_retries.saturating_add(1);
        if self.znak_retries > MAX_RECEIVER_ZNAK_RETRIES {
            return self.on_cancel();
        }
        match self.last_reply {
            Some(ReceiverReply::Zrinit) => self.queue_zrinit(),
            Some(ReceiverReply::Zrpos(count)) => self.queue_zrpos(count),
            Some(ReceiverReply::Zack(count)) => {
                self.queue_header(ZACK_HEADER.with_count(count))?;
                self.last_reply = Some(ReceiverReply::Zack(count));
                Ok(())
            }
            Some(ReceiverReply::Zskip) => {
                self.queue_header(Header::new(Encoding::ZHEX, Frame::ZSKIP, [0; 4]))?;
                self.last_reply = Some(ReceiverReply::Zskip);
                Ok(())
            }
            Some(ReceiverReply::Zfin) => self.queue_zfin(),
            None => self.queue_nak(),
        }
    }

    fn on_cancel(&mut self) -> Result<(), Error> {
        self.state = ReceiverPhase::SessionEnd;
        self.file_active = false;
        self.subpacket_state = SubpacketPhase::Idle;
        self.subpacket_optional_xon = false;
        self.subpacket_escape_pending = false;
        self.final_hex_trailer_phase = None;
        self.final_hex_optional_xon = false;
        self.buf.clear();
        self.buf_write_offset = 0;
        self.outgoing.clear();
        self.outgoing_offset = 0;
        self.pending_events = [None; RECEIVER_EVENT_QUEUE_CAP];
        self.pending_event_head = 0;
        self.pending_event_len = 0;
        self.push_event(ReceiverEvent::Aborted)
    }

    /// Processes only bytes that are unambiguously part of the closing
    /// handshake. Opaque bytes are left unconsumed for the embedding
    /// application, and a partial `O`, CAN run, or header is left in the
    /// caller's buffer until it can be classified atomically.
    fn process_final_handshake(&mut self, reader: &mut SliceReader<'_>) -> Result<bool, Error> {
        if self.consume_final_hex_trailer(reader) {
            return Ok(true);
        }

        let remaining = reader.remaining();
        if remaining.starts_with(b"OO") {
            self.cancel_detector.observe(b'O')?;
            self.cancel_detector.observe(b'O')?;
            reader.advance(2);
            self.state = ReceiverPhase::SessionEnd;
            self.push_event(ReceiverEvent::SessionComplete)?;
            return Ok(true);
        }
        if remaining.first() == Some(&b'O') {
            return Ok(false);
        }

        if remaining.starts_with(&[ZDLE; 5]) {
            reader.advance(5);
            self.on_cancel()?;
            return Ok(true);
        }
        if remaining.first() == Some(&ZDLE) {
            return Ok(false);
        }

        if !has_confirmed_header_start(remaining) {
            return Ok(false);
        }

        // Parse closing-phase headers speculatively. An incomplete header
        // consumes nothing, so a caller can retain the slice and append the
        // next transport chunk without losing a possible shell prefix.
        let mut candidate_reader = SliceReader::new(remaining);
        let mut candidate_header_reader = HeaderReader::new();
        let mut candidate_cancel_detector = self.cancel_detector;
        match candidate_header_reader.read(&mut candidate_reader, &mut candidate_cancel_detector) {
            Ok(Some(header)) => {
                reader.advance(candidate_reader.consumed());
                self.cancel_detector = candidate_cancel_detector;
                self.handle_header(header)?;
                self.peer_progress_epoch = self.peer_progress_epoch.saturating_add(1);
                Ok(true)
            }
            Ok(None) => Ok(false),
            Err(Error::Cancelled) => {
                reader.advance(candidate_reader.consumed());
                self.cancel_detector = candidate_cancel_detector;
                self.on_cancel()?;
                Ok(true)
            }
            Err(_) => {
                reader.advance(candidate_reader.consumed());
                self.cancel_detector = candidate_cancel_detector;
                self.queue_nak()?;
                Ok(true)
            }
        }
    }

    /// Consumes the single LF or CR/LF trailer belonging to the most recently
    /// decoded ZHEX header, plus at most one optional XON. Framing comparisons
    /// ignore parity, and a mismatching byte is left for the caller.
    fn consume_final_hex_trailer(&mut self, reader: &mut SliceReader<'_>) -> bool {
        if self.final_hex_optional_xon {
            let Some(byte) = reader.peek() else {
                return false;
            };
            self.final_hex_optional_xon = false;
            if byte & 0x7f == XON {
                reader.advance(1);
                return true;
            }
        }

        let Some(phase) = self.final_hex_trailer_phase else {
            return false;
        };
        let Some(byte) = reader.peek() else {
            return false;
        };
        match (phase, byte & 0x7f) {
            (HexTrailerPhase::LineStart, b'\r') => {
                reader.advance(1);
                self.final_hex_trailer_phase = Some(HexTrailerPhase::LineFeed);
                true
            }
            (HexTrailerPhase::LineStart | HexTrailerPhase::LineFeed, b'\n') => {
                reader.advance(1);
                self.final_hex_trailer_phase = None;
                self.final_hex_optional_xon = true;
                true
            }
            _ => {
                self.final_hex_trailer_phase = None;
                false
            }
        }
    }

    fn expect_final_hex_trailer(&mut self, header: Header) {
        self.final_hex_trailer_phase = if header.encoding() == Encoding::ZHEX {
            Some(HexTrailerPhase::LineStart)
        } else {
            None
        };
        self.final_hex_optional_xon = false;
    }

    fn begin_subpacket(&mut self, header_encoding: Encoding) {
        // ZHEX describes only the header. Every following data subpacket is
        // binary CRC16, after the header's line trailer.
        self.data_encoding = match header_encoding {
            Encoding::ZHEX => Encoding::ZBIN,
            other => other,
        };
        self.subpacket_state = if header_encoding == Encoding::ZHEX {
            SubpacketPhase::SkipTrailer(HexTrailerPhase::LineStart)
        } else {
            SubpacketPhase::Reading
        };
        self.subpacket_optional_xon = false;
        self.subpacket_escape_pending = false;
        self.crc.reset();
        self.buf.clear();
        self.buf_write_offset = 0;
    }

    #[allow(clippy::too_many_lines)]
    fn handle_header(&mut self, header: Header) -> Result<(), Error> {
        if self.state == ReceiverPhase::WaitFinalOo {
            self.expect_final_hex_trailer(header);
        }
        if header.frame() == Frame::ZNAK {
            return self.resend_last_reply();
        }
        self.znak_retries = 0;
        match header.frame() {
            Frame::ZCHALLENGE => {
                self.queue_zack_count(header.count())?;
            }
            Frame::ZRQINIT | Frame::ZDATA if self.state == ReceiverPhase::SessionBegin => {
                self.queue_zrinit()?;
            }
            Frame::ZSINIT if self.state == ReceiverPhase::SessionBegin => {
                // ZSINIT (e.g. lrzsz's `sz -e`) is followed by a data
                // subpacket with the attn string; read it so it is not
                // misparsed as headers, then acknowledge (see the
                // SinitReadingData completion). lrzsz sends the header
                // as ZHEX: there is no hex data encoding on the wire,
                // the subpacket that follows is binary with CRC16, and
                // the hex line trailer before it must be skipped.
                self.metadata_return_state = ReceiverPhase::SessionBegin;
                self.state = ReceiverPhase::SinitReadingData;
                self.begin_subpacket(header.encoding());
            }
            Frame::ZFILE
                if self.file_active
                    && matches!(
                        self.state,
                        ReceiverPhase::FileBegin | ReceiverPhase::FileWaitingSubpacket
                    ) =>
            {
                // A lost ZRPOS makes conforming senders repeat the complete
                // ZFILE header and metadata. Consume and CRC-check that retry,
                // but keep the already-authorized file identity and staging
                // handle intact; completion reissues the current ZRPOS without
                // another FileStarted event.
                self.metadata_return_state = self.state;
                self.state = ReceiverPhase::FileReadingDuplicateMetadata;
                self.begin_subpacket(header.encoding());
            }
            Frame::ZFILE
                if matches!(
                    self.state,
                    ReceiverPhase::SessionBegin | ReceiverPhase::FileBegin
                ) =>
            {
                // ZHEX describes the header only. Its following metadata
                // subpacket is binary CRC16 and begins after the hex line
                // trailer, exactly like ZSINIT.
                self.metadata_return_state = self.state;
                self.state = ReceiverPhase::FileReadingMetadata;
                self.begin_subpacket(header.encoding());
            }
            Frame::ZDATA if self.state == ReceiverPhase::FileBegin && !self.file_active => {
                // A sender may already have put a data frame on the wire when
                // the caller declines a file. Keep the between-files state and
                // scan past that stale subpacket without ever surfacing its
                // payload as file data. The next well-formed header (normally
                // ZFILE or ZFIN after the peer processes ZSKIP) realigns the
                // stream.
                self.header_reader.enter_resync();
            }
            Frame::ZDATA
                if matches!(
                    self.state,
                    ReceiverPhase::FileBegin | ReceiverPhase::FileWaitingSubpacket
                ) && self.file_active =>
            {
                if header.count() != self.count {
                    self.queue_zrpos(self.count)?;
                    return Ok(());
                }
                self.state = ReceiverPhase::FileReadingSubpacket;
                self.begin_subpacket(header.encoding());
            }
            Frame::ZEOF
                if (self.state == ReceiverPhase::FileWaitingSubpacket
                    || (self.state == ReceiverPhase::FileBegin && self.file_active))
                    && header.count() == self.count =>
            {
                // FileBegin is reached both while a file is active (right
                // after accept_file_at / auto-accept, before any ZDATA,
                // where a resume at EOF or an empty file yields an
                // immediate ZEOF) and between files (after a prior
                // completion). The file_active guard keeps a stray or
                // resent ZEOF in the between-files state from emitting a
                // second FileComplete.
                self.queue_zrinit()?;
                self.state = ReceiverPhase::FileBegin;
                self.file_active = false;
                self.timeout_retries = 0;
                self.push_event(ReceiverEvent::FileComplete)?;
            }
            Frame::ZABORT | Frame::ZFERR | Frame::ZCAN => {
                self.on_cancel()?;
            }
            Frame::ZFIN if self.state == ReceiverPhase::WaitFinalOo => {
                self.queue_zfin()?;
            }
            Frame::ZFIN if self.file_active || self.state == ReceiverPhase::FileAcceptPending => {
                // Session completion is invalid while an accepted file has
                // not reached matching ZEOF, or while a received file offer
                // is still awaiting the caller's decision. Abort rather than
                // reporting a successful session and abandoning the file.
                self.on_cancel()?;
            }
            Frame::ZFIN
                if matches!(
                    self.state,
                    ReceiverPhase::SessionBegin
                        | ReceiverPhase::FileWaitingSubpacket
                        | ReceiverPhase::FileBegin
                ) =>
            {
                self.queue_zfin()?;
                self.state = ReceiverPhase::WaitFinalOo;
                self.zfin_retries = 0;
                self.expect_final_hex_trailer(header);
            }
            _ => {}
        }
        Ok(())
    }

    /// Parses the file info buffer after a ZFILE subpacket is received.
    fn parse_zfile_buf(&mut self) -> Result<(), Error> {
        let metadata = parse_zfile_payload(&self.buf)?;
        self.file_name.clear();
        self.file_name
            .extend_from_slice(metadata.name)
            .map_err(|_| Error::OutOfMemory)?;
        self.file_size = metadata.size;
        self.file_modification_time = metadata.modification_time;
        self.count = 0;
        Ok(())
    }

    fn duplicate_zfile_matches(&self) -> Result<bool, Error> {
        let metadata = parse_zfile_payload(&self.buf)?;
        Ok(metadata.name == self.file_name.as_ref()
            && metadata.size == self.file_size
            && metadata.modification_time == self.file_modification_time)
    }

    /// Handles the byte after a `ZDLE`: either a subpacket terminator
    /// or an escaped data byte.
    fn receive_subpacket_followup_byte(&mut self, byte: u8) -> Result<Option<()>, Error> {
        if let Ok(packet) = SubpacketType::try_from(byte) {
            self.crc.update(packet as u8, self.data_encoding);
            self.subpacket_state = SubpacketPhase::Crc(packet);
        } else {
            let unescaped = zdle::UNZDLE_TABLE[byte as usize];
            self.buf.push(unescaped).map_err(|_| Error::OutOfMemory)?;
            self.crc.update(unescaped, self.data_encoding);
        }
        Ok(Some(()))
    }

    /// Handles a plain (non-escape-continuation) subpacket byte.
    fn receive_subpacket_plain_byte<P>(
        &mut self,
        port: &mut P,
        byte: u8,
    ) -> Result<Option<()>, Error>
    where
        P: Read + ?Sized,
    {
        // Software flow control is transport noise when it appears raw in a
        // binary data stream. A quoted ZDLE sequence bypasses this function
        // and remains real payload, including parity-marked variants.
        if matches!(byte & 0x7f, XON | XOFF) {
            return Ok(Some(()));
        }
        if byte == ZDLE {
            let Some(next) = read_escape_followup(port, &mut self.cancel_detector)? else {
                self.subpacket_escape_pending = true;
                return Ok(None);
            };
            return self.receive_subpacket_followup_byte(next);
        }
        self.buf.push(byte).map_err(|_| Error::OutOfMemory)?;
        self.crc.update(byte, self.data_encoding);
        Ok(Some(()))
    }

    /// Handles reading a single byte for the `SubpacketPhase::Reading` state.
    fn receive_subpacket_data_byte<P>(&mut self, port: &mut P) -> Result<Option<()>, Error>
    where
        P: Read + ?Sized,
    {
        if self.subpacket_optional_xon {
            let Some(byte) = read_byte_detecting_cancel(port, &mut self.cancel_detector)? else {
                return Ok(None);
            };
            self.subpacket_optional_xon = false;
            if byte & 0x7f == XON {
                return Ok(Some(()));
            }
            return self.receive_subpacket_plain_byte(port, byte);
        }

        if self.subpacket_escape_pending {
            let Some(byte) = read_escape_followup(port, &mut self.cancel_detector)? else {
                return Ok(None);
            };
            self.subpacket_escape_pending = false;
            return self.receive_subpacket_followup_byte(byte);
        }

        let Some(byte) = read_byte_detecting_cancel(port, &mut self.cancel_detector)? else {
            return Ok(None);
        };
        self.receive_subpacket_plain_byte(port, byte)
    }

    fn consume_subpacket_hex_trailer<P>(
        &mut self,
        port: &mut P,
        phase: HexTrailerPhase,
    ) -> Result<Option<()>, Error>
    where
        P: Read + ?Sized,
    {
        let Some(byte) = read_byte_detecting_cancel(port, &mut self.cancel_detector)? else {
            return Ok(None);
        };
        match (phase, byte & 0x7f) {
            (HexTrailerPhase::LineStart, b'\r') => {
                self.subpacket_state = SubpacketPhase::SkipTrailer(HexTrailerPhase::LineFeed);
                Ok(Some(()))
            }
            (HexTrailerPhase::LineStart | HexTrailerPhase::LineFeed, b'\n') => {
                self.subpacket_state = SubpacketPhase::Reading;
                self.subpacket_optional_xon = true;
                Ok(Some(()))
            }
            _ => {
                // Do not turn a run of payload newlines or flow-control bytes
                // into framing. After the one structural line ending is absent
                // or complete, this byte is payload.
                self.subpacket_state = SubpacketPhase::Reading;
                self.receive_subpacket_plain_byte(port, byte)
            }
        }
    }

    fn process_subpacket<P>(&mut self, port: &mut P) -> Result<Option<()>, Error>
    where
        P: Read + ?Sized,
    {
        match self.subpacket_state {
            SubpacketPhase::SkipTrailer(phase) => self.consume_subpacket_hex_trailer(port, phase),
            SubpacketPhase::Reading => self.receive_subpacket_data_byte(port),
            SubpacketPhase::Crc(packet) => {
                match self
                    .crc
                    .process(port, self.data_encoding, &mut self.cancel_detector)
                {
                    Ok(Some(())) => {}
                    Ok(None) => return Ok(None),
                    // A corrupt DATA subpacket is recoverable: ZMODEM's
                    // whole reason for existing over X/YMODEM is that the
                    // receiver asks the sender to retransmit from the last
                    // good offset instead of aborting. Metadata (ZFILE)
                    // and ZSINIT CRC failures stay fatal: there is no
                    // meaningful offset to rewind a header to.
                    Err(e @ (Error::UnexpectedCrc16 | Error::UnexpectedCrc32))
                        if self.state == ReceiverPhase::FileReadingSubpacket =>
                    {
                        return self.recover_corrupt_subpacket(e);
                    }
                    Err(e @ (Error::UnexpectedCrc16 | Error::UnexpectedCrc32))
                        if matches!(
                            self.state,
                            ReceiverPhase::FileReadingMetadata
                                | ReceiverPhase::FileReadingDuplicateMetadata
                                | ReceiverPhase::SinitReadingData
                        ) =>
                    {
                        return self.recover_corrupt_metadata(e);
                    }
                    Err(e) => return Err(e),
                }

                if self.state == ReceiverPhase::FileReadingMetadata {
                    self.parse_zfile_buf()?;
                    self.metadata_retries = 0;
                    self.timeout_retries = 0;
                    self.buf.clear();
                    self.buf_write_offset = 0;
                    self.crc.reset();
                    self.subpacket_optional_xon = false;
                    self.subpacket_escape_pending = false;

                    if self.manual_accept {
                        // Hold the ZRPOS until the caller decides via
                        // accept_file_at() / skip_file().
                        self.state = ReceiverPhase::FileAcceptPending;
                    } else {
                        self.queue_zrpos(0)?;
                        self.state = ReceiverPhase::FileBegin;
                        // Same as accept_file_at: an empty file makes the
                        // sender answer ZRPOS(0) with an immediate ZEOF(0)
                        // and no data frame, which must complete from
                        // FileBegin.
                        self.file_active = true;
                    }
                    self.subpacket_state = SubpacketPhase::Idle;
                    self.push_event(ReceiverEvent::FileStart)?;
                } else if self.state == ReceiverPhase::FileReadingDuplicateMetadata {
                    if !self.duplicate_zfile_matches().unwrap_or(false) {
                        self.on_cancel()?;
                        return Ok(Some(()));
                    }
                    self.metadata_retries = 0;
                    self.buf.clear();
                    self.buf_write_offset = 0;
                    self.crc.reset();
                    self.subpacket_optional_xon = false;
                    self.subpacket_escape_pending = false;
                    self.subpacket_state = SubpacketPhase::Idle;
                    self.state = ReceiverPhase::FileWaitingSubpacket;
                    self.queue_zrpos(self.count)?;
                } else if self.state == ReceiverPhase::SinitReadingData {
                    // ZSINIT's payload (the attn string) carries nothing
                    // we act on, but the sender blocks until the frame
                    // is acknowledged.
                    self.buf.clear();
                    self.buf_write_offset = 0;
                    self.crc.reset();
                    self.subpacket_optional_xon = false;
                    self.subpacket_escape_pending = false;

                    self.metadata_retries = 0;
                    self.queue_header(ZACK_HEADER)?;
                    self.last_reply = Some(ReceiverReply::Zack(0));

                    self.state = ReceiverPhase::SessionBegin;
                    self.subpacket_state = SubpacketPhase::Idle;
                } else {
                    self.subpacket_state = SubpacketPhase::Writing(packet);
                    self.buf_write_offset = 0;
                    if self.buf.is_empty() {
                        self.finish_subpacket(packet)?;
                    }
                }
                Ok(Some(()))
            }
            SubpacketPhase::Writing(_) => Ok(Some(())),
            SubpacketPhase::Idle => Err(Error::InvalidState),
        }
    }

    fn finish_subpacket(&mut self, packet: SubpacketType) -> Result<(), Error> {
        let len = u32::try_from(self.buf.len()).map_err(|_| Error::OutOfMemory)?;
        // The running offset is a u32 (ZMODEM positions are 32-bit). A
        // sender that keeps streaming past 4 GiB, whether buggy or
        // hostile, must not be able to wrap it back to a low offset and
        // desynchronise the transfer: refuse instead.
        self.count = self.count.checked_add(len).ok_or(Error::OutOfMemory)?;
        self.buf.clear();
        self.buf_write_offset = 0;
        self.crc.reset();
        self.subpacket_optional_xon = false;
        // A clean subpacket landed: the offset advanced, so the corrupt
        // streak (if any) is broken and the retry budget is replenished.
        self.zrpos_retries = 0;
        if len > 0 {
            self.timeout_retries = 0;
        }

        match packet {
            SubpacketType::ZCRCW => {
                self.queue_zack()?;
                self.state = ReceiverPhase::FileWaitingSubpacket;
                self.subpacket_state = SubpacketPhase::Idle;
                self.subpacket_escape_pending = false;
            }
            SubpacketType::ZCRCQ => {
                self.queue_zack()?;
                self.subpacket_state = SubpacketPhase::Reading;
                self.subpacket_escape_pending = false;
            }
            SubpacketType::ZCRCG => {
                self.subpacket_state = SubpacketPhase::Reading;
                self.subpacket_escape_pending = false;
            }
            SubpacketType::ZCRCE => {
                self.state = ReceiverPhase::FileWaitingSubpacket;
                self.subpacket_state = SubpacketPhase::Idle;
                self.subpacket_escape_pending = false;
            }
        }
        Ok(())
    }

    /// Recovers from a corrupt data subpacket by asking the sender to
    /// rewind. The buffered (bad) bytes are dropped and `count` is left
    /// at the last acknowledged offset, so nothing corrupt is persisted
    /// and no data is skipped; a ZRPOS(count) tells the sender to
    /// retransmit from there. The header reader is put into resync mode
    /// because a streaming sender keeps emitting the tail of the aborted
    /// window before it honours the ZRPOS, and that tail must be skipped
    /// rather than mistaken for framing.
    ///
    /// `err` is returned unchanged once the retry budget is spent, so a
    /// hopelessly noisy link fails with the same CRC error it would have
    /// before, just after trying to recover.
    fn recover_corrupt_subpacket(&mut self, err: Error) -> Result<Option<()>, Error> {
        self.zrpos_retries = self.zrpos_retries.saturating_add(1);
        if self.zrpos_retries > MAX_ZRPOS_RETRIES {
            return Err(err);
        }
        self.buf.clear();
        self.buf_write_offset = 0;
        self.crc.reset();
        self.subpacket_optional_xon = false;
        self.subpacket_escape_pending = false;
        self.queue_zrpos(self.count)?;
        self.state = ReceiverPhase::FileWaitingSubpacket;
        self.subpacket_state = SubpacketPhase::Idle;
        self.header_reader.enter_resync();
        Ok(Some(()))
    }

    /// Drops an incomplete data subpacket after a response timeout and asks
    /// the sender to restart at the last persisted offset. Timeout retries use
    /// the same no-progress budget as the header-waiting phases, so repeatedly
    /// truncating a subpacket cannot pin the receiver indefinitely.
    fn recover_incomplete_subpacket_timeout(&mut self) -> Result<(), Error> {
        self.timeout_retries = self.timeout_retries.saturating_add(1);
        if self.timeout_retries > MAX_TIMEOUT_RETRIES {
            return self.on_cancel();
        }
        self.buf.clear();
        self.buf_write_offset = 0;
        self.crc.reset();
        self.subpacket_optional_xon = false;
        self.subpacket_escape_pending = false;
        self.queue_zrpos(self.count)?;
        self.state = ReceiverPhase::FileWaitingSubpacket;
        self.subpacket_state = SubpacketPhase::Idle;
        self.header_reader.enter_resync();
        Ok(())
    }

    /// Requests retransmission of a corrupt ZFILE metadata or ZSINIT data
    /// frame. Unlike file payload corruption there is no byte offset to rewind,
    /// so ZNAK asks the sender to repeat the complete header and subpacket.
    fn recover_corrupt_metadata(&mut self, _err: Error) -> Result<Option<()>, Error> {
        self.metadata_retries = self.metadata_retries.saturating_add(1);
        if self.metadata_retries > MAX_METADATA_RETRIES {
            self.on_cancel()?;
            return Ok(Some(()));
        }
        self.buf.clear();
        self.buf_write_offset = 0;
        self.crc.reset();
        self.subpacket_optional_xon = false;
        self.subpacket_escape_pending = false;
        self.subpacket_state = SubpacketPhase::Idle;
        self.state = self.metadata_return_state;
        self.queue_nak()?;
        Ok(Some(()))
    }
}

struct ZfileMetadata<'a> {
    name: &'a [u8],
    size: Option<u32>,
    modification_time: Option<u64>,
}

fn parse_zfile_payload(payload: &[u8]) -> Result<ZfileMetadata<'_>, Error> {
    let mut fields = payload.split(|&byte| byte == b'\0');
    let file_name = fields.next().ok_or(Error::MalformedFileName)?;
    if file_name.is_empty() {
        return Err(Error::MalformedFileName);
    }

    let Some(metadata) = fields.next() else {
        return Ok(ZfileMetadata {
            name: file_name,
            size: None,
            modification_time: None,
        });
    };
    let mut metadata_fields = metadata.split(|&byte| byte == b' ');
    let file_size = parse_file_size(metadata_fields.next().unwrap_or_default())?;
    let file_modification_time =
        parse_file_modification_time(metadata_fields.next().unwrap_or_default())?;
    Ok(ZfileMetadata {
        name: file_name,
        size: file_size,
        modification_time: file_modification_time,
    })
}
