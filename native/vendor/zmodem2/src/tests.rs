// SPDX-License-Identifier: MIT OR Apache-2.0
// Copyright (c) 2017-2020 Alexey Arbuzov
// Copyright (c) 2023-2026 Jarkko Sakkinen

//! Protocol-level unit tests exercising crate-internal framing and the
//! public poll/submit API.

use crate::buffer::Buffer;
use crate::header::{Encoding, Frame, Header, Zrinit, write_slice_escaped_with_escape_options};
use crate::receiver::{
    MAX_METADATA_RETRIES, MAX_RECEIVER_ZNAK_RETRIES,
    MAX_TIMEOUT_RETRIES as MAX_RECEIVER_TIMEOUT_RETRIES, MAX_ZFIN_RETRIES, MAX_ZRPOS_RETRIES,
};
use crate::sender::{MAX_TIMEOUT_RETRIES as MAX_SENDER_TIMEOUT_RETRIES, MAX_ZNAK_RETRIES};
use crate::wire::{
    BufferWriter, CancelDetector, HeaderReader, MAX_RECEIVE_SUBPACKET_ESCAPED, SliceReader,
    SubpacketType, write_subpacket_with_escape_options,
};
use crate::{Action, Error, Event, FileInfo, Position, Receiver, Sender, ZDLE, ZPAD};
use rstest::rstest;
use std::{vec, vec::Vec};

fn write_header(header: Header) -> Vec<u8> {
    let mut buf = Buffer::<64>::new();
    let mut writer = BufferWriter::new(&mut buf);
    assert_eq!(header.write(&mut writer), Ok(Some(())));
    buf.to_vec()
}

/// Parses a header through the production [`HeaderReader`], prepending the
/// `ZPAD ZDLE` framing the reader seeks for.
fn read_header(bytes: &[u8]) -> Header {
    let mut framed = Vec::with_capacity(bytes.len() + 2);
    framed.push(ZPAD);
    framed.push(ZDLE);
    framed.extend_from_slice(bytes);
    let mut reader = SliceReader::new(&framed);
    let mut header_reader = HeaderReader::new();
    header_reader
        .read(&mut reader, &mut CancelDetector::new())
        .unwrap()
        .unwrap()
}

/// Drains pending outgoing wire bytes while no event is queued.
fn drain_wire_sender(sender: &mut Sender) {
    while let Action::WriteWire(bytes) = sender.poll() {
        let n = bytes.len();
        sender.wire_written(n);
    }
}

fn drain_wire_receiver(receiver: &mut Receiver) {
    while let Action::WriteWire(bytes) = receiver.poll() {
        let n = bytes.len();
        receiver.wire_written(n);
    }
}

fn take_sender_wire(sender: &mut Sender) -> Vec<u8> {
    let Action::WriteWire(bytes) = sender.poll() else {
        panic!("sender did not produce wire output");
    };
    let n = bytes.len();
    let wire = bytes.to_vec();
    sender.wire_written(n);
    wire
}

fn take_receiver_wire(receiver: &mut Receiver) -> Vec<u8> {
    let Action::WriteWire(bytes) = receiver.poll() else {
        panic!("receiver did not produce wire output");
    };
    let n = bytes.len();
    let wire = bytes.to_vec();
    receiver.wire_written(n);
    wire
}

fn feed_until_receiver_wire(receiver: &mut Receiver, input: &[u8]) -> Vec<u8> {
    let mut offset = 0;
    loop {
        match receiver.poll() {
            Action::WriteWire(bytes) => {
                let n = bytes.len();
                let wire = bytes.to_vec();
                receiver.wire_written(n);
                return wire;
            }
            Action::Idle => {
                assert!(offset < input.len(), "receiver produced no response");
                let consumed = receiver.submit_wire(&input[offset..]).unwrap();
                assert!(consumed > 0);
                offset += consumed;
            }
            other => panic!("unexpected action before wire response: {other:?}"),
        }
    }
}

#[test]
fn test_escape_ctrl_quotes_all_control_bytes() {
    let mut buf = Buffer::<64>::new();
    let mut writer = BufferWriter::new(&mut buf);
    assert_eq!(
        write_slice_escaped_with_escape_options(
            &mut writer,
            &[0x00, 0x0a, 0x1f, 0x7f, 0x80, 0x9f, 0xa0, b'A'],
            true,
            false,
        ),
        Ok(Some(()))
    );
    assert_eq!(
        buf.as_ref(),
        &[
            ZDLE, 0x40, ZDLE, 0x4a, ZDLE, 0x5f, ZDLE, 0x6c, ZDLE, 0xc0, ZDLE, 0xdf, 0xa0, b'A',
        ]
    );
}

#[test]
fn test_sender_honours_escape_ctrl_from_zrinit() {
    let mut sender = Sender::new().unwrap();
    drain_wire_sender(&mut sender);
    sender
        .start_file(FileInfo::new(b"control.bin", Some(Position::new(4))))
        .unwrap();

    let zrinit = write_header(Header::new(
        Encoding::ZHEX,
        Frame::ZRINIT,
        [0, 0, 0, Zrinit::ESCCTL.bits()],
    ));
    assert!(sender.submit_wire(&zrinit).unwrap() > 0);

    let mut zfile_wire = Vec::new();
    while let Action::WriteWire(bytes) = sender.poll() {
        zfile_wire.extend_from_slice(bytes);
        let n = bytes.len();
        sender.wire_written(n);
    }
    assert!(zfile_wire.windows(2).any(|pair| pair == [ZDLE, b'@']));

    let zrpos = write_header(Header::new(Encoding::ZHEX, Frame::ZRPOS, [0; 4]));
    assert!(sender.submit_wire(&zrpos).unwrap() > 0);
    assert_eq!(
        sender.poll(),
        Action::ReadFile {
            offset: Position::new(0),
            max_len: 4,
        }
    );
    sender.submit_file(b"A\nB\0").unwrap();

    let Action::WriteWire(data_wire) = sender.poll() else {
        panic!("sender did not emit ZDATA");
    };
    assert!(data_wire.windows(2).any(|pair| pair == [ZDLE, b'J']));
    assert!(data_wire.windows(2).any(|pair| pair == [ZDLE, b'@']));
    assert!(!data_wire.contains(&b'\n'));
}

#[test]
fn test_escape8_quotes_gnu_decodable_parity_controls_only() {
    let parity_controls: Vec<u8> = (0x80..=0x9f).collect();
    let mut buf = Buffer::<64>::new();
    let mut writer = BufferWriter::new(&mut buf);
    assert_eq!(
        write_slice_escaped_with_escape_options(&mut writer, &parity_controls, false, true),
        Ok(Some(()))
    );
    let expected: Vec<u8> = parity_controls
        .iter()
        .flat_map(|value| [ZDLE, value ^ 0x40])
        .collect();
    assert_eq!(buf.as_ref(), expected.as_slice());

    let mut compatibility = Buffer::<16>::new();
    let mut writer = BufferWriter::new(&mut compatibility);
    assert_eq!(
        write_slice_escaped_with_escape_options(
            &mut writer,
            &[0xa0, 0xc0, 0xe0, 0xfe, 0xff],
            false,
            true,
        ),
        Ok(Some(()))
    );
    assert_eq!(
        compatibility.as_ref(),
        &[0xa0, 0xc0, 0xe0, 0xfe, ZDLE, 0x6d]
    );
}

#[test]
fn test_sender_rejects_escape8_when_full_7_bit_encoding_is_unavailable() {
    let mut sender = Sender::new().unwrap();
    drain_wire_sender(&mut sender);
    sender
        .start_file(FileInfo::new(
            b"parity-\x80-printable-\xa0-rub-\xff.bin",
            Some(Position::new(128)),
        ))
        .unwrap();

    let zrinit = write_header(Header::new(
        Encoding::ZHEX,
        Frame::ZRINIT,
        [0, 0, 0, (Zrinit::CANFC32 | Zrinit::ESC8).bits()],
    ));
    assert_eq!(sender.submit_wire(&zrinit), Err(Error::UnsupportedFeature));
}

#[rstest]
#[case(Encoding::ZBIN, Frame::ZRQINIT, [0; 4], &[ZPAD, ZDLE, Encoding::ZBIN as u8, 0, 0, 0, 0, 0, 0, 0])]
#[case(Encoding::ZBIN32, Frame::ZRQINIT, [0; 4], &[ZPAD, ZDLE, Encoding::ZBIN32 as u8, 0, 0, 0, 0, 0, 29, 247, 34, 198])]
#[case(Encoding::ZBIN, Frame::ZRQINIT, [1; 4], &[ZPAD, ZDLE, Encoding::ZBIN as u8, 0, 1, 1, 1, 1, 98, 148])]
#[case(Encoding::ZHEX, Frame::ZRQINIT, [1; 4], &[ZPAD, ZPAD, ZDLE, Encoding::ZHEX as u8, b'0', b'0', b'0', b'1', b'0', b'1', b'0', b'1', b'0', b'1', 54, 50, 57, 52, b'\r', b'\n', crate::XON])]
fn test_header_write(
    #[case] encoding: Encoding,
    #[case] frame: Frame,
    #[case] flags: [u8; 4],
    #[case] expected: &[u8],
) {
    assert_eq!(write_header(Header::new(encoding, frame, flags)), expected);
}

#[rstest]
#[case(&[Encoding::ZHEX as u8, b'0', b'1', b'0', b'1', b'0', b'2', b'0', b'3', b'0', b'4', b'a', b'7', b'5', b'2'], Encoding::ZHEX, Frame::ZRINIT, [0x1, 0x2, 0x3, 0x4])]
#[case(&[Encoding::ZBIN as u8, Frame::ZRINIT as u8, 0xa, 0xb, 0xc, 0xd, 0xa6, 0xcb], Encoding::ZBIN, Frame::ZRINIT, [0xa, 0xb, 0xc, 0xd])]
#[case(&[Encoding::ZBIN32 as u8, Frame::ZRINIT as u8, 0xa, 0xb, 0xc, 0xd, 0x99, 0xe2, 0xae, 0x4a], Encoding::ZBIN32, Frame::ZRINIT, [0xa, 0xb, 0xc, 0xd])]
#[case(&[Encoding::ZBIN as u8, Frame::ZRINIT as u8, 0xa, ZDLE, b'l', 0xd, ZDLE, b'm', 0x5e, 0x6f], Encoding::ZBIN, Frame::ZRINIT, [0xa, 0x7f, 0xd, 0xff])]
fn test_header_read(
    #[case] port: &[u8],
    #[case] encoding: Encoding,
    #[case] frame: Frame,
    #[case] flags: [u8; 4],
) {
    assert_eq!(read_header(port), Header::new(encoding, frame, flags));
}

#[test]
fn test_zhex_header_ignores_parity_but_binary_body_does_not() {
    let expected = Header::new(Encoding::ZHEX, Frame::ZRPOS, 37u32.to_le_bytes());
    let mut hex_wire = write_header(expected);
    let trailer_len = 3;
    let header_len = hex_wire.len() - trailer_len;
    for byte in &mut hex_wire[..header_len] {
        *byte |= 0x80;
    }
    assert_eq!(parse_first_header(&hex_wire), expected);

    let mut binary_wire = write_header(Header::new(
        Encoding::ZBIN,
        Frame::ZRPOS,
        37u32.to_le_bytes(),
    ));
    binary_wire[3] |= 0x80;
    let mut reader = SliceReader::new(&binary_wire);
    let mut header_reader = HeaderReader::new();
    assert!(
        header_reader
            .read(&mut reader, &mut CancelDetector::new())
            .is_err()
    );
}

#[test]
fn test_receive_malformed_header() {
    let mut receiver = Receiver::new().unwrap();
    drain_wire_receiver(&mut receiver);

    let input = b"malformed data";
    let consumed = receiver.submit_wire(input).unwrap();

    assert_eq!(consumed, input.len());
    assert_eq!(receiver.poll(), Action::Idle);
}

#[test]
fn test_corrupt_header_is_recoverable_and_preserves_progress() {
    let mut receiver = Receiver::new().unwrap();
    drain_wire_receiver(&mut receiver);

    let mut corrupt = write_header(Header::new(Encoding::ZBIN32, Frame::ZRQINIT, [0; 4]));
    let last = corrupt.last_mut().unwrap();
    *last ^= 1;
    let valid = write_header(Header::new(Encoding::ZHEX, Frame::ZRQINIT, [0; 4]));
    corrupt.extend_from_slice(&valid);

    // Only the corrupt header is consumed before ZNAK backpressure stops the
    // parser. The valid header remains available to be resubmitted.
    let consumed = receiver.submit_wire(&corrupt).unwrap();
    assert!(consumed > 0);
    assert!(consumed < corrupt.len());
    let znak = match receiver.poll() {
        Action::WriteWire(bytes) => parse_first_header(bytes),
        other => panic!("expected ZNAK, got {other:?}"),
    };
    assert_eq!(znak.frame(), Frame::ZNAK);
    drain_wire_receiver(&mut receiver);

    let recovered = receiver.submit_wire(&corrupt[consumed..]).unwrap();
    assert!(recovered > 0);
    let zrinit = match receiver.poll() {
        Action::WriteWire(bytes) => parse_first_header(bytes),
        other => panic!("expected recovered ZRINIT, got {other:?}"),
    };
    assert_eq!(zrinit.frame(), Frame::ZRINIT);
}

#[test]
fn test_header_resync_reconsiders_overlapping_zpad_inside_bad_crc_candidate() {
    let expected = Header::new(Encoding::ZHEX, Frame::ZRPOS, 37u32.to_le_bytes());
    let valid = write_header(expected);

    // The false ZBIN32 candidate consumes the beginning of the valid header
    // as its body before its CRC fails. A reset-to-end scanner loses that
    // embedded `ZPAD ZPAD ZDLE`; overlapping replay must find it.
    let mut wire = vec![ZPAD, ZDLE, Encoding::ZBIN32 as u8];
    wire.extend_from_slice(&valid);
    let split = 13;

    let mut header_reader = HeaderReader::new();
    header_reader.enter_resync();
    let mut cancel = CancelDetector::new();
    let mut first = SliceReader::new(&wire[..split]);
    assert_eq!(header_reader.read(&mut first, &mut cancel).unwrap(), None);
    assert_eq!(first.consumed(), split);

    let mut second = SliceReader::new(&wire[split..]);
    assert_eq!(
        header_reader.read(&mut second, &mut cancel).unwrap(),
        Some(expected)
    );
}

