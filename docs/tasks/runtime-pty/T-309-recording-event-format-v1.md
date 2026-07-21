# T-309 Recording Event Format V1

## Goal

Start handoff Iteration 03 with one stable contract: define a versioned deterministic recording
metadata/event format with explicit input privacy and structured decode failures.

## Scope

- Define Recording Metadata with schema version, session id, UTC creation time and input policy.
- Define SessionStarted, PtyOutput, UserInput, Resize and SessionExited event records.
- Encode raw bytes as Base64 and order events with contiguous sequence plus monotonic offset.
- Implement a canonical newline-delimited JSON codec.
- Reject truncated, malformed, unsupported, mixed-session and out-of-order recordings with stable
  error codes and line numbers.
- Add a fixed v1 fixture and unit coverage for deterministic round trips and privacy behavior.

## Non-goals

- Do not connect a live recorder to the PTY reader or runtime controller.
- Do not implement ReplayBackend, playback timing, file persistence or product UI.
- Do not treat existing viewport `InstantReplayStore` frames as raw PTY output.
- Do not add checkpoints, seek, speed control, graphics asset bundles or Host Request/Response
  recording.
- Do not change Frame JSON/Protobuf, FFI or native Session behavior.

## Files In Scope

- `packages/ianvs_terminal/lib/ianvs_terminal.dart`
- `packages/ianvs_terminal/lib/src/recording/terminal_recording.dart`
- `packages/ianvs_terminal/test/fixtures/recording/basic_v1.ndjson`
- `packages/ianvs_terminal/test/terminal_recording_codec_test.dart`
- `docs/recording/FORMAT_V1.md`
- `docs/tasks/runtime-pty/T-309-recording-event-format-v1.md`

## Functional Acceptance

- The v1 fixture decodes and canonical re-encoding is byte-stable.
- All five MVP event kinds preserve session, sequence and monotonic offset.
- Additive unknown fields do not break a v1 reader.
- Unsupported version, truncated JSON, sequence gaps and decreasing timestamps produce structured
  errors.
- Redacted input stores its byte length but never serializes the original bytes.
- Recorded input round trips exact bytes only under the explicit `record` metadata policy.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
cd packages/ianvs_terminal
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test test/terminal_recording_codec_test.dart
flutter test

cd ../..
dart test test/docs_contract_test.dart
make verify
```

## Result

- Added the public v1 Recording Metadata/Event model and canonical NDJSON codec.
- Added stable format error codes for malformed JSON/records, unsupported versions/kinds,
  cross-session data, sequence gaps, decreasing monotonic offsets and invalid payloads.
- Added explicit `record` and `redact` input policies. The redacted form stores only byte length;
  the format documentation also records that PTY output can itself contain sensitive data.
- Added the fixed five-event `basic_v1.ndjson` fixture. Seven focused codec/privacy tests pass,
  and `flutter analyze` reports no issues.
- The complete `ianvs_terminal` package suite passed 492 tests with 1 intentional skip;
  documentation contracts passed 12 tests.
- The final `make verify` passed the complete repository gate: vendored Rust 1,733 tests with 1
  ignored, native core 116 unit + 512 session + 3 `vttest` regressions, `ianvs_pty` 22 tests,
  example 1,063 tests, macOS smoke 4 tests, real PTY 46 tests and Runner XCTest 16 tests.
- The verification benchmark was written to `build/bench-results-ci/20260721T030204Z`; all six
  correctness hashes are byte-identical to the T-308 closeout baseline.
- T-309 is closed. Live capture remains the separately scoped T-310 follow-up.

## Risks / Follow-ups

- Raw PTY output is consumed inside native `TerminalSession`; it is not currently observable on
  the Dart `PtySessionBackend` interface. T-310 must add a bounded output-recording seam without
  confusing render Frames with PTY bytes.
- ReplayBackend remains unimplemented and must be a separate slice after live event capture is
  deterministic.
