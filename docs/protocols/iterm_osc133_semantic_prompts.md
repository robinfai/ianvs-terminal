# iTerm2 OSC 133 semantic prompts and lifecycle identifiers

Ianvs accepts the modern iTerm2 shell-integration grammar:

```text
OSC 133 ; A|N|P [ ; k=i|s|c|r ] [ ; aid=<opaque-id> ] ST
OSC 133 ; B [ ; aid=<opaque-id> ] ST
OSC 133 ; C [ ; <command> ] [ ; aid=<opaque-id> ] ST
OSC 133 ; D [ ; <exit-code> ] [ ; aid=<opaque-id> ] ST
```

`A` and `N` carry fresh-line semantics; `P` does not. Empty, absent, or unknown
`k` values normalize to `initial`; `s`, `c`, and `r` become secondary,
continuation, and right prompts. Non-initial prompts emit typed metadata but do
not mutate the command lifecycle or create another product navigation mark.

`aid` is an opaque correlation value, not authority. It is limited to 256
UTF-8 bytes, rejects controls, is never executed, and only selects the current
or a suspended shell lifecycle. An unknown `aid` on `D` has no side effect. A
matching outer `aid` closes intervening nested lifecycles and reports the
bounded implicit-close count. Legacy integrations without `aid` retain the
existing conservative consecutive-`D` recovery behavior.

The event bridge adds optional `promptKind`, `aid`, `parentAid`, `freshLine`,
and `implicitClosedCount` fields. JSON and protobuf additions are backwards
compatible; old readers continue to receive the original event fields.

The behavior follows the current iTerm2 `VT100Terminal.m` implementation and
its `k=`/`aid=` end-to-end change (`131b9c60`, reviewed 2026-07-13). Host-side
fresh-line rendering remains terminal-owned: Ianvs records the semantic flag
without inserting bytes into the PTY stream.