#[test]
fn test_challenge_is_acknowledged_with_identical_count_bytewise() {
    let count = 0x7856_3412u32;
    let challenge = write_header(Header::new(
        Encoding::ZBIN32,
        Frame::ZCHALLENGE,
        count.to_le_bytes(),
    ));
    let mut noisy_challenge = Vec::new();
    for (index, byte) in challenge.into_iter().enumerate() {
        noisy_challenge.push(byte);
        if index == 0 {
            noisy_challenge.extend_from_slice(&[crate::XON, 0x93]);
        } else if index == 2 {
            noisy_challenge.extend_from_slice(&[crate::XOFF, 0x91]);
        }
    }

    let mut sender = Sender::new().unwrap();
    drain_wire_sender(&mut sender);
    for byte in noisy_challenge.iter().copied() {
        assert_eq!(sender.submit_wire(&[byte]), Ok(1));
    }
    let sender_ack = parse_first_header(&take_sender_wire(&mut sender));
    assert_eq!(
        (sender_ack.frame(), sender_ack.count()),
        (Frame::ZACK, count)
    );

    let mut receiver = Receiver::new().unwrap();
    drain_wire_receiver(&mut receiver);
    for byte in noisy_challenge.iter().copied() {
        assert_eq!(receiver.submit_wire(&[byte]), Ok(1));
    }
    let receiver_ack = parse_first_header(&take_receiver_wire(&mut receiver));
    assert_eq!(
        (receiver_ack.frame(), receiver_ack.count()),
        (Frame::ZACK, count)
    );
}

#[test]
fn test_receive_zfile_with_non_utf8_name() {
    let file_name = b"bad\x80name";
    let file_size = 123u32;
    let modification_time = 1_700_000_000_u64;

    let mut sender = Sender::new().unwrap();
    drain_wire_sender(&mut sender);
    sender
        .start_file(
            FileInfo::new(file_name, Some(Position::new(file_size)))
                .with_modification_time(modification_time),
        )
        .unwrap();

    let receiver_init = write_header(Header::new(Encoding::ZHEX, Frame::ZRINIT, [0; 4]));
    assert!(sender.submit_wire(&receiver_init).unwrap() > 0);

    // Collect the ZFILE frame the sender emits.
    let mut wire = Vec::new();
    while let Action::WriteWire(bytes) = sender.poll() {
        wire.extend_from_slice(bytes);
        let n = bytes.len();
        sender.wire_written(n);
    }
    assert!(!wire.is_empty());

    let mut receiver = Receiver::new().unwrap();
    drain_wire_receiver(&mut receiver);

    let mut offset = 0;
    let mut started: Option<(Vec<u8>, Option<u32>, Option<u64>)> = None;
    while started.is_none() {
        match receiver.poll() {
            Action::WriteWire(bytes) => {
                let n = bytes.len();
                receiver.wire_written(n);
            }
            Action::Event(Event::FileStarted(info)) => {
                started = Some((
                    info.name.to_vec(),
                    info.size.map(Position::get),
                    info.modification_time,
                ));
            }
            Action::Event(event) => panic!("unexpected event: {event:?}"),
            Action::Idle => {
                assert!(offset < wire.len(), "ran out of input before FileStarted");
                let consumed = receiver.submit_wire(&wire[offset..]).unwrap();
                assert!(consumed > 0);
                offset += consumed;
            }
            other => panic!("unexpected action: {other:?}"),
        }
    }

    let (name, size, received_modification_time) = started.unwrap();
    assert_eq!(name, file_name);
    assert_eq!(size, Some(file_size));
    assert_eq!(received_modification_time, Some(modification_time));
}

fn test_crc32_iso_hdlc(data: &[u8]) -> u32 {
    let mut crc = 0xffff_ffffu32;
    for &byte in data {
        crc ^= u32::from(byte);
        for _ in 0..8 {
            if crc & 1 != 0 {
                crc = (crc >> 1) ^ 0xedb8_8320;
            } else {
                crc >>= 1;
            }
        }
    }
    !crc
}

fn encode_zdle(byte: u8) -> u8 {
    match byte {
        0x0d => 0x4d,
        0x10 => 0x50,
        0x11 => 0x51,
        0x13 => 0x53,
        0x18 => 0x58,
        0x7f => 0x6c,
        0x8d => 0xcd,
        0x90 => 0xd0,
        0x91 => 0xd1,
        0x93 => 0xd3,
        0xff => 0x6d,
        _ => byte,
    }
}

fn inject_raw_flow_after_zdle(input: &[u8]) -> Vec<u8> {
    let mut output = Vec::with_capacity(input.len() * 2);
    for &byte in input {
        output.push(byte);
        if byte == ZDLE {
            output.extend_from_slice(&[crate::XON, crate::XOFF, 0x91, 0x93]);
        }
    }
    output
}

fn escaped_zbin32_subpacket(kind: SubpacketType, data: &[u8]) -> Vec<u8> {
    fn push_escaped(out: &mut Vec<u8>, byte: u8) {
        let escaped = encode_zdle(byte);
        if escaped != byte {
            out.push(ZDLE);
        }
        out.push(escaped);
    }

    let mut out = Vec::new();
    for &byte in data {
        push_escaped(&mut out, byte);
    }
    out.push(ZDLE);
    out.push(kind as u8);

    let mut crc_input = Vec::from(data);
    crc_input.push(kind as u8);
    for byte in test_crc32_iso_hdlc(&crc_input).to_le_bytes() {
        push_escaped(&mut out, byte);
    }
    out
}

fn escaped_zbin16_subpacket(kind: SubpacketType, data: &[u8]) -> Vec<u8> {
    fn push_escaped(out: &mut Vec<u8>, byte: u8) {
        let escaped = encode_zdle(byte);
        if escaped != byte {
            out.push(ZDLE);
        }
        out.push(escaped);
    }

    let mut out = Vec::new();
    for &byte in data {
        push_escaped(&mut out, byte);
    }
    out.push(ZDLE);
    out.push(kind as u8);

    let mut crc_input = Vec::from(data);
    crc_input.push(kind as u8);
    for byte in crate::crc::crc16_xmodem(&crc_input).to_be_bytes() {
        push_escaped(&mut out, byte);
    }
    out
}

fn receive_file_info(receiver: &mut Receiver, wire: &[u8]) -> (Vec<u8>, Option<u32>) {
    let mut offset = 0;
    loop {
        match receiver.poll() {
            Action::WriteWire(bytes) => {
                let n = bytes.len();
                receiver.wire_written(n);
            }
            Action::Event(Event::FileStarted(info)) => {
                return (info.name.to_vec(), info.size.map(Position::get));
            }
            Action::Idle => {
                assert!(offset < wire.len(), "ran out of ZFILE metadata");
                let consumed = receiver.submit_wire(&wire[offset..]).unwrap();
                assert!(consumed > 0);
                offset += consumed;
            }
            other => panic!("unexpected action: {other:?}"),
        }
    }
}

fn receive_file_info_bytewise(receiver: &mut Receiver, wire: &[u8]) -> (Vec<u8>, Option<u32>) {
    let mut offset = 0;
    loop {
        match receiver.poll() {
            Action::WriteWire(bytes) => {
                let n = bytes.len();
                receiver.wire_written(n);
            }
            Action::Event(Event::FileStarted(info)) => {
                return (info.name.to_vec(), info.size.map(Position::get));
            }
            Action::Idle => {
                assert!(offset < wire.len(), "ran out of chunked ZFILE metadata");
                let consumed = receiver.submit_wire(&wire[offset..=offset]).unwrap();
                assert_eq!(consumed, 1);
                offset += 1;
            }
            other => panic!("unexpected action: {other:?}"),
        }
    }
}

#[test]
fn test_zhex_zfile_trailer_and_unknown_size_are_parsed() {
    let mut receiver = Receiver::new().unwrap();
    drain_wire_receiver(&mut receiver);

    // A ZHEX header's CR/LF/XON trailer is header framing. The metadata
    // subpacket itself uses binary CRC16, and an empty first metadata field
    // means that file size was not advertised (not a zero-byte file).
    let mut wire = write_header(Header::new(Encoding::ZHEX, Frame::ZFILE, [0; 4]));
    wire.extend(escaped_zbin16_subpacket(
        SubpacketType::ZCRCW,
        b"unknown.bin\x00\x00",
    ));

    assert_eq!(
        receive_file_info(&mut receiver, &wire),
        (b"unknown.bin".to_vec(), None)
    );
}

#[test]
fn test_zhex_metadata_trailer_is_exact_and_preserves_payload_lf() {
    for trailer in [&b"\n"[..], &b"\x8d\x8a\x91"[..]] {
        let mut receiver = Receiver::new().unwrap();
        drain_wire_receiver(&mut receiver);

        let mut wire = write_header(Header::new(Encoding::ZHEX, Frame::ZFILE, [0; 4]));
        wire.truncate(wire.len() - 3);
        wire.extend_from_slice(trailer);
        wire.extend(escaped_zbin16_subpacket(
            SubpacketType::ZCRCW,
            b"\nleading-newline.bin\x001\x00",
        ));

        assert_eq!(
            receive_file_info_bytewise(&mut receiver, &wire),
            (b"\nleading-newline.bin".to_vec(), Some(1))
        );
    }
}

#[test]
fn test_zfile_zero_size_remains_known() {
    let mut receiver = Receiver::new().unwrap();
    drain_wire_receiver(&mut receiver);

    let mut wire = write_header(Header::new(Encoding::ZBIN32, Frame::ZFILE, [0; 4]));
    wire.extend(escaped_zbin32_subpacket(
        SubpacketType::ZCRCW,
        b"empty.bin\x000\x00",
    ));

    assert_eq!(
        receive_file_info(&mut receiver, &wire),
        (b"empty.bin".to_vec(), Some(0))
    );
}

fn zfile_metadata_wire(corrupt: bool) -> Vec<u8> {
    let mut wire = write_header(Header::new(Encoding::ZBIN32, Frame::ZFILE, [0; 4]));
    let mut metadata =
        escaped_zbin32_subpacket(SubpacketType::ZCRCW, b"retry.bin\x004\x0014524770400 0\0");
    if corrupt {
        metadata[0] ^= 1;
    }
    wire.extend(metadata);
    wire
}

#[test]
fn test_corrupt_zfile_metadata_znaks_then_recovers() {
    let mut receiver = Receiver::new().unwrap();
    drain_wire_receiver(&mut receiver);

    let response = feed_until_receiver_wire(&mut receiver, &zfile_metadata_wire(true));
    assert_eq!(parse_first_header(&response).frame(), Frame::ZNAK);

    assert_eq!(
        receive_file_info(&mut receiver, &zfile_metadata_wire(false)),
        (b"retry.bin".to_vec(), Some(4))
    );
}

#[test]
fn test_corrupt_zsinit_data_znaks_then_recovers() {
    let mut receiver = Receiver::new().unwrap();
    drain_wire_receiver(&mut receiver);

    let header = write_header(Header::new(Encoding::ZBIN32, Frame::ZSINIT, [0; 4]));
    let mut bad = header.clone();
    let mut bad_data = escaped_zbin32_subpacket(SubpacketType::ZCRCW, b"\0");
    bad_data[0] ^= 1;
    bad.extend(bad_data);
    let response = feed_until_receiver_wire(&mut receiver, &bad);
    assert_eq!(parse_first_header(&response).frame(), Frame::ZNAK);

    let mut good = header;
    good.extend(escaped_zbin32_subpacket(SubpacketType::ZCRCW, b"\0"));
    let response = feed_until_receiver_wire(&mut receiver, &good);
    assert_eq!(parse_first_header(&response).frame(), Frame::ZACK);
}

#[test]
fn test_corrupt_metadata_has_finite_retry_budget() {
    let mut receiver = Receiver::new().unwrap();
    drain_wire_receiver(&mut receiver);
    let bad = zfile_metadata_wire(true);

    for _ in 0..MAX_METADATA_RETRIES {
        let response = feed_until_receiver_wire(&mut receiver, &bad);
        assert_eq!(parse_first_header(&response).frame(), Frame::ZNAK);
    }

    let mut offset = 0;
    loop {
        match receiver.poll() {
            Action::Event(Event::Aborted) => break,
            Action::Idle => {
                assert!(offset < bad.len(), "retry budget did not terminate");
                let consumed = receiver.submit_wire(&bad[offset..]).unwrap();
                assert!(consumed > 0);
                offset += consumed;
            }
            other => panic!("unexpected action after retry exhaustion: {other:?}"),
        }
    }
}

/// Drives a receiver through a ZFILE frame, leaving it ready to receive data.
fn feed_receiver_zfile(receiver: &mut Receiver) {
    drain_wire_receiver(receiver);

    let mut bytes = write_header(Header::new(Encoding::ZBIN32, Frame::ZFILE, [0; 4]));
    bytes.extend(escaped_zbin32_subpacket(
        SubpacketType::ZCRCW,
        b"file.bin\x00123\x00",
    ));

    let mut offset = 0;
    let mut started = false;
    while !started {
        match receiver.poll() {
            Action::WriteWire(b) => {
                let n = b.len();
                receiver.wire_written(n);
            }
            Action::Event(Event::FileStarted(_)) => started = true,
            Action::Event(event) => panic!("unexpected event: {event:?}"),
            Action::Idle => {
                assert!(offset < bytes.len(), "ran out of input before FileStarted");
                let consumed = receiver.submit_wire(&bytes[offset..]).unwrap();
                assert!(consumed > 0);
                offset += consumed;
            }
            other => panic!("unexpected action: {other:?}"),
        }
    }

    drain_wire_receiver(receiver);
}

