# OSC support matrix

Status reflects product behavior on 2026-07-11, not parser match arms alone.

| OSC | Status | Product behavior / remaining work |
|---|---|---|
| 0/1/2 | supported | title/icon metadata |
| 4/104 | partial | set/query/reset configurable palette 0–15; 16–255 deferred |
| 7 | supported | typed cwd/remote context with host policy |
| 8 | supported | URI and optional `id=` preserved through JSON/protobuf/Dart |
| 9, 9;4 | supported subset | notification and progress |
| 9;9 | unsupported | cwd compatibility adapter deferred |
| 10/11/12 | supported | dynamic foreground/background/cursor set/query |
| 21 | safe unsupported | consumed without title side effect; Kitty colors deferred |
| 22 | safe unsupported | consumed without title side effect; pointer UI deferred |
| 23 | legacy partial | retained title-stack pop; interoperability review pending |
| 52 | supported text subset | capability policy and size validation; binary/MIME deferred |
| 66/72/99 | unsupported | Kitty extensions deferred |
| 110/111/112 | supported | restore configured session/profile baseline |
| 133 A–D | partial | typed shell lifecycle and zones; malformed-order corpus incomplete |
| 633 | unsupported | VS Code adapter deferred |
| 777 | supported subset | notification |
| 934 | private supported | Ianvs/par-term named progress; see `ianvs_osc934.md` |
| 1337 | supported subset | cwd, remote host, user var, badge, inline image |
| 3008 | unsupported | UAPI context deferred |

Unsupported protocols must be no-op without state mutation. Host actions remain
policy-gated. JSON compatibility and additive protobuf evolution are required.
