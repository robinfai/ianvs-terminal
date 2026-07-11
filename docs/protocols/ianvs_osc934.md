# Ianvs OSC 934

OSC 934 is an Ianvs/par-term private extension for named progress state. It is
not advertised as an xterm, Kitty, iTerm2, or ECMA-48 standard.

Current implementation accepts the existing named progress payload and emits a
typed progress event. Consumers must feature-detect support; `$TERM` alone is
not a capability claim. Unknown or malformed payloads are ignored, identifiers
are scoped to the terminal session, and the sequence grants no host permission.

Protocol version for the existing wire shape: `ianvs-osc934/1`.

Future incompatible semantics require a new version/capability value. They must
not silently reinterpret version 1 payloads.