#[test]
fn test_receiver_discards_raw_flow_control_but_preserves_escaped_payload() {
    let mut receiver = Receiver::new().unwrap();
    feed_receiver_zfile(&mut receiver);

    let mut raw_noise = write_header(Header::new(Encoding::ZBIN32, Frame::ZDATA, [0; 4]));
    let encoded = escaped_zbin32_subpacket(SubpacketType::ZCRCE, b"AB");
    raw_noise.extend_from_slice(&[crate::XON, b'A', crate::XOFF, 0x91, b'B', 0x93]);
    raw_noise.extend_from_slice(&encoded[2..4]);
    raw_noise.extend_from_slice(&[crate::XOFF, 0x91, crate::XON, 0x93]);
    raw_noise.extend_from_slice(&encoded[4..]);
    consume_file_chunk(&mut receiver, &raw_noise, b"AB");

    let escaped_payload = [crate::XON, crate::XOFF, 0x91, 0x93];
    let mut quoted = write_header(Header::new(
        Encoding::ZBIN32,
        Frame::ZDATA,
        2u32.to_le_bytes(),
    ));
    quoted.extend(escaped_zbin32_subpacket(
        SubpacketType::ZCRCE,
        &escaped_payload,
    ));
    consume_file_chunk(&mut receiver, &quoted, &escaped_payload);
}

#[test]
fn test_binary_header_escape_continuations_ignore_split_raw_flow_control() {
    let expected = Header::new(
        Encoding::ZBIN32,
        Frame::ZDATA,
        [crate::XON, crate::XOFF, ZDLE, 0x91],
    );
    let noisy = inject_raw_flow_after_zdle(&write_header(expected));
    let mut header_reader = HeaderReader::new();
    let mut cancel = CancelDetector::new();
    let mut decoded = None;

    for byte in noisy {
        let mut reader = SliceReader::new(core::slice::from_ref(&byte));
        let header = header_reader.read(&mut reader, &mut cancel).unwrap();
        assert_eq!(reader.consumed(), 1);
        if header.is_some() {
            assert!(decoded.is_none());
            decoded = header;
        }
    }

    assert_eq!(decoded, Some(expected));
}

#[test]
fn test_receiver_escape_continuations_ignore_split_raw_flow_control() {
    let mut receiver = Receiver::new().unwrap();
    feed_receiver_zfile(&mut receiver);

    // The final 0x10 makes this ZCRCW's CRC end in 0x18, so the same test
    // exercises escaped payload, terminator, and escaped CRC continuations.
    let expected = [crate::XON, crate::XOFF, 0x91, 0x93, ZDLE, 0x10];
    let mut frame = write_header(Header::new(Encoding::ZBIN32, Frame::ZDATA, [0; 4]));
    frame.extend(escaped_zbin32_subpacket(SubpacketType::ZCRCW, &expected));
    let noisy = inject_raw_flow_after_zdle(&frame);
    let mut offset = 0;

    loop {
        match receiver.poll() {
            Action::WriteFile(bytes) => {
                assert_eq!(bytes, expected);
                let len = bytes.len();
                receiver.file_written(len).unwrap();
                break;
            }
            Action::WriteWire(bytes) => {
                let len = bytes.len();
                receiver.wire_written(len);
            }
            Action::Idle => {
                assert!(offset < noisy.len(), "ran out of split wire input");
                let consumed = receiver.submit_wire(&noisy[offset..=offset]).unwrap();
                assert_eq!(consumed, 1);
                offset += 1;
            }
            other => panic!("unexpected action: {other:?}"),
        }
    }
}

#[test]
fn test_active_duplicate_zfile_reissues_zrpos_without_second_file_event() {
    let mut receiver = Receiver::new().unwrap();
    feed_receiver_zfile(&mut receiver);

    let mut first_data = write_header(Header::new(Encoding::ZBIN32, Frame::ZDATA, [0; 4]));
    first_data.extend(escaped_zbin32_subpacket(SubpacketType::ZCRCE, b"abc"));
    let mut first_offset = 0;
    loop {
        match receiver.poll() {
            Action::WriteFile(bytes) => {
                assert_eq!(bytes, b"abc");
                let bytes_len = bytes.len();
                receiver.file_written(bytes_len).unwrap();
                break;
            }
            Action::Idle => {
                let consumed = receiver.submit_wire(&first_data[first_offset..]).unwrap();
                assert!(consumed > 0);
                first_offset += consumed;
            }
            other => panic!("unexpected action while receiving initial data: {other:?}"),
        }
    }
    assert_eq!(first_offset, first_data.len());

    let mut duplicate = write_header(Header::new(Encoding::ZHEX, Frame::ZFILE, [0; 4]));
    duplicate.extend(escaped_zbin16_subpacket(
        SubpacketType::ZCRCW,
        b"file.bin\x00123\x00",
    ));
    let mut next_data = write_header(Header::new(
        Encoding::ZHEX,
        Frame::ZDATA,
        3u32.to_le_bytes(),
    ));
    next_data.extend(escaped_zbin16_subpacket(SubpacketType::ZCRCE, b"\n\x11z"));

    // Mirror the core's retained-buffer contract: the duplicate metadata and
    // the next frame arrive together. Backpressure stops exactly after the
    // duplicate, leaving ZDATA to be resubmitted after ZRPOS is drained.
    let mut retained = duplicate.clone();
    retained.extend_from_slice(&next_data);
    let mut retained_offset = 0;
    let zrpos = loop {
        match receiver.poll() {
            Action::WriteWire(bytes) => {
                let wire = bytes.to_vec();
                let n = bytes.len();
                receiver.wire_written(n);
                break wire;
            }
            Action::Idle => {
                let consumed = receiver.submit_wire(&retained[retained_offset..]).unwrap();
                assert!(consumed > 0);
                retained_offset += consumed;
            }
            Action::Event(event) => panic!("duplicate ZFILE emitted an event: {event:?}"),
            other => panic!("unexpected duplicate-ZFILE action: {other:?}"),
        }
    };
    assert_eq!(retained_offset, duplicate.len());
    let zrpos = parse_first_header(&zrpos);
    assert_eq!(zrpos.frame(), Frame::ZRPOS);
    assert_eq!(zrpos.count(), 3);
    assert_eq!(receiver.poll(), Action::Idle);

    loop {
        match receiver.poll() {
            Action::WriteFile(bytes) => {
                assert_eq!(bytes, b"\n\x11z");
                let bytes_len = bytes.len();
                receiver.file_written(bytes_len).unwrap();
                break;
            }
            Action::Idle => {
                let consumed = receiver.submit_wire(&retained[retained_offset..]).unwrap();
                assert!(consumed > 0);
                retained_offset += consumed;
            }
            other => panic!("unexpected ZHEX ZDATA action: {other:?}"),
        }
    }
    assert_eq!(retained_offset, retained.len());
    assert_eq!(receiver.poll(), Action::Idle);
}

#[rstest]
#[case(b"other.bin\x00123\x00")]
#[case(b"file.bin\x00124\x00")]
#[case(b"file.bin\x00123 14524770400 0\x00")]
fn test_active_duplicate_zfile_must_match_original_metadata(#[case] metadata: &[u8]) {
    let mut receiver = Receiver::new().unwrap();
    feed_receiver_zfile(&mut receiver);

    let mut duplicate = write_header(Header::new(Encoding::ZBIN32, Frame::ZFILE, [0; 4]));
    duplicate.extend(escaped_zbin32_subpacket(SubpacketType::ZCRCW, metadata));

    let mut offset = 0;
    loop {
        match receiver.poll() {
            Action::Event(Event::Aborted) => break,
            Action::Idle => {
                assert!(offset < duplicate.len(), "mismatched ZFILE was ignored");
                let consumed = receiver.submit_wire(&duplicate[offset..]).unwrap();
                assert!(consumed > 0);
                offset += consumed;
            }
            other => panic!("unexpected action for mismatched duplicate ZFILE: {other:?}"),
        }
    }
}

/// Parses the first header out of raw outgoing wire bytes (which carry
/// their own `ZPAD`/`ZDLE` framing, unlike [`read_header`]'s input).
fn parse_first_header(bytes: &[u8]) -> Header {
    let mut reader = SliceReader::new(bytes);
    let mut header_reader = HeaderReader::new();
    header_reader
        .read(&mut reader, &mut CancelDetector::new())
        .unwrap()
        .unwrap()
}

#[test]
fn test_manual_accept_resumes_from_offset() {
    let mut receiver = Receiver::new().unwrap();
    receiver.set_manual_file_accept(true);
    feed_receiver_zfile(&mut receiver);

    // The decision is pending: no ZRPOS may leave until the caller
    // accepts, and data-phase calls are rejected.
    assert_eq!(receiver.poll(), Action::Idle);

    receiver.accept_file_at(64).unwrap();
    let (header, n) = match receiver.poll() {
        Action::WriteWire(bytes) => (parse_first_header(bytes), bytes.len()),
        other => panic!("unexpected action: {other:?}"),
    };
    receiver.wire_written(n);
    assert_eq!(header.frame(), Frame::ZRPOS);
    assert_eq!(header.count(), 64);

    // Data arriving at the resumed offset is accepted and surfaced.
    let mut wire = write_header(Header::new(
        Encoding::ZBIN32,
        Frame::ZDATA,
        64u32.to_le_bytes(),
    ));
    wire.extend(escaped_zbin32_subpacket(SubpacketType::ZCRCE, b"hello"));
    let mut offset = 0;
    let mut got = Vec::new();
    while got.is_empty() {
        match receiver.poll() {
            Action::WriteWire(bytes) => {
                let n = bytes.len();
                receiver.wire_written(n);
            }
            Action::WriteFile(bytes) => {
                got = bytes.to_vec();
                let n = bytes.len();
                receiver.file_written(n).unwrap();
            }
            Action::Idle => {
                assert!(offset < wire.len(), "ran out of input before file data");
                let consumed = receiver.submit_wire(&wire[offset..]).unwrap();
                assert!(consumed > 0);
                offset += consumed;
            }
            other => panic!("unexpected action: {other:?}"),
        }
    }
    assert_eq!(got, b"hello");
}

#[test]
fn test_manual_accept_can_skip_a_file() {
    let mut receiver = Receiver::new().unwrap();
    receiver.set_manual_file_accept(true);
    feed_receiver_zfile(&mut receiver);

    receiver.skip_file().unwrap();
    let (header, n) = match receiver.poll() {
        Action::WriteWire(bytes) => (parse_first_header(bytes), bytes.len()),
        other => panic!("unexpected action: {other:?}"),
    };
    receiver.wire_written(n);
    assert_eq!(header.frame(), Frame::ZSKIP);

    // Out of the pending state, further decisions are invalid.
    assert_eq!(receiver.accept_file_at(0), Err(Error::InvalidState));
    assert_eq!(receiver.skip_file(), Err(Error::InvalidState));
}

#[test]
fn test_skipped_file_ignores_late_zdata() {
    let mut receiver = Receiver::new().unwrap();
    receiver.set_manual_file_accept(true);
    feed_receiver_zfile(&mut receiver);

    receiver.skip_file().unwrap();
    let zskip = take_receiver_wire(&mut receiver);
    assert_eq!(parse_first_header(&zskip).frame(), Frame::ZSKIP);

    // The sender may have started this frame before receiving ZSKIP. Consume
    // the stale frame and subpacket as opaque wire data; none of its payload
    // may be offered to the caller as file bytes.
    let mut late = write_header(Header::new(Encoding::ZBIN32, Frame::ZDATA, [0; 4]));
    late.extend(escaped_zbin32_subpacket(
        SubpacketType::ZCRCW,
        b"must-not-be-written",
    ));
    assert_eq!(receiver.submit_wire(&late), Ok(late.len()));
    assert_eq!(receiver.poll(), Action::Idle);

    // The receiver remains between files, so its timeout response is ZRINIT,
    // not a request to resume the skipped file.
    receiver.timeout().unwrap();
    let retry = take_receiver_wire(&mut receiver);
    assert_eq!(parse_first_header(&retry).frame(), Frame::ZRINIT);
}

#[test]
fn test_zsinit_is_acknowledged() {
    let mut receiver = Receiver::new().unwrap();
    drain_wire_receiver(&mut receiver);

    // lrzsz's `sz -e` opens with ZSINIT plus an attn-string subpacket
    // and blocks until the receiver acknowledges it.
    let mut wire = write_header(Header::new(Encoding::ZBIN32, Frame::ZSINIT, [0; 4]));
    wire.extend(escaped_zbin32_subpacket(SubpacketType::ZCRCW, b"\x00"));

    let mut offset = 0;
    let mut acked = false;
    while !acked {
        match receiver.poll() {
            Action::WriteWire(bytes) => {
                let header = parse_first_header(bytes);
                let n = bytes.len();
                receiver.wire_written(n);
                if header.frame() == Frame::ZACK {
                    acked = true;
                }
            }
            Action::Idle => {
                assert!(offset < wire.len(), "input ran out before the ZACK");
                let consumed = receiver.submit_wire(&wire[offset..]).unwrap();
                assert!(consumed > 0);
                offset += consumed;
            }
            other => panic!("unexpected action: {other:?}"),
        }
    }

    // The handshake continues normally afterwards.
    feed_receiver_zfile(&mut receiver);
}

