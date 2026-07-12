# iTerm2 OSC 1337 CursorShape and dynamic cursor contract

## Sources and grammar

Ianvs follows the current iTerm2 proprietary escape-code documentation for:

```text
OSC 1337 ; CursorShape=0 ST  # block
OSC 1337 ; CursorShape=1 ST  # vertical bar / beam
OSC 1337 ; CursorShape=2 ST  # underline
```

It also exports the existing xterm/DEC `DECSCUSR` parser state:

```text
CSI 0 SP q / CSI 1 SP q  blinking block
CSI 2 SP q                 steady block
CSI 3 SP q                 blinking underline
CSI 4 SP q                 steady underline
CSI 5 SP q                 blinking beam
CSI 6 SP q                 steady beam
```

Primary references:

- <https://iterm2.com/documentation-escape-codes.html#set-cursor-shape>
- <https://www.invisible-island.net/xterm/ctlseqs/ctlseqs.html>

## State and precedence

The configured profile remains the fallback. OSC 1337 changes shape only, so
an absent protocol blink override continues to use the profile's blink choice.
DECSCUSR explicitly owns both shape and blink. A later OSC shape change preserves
an already-explicit DECSCUSR blink value. `Ps=0` remains xterm-compatible
blinking block. RIS/new-session state and legacy frames with no cursor override
fields return control to the profile.

Cursor state follows existing save/restore behavior across alternate-screen
entry and exit. Invalid OSC values, multi-digit aliases such as `01`, and
unknown DECSCUSR values are consumed without mutation.

## Wire and renderer

`TerminalCursor` adds optional JSON/protobuf fields:

```text
shape: block | underline | beam   # protobuf tag 4
blink: bool                       # protobuf tag 5
```

Missing or unknown shape fields and a missing blink field preserve legacy
profile behavior. Cursor-only changes produce delta frames even when no cell is
dirty. The Flutter viewport resolves each field independently, so an OSC shape
can override the profile shape without changing its blink timer.

## Policy and security

OSC CursorShape is appearance-only and uses the existing 4 KiB streaming
appearance budget. It has no input, pointer, clipboard, file, process, or host
action authority. Fine-grained appearance denial and the VT220 profile consume
the OSC without state changes. The historical legacy security switch keeps its
existing mapping. Diagnostics contain only counters and categories.

DECSCUSR is a CSI presentation sequence rather than an OSC host action. Its
handler no longer mutates warning-bell volume; that previous coupling was a
confirmed unrelated side effect.

## Verification contract

- exact OSC values, malformed values, BEL/ST and every byte split;
- appearance/metadata policy independence and VT220 OSC denial;
- DECSCUSR 0–6, unknown-value no-op and no warning-bell mutation;
- alternate-screen save/restore and RIS reset;
- cursor-only native delta plus JSON/protobuf parity;
- missing-field Dart compatibility and cursor-only delta apply/clear;
- profile-shape override and protocol blink behavior in Flutter;
- real PTY transitions from OSC beam to steady CSI underline;
- shared byte corpus and semantic probe.
