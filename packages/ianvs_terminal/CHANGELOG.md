# Changelog

## 2.0.0 - 2026-08-11

### Breaking

- `TerminalFrameDiff.fromProtobufBytes` moved out of the terminal domain so
  generated protobuf transport code no longer flows into domain models.
  Replace calls with `const TerminalProtobufFrameCodec().decode(bytes)`.
- `LegacyTerminalFrameDiffProtobuf.fromProtobufBytes(bytes)` is available as a
  deprecated transition facade and will be removed in the next major version.

### Architecture

- Frame validation and wire-compatibility policies now live in neutral
  contracts shared by the domain and transport adapters.
- Runtime frame and packet decoders obtain domain frames only through
  protobuf transport codecs.