/// Byte-exact ZSINIT opening captured from lrzsz's `sz -b -e` (after
/// receiving a CANFC32 ZRINIT): a ZHEX header, its CR LF(high-bit) XON
/// line trailer, then a BINARY CRC16 subpacket with the empty attn
/// string. The hex encoding maps to CRC16 data and the trailer must be
/// skipped; both mistakes surfaced as `UnexpectedCrc16` against the real
/// tool.
#[test]
fn test_zsinit_hex_header_from_lrzsz_is_acknowledged() {
    const LRZSZ_ZSINIT: &[u8] = &[
        0x2a, 0x2a, 0x18, 0x42, // ** ZDLE 'B'
        0x30, 0x32, // "02" ZSINIT
        0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x34, 0x30, // flags "00000040" (ESCCTL)
        0x30, 0x63, 0x34, 0x37, // crc "0c47"
        0x0d, 0x8a, 0x11, // CR LF|0x80 XON line trailer
        0x18, 0x40, // escaped NUL (empty attn string)
        0x18, 0x6b, // ZDLE ZCRCW
        0xdd, 0xcd, // CRC16
        0x11, // trailing XON
    ];
    let mut receiver = Receiver::new().unwrap();
    drain_wire_receiver(&mut receiver);

    let mut offset = 0;
    let mut acked = false;
    while !acked {
        match receiver.poll() {
            Action::WriteWire(bytes) => {
                let header = parse_first_header(bytes);
                let n = bytes.len();
                receiver.wire_written(n);
                if header.frame() == Frame::ZACK {
                    acked = true;
                }
            }
            Action::Idle => {
                assert!(offset < LRZSZ_ZSINIT.len(), "input ran out before the ZACK");
                let consumed = receiver.submit_wire(&LRZSZ_ZSINIT[offset..]).unwrap();
                assert!(consumed > 0);
                offset += consumed;
            }
            other => panic!("unexpected action: {other:?}"),
        }
    }

    // The handshake continues normally afterwards.
    feed_receiver_zfile(&mut receiver);
}

#[test]
fn test_sender_resumes_from_zrpos() {
    let mut sender = Sender::new().unwrap();
    drain_wire_sender(&mut sender);
    sender
        .start_file(FileInfo::new(b"resume.bin", Some(Position::new(16))))
        .unwrap();

    let zrinit = write_header(Header::new(Encoding::ZHEX, Frame::ZRINIT, [0; 4]));
    assert!(sender.submit_wire(&zrinit).unwrap() > 0);
    drain_wire_sender(&mut sender);

    let zrpos = write_header(Header::new(
        Encoding::ZHEX,
        Frame::ZRPOS,
        5u32.to_le_bytes(),
    ));
    assert!(sender.submit_wire(&zrpos).unwrap() > 0);

    match sender.poll() {
        Action::ReadFile { offset, .. } => assert_eq!(offset, Position::new(5)),
        other => panic!("unexpected action: {other:?}"),
    }
}

#[test]
fn test_sender_skips_file_on_zskip() {
    let mut sender = Sender::new().unwrap();
    drain_wire_sender(&mut sender);
    sender
        .start_file(FileInfo::new(b"skip.bin", Some(Position::new(16))))
        .unwrap();
    sender.finish().unwrap();

    let zrinit = write_header(Header::new(Encoding::ZHEX, Frame::ZRINIT, [0; 4]));
    sender.submit_wire(&zrinit).unwrap();
    drain_wire_sender(&mut sender);

    let zskip = write_header(Header::new(Encoding::ZHEX, Frame::ZSKIP, [0; 4]));
    sender.submit_wire(&zskip).unwrap();

    assert_eq!(sender.poll(), Action::Event(Event::FileSkipped));
    let header = match sender.poll() {
        Action::WriteWire(bytes) => parse_first_header(bytes),
        other => panic!("expected session-closing ZFIN, got {other:?}"),
    };
    assert_eq!(header.frame(), Frame::ZFIN);
}

fn start_sender_with_caps(size: u32, caps: Zrinit) -> Sender {
    let mut sender = Sender::new().unwrap();
    drain_wire_sender(&mut sender);
    sender
        .start_file(FileInfo::new(b"caps.bin", Some(Position::new(size))))
        .unwrap();
    let zrinit = write_header(Header::new(
        Encoding::ZHEX,
        Frame::ZRINIT,
        [0, 0, 0, caps.bits()],
    ));
    assert!(sender.submit_wire(&zrinit).unwrap() > 0);
    sender
}

#[rstest]
#[case(Zrinit::empty(), Encoding::ZBIN)]
#[case(Zrinit::CANFC32, Encoding::ZBIN32)]
fn test_sender_respects_canfc32_for_file_frames(#[case] caps: Zrinit, #[case] expected: Encoding) {
    let mut sender = start_sender_with_caps(4, caps);

    let zfile = take_sender_wire(&mut sender);
    let header = parse_first_header(&zfile);
    assert_eq!(header.frame(), Frame::ZFILE);
    assert_eq!(header.encoding(), expected);

    let zrpos = write_header(Header::new(Encoding::ZHEX, Frame::ZRPOS, [0; 4]));
    assert!(sender.submit_wire(&zrpos).unwrap() > 0);
    assert_eq!(
        sender.poll(),
        Action::ReadFile {
            offset: Position::ZERO,
            max_len: 4,
        }
    );
    sender.submit_file(b"data").unwrap();
    let zdata = take_sender_wire(&mut sender);
    let header = parse_first_header(&zdata);
    assert_eq!(header.frame(), Frame::ZDATA);
    assert_eq!(header.encoding(), expected);

    let zack = write_header(Header::new(
        Encoding::ZHEX,
        Frame::ZACK,
        4_u32.to_le_bytes(),
    ));
    assert!(sender.submit_wire(&zack).unwrap() > 0);
    let zeof = take_sender_wire(&mut sender);
    let header = parse_first_header(&zeof);
    assert_eq!(header.frame(), Frame::ZEOF);
    assert_eq!(header.encoding(), expected);
    assert_eq!(header.count(), 4);
}

#[test]
fn test_sender_rejects_zrpos_beyond_file_size() {
    let mut sender = start_sender_with_caps(4, Zrinit::CANFC32);
    drain_wire_sender(&mut sender);

    let oversized = write_header(Header::new(
        Encoding::ZHEX,
        Frame::ZRPOS,
        5_u32.to_le_bytes(),
    ));
    assert!(sender.submit_wire(&oversized).unwrap() > 0);
    assert_eq!(sender.poll(), Action::Event(Event::Aborted));
    assert_eq!(sender.poll(), Action::Idle, "must not emit oversized ZEOF");

    let mut sender = start_sender_with_caps(4, Zrinit::CANFC32);
    drain_wire_sender(&mut sender);
    let at_eof = write_header(Header::new(
        Encoding::ZHEX,
        Frame::ZRPOS,
        4_u32.to_le_bytes(),
    ));
    assert!(sender.submit_wire(&at_eof).unwrap() > 0);
    let zeof = parse_first_header(&take_sender_wire(&mut sender));
    assert_eq!(zeof.frame(), Frame::ZEOF);
    assert_eq!(zeof.count(), 4);
}

#[test]
fn test_sender_retransmits_lost_zfile_on_zrinit_and_timeout() {
    let mut sender = start_sender_with_caps(4, Zrinit::CANFC32);
    let first_zfile = take_sender_wire(&mut sender);

    let zrinit = write_header(Header::new(
        Encoding::ZBIN32,
        Frame::ZRINIT,
        [0, 0, 0, Zrinit::CANFC32.bits()],
    ));
    for byte in zrinit {
        assert_eq!(sender.submit_wire(&[byte]), Ok(1));
    }
    assert_eq!(take_sender_wire(&mut sender), first_zfile);

    // The embedding timeout pump can also recover the same dropped offer
    // without waiting for the peer's own ZRINIT timer.
    sender.timeout().unwrap();
    assert_eq!(take_sender_wire(&mut sender), first_zfile);
}

#[test]
fn test_sender_timeout_rebuilds_lost_data_frame_and_retransmits_zeof() {
    let mut sender = start_sender_with_caps(4, Zrinit::CANFC32);
    drain_wire_sender(&mut sender); // drop ZFILE after the receiver saw it

    let zrpos = write_header(Header::new(Encoding::ZHEX, Frame::ZRPOS, [0; 4]));
    assert!(sender.submit_wire(&zrpos).unwrap() > 0);
    assert!(matches!(sender.poll(), Action::ReadFile { .. }));
    sender.submit_file(b"data").unwrap();
    let first_zdata = take_sender_wire(&mut sender); // its ZACK is lost

    sender.timeout().unwrap();
    assert_eq!(
        sender.poll(),
        Action::ReadFile {
            offset: Position::ZERO,
            max_len: 4,
        }
    );
    sender.submit_file(b"data").unwrap();
    assert_eq!(take_sender_wire(&mut sender), first_zdata);

    let zack = write_header(Header::new(Encoding::ZHEX, Frame::ZACK, 4u32.to_le_bytes()));
    assert!(sender.submit_wire(&zack).unwrap() > 0);
    let first_zeof = take_sender_wire(&mut sender); // the ZEOF is lost
    assert_eq!(parse_first_header(&first_zeof).frame(), Frame::ZEOF);

    sender.timeout().unwrap();
    assert_eq!(take_sender_wire(&mut sender), first_zeof);

    let zrinit = write_header(Header::new(Encoding::ZHEX, Frame::ZRINIT, [0; 4]));
    assert!(sender.submit_wire(&zrinit).unwrap() > 0);
    assert_eq!(sender.poll(), Action::Event(Event::FileCompleted));
}

#[test]
fn test_sender_timeout_retransmits_zfin_with_a_bounded_budget() {
    let mut sender = sender_waiting_for_peer_zfin();

    for _ in 0..MAX_SENDER_TIMEOUT_RETRIES {
        sender.timeout().unwrap();
        let retry = take_sender_wire(&mut sender);
        assert_eq!(parse_first_header(&retry).frame(), Frame::ZFIN);
    }

    sender.timeout().unwrap();
    assert_eq!(sender.poll(), Action::Event(Event::Aborted));
    assert_eq!(sender.poll(), Action::Idle);
}

#[test]
fn test_sender_timeout_budget_is_bounded_and_resets_after_forward_ack() {
    let mut sender = start_sender_with_caps(2048, Zrinit::CANFC32);
    drain_wire_sender(&mut sender);
    let zrpos = write_header(Header::new(Encoding::ZHEX, Frame::ZRPOS, [0; 4]));
    assert!(sender.submit_wire(&zrpos).unwrap() > 0);
    assert!(matches!(sender.poll(), Action::ReadFile { .. }));
    sender.submit_file(&[0; 1024]).unwrap();
    drain_wire_sender(&mut sender);

    for _ in 0..MAX_SENDER_TIMEOUT_RETRIES {
        sender.timeout().unwrap();
        assert_eq!(
            sender.poll(),
            Action::ReadFile {
                offset: Position::ZERO,
                max_len: 1024,
            }
        );
        sender.submit_file(&[0; 1024]).unwrap();
        drain_wire_sender(&mut sender);
    }

    let forward_ack = write_header(Header::new(
        Encoding::ZHEX,
        Frame::ZACK,
        1024u32.to_le_bytes(),
    ));
    assert!(sender.submit_wire(&forward_ack).unwrap() > 0);
    assert_eq!(
        sender.poll(),
        Action::ReadFile {
            offset: Position::new(1024),
            max_len: 1024,
        }
    );
    sender.submit_file(&[0; 1024]).unwrap();
    drain_wire_sender(&mut sender);

    for _ in 0..MAX_SENDER_TIMEOUT_RETRIES {
        sender.timeout().unwrap();
        assert!(matches!(sender.poll(), Action::ReadFile { .. }));
        sender.submit_file(&[0; 1024]).unwrap();
        drain_wire_sender(&mut sender);
    }
    sender.timeout().unwrap();
    assert_eq!(sender.poll(), Action::Event(Event::Aborted));
}

#[test]
fn test_znak_retransmits_zfile_data_and_zeof_by_phase() {
    let znak = write_header(Header::new(Encoding::ZHEX, Frame::ZNAK, [0; 4]));
    let mut sender = start_sender_with_caps(4, Zrinit::CANFC32);

    let first_zfile = take_sender_wire(&mut sender);
    assert!(sender.submit_wire(&znak).unwrap() > 0);
    assert_eq!(take_sender_wire(&mut sender), first_zfile);

    let zrpos = write_header(Header::new(Encoding::ZHEX, Frame::ZRPOS, [0; 4]));
    assert!(sender.submit_wire(&zrpos).unwrap() > 0);
    sender.submit_file(b"data").unwrap();
    let first_zdata = take_sender_wire(&mut sender);
    assert!(sender.submit_wire(&znak).unwrap() > 0);
    assert_eq!(
        sender.poll(),
        Action::ReadFile {
            offset: Position::ZERO,
            max_len: 4,
        }
    );
    sender.submit_file(b"data").unwrap();
    assert_eq!(take_sender_wire(&mut sender), first_zdata);

    let zack = write_header(Header::new(
        Encoding::ZHEX,
        Frame::ZACK,
        4_u32.to_le_bytes(),
    ));
    assert!(sender.submit_wire(&zack).unwrap() > 0);
    let first_zeof = take_sender_wire(&mut sender);
    assert!(sender.submit_wire(&znak).unwrap() > 0);
    assert_eq!(take_sender_wire(&mut sender), first_zeof);
}

#[test]
fn test_znak_is_honoured_while_file_read_is_pending() {
    let mut sender = start_sender_with_caps(4, Zrinit::CANFC32);
    drain_wire_sender(&mut sender);
    let zrpos = write_header(Header::new(Encoding::ZHEX, Frame::ZRPOS, [0; 4]));
    assert!(sender.submit_wire(&zrpos).unwrap() > 0);
    assert!(matches!(sender.poll(), Action::ReadFile { .. }));

    let znak = write_header(Header::new(Encoding::ZHEX, Frame::ZNAK, [0; 4]));
    assert!(sender.submit_wire(&znak).unwrap() > 0);
    assert_eq!(
        sender.poll(),
        Action::ReadFile {
            offset: Position::ZERO,
            max_len: 4,
        }
    );
}

