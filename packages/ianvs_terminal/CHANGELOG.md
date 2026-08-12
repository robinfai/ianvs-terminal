# Changelog

## 2.0.0 - 2026-08-11

### Breaking

- Removed the predecessor xterm facade and public frame-codec facade. Session
  creation and rendering now enter through the current runtime controller and
  versioned frame-packet contract only.
- Removed the predecessor JSON/raw-Protobuf frame paths, compatibility
  preference, contextless clipboard/pre-close callbacks and split runtime,
  ZMODEM and deferred-failure streams.

### Architecture

- `TerminalRuntimeController.runtimeSignals` is the single ordered public
  stream for session, ZMODEM and deferred-write-failure signals.
- SessionConfig v1, requests, diagnostics and frame packets are exact current
  contracts: missing, unknown, case-aliased and unsupported shapes fail closed
  in Dart, Rust and the C FFI.
- Frame normalization remains transport-neutral; the runtime coordinator has
  one current Protobuf frame-packet route and no downgrade chain.
- Architecture tests parse Dart directives with the analyzer and enforce
  validated owner/part relationships plus direct and transitive domain,
  contract, runtime-decoder, and global internal composition boundaries with
  dependency-path diagnostics.
