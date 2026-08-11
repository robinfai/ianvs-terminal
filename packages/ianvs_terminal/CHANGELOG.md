# Changelog

## 2.0.0 - 2026-08-11

### Breaking

- `TerminalFrameDiff.fromProtobufBytes` moved out of the terminal domain so
  generated protobuf transport code no longer flows into domain models.
  Replace calls with `const TerminalProtobufFrameCodec().decode(bytes)`.
- `LegacyTerminalFrameDiffProtobuf.fromProtobufBytes(bytes)` is available as a
  deprecated transition facade and will be removed in the next major version.

### Architecture

- Added the additive `TerminalRuntimeController.runtimeSignals` stream. It
  wraps the existing session, ZMODEM, and deferred-write-failure payloads with
  a controller-wide sequence and session epoch while preserving the 2.x event
  streams unchanged.
- Frame validation, wire compatibility, and frame normalization now live in
  neutral contracts shared by JSON/domain and protobuf adapters.
- Runtime frame and packet decoders depend only on decode ports; the frame
  transport coordinator is the explicit composition boundary for concrete
  JSON and protobuf adapters.
- Architecture tests parse Dart directives with the analyzer and enforce
  validated owner/part relationships plus direct and transitive domain,
  contract, runtime-decoder, and global internal composition boundaries with
  dependency-path diagnostics.