#[test]
fn test_repeated_znak_has_finite_retry_budget() {
    let mut sender = start_sender_with_caps(1, Zrinit::CANFC32);
    drain_wire_sender(&mut sender);
    let znak = write_header(Header::new(Encoding::ZHEX, Frame::ZNAK, [0; 4]));

    for _ in 0..MAX_ZNAK_RETRIES {
        assert!(sender.submit_wire(&znak).unwrap() > 0);
        let resent = take_sender_wire(&mut sender);
        assert_eq!(parse_first_header(&resent).frame(), Frame::ZFILE);
    }
    assert!(sender.submit_wire(&znak).unwrap() > 0);
    assert_eq!(sender.poll(), Action::Event(Event::Aborted));
}

#[test]
fn test_znak_retransmits_handshake_headers() {
    let znak = write_header(Header::new(Encoding::ZHEX, Frame::ZNAK, [0; 4]));
    let mut sender = Sender::new().unwrap();
    let zrqinit = take_sender_wire(&mut sender);
    assert!(sender.submit_wire(&znak).unwrap() > 0);
    assert_eq!(take_sender_wire(&mut sender), zrqinit);

    let receiver_init = write_header(Header::new(Encoding::ZHEX, Frame::ZRINIT, [0; 4]));
    assert!(sender.submit_wire(&receiver_init).unwrap() > 0);
    sender.finish().unwrap();
    let zfin = take_sender_wire(&mut sender);
    assert_eq!(parse_first_header(&zfin).frame(), Frame::ZFIN);
    assert!(sender.submit_wire(&znak).unwrap() > 0);
    assert_eq!(take_sender_wire(&mut sender), zfin);
}

#[test]
fn test_sender_recovers_from_corrupt_header_with_znak() {
    let mut sender = Sender::new().unwrap();
    drain_wire_sender(&mut sender);
    let mut corrupt = write_header(Header::new(Encoding::ZBIN, Frame::ZRINIT, [0; 4]));
    *corrupt.last_mut().unwrap() ^= 1;
    let valid = write_header(Header::new(Encoding::ZHEX, Frame::ZRINIT, [0; 4]));
    corrupt.extend_from_slice(&valid);

    let consumed = sender.submit_wire(&corrupt).unwrap();
    assert!(consumed > 0 && consumed < corrupt.len());
    assert_eq!(
        parse_first_header(&take_sender_wire(&mut sender)).frame(),
        Frame::ZNAK
    );
    assert_eq!(
        sender.submit_wire(&corrupt[consumed..]),
        Ok(corrupt.len() - consumed)
    );
    assert_eq!(sender.poll(), Action::Idle);
    sender.finish().unwrap();
    assert_eq!(
        parse_first_header(&take_sender_wire(&mut sender)).frame(),
        Frame::ZFIN
    );
}

#[test]
fn test_reverse_header_corruption_recovers_through_receiver_znak_replay() {
    let mut receiver = Receiver::new().unwrap();
    receiver.set_manual_file_accept(true);
    feed_receiver_zfile(&mut receiver);
    receiver.accept_file_at(0).unwrap();
    let original_zrpos = take_receiver_wire(&mut receiver);
    assert_eq!(parse_first_header(&original_zrpos).frame(), Frame::ZRPOS);

    let mut sender = start_sender_with_caps(4, Zrinit::CANFC32);
    drain_wire_sender(&mut sender);
    let mut corrupt_zrpos = original_zrpos.clone();
    let crc_nibble = corrupt_zrpos.len() - 4;
    corrupt_zrpos[crc_nibble] ^= 1;
    assert!(sender.submit_wire(&corrupt_zrpos).unwrap() > 0);
    let znak = take_sender_wire(&mut sender);
    assert_eq!(parse_first_header(&znak).frame(), Frame::ZNAK);

    assert!(receiver.submit_wire(&znak).unwrap() > 0);
    let replayed_zrpos = take_receiver_wire(&mut receiver);
    assert_eq!(replayed_zrpos, original_zrpos);
    assert!(sender.submit_wire(&replayed_zrpos).unwrap() > 0);
    assert_eq!(
        sender.poll(),
        Action::ReadFile {
            offset: Position::ZERO,
            max_len: 4,
        }
    );
}

#[test]
fn test_receiver_znak_replays_zack_and_zfin() {
    let znak = write_header(Header::new(Encoding::ZHEX, Frame::ZNAK, [0; 4]));
    let mut receiver = Receiver::new().unwrap();
    feed_receiver_zfile(&mut receiver);

    let mut data = write_header(Header::new(Encoding::ZBIN32, Frame::ZDATA, [0; 4]));
    data.extend(escaped_zbin32_subpacket(SubpacketType::ZCRCW, b"data"));
    consume_file_chunk(&mut receiver, &data, b"data");
    let zack = take_receiver_wire(&mut receiver);
    assert_eq!(parse_first_header(&zack).frame(), Frame::ZACK);
    assert!(receiver.submit_wire(&znak).unwrap() > 0);
    assert_eq!(take_receiver_wire(&mut receiver), zack);

    let mut receiver = drive_receiver_to_final_oo();
    assert!(receiver.submit_wire(&znak).unwrap() > 0);
    let zfin = take_receiver_wire(&mut receiver);
    assert_eq!(parse_first_header(&zfin).frame(), Frame::ZFIN);
    assert!(receiver.is_waiting_final_oo());
}

#[test]
fn test_receiver_znak_replay_has_finite_budget() {
    let mut receiver = Receiver::new().unwrap();
    let zrinit = take_receiver_wire(&mut receiver);
    let znak = write_header(Header::new(Encoding::ZHEX, Frame::ZNAK, [0; 4]));

    for _ in 0..MAX_RECEIVER_ZNAK_RETRIES {
        assert!(receiver.submit_wire(&znak).unwrap() > 0);
        assert_eq!(take_receiver_wire(&mut receiver), zrinit);
    }
    assert!(receiver.submit_wire(&znak).unwrap() > 0);
    assert_eq!(receiver.poll(), Action::Event(Event::Aborted));
}

#[test]
fn test_abort_events() {
    for frame in [Frame::ZABORT, Frame::ZFERR, Frame::ZCAN] {
        let abort = write_header(Header::new(Encoding::ZHEX, frame, [0; 4]));

        let mut sender = Sender::new().unwrap();
        drain_wire_sender(&mut sender);
        assert!(sender.submit_wire(&abort).unwrap() > 0);
        assert_eq!(sender.poll(), Action::Event(Event::Aborted));

        let mut receiver = Receiver::new().unwrap();
        drain_wire_receiver(&mut receiver);
        assert!(receiver.submit_wire(&abort).unwrap() > 0);
        assert_eq!(receiver.poll(), Action::Event(Event::Aborted));
    }
}

#[test]
fn test_bare_cancel_sequence_aborts_across_submit_chunks() {
    let prefix = [ZDLE; 3];
    let suffix = [ZDLE, ZDLE, ZDLE, ZDLE, ZDLE, 0x08, 0x08];

    let mut sender = Sender::new().unwrap();
    drain_wire_sender(&mut sender);
    assert_eq!(sender.submit_wire(&prefix), Ok(prefix.len()));
    assert_eq!(sender.poll(), Action::Idle);
    // The fifth consecutive CAN is sufficient; leave the remaining CAN/BS
    // bytes unconsumed for the embedding terminal to discard with the
    // transfer session.
    assert_eq!(sender.submit_wire(&suffix), Ok(2));
    assert_eq!(sender.poll(), Action::Event(Event::Aborted));

    let mut receiver = Receiver::new().unwrap();
    drain_wire_receiver(&mut receiver);
    assert_eq!(receiver.submit_wire(&prefix), Ok(prefix.len()));
    assert_eq!(receiver.poll(), Action::Idle);
    assert_eq!(receiver.submit_wire(&suffix), Ok(2));
    assert_eq!(receiver.poll(), Action::Event(Event::Aborted));
}

#[test]
fn test_escaped_can_payload_is_not_mistaken_for_cancel() {
    let mut receiver = Receiver::new().unwrap();
    feed_receiver_zfile(&mut receiver);

    let payload = [ZDLE; 16];
    let mut wire = write_header(Header::new(Encoding::ZBIN32, Frame::ZDATA, [0; 4]));
    wire.extend(escaped_zbin32_subpacket(SubpacketType::ZCRCE, &payload));

    let mut input_offset = 0;
    let mut persisted = Vec::new();
    while persisted.is_empty() {
        match receiver.poll() {
            Action::WriteFile(bytes) => {
                persisted.extend_from_slice(bytes);
                let n = bytes.len();
                receiver.file_written(n).unwrap();
            }
            Action::Idle => {
                let consumed = receiver.submit_wire(&wire[input_offset..]).unwrap();
                assert!(consumed > 0);
                input_offset += consumed;
            }
            Action::WriteWire(bytes) => {
                let n = bytes.len();
                receiver.wire_written(n);
            }
            other => panic!("unexpected action: {other:?}"),
        }
    }
    assert_eq!(persisted, payload);
}

#[test]
fn test_bare_cancel_run_crosses_crc_resync_and_submit_boundaries() {
    let mut receiver = Receiver::new().unwrap();
    feed_receiver_zfile(&mut receiver);

    let mut wire = write_header(Header::new(Encoding::ZBIN, Frame::ZDATA, [0; 4]));
    wire.push(b'x');
    wire.extend_from_slice(&[ZDLE, SubpacketType::ZCRCG as u8]);
    // Four raw CAN bytes decode as the two (invalid) CRC16 bytes. The CRC
    // recovery moves
    // from the subpacket parser to header resynchronisation without resetting
    // the session-wide detector.
    wire.extend_from_slice(&[ZDLE; 4]);
    let consumed = receiver.submit_wire(&wire).unwrap();
    assert!(consumed > 0 && consumed < wire.len());
    assert_eq!(
        receiver.submit_wire(&wire[consumed..]),
        Ok(wire.len() - consumed)
    );
    let zrpos = match receiver.poll() {
        Action::WriteWire(bytes) => parse_first_header(bytes),
        other => panic!("expected recovery ZRPOS, got {other:?}"),
    };
    assert_eq!(zrpos.frame(), Frame::ZRPOS);
    drain_wire_receiver(&mut receiver);

    // The fifth raw CAN arrives in another submit call and aborts even though
    // the parser changed from CRC to header mode in between.
    assert_eq!(receiver.submit_wire(&[ZDLE]), Ok(1));
    assert_eq!(receiver.poll(), Action::Event(Event::Aborted));
}

fn drive_receiver_to_before_final_zfin() -> Receiver {
    let mut receiver = Receiver::new().unwrap();
    feed_receiver_zfile(&mut receiver);

    let zeof = write_header(Header::new(Encoding::ZBIN32, Frame::ZEOF, [0; 4]));
    assert!(receiver.submit_wire(&zeof).unwrap() > 0);
    assert_eq!(receiver.poll(), Action::Event(Event::FileCompleted));
    drain_wire_receiver(&mut receiver);
    receiver
}

fn drive_receiver_to_final_oo() -> Receiver {
    let mut receiver = drive_receiver_to_before_final_zfin();

    let zfin = write_header(Header::new(Encoding::ZHEX, Frame::ZFIN, [0; 4]));
    let mut offset = 0;
    while offset < zfin.len() {
        let consumed = receiver.submit_wire(&zfin[offset..]).unwrap();
        assert!(consumed > 0);
        offset += consumed;
        drain_wire_receiver(&mut receiver);
    }
    receiver
}

#[test]
fn test_receiver_final_zfin_accepts_lf_or_crlf_and_optional_xon() {
    for trailer in [&b"\x8a"[..], &b"\x8d\x8a"[..], &b"\x8d\x8a\x91"[..]] {
        let mut receiver = drive_receiver_to_before_final_zfin();
        let mut header = write_header(Header::new(Encoding::ZHEX, Frame::ZFIN, [0; 4]));
        header.truncate(header.len() - 2);
        let marker = b"terminal-after-zmodem";
        let mut retained = header.clone();
        retained.extend_from_slice(trailer);
        retained.extend_from_slice(b"OO");
        retained.extend_from_slice(marker);

        assert_eq!(receiver.submit_wire(&retained), Ok(header.len()));
        let response = take_receiver_wire(&mut receiver);
        assert_eq!(parse_first_header(&response).frame(), Frame::ZFIN);

        assert_eq!(
            receiver.submit_wire(&retained[header.len()..]),
            Ok(trailer.len() + 2)
        );
        assert_eq!(receiver.poll(), Action::Event(Event::SessionCompleted));
        assert_eq!(receiver.submit_wire(marker), Ok(0));
    }
}

#[test]
fn test_receiver_completes_only_after_final_oo() {
    let mut receiver = drive_receiver_to_final_oo();
    assert_eq!(receiver.poll(), Action::Idle);

    // A lone O is ambiguous terminal output. Keep it in the caller's buffer
    // until the second byte proves that this is the closing token.
    assert_eq!(receiver.submit_wire(b"O"), Ok(0));
    assert_eq!(receiver.poll(), Action::Idle);

    // Stop exactly after the final O: shell/application bytes following the
    // ZMODEM session must not be swallowed by the protocol engine.
    assert_eq!(receiver.submit_wire(b"OOafter"), Ok(2));
    assert_eq!(receiver.poll(), Action::Event(Event::SessionCompleted));
    assert_eq!(receiver.submit_wire(b"after"), Ok(0));
}

#[test]
fn test_receiver_preserves_plain_text_until_trustworthy_eof() {
    let mut receiver = drive_receiver_to_final_oo();
    let marker = b"IANVS_ZMODEM_RECEIVE_MD5=abc_MTIME=1700000123_DONE\r\n";

    assert_eq!(receiver.submit_wire(marker), Ok(0));
    assert!(receiver.is_waiting_final_oo());
    assert_eq!(receiver.poll(), Action::Idle);

    assert_eq!(receiver.transport_closed(), Ok(()));
    assert_eq!(receiver.poll(), Action::Event(Event::SessionCompleted));
    assert_eq!(receiver.submit_wire(marker), Ok(0));
}

