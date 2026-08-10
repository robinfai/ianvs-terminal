# Ianvs local changes

This directory vendors `zmodem2` 0.7.2 under its original MIT OR Apache-2.0
license. The reproducible upstream baseline is:

- upstream commit: `fc6b0fd9bbf5348b2fac00ecb22bc9e40f4251f5`
- crates.io `zmodem2-0.7.2.crate` SHA-256:
  `a2ac5e85856f619f7d6c15cbf915448147607f31d028f54b08a0a3ea7ff632e5`

Ianvs adds sender-side handling for the receiver's `ZRINIT.ESCCTL`
capability: binary headers, file metadata, data and CRC bytes quote the
requested control characters while preserving ZMODEM framing and hex-header
trailers. A peer that requires `ZRINIT.ESC8` is rejected with
`UnsupportedFeature`; ZMODEM has no reversible 7-bit ZDLE representation for
every possible octet, so the engine fails closed instead of claiming partial
8-bit quoting support.

The local tests `test_escape_ctrl_quotes_all_control_bytes` and
`test_sender_honours_escape_ctrl_from_zrinit` cover the added behavior. Ianvs'
real OpenSSH fixture additionally exercises GNU `lrzsz` with `rz -bye`.

The fork also exposes complete batch control behavior that the native session
depends on. Receivers can explicitly decline an offered file with `ZSKIP`;
senders surface that decision as `Event::FileSkipped`, advance to the next
file without counting it as completed, and keep final batch statistics
separate. Vendor unit coverage includes
`test_manual_accept_can_skip_a_file` and `test_sender_skips_file_on_zskip`;
native core coverage for continuing a multi-file batch and preserving its
statistics is `peer_skip_emits_file_event_continues_batch_and_reports_statistics`.
The Docker/OpenSSH gate transfers two distinct files in each direction so
post-first-file `ZFILE`/completion behavior is exercised against GNU lrzsz.

Raw peer cancellation is detected across every parser state, including split
input chunks and CRC/header resynchronization. A stateful `CancelDetector`
recognizes the protocol's run of bare CAN bytes while explicitly excluding
ZDLE-escaped CAN payload data. The regression tests
`test_bare_cancel_sequence_aborts_across_submit_chunks`,
`test_escaped_can_payload_is_not_mistaken_for_cancel`, and
`test_bare_cancel_run_crosses_crc_resync_and_submit_boundaries` cover the
public cancellation behavior.

Ianvs also carries ZFILE modification-time support. `FileInfo` exposes optional
Unix-second mtime metadata; senders encode it as the standard octal field and
receivers parse it without treating a missing or zero value as the Unix epoch.
The core uses that metadata to preserve mtime in both transfer directions.

Ianvs also makes the upstream `no_std` claim mechanically enforceable: `hex`
has default features disabled and `thiserror` is optional behind the `std`
feature. CI compiles the library with `--no-default-features` for the real
`thumbv7em-none-eabihf` target in addition to running host-side tests.

The receive path also carries compatibility fixes for GNU `lrzsz` and noisy
PTYs: ZHEX framing and bodies ignore parity, ZHEX data headers select binary
CRC16 subpackets, and LF/CRLF trailers are consumed incrementally without
swallowing payload control bytes. Repeated ZFILE metadata for an active file is
CRC-checked and must match the original raw name, size and modification time
before it is answered with the current ZRPOS; a mismatched identity aborts
instead of appending another file's payload to the active staging file. No
second file offer is emitted for a valid retransmission. Closing ZFIN trailers
are consumed exactly on both sides so subsequent shell output remains outside
the protocol stream.

Raw XON/XOFF bytes, including parity-marked variants, are also ignored between
ZDLE and its encoded continuation across submit boundaries. Receiver timeouts
discard incomplete metadata or data subpackets and request a bounded replay,
and sender timeouts retransmit the closing ZFIN with the same finite retry
budget used by the other acknowledged phases.

Both state machines expose a monotonic peer-progress epoch that advances only
after a CRC-valid header is accepted. The native session uses this marker to
rearm short retransmission timers without allowing arbitrary PTY noise to
extend the independent hard no-progress deadline.

The receiver also accepts GNU lrzsz's optional 4 KiB and 8 KiB starting
subpackets (including CRC16, CRC32 and ESCCTL streams), while its conservative
default flow-control advertisement remains 1 KiB. A ZFIN in
the initial session phase now completes an intentionally empty file list.
