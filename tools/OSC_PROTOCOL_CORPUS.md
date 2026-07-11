# OSC protocol corpus and cross-terminal probes

The shared OSC corpus is stored in two mirrored locations so native and Dart
validation can consume the same byte-level cases:

- `native/core/tests/fixtures/osc/osc_protocol_corpus_v1.json`
- `packages/ianvs_terminal/test/fixtures/osc/osc_protocol_corpus_v1.json`

`chunks_hex` preserves parser chunk boundaries. The oversized case uses a
prefix/repeated-byte/suffix recipe so validation does not allocate a large
payload. Every case records its terminator, semantic intent, expected state
effect, reply behavior, and the invariant that malformed input must not crash.

Validate the corpus and its Dart mirror:

```bash
python3 tools/validate_osc_protocol_corpus.py
cd packages/ianvs_terminal
flutter test test/osc_protocol_corpus_test.dart
```

The repository verification gate runs both the corpus validator and the full
Dart test suite. It also runs format, strict Clippy, and tests directly in the
vendored terminal crate; compiling it only as a dependency is not sufficient.

## Cross-terminal semantic probes

List the deterministic probes or inspect escaped bytes without changing the
active terminal:

```bash
python3 tools/osc_semantic_probe.py --list
python3 tools/osc_semantic_probe.py --intent all --format escaped
python3 tools/osc_semantic_probe.py --intent all --format json
```

Raw mode intentionally writes control bytes to the active terminal:

```bash
python3 tools/osc_semantic_probe.py --intent title --format raw
python3 tools/osc_semantic_probe.py --intent hyperlink_with_id --format raw
```

Use raw mode only in a disposable test shell. Clipboard probes can request host
clipboard access, notification probes can request a system notification, and a
clipboard query can cause the terminal to write a response into the PTY. These
actions remain subject to the terminal's policy and should never be treated as
pre-authorized.

Run each intent in at least one reference terminal such as iTerm2, WezTerm,
Windows Terminal, Ghostty, Kitty, or VS Code, then record:

| Terminal | Intent | Consumed | Raw bytes echoed | Host action | Reply | ID/metadata retained | Security default |
|---|---|---:|---:|---|---|---:|---|
| Example | `hyperlink_with_id` | yes/no | yes/no | none/request/result | bytes or none | yes/no | allow/ask/deny |

Pixel equality is not required. The comparison is semantic: whether the
sequence is consumed, whether unsupported bytes leak into the display, whether
a host action is requested, whether a reply is produced, whether protocol
identity survives, and which security default applies.