#[test]
fn test_final_zhex_trailer_can_cross_submit_boundaries() {
    let mut receiver = Receiver::new().unwrap();
    feed_receiver_zfile(&mut receiver);
    let zeof = write_header(Header::new(Encoding::ZBIN32, Frame::ZEOF, [0; 4]));
    assert!(receiver.submit_wire(&zeof).unwrap() > 0);
    assert_eq!(receiver.poll(), Action::Event(Event::FileCompleted));
    drain_wire_receiver(&mut receiver);

    let zfin = write_header(Header::new(Encoding::ZHEX, Frame::ZFIN, [0; 4]));
    let header_len = zfin.len() - 2;
    assert_eq!(receiver.submit_wire(&zfin[..header_len]), Ok(header_len));
    drain_wire_receiver(&mut receiver);
    // lrzsz commonly sets the parity bit on the CR/LF trailer bytes.
    assert_eq!(receiver.submit_wire(b"\x8d"), Ok(1));

    let marker = b"terminal-output";
    let mut tail = b"\x8aOO".to_vec();
    tail.extend_from_slice(marker);
    assert_eq!(receiver.submit_wire(&tail), Ok(3));
    assert_eq!(receiver.poll(), Action::Event(Event::SessionCompleted));
    assert_eq!(receiver.submit_wire(marker), Ok(0));
}

#[test]
fn test_wait_final_oo_handles_cancel_atomically() {
    let mut receiver = drive_receiver_to_final_oo();
    assert_eq!(receiver.submit_wire(&[ZDLE; 3]), Ok(0));
    assert!(receiver.is_waiting_final_oo());

    assert_eq!(receiver.submit_wire(&[ZDLE; 5]), Ok(5));
    assert_eq!(receiver.poll(), Action::Event(Event::Aborted));
    assert_eq!(receiver.submit_wire(b"terminal-output"), Ok(0));
}

#[test]
fn test_wait_final_oo_headers_preserve_trailing_terminal_text() {
    let marker = b"terminal-output";

    for (frame, trailer_len) in [(Frame::ZFIN, 2), (Frame::ZNAK, 3)] {
        let mut receiver = drive_receiver_to_final_oo();
        let header = write_header(Header::new(Encoding::ZHEX, frame, [0; 4]));
        let mut input = header.clone();
        input.extend_from_slice(marker);

        let header_len = header.len() - trailer_len;
        assert_eq!(receiver.submit_wire(&input), Ok(header_len));
        let replay = take_receiver_wire(&mut receiver);
        assert_eq!(parse_first_header(&replay).frame(), Frame::ZFIN);

        assert_eq!(receiver.submit_wire(&input[header_len..]), Ok(trailer_len));
        assert!(receiver.is_waiting_final_oo());
        assert_eq!(receiver.submit_wire(marker), Ok(0));
    }
}

#[test]
fn test_mid_file_zfin_and_oo_abort_instead_of_completing() {
    let mut receiver = Receiver::new().unwrap();
    receiver.set_manual_file_accept(true);
    feed_receiver_zfile(&mut receiver);
    receiver.accept_file_at(0).unwrap();
    drain_wire_receiver(&mut receiver);

    let mut close = write_header(Header::new(Encoding::ZHEX, Frame::ZFIN, [0; 4]));
    close.extend_from_slice(b"OO");
    let consumed = receiver.submit_wire(&close).unwrap();
    assert!(consumed > 0);
    assert_eq!(receiver.poll(), Action::Event(Event::Aborted));
    assert!(!receiver.is_waiting_final_oo());
    if consumed < close.len() {
        assert_eq!(receiver.submit_wire(&close[consumed..]), Ok(0));
    }
    assert_eq!(receiver.poll(), Action::Idle);
}

#[test]
fn test_pending_file_zfin_and_oo_abort_instead_of_completing() {
    let mut receiver = Receiver::new().unwrap();
    receiver.set_manual_file_accept(true);
    feed_receiver_zfile(&mut receiver);

    let mut close = write_header(Header::new(Encoding::ZHEX, Frame::ZFIN, [0; 4]));
    close.extend_from_slice(b"OO");
    let consumed = receiver.submit_wire(&close).unwrap();
    assert!(consumed > 0);
    assert_eq!(receiver.poll(), Action::Event(Event::Aborted));
    assert!(!receiver.is_waiting_final_oo());
    assert_ne!(receiver.poll(), Action::Event(Event::SessionCompleted));
}

#[test]
fn test_sender_wait_finish_ignores_duplicate_zrinit_until_zfin() {
    let mut sender = Sender::new().unwrap();
    drain_wire_sender(&mut sender);
    let zrinit = write_header(Header::new(Encoding::ZHEX, Frame::ZRINIT, [0; 4]));
    assert!(sender.submit_wire(&zrinit).unwrap() > 0);
    sender.finish().unwrap();
    let original_zfin = take_sender_wire(&mut sender);
    assert_eq!(parse_first_header(&original_zfin).frame(), Frame::ZFIN);

    assert!(sender.submit_wire(&zrinit).unwrap() > 0);
    assert_eq!(take_sender_wire(&mut sender), original_zfin);
    assert_eq!(sender.poll(), Action::Idle);

    let zfin = write_header(Header::new(Encoding::ZHEX, Frame::ZFIN, [0; 4]));
    assert!(sender.submit_wire(&zfin).unwrap() > 0);
    assert_eq!(sender.poll(), Action::Event(Event::SessionCompleted));
    assert_eq!(sender.poll(), Action::WriteWire(b"OO"));
}

fn sender_waiting_for_peer_zfin() -> Sender {
    let mut sender = Sender::new().unwrap();
    drain_wire_sender(&mut sender);
    let zrinit = write_header(Header::new(Encoding::ZHEX, Frame::ZRINIT, [0; 4]));
    assert!(sender.submit_wire(&zrinit).unwrap() > 0);
    sender.finish().unwrap();
    let request = take_sender_wire(&mut sender);
    assert_eq!(parse_first_header(&request).frame(), Frame::ZFIN);
    sender
}

#[test]
fn test_sender_consumes_zfin_trailer_and_preserves_shell_text() {
    for trailer in [&b"\x8a"[..], &b"\x8d\x8a"[..], &b"\x8d\x8a\x91"[..]] {
        let mut sender = sender_waiting_for_peer_zfin();
        let mut header = write_header(Header::new(Encoding::ZHEX, Frame::ZFIN, [0; 4]));
        header.truncate(header.len() - 2);
        let marker = b"shell-output";
        let mut retained = header.clone();
        retained.extend_from_slice(trailer);
        retained.extend_from_slice(marker);

        assert_eq!(
            sender.submit_wire(&retained),
            Ok(header.len() + trailer.len())
        );
        assert_eq!(sender.poll(), Action::Event(Event::SessionCompleted));
        assert_eq!(take_sender_wire(&mut sender), b"OO");
        assert_eq!(sender.submit_wire(marker), Ok(0));
    }
}

#[test]
fn test_sender_zfin_trailer_and_optional_xon_cross_submit_boundaries() {
    let mut sender = sender_waiting_for_peer_zfin();
    let mut header = write_header(Header::new(Encoding::ZHEX, Frame::ZFIN, [0; 4]));
    header.truncate(header.len() - 2);

    assert_eq!(sender.submit_wire(&header), Ok(header.len()));
    assert_eq!(sender.poll(), Action::Idle);
    assert_eq!(sender.submit_wire(b"\x8d"), Ok(1));
    assert_eq!(sender.poll(), Action::Idle);
    assert_eq!(sender.submit_wire(b"\x8a"), Ok(1));
    assert_eq!(sender.poll(), Action::Event(Event::SessionCompleted));
    assert_eq!(take_sender_wire(&mut sender), b"OO");

    let marker = b"shell-output";
    let mut tail = b"\x91".to_vec();
    tail.extend_from_slice(marker);
    assert_eq!(sender.submit_wire(&tail), Ok(1));
    assert_eq!(sender.submit_wire(marker), Ok(0));
}

#[test]
fn test_trustworthy_transport_eof_completes_only_after_zfin_reply() {
    let mut receiver = drive_receiver_to_final_oo();
    assert!(receiver.is_waiting_final_oo());
    assert_eq!(receiver.transport_closed(), Ok(()));
    assert!(!receiver.is_waiting_final_oo());
    assert_eq!(receiver.poll(), Action::Event(Event::SessionCompleted));
    assert_eq!(
        receiver.transport_closed(),
        Ok(()),
        "completion is idempotent"
    );

    let mut receiver = Receiver::new().unwrap();
    drain_wire_receiver(&mut receiver);
    assert_eq!(receiver.transport_closed(), Err(Error::UnexpectedEof));
    assert_eq!(receiver.poll(), Action::Event(Event::Aborted));
}

#[test]
fn test_receiver_missing_oo_completes_after_bounded_zfin_retries() {
    for remainder in [&b"O"[..], &b"ordinary shell output"[..]] {
        let mut receiver = drive_receiver_to_final_oo();
        assert_eq!(receiver.submit_wire(remainder), Ok(0));

        for _ in 0..MAX_ZFIN_RETRIES {
            receiver.timeout().unwrap();
            let header = match receiver.poll() {
                Action::WriteWire(bytes) => parse_first_header(bytes),
                other => panic!("expected a retransmitted ZFIN, got {other:?}"),
            };
            assert_eq!(header.frame(), Frame::ZFIN);
            drain_wire_receiver(&mut receiver);
        }

        receiver.timeout().unwrap();
        assert_eq!(receiver.poll(), Action::Event(Event::SessionCompleted));
        assert!(!receiver.is_waiting_final_oo());
        assert_eq!(receiver.submit_wire(remainder), Ok(0));
    }
}

#[test]
fn test_receiver_timeout_requeues_zrinit() {
    let mut receiver = Receiver::new().unwrap();
    drain_wire_receiver(&mut receiver);

    receiver.timeout().unwrap();

    match receiver.poll() {
        Action::WriteWire(bytes) => assert!(!bytes.is_empty()),
        other => panic!("unexpected action: {other:?}"),
    }
}

#[test]
fn test_receiver_timeout_requeues_active_zrpos_then_zrinit_between_files() {
    let mut receiver = Receiver::new().unwrap();
    feed_receiver_zfile(&mut receiver);

    receiver.timeout().unwrap();
    let active_retry = take_receiver_wire(&mut receiver);
    let active_header = parse_first_header(&active_retry);
    assert_eq!(active_header.frame(), Frame::ZRPOS);
    assert_eq!(active_header.count(), 0);

    let zeof = write_header(Header::new(Encoding::ZBIN32, Frame::ZEOF, [0; 4]));
    assert!(receiver.submit_wire(&zeof).unwrap() > 0);
    assert_eq!(receiver.poll(), Action::Event(Event::FileCompleted));
    drain_wire_receiver(&mut receiver);

    receiver.timeout().unwrap();
    let between_files_retry = take_receiver_wire(&mut receiver);
    assert_eq!(
        parse_first_header(&between_files_retry).frame(),
        Frame::ZRINIT
    );
}

#[test]
fn test_receiver_waiting_subpacket_timeout_reissues_current_zrpos() {
    let mut receiver = Receiver::new().unwrap();
    feed_receiver_zfile(&mut receiver);

    let mut data = write_header(Header::new(Encoding::ZBIN32, Frame::ZDATA, [0; 4]));
    data.extend(escaped_zbin32_subpacket(SubpacketType::ZCRCE, b"abc"));
    consume_file_chunk(&mut receiver, &data, b"abc");

    receiver.timeout().unwrap();
    let retry = parse_first_header(&take_receiver_wire(&mut receiver));
    assert_eq!((retry.frame(), retry.count()), (Frame::ZRPOS, 3));
}

#[test]
fn test_receiver_incomplete_metadata_timeout_znaks_with_a_bounded_budget() {
    let mut receiver = Receiver::new().unwrap();
    drain_wire_receiver(&mut receiver);
    let mut partial = write_header(Header::new(Encoding::ZBIN32, Frame::ZFILE, [0; 4]));
    partial.extend_from_slice(b"partial metadata");

    for _ in 0..MAX_METADATA_RETRIES {
        assert_eq!(receiver.submit_wire(&partial), Ok(partial.len()));
        receiver.timeout().unwrap();
        let retry = take_receiver_wire(&mut receiver);
        assert_eq!(parse_first_header(&retry).frame(), Frame::ZNAK);
    }

    assert_eq!(receiver.submit_wire(&partial), Ok(partial.len()));
    receiver.timeout().unwrap();
    assert_eq!(receiver.poll(), Action::Event(Event::Aborted));
}

#[test]
fn test_receiver_incomplete_subpacket_timeout_zrpos_is_bounded() {
    let mut receiver = Receiver::new().unwrap();
    feed_receiver_zfile(&mut receiver);
    let mut partial = write_header(Header::new(Encoding::ZBIN32, Frame::ZDATA, [0; 4]));
    partial.extend_from_slice(b"partial payload");

    for _ in 0..MAX_RECEIVER_TIMEOUT_RETRIES {
        assert_eq!(receiver.submit_wire(&partial), Ok(partial.len()));
        receiver.timeout().unwrap();
        let retry = parse_first_header(&take_receiver_wire(&mut receiver));
        assert_eq!((retry.frame(), retry.count()), (Frame::ZRPOS, 0));
    }

    assert_eq!(receiver.submit_wire(&partial), Ok(partial.len()));
    receiver.timeout().unwrap();
    assert_eq!(receiver.poll(), Action::Event(Event::Aborted));
}

#[test]
fn test_receiver_incomplete_crc_timeout_recovers_from_current_zrpos() {
    let mut receiver = Receiver::new().unwrap();
    feed_receiver_zfile(&mut receiver);
    let mut frame = write_header(Header::new(Encoding::ZBIN32, Frame::ZDATA, [0; 4]));
    frame.extend(escaped_zbin32_subpacket(SubpacketType::ZCRCE, b"abc"));
    let truncated = &frame[..frame.len() - 1];

    let mut offset = 0;
    while offset < truncated.len() {
        let consumed = receiver.submit_wire(&truncated[offset..]).unwrap();
        assert!(consumed > 0);
        offset += consumed;
    }
    receiver.timeout().unwrap();
    let retry = parse_first_header(&take_receiver_wire(&mut receiver));
    assert_eq!((retry.frame(), retry.count()), (Frame::ZRPOS, 0));

    consume_file_chunk(&mut receiver, &frame, b"abc");
}

#[test]
fn test_receiver_timeout_budget_is_bounded_and_resets_after_persisted_progress() {
    let mut receiver = Receiver::new().unwrap();
    feed_receiver_zfile(&mut receiver);

    let mut first = write_header(Header::new(Encoding::ZBIN32, Frame::ZDATA, [0; 4]));
    first.extend(escaped_zbin32_subpacket(SubpacketType::ZCRCE, b"a"));
    consume_file_chunk(&mut receiver, &first, b"a");

    for _ in 0..MAX_RECEIVER_TIMEOUT_RETRIES {
        receiver.timeout().unwrap();
        let retry = parse_first_header(&take_receiver_wire(&mut receiver));
        assert_eq!((retry.frame(), retry.count()), (Frame::ZRPOS, 1));
    }

    let mut second = write_header(Header::new(
        Encoding::ZBIN32,
        Frame::ZDATA,
        1u32.to_le_bytes(),
    ));
    second.extend(escaped_zbin32_subpacket(SubpacketType::ZCRCE, b"b"));
    consume_file_chunk(&mut receiver, &second, b"b");

    for _ in 0..MAX_RECEIVER_TIMEOUT_RETRIES {
        receiver.timeout().unwrap();
        let retry = parse_first_header(&take_receiver_wire(&mut receiver));
        assert_eq!((retry.frame(), retry.count()), (Frame::ZRPOS, 2));
    }
    receiver.timeout().unwrap();
    assert_eq!(receiver.poll(), Action::Event(Event::Aborted));
}

#[test]
fn test_start_file_rejects_unknown_size() {
    let mut sender = Sender::new().unwrap();

    assert_eq!(
        sender.start_file(FileInfo::new(b"unknown.bin", None)),
        Err(Error::UnsupportedFeature)
    );
}

/// Feeds one ZDATA frame at `offset` whose data subpacket is corrupted,
/// plus a run of mid-window garbage, and returns the count carried by the
/// ZRPOS the receiver queues in response. Propagates the receiver error
/// when recovery is refused (retry budget spent).
fn feed_corrupt_subpacket(receiver: &mut Receiver, offset: u32) -> Result<u32, Error> {
    let mut bytes = write_header(Header::new(
        Encoding::ZBIN32,
        Frame::ZDATA,
        offset.to_le_bytes(),
    ));
    // ZCRCG keeps the frame open (streaming), like a fast sender.
    let mut subpacket = escaped_zbin32_subpacket(SubpacketType::ZCRCG, b"corrupt");
    subpacket[0] ^= 0x01; // flip a payload byte so the CRC mismatches
    bytes.extend(subpacket);
    // The sender is still emitting the tail of the aborted window when
    // the receiver reacts. This run includes a byte pattern that would
    // have fatally tripped the old header scanner: `*` (a legal data
    // byte) then `ZDLE` then a non-encoding escape byte.
    bytes.extend_from_slice(&[ZPAD, ZDLE, encode_zdle(0x11), b'x', b'y']);

    let mut consumed_total = 0;
    let mut zrpos = None;
    loop {
        match receiver.poll() {
            Action::WriteWire(b) => {
                let header = parse_first_header(b);
                if header.frame() == Frame::ZRPOS {
                    zrpos = Some(header.count());
                }
                let n = b.len();
                receiver.wire_written(n);
            }
            Action::WriteFile(_) => panic!("corrupt data must never be written"),
            Action::Idle => {
                if consumed_total >= bytes.len() {
                    break;
                }
                let consumed = receiver.submit_wire(&bytes[consumed_total..])?;
                assert!(consumed > 0, "receiver made no progress on input");
                consumed_total += consumed;
            }
            other => panic!("unexpected action: {other:?}"),
        }
    }
    Ok(zrpos.expect("a corrupt subpacket must queue a ZRPOS"))
}

#[test]
fn test_corrupt_subpacket_triggers_zrpos_and_recovers() {
    let mut receiver = Receiver::new().unwrap();
    feed_receiver_zfile(&mut receiver);

    // A corrupt subpacket at offset 0 must not abort: the receiver asks
    // the sender to rewind to the last good offset and skips the garbage
    // tail without tripping on it.
    let count = feed_corrupt_subpacket(&mut receiver, 0).unwrap();
    assert_eq!(count, 0, "receiver should rewind to the last good offset");

    // The sender honours the ZRPOS and retransmits cleanly from 0; the
    // stream is realigned and the good data flows through.
    let mut good = write_header(Header::new(Encoding::ZBIN32, Frame::ZDATA, [0; 4]));
    good.extend(escaped_zbin32_subpacket(SubpacketType::ZCRCE, b"clean"));
    consume_file_chunk(&mut receiver, &good, b"clean");
}

#[test]
fn test_repeated_corruption_eventually_fails() {
    let mut receiver = Receiver::new().unwrap();
    feed_receiver_zfile(&mut receiver);

    // Every retransmission arrives corrupt at the same offset: no forward
    // progress, so the retry budget is never replenished and the receiver
    // must give up rather than ZRPOS-loop forever. The loop bound exceeds
    // the internal retry ceiling; recovery must fail before it is hit.
    let mut result = Ok(0);
    for _ in 0..64 {
        result = feed_corrupt_subpacket(&mut receiver, 0);
        if result.is_err() {
            break;
        }
    }
    assert_eq!(result, Err(Error::UnexpectedCrc32));
}

#[test]
fn test_recovery_budget_replenishes_on_progress() {
    let mut receiver = Receiver::new().unwrap();
    feed_receiver_zfile(&mut receiver);

    // Line noise on a long transfer: errors are spread out, and every
    // retransmission after a rewind arrives clean. Far more corrupt
    // subpackets than the retry ceiling must still recover, because the
    // budget counts a consecutive streak, not a lifetime total. A link
    // that merely accumulates occasional errors would otherwise fail
    // once, arbitrarily, after enough good data had gone through.
    let mut offset = 0u32;
    for _ in 0..(u32::from(MAX_ZRPOS_RETRIES) * 3) {
        let count = feed_corrupt_subpacket(&mut receiver, offset).unwrap();
        assert_eq!(
            count, offset,
            "receiver should rewind to the last good offset"
        );

        let mut good = write_header(Header::new(
            Encoding::ZBIN32,
            Frame::ZDATA,
            offset.to_le_bytes(),
        ));
        good.extend(escaped_zbin32_subpacket(SubpacketType::ZCRCE, b"clean"));
        consume_file_chunk(&mut receiver, &good, b"clean");
        offset += 5;
    }
}

#[test]
fn test_offset_overflow_is_refused() {
    let mut receiver = Receiver::new().unwrap();
    receiver.set_manual_file_accept(true);
    feed_receiver_zfile(&mut receiver);

    // Resume a few bytes short of the 4 GiB position ceiling, then feed a
    // subpacket long enough to push the running offset past u32::MAX. The
    // counter must refuse to wrap (which would rewind the transfer to a
    // low offset) and surface an error instead.
    let near = u32::MAX - 4;
    receiver.accept_file_at(near).unwrap();
    loop {
        match receiver.poll() {
            Action::WriteWire(b) => {
                let n = b.len();
                receiver.wire_written(n);
            }
            Action::Idle => break,
            other => panic!("unexpected action: {other:?}"),
        }
    }

    let mut wire = write_header(Header::new(
        Encoding::ZBIN32,
        Frame::ZDATA,
        near.to_le_bytes(),
    ));
    wire.extend(escaped_zbin32_subpacket(SubpacketType::ZCRCE, b"overflow!"));

    let mut offset = 0;
    let err = loop {
        match receiver.poll() {
            Action::WriteWire(b) => {
                let n = b.len();
                receiver.wire_written(n);
            }
            Action::WriteFile(b) => {
                let n = b.len();
                if let Err(e) = receiver.file_written(n) {
                    break e;
                }
            }
            Action::Idle => {
                assert!(offset < wire.len(), "ran out of input before overflow");
                let consumed = receiver.submit_wire(&wire[offset..]).unwrap();
                offset += consumed;
            }
            other => panic!("unexpected action: {other:?}"),
        }
    };
    assert_eq!(err, Error::OutOfMemory);
}

#[test]
fn test_receiver_zcrcq_and_zcrce() {
    let mut receiver = Receiver::new().unwrap();
    feed_receiver_zfile(&mut receiver);

    let mut first = write_header(Header::new(Encoding::ZBIN32, Frame::ZDATA, [0; 4]));
    first.extend(escaped_zbin32_subpacket(SubpacketType::ZCRCQ, b"abc"));
    consume_file_chunk(&mut receiver, &first, b"abc");

    // ZCRCQ requests an acknowledgement, so a ZACK is queued.
    match receiver.poll() {
        Action::WriteWire(bytes) => {
            assert!(!bytes.is_empty());
            let n = bytes.len();
            receiver.wire_written(n);
        }
        other => panic!("expected ZACK, got {other:?}"),
    }

    let second = escaped_zbin32_subpacket(SubpacketType::ZCRCE, b"def");
    consume_file_chunk(&mut receiver, &second, b"def");

    // ZCRCE ends the frame without an acknowledgement.
    assert_eq!(receiver.poll(), Action::Idle);

    let zeof = write_header(Header::new(
        Encoding::ZBIN32,
        Frame::ZEOF,
        6u32.to_le_bytes(),
    ));
    assert!(receiver.submit_wire(&zeof).unwrap() > 0);
    assert_eq!(receiver.poll(), Action::Event(Event::FileCompleted));
}

/// Feeds a single data subpacket and asserts the receiver yields `expected`
/// file bytes, then acknowledges them.
fn consume_file_chunk(receiver: &mut Receiver, input: &[u8], expected: &[u8]) {
    let mut offset = 0;
    loop {
        match receiver.poll() {
            Action::WriteFile(bytes) => {
                assert_eq!(bytes, expected);
                let n = bytes.len();
                receiver.file_written(n).unwrap();
                break;
            }
            Action::WriteWire(bytes) => {
                let n = bytes.len();
                receiver.wire_written(n);
            }
            Action::Idle => {
                assert!(offset < input.len(), "ran out of input before file data");
                let consumed = receiver.submit_wire(&input[offset..]).unwrap();
                offset += consumed;
            }
            other => panic!("unexpected action: {other:?}"),
        }
    }
}

#[test]
fn test_abort_event() {
    let mut sender = Sender::new().unwrap();
    drain_wire_sender(&mut sender);

    sender.abort();
    assert_eq!(sender.poll(), Action::Event(Event::Aborted));
}

#[test]
fn test_zrinit_advertises_configured_flow_control() {
    // Default construction is unchanged: one-subpacket buffer, no
    // CANOVIO.
    let mut receiver = Receiver::new().unwrap();
    let header = match receiver.poll() {
        Action::WriteWire(bytes) => parse_first_header(bytes),
        other => panic!("unexpected action: {other:?}"),
    };
    let flags = header.count().to_le_bytes();
    assert_eq!(u16::from_le_bytes([flags[0], flags[1]]), 1024);
    assert_eq!(flags[3] & Zrinit::CANOVIO.bits(), 0);

    // Streaming configuration: zero buffer length plus CANOVIO, the
    // combination lrzsz's `sz` requires before it streams nonstop.
    let mut receiver = Receiver::with_flow_control(0, true).unwrap();
    let header = match receiver.poll() {
        Action::WriteWire(bytes) => parse_first_header(bytes),
        other => panic!("unexpected action: {other:?}"),
    };
    let flags = header.count().to_le_bytes();
    assert_eq!(u16::from_le_bytes([flags[0], flags[1]]), 0);
    assert_ne!(flags[3] & Zrinit::CANOVIO.bits(), 0);
}

/// Runs an upload against a simulated nonstop receiver (zero buffer,
/// CANOVIO) and returns how many ZCRCW (wait-for-ack) data subpackets
/// went out (the ZFILE frame is drained before counting starts).
fn count_zcrcw_waits(window: Option<usize>, window_after: Option<usize>, file_len: usize) -> usize {
    let mut sender = Sender::new().unwrap();
    if let Some(window) = window {
        sender.set_streaming_window(window);
    }
    drain_wire_sender(&mut sender);
    sender
        .start_file(FileInfo::new(
            b"stream.bin",
            Some(Position::new(u32::try_from(file_len).unwrap())),
        ))
        .unwrap();

    let mut flags = [0u8; 4];
    flags[3] = (Zrinit::CANFDX | Zrinit::CANFC32 | Zrinit::CANOVIO).bits();
    let zrinit = write_header(Header::new(Encoding::ZHEX, Frame::ZRINIT, flags));
    assert!(sender.submit_wire(&zrinit).unwrap() > 0);
    // Setting the window after ZRINIT must still change the ack cadence:
    // the negotiated pacing is recomputed on the fly.
    if let Some(window) = window_after {
        sender.set_streaming_window(window);
    }
    drain_wire_sender(&mut sender);
    let zrpos = write_header(Header::new(
        Encoding::ZHEX,
        Frame::ZRPOS,
        0u32.to_le_bytes(),
    ));
    assert!(sender.submit_wire(&zrpos).unwrap() > 0);

    let mut zcrcw = 0usize;
    let mut sent = 0usize;
    loop {
        match sender.poll() {
            Action::WriteWire(bytes) => {
                // A literal ZDLE in escaped data never precedes 0x6b,
                // so this exact pair only matches subpacket terminators.
                zcrcw += bytes
                    .windows(2)
                    .filter(|pair| pair == &[ZDLE, SubpacketType::ZCRCW as u8])
                    .count();
                let n = bytes.len();
                sender.wire_written(n);
            }
            Action::ReadFile { offset, max_len } => {
                let remaining = file_len - offset.get() as usize;
                let n = remaining.min(max_len);
                sender.submit_file(&vec![0u8; n]).unwrap();
                sent += n;
            }
            Action::Idle => {
                if sent >= file_len {
                    break;
                }
                // Mid-file idle means the machine is waiting out a
                // ZCRCW; acknowledge it like a receiver would.
                let zack = write_header(Header::new(
                    Encoding::ZHEX,
                    Frame::ZACK,
                    u32::try_from(sent).unwrap().to_le_bytes(),
                ));
                assert!(sender.submit_wire(&zack).unwrap() > 0);
            }
            Action::Event(_) => {}
            other => panic!("unexpected action: {other:?}"),
        }
    }
    zcrcw
}

#[test]
fn test_streaming_window_controls_ack_cadence() {
    // 32 KiB = 32 subpackets. Default window (10): waits at
    // subpackets 10, 20, 30 and the final one.
    assert_eq!(count_zcrcw_waits(None, None, 32 * 1024), 4);
    // Conservative PTY compatibility: every subpacket ends in ZCRCW, so
    // lrzsz consumes one bounded unit before the next is emitted.
    assert_eq!(count_zcrcw_waits(Some(1), None, 32 * 1024), 32);
    // Nonstop streaming: only the final subpacket waits.
    assert_eq!(count_zcrcw_waits(Some(usize::MAX), None, 32 * 1024), 1);
}

#[test]
fn test_streaming_window_applies_after_zrinit() {
    // Setting the window before the handshake and after it must reach the
    // same nonstop cadence: the setter recomputes the negotiated pacing
    // instead of silently no-opping once ZRINIT has been processed.
    assert_eq!(count_zcrcw_waits(Some(usize::MAX), None, 32 * 1024), 1);
    assert_eq!(count_zcrcw_waits(None, Some(usize::MAX), 32 * 1024), 1);
}

/// Drives a live [`Sender`] and [`Receiver`] against each other over
/// in-memory wire queues and returns the bytes the receiver persisted.
///
/// Panics if the transfer fails to complete within a generous step
/// budget, so a protocol deadlock (for instance a dropped ZEOF) surfaces
/// as a test failure rather than an infinite loop.
fn run_full_transfer(contents: &[u8]) -> Vec<u8> {
    run_full_transfer_with_options(contents, false, None)
}

fn run_full_transfer_with_first_zrpos_loss(contents: &[u8], drop_first_zrpos: bool) -> Vec<u8> {
    run_full_transfer_with_options(contents, drop_first_zrpos, None)
}

fn receiver_wire_with_caps(
    wire: &[u8],
    receiver_caps: Option<Zrinit>,
    caps_sent: &mut bool,
) -> Vec<u8> {
    let header = parse_first_header(wire);
    if !*caps_sent
        && header.frame() == Frame::ZRINIT
        && let Some(caps) = receiver_caps
    {
        *caps_sent = true;
        return write_header(Header::new(
            Encoding::ZHEX,
            Frame::ZRINIT,
            [0, 4, 0, caps.bits()],
        ));
    }
    wire.to_vec()
}

fn run_full_transfer_with_options(
    contents: &[u8],
    drop_first_zrpos: bool,
    receiver_caps: Option<Zrinit>,
) -> Vec<u8> {
    let mut sender = Sender::new().unwrap();
    let mut receiver = Receiver::new().unwrap();
    sender
        .start_file(FileInfo::new(
            b"payload.bin",
            Some(Position::new(u32::try_from(contents.len()).unwrap())),
        ))
        .unwrap();
    // Single-file transfer: request the closing ZFIN handshake now. The
    // flag is honored once this file's ZEOF is acknowledged.
    sender.finish().unwrap();

    let mut downstream: Vec<u8> = Vec::new();
    let mut upstream: Vec<u8> = Vec::new();
    let mut persisted: Vec<u8> = Vec::new();
    let mut file_done = false;
    let mut session_done = false;
    let mut first_zrpos_dropped = false;
    let mut receiver_caps_sent = false;

    let step_budget = 100_000usize.max(contents.len().div_ceil(1024).saturating_mul(16));
    for _ in 0..step_budget {
        let mut progressed = false;

        match sender.poll() {
            Action::WriteWire(bytes) => {
                let n = bytes.len();
                downstream.extend_from_slice(bytes);
                sender.wire_written(n);
                progressed = true;
            }
            Action::ReadFile { offset, max_len } => {
                let start = offset.get() as usize;
                let end = (start + max_len).min(contents.len());
                sender.submit_file(&contents[start..end]).unwrap();
                progressed = true;
            }
            Action::Event(Event::SessionCompleted) => {
                session_done = true;
                progressed = true;
            }
            Action::Event(_) => progressed = true,
            Action::Idle => {
                if !upstream.is_empty() {
                    let consumed = sender.submit_wire(&upstream).unwrap();
                    upstream.drain(..consumed);
                    progressed = true;
                }
            }
            other => panic!("unexpected sender action: {other:?}"),
        }

        match receiver.poll() {
            Action::WriteWire(bytes) => {
                let n = bytes.len();
                let should_drop = drop_first_zrpos
                    && !first_zrpos_dropped
                    && parse_first_header(bytes).frame() == Frame::ZRPOS;
                if should_drop {
                    first_zrpos_dropped = true;
                } else {
                    upstream.extend(receiver_wire_with_caps(
                        bytes,
                        receiver_caps,
                        &mut receiver_caps_sent,
                    ));
                }
                receiver.wire_written(n);
                if should_drop {
                    // Simulate the response timeout observed when the first
                    // ZRPOS is lost in transit. The retry must remain a ZRPOS
                    // for the active file, allowing the peer pair to finish.
                    receiver.timeout().unwrap();
                }
                progressed = true;
            }
            Action::WriteFile(bytes) => {
                persisted.extend_from_slice(bytes);
                let n = bytes.len();
                receiver.file_written(n).unwrap();
                progressed = true;
            }
            Action::Event(Event::FileCompleted) => {
                file_done = true;
                progressed = true;
            }
            Action::Event(_) => progressed = true,
            Action::Idle => {
                if !downstream.is_empty() {
                    let consumed = receiver.submit_wire(&downstream).unwrap();
                    downstream.drain(..consumed);
                    progressed = true;
                }
            }
            other => panic!("unexpected receiver action: {other:?}"),
        }

        if session_done && downstream.is_empty() && upstream.is_empty() {
            break;
        }
        if !progressed {
            break;
        }
    }

    assert!(file_done, "file transfer never completed (deadlock?)");
    assert!(session_done, "session never completed");
    assert_eq!(first_zrpos_dropped, drop_first_zrpos);
    assert_eq!(receiver_caps_sent, receiver_caps.is_some());
    persisted
}

#[test]
fn test_empty_file_transfer_completes() {
    // A zero-length file drives the sender to answer ZRPOS(0) with an
    // immediate ZEOF(0) and no data frame. The receiver, still in
    // FileBegin, must accept that completion instead of stalling. This is
    // zmodem2's own sender deadlocking its own receiver before the fix,
    // no external peer required.
    assert_eq!(run_full_transfer(b""), b"");
}

#[test]
fn test_nonempty_file_transfer_roundtrips() {
    // Guards the empty-file fix against regressing the ordinary path: a
    // multi-subpacket file must still arrive byte-for-byte.
    let contents: Vec<u8> = (0..5000u32).map(|i| (i % 251) as u8).collect();
    assert_eq!(run_full_transfer(&contents), contents);
}

#[test]
fn test_escape8_receiver_capability_fails_closed() {
    let mut sender = Sender::new().unwrap();
    drain_wire_sender(&mut sender);
    let caps = Zrinit::CANFDX | Zrinit::CANFC32 | Zrinit::ESC8;
    let zrinit = write_header(Header::new(
        Encoding::ZHEX,
        Frame::ZRINIT,
        [0, 0, 0, caps.bits()],
    ));
    assert_eq!(sender.submit_wire(&zrinit), Err(Error::UnsupportedFeature));
}

#[rstest]
#[case(4096, Encoding::ZBIN, false)]
#[case(4096, Encoding::ZBIN, true)]
#[case(4096, Encoding::ZBIN32, false)]
#[case(4096, Encoding::ZBIN32, true)]
#[case(8192, Encoding::ZBIN, false)]
#[case(8192, Encoding::ZBIN, true)]
#[case(8192, Encoding::ZBIN32, false)]
#[case(8192, Encoding::ZBIN32, true)]
fn test_receiver_accepts_gnu_large_subpackets(
    #[case] len: usize,
    #[case] encoding: Encoding,
    #[case] escape_ctrl: bool,
) {
    let mut receiver = Receiver::with_flow_control(0, true).unwrap();
    feed_receiver_zfile(&mut receiver);

    let payload: Vec<u8> = (0..len)
        .map(|index| u8::try_from(index % 251).unwrap())
        .collect();
    let mut wire = write_header(Header::new(encoding, Frame::ZDATA, [0; 4]));
    let mut subpacket = Buffer::<MAX_RECEIVE_SUBPACKET_ESCAPED>::new();
    let mut writer = BufferWriter::new(&mut subpacket);
    assert_eq!(
        write_subpacket_with_escape_options(
            &mut writer,
            encoding,
            SubpacketType::ZCRCE,
            &payload,
            escape_ctrl,
            false,
        ),
        Ok(Some(()))
    );
    wire.extend_from_slice(subpacket.as_ref());

    let mut input_offset = 0;
    let mut persisted = Vec::with_capacity(payload.len());
    while persisted.len() < payload.len() {
        match receiver.poll() {
            Action::WriteWire(bytes) => {
                let n = bytes.len();
                receiver.wire_written(n);
            }
            Action::WriteFile(bytes) => {
                persisted.extend_from_slice(bytes);
                let n = bytes.len();
                receiver.file_written(n).unwrap();
            }
            Action::Idle => {
                assert!(
                    input_offset < wire.len(),
                    "receiver stalled before the large subpacket"
                );
                let consumed = receiver.submit_wire(&wire[input_offset..]).unwrap();
                assert!(consumed > 0);
                input_offset += consumed;
            }
            other => panic!("unexpected receiver action: {other:?}"),
        }
    }
    assert_eq!(persisted, payload);
}

#[test]
fn test_empty_file_list_completes_the_session_handshake() {
    let mut sender = Sender::new().unwrap();
    let mut receiver = Receiver::new().unwrap();
    sender.finish().unwrap();

    let mut downstream = Vec::new();
    let mut upstream = Vec::new();
    let mut sender_done = false;
    let mut receiver_done = false;

    for _ in 0..1000 {
        let mut progressed = false;
        match sender.poll() {
            Action::WriteWire(bytes) => {
                downstream.extend_from_slice(bytes);
                let n = bytes.len();
                sender.wire_written(n);
                progressed = true;
            }
            Action::Event(Event::SessionCompleted) => {
                sender_done = true;
                progressed = true;
            }
            Action::Idle if !upstream.is_empty() => {
                let consumed = sender.submit_wire(&upstream).unwrap();
                upstream.drain(..consumed);
                progressed = true;
            }
            Action::Idle => {}
            other => panic!("unexpected sender action: {other:?}"),
        }

        match receiver.poll() {
            Action::WriteWire(bytes) => {
                upstream.extend_from_slice(bytes);
                let n = bytes.len();
                receiver.wire_written(n);
                progressed = true;
            }
            Action::Event(Event::SessionCompleted) => {
                receiver_done = true;
                progressed = true;
            }
            Action::Idle if !downstream.is_empty() => {
                let consumed = receiver.submit_wire(&downstream).unwrap();
                downstream.drain(..consumed);
                progressed = true;
            }
            Action::Idle => {}
            other => panic!("unexpected receiver action: {other:?}"),
        }

        if sender_done && receiver_done && downstream.is_empty() && upstream.is_empty() {
            break;
        }
        assert!(progressed, "empty file-list handshake deadlocked");
    }

    assert!(
        sender_done,
        "sender did not complete the empty file-list handshake"
    );
    assert!(
        receiver_done,
        "receiver did not complete the empty file-list handshake"
    );
}

#[test]
fn test_thirteen_mib_transfer_crosses_thousands_of_ack_windows() {
    // The real OpenSSH regression first stalled after 10,830 subpackets
    // (11,089,920 bytes). Cross that boundary with a payload containing every
    // raw and parity-marked flow-control value many times. This isolates the
    // vendor engines from the embedding application's timeout scheduler and
    // proves that long-window framing, escaping, CRC and ACK offsets remain
    // byte-exact beyond the observed failure point.
    const LEN: usize = 13 * 1024 * 1024 + 137;
    let contents: Vec<u8> = (0..LEN).map(|i| u8::try_from(i % 251).unwrap()).collect();
    assert_eq!(run_full_transfer(&contents), contents);
}

#[test]
fn test_first_zrpos_loss_recovers_full_transfer() {
    let contents: Vec<u8> = (0..5000u32).map(|i| (i % 251) as u8).collect();
    assert_eq!(
        run_full_transfer_with_first_zrpos_loss(&contents, true),
        contents
    );
}

#[test]
fn test_manual_accept_at_eof_completes() {
    // The maintainer's example: accepting a file at an offset that already
    // sits at EOF (the whole file is present locally) leaves the receiver
    // in FileBegin, and the sender replies with ZEOF and no data frame.
    let mut receiver = Receiver::new().unwrap();
    receiver.set_manual_file_accept(true);
    // feed_receiver_zfile announces a 123-byte file.
    feed_receiver_zfile(&mut receiver);

    receiver.accept_file_at(123).unwrap();
    // Drain the ZRPOS(123) the acceptance queued.
    drain_wire_receiver(&mut receiver);

    let zeof = write_header(Header::new(
        Encoding::ZBIN32,
        Frame::ZEOF,
        123u32.to_le_bytes(),
    ));
    assert!(receiver.submit_wire(&zeof).unwrap() > 0);
    assert_eq!(receiver.poll(), Action::Event(Event::FileCompleted));
}
