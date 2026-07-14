# iTerm2 OSC 1337 UnicodeVersion

Ianvs supports iTerm2's terminal-local Unicode cell-width compatibility
control:

```text
OSC 1337 ; UnicodeVersion=8 ST
OSC 1337 ; UnicodeVersion=9 ST
OSC 1337 ; UnicodeVersion=push[ <label>] ST
OSC 1337 ; UnicodeVersion=pop[ <label>] ST
```

Both BEL and `ESC \\` terminate the control string. The command has no reply
and grants no host action, disclosure, filesystem access, profile persistence,
or external side effect.

## Width contract

- `8` uses the official Unicode 8.0 East Asian Width `W`, `F`, and `A` tables.
  With the default narrow ambiguous-width setting, plain U+2615 HOT BEVERAGE
  occupies one terminal cell; the CJK ambiguous-width setting makes it two.
- `9` selects modern emoji widths. As in current iTerm2, Unicode 9 and later
  compatibility uses the current generated width table; plain U+2615 occupies
  two terminal cells.
- CJK wide/full-width characters remain two cells in both modes.
- An explicit emoji-presentation selector (VS16) can still request a two-cell
  grapheme in Unicode 8. Plain flag and ZWJ emoji clusters otherwise use their
  base-character width in the Unicode 8 compatibility path.
- Private-use codepoints remain one cell even in CJK mode. This is Ianvs's
  established Nerd Font/Powerline alignment override and is deliberately
  applied before Unicode's ambiguous private-use ranges.

The setting changes actual cell allocation, wide-character spacers, style-run
columns, wrapping and cursor advancement. It is not merely parser metadata.

## Push, pop, and lifecycle

`push` saves the current version. `pop` removes the newest entry and restores
its saved version. A labeled pop discards newer entries until it finds the
matching label, then restores that entry; when no label matches, the stack is
emptied and the current version is unchanged. This matches iTerm2's source
behavior.

Labels are non-empty printable ASCII, at most 128 bytes. The stack holds at
most 64 entries. A push at the limit is ignored so existing recovery entries
are never discarded. Versions other than exact `8` and `9`, empty/oversized/
non-ASCII labels, controls, case variants, and near-match prefixes are bounded
no-ops.

The current version and stack are session-local and captured by terminal
snapshots, so transcript resize replay remains deterministic. DECSC saves the
current version and DECRC restores it with the cursor. RIS preserves the
session-specific current version and push/pop stack but clears the saved cursor
slot; iTerm2 Clear Buffer likewise invalidates the saved cursor version.

## Policy and evidence

The streaming gate classifies the command as `Appearance`. Xterm-compatible
profiles accept it; VT220 profiles and an explicit Appearance denial consume it
without changing layout. No Dart or Protobuf field was added because existing
frame rows, style-run terminal columns and cursor coordinates already express
the result.

Automated coverage includes Unicode table helpers, plain and composed emoji,
CJK and private-use cases, BEL/ST and every-byte fragmentation, malformed and
bounded stack operations, saved cursor, RIS, snapshots, shared byte corpus,
real PTY, resize replay, VT220 denial, and macOS application continued input.
The final verifier-built application also passed a cold-launch Computer Use
gate: a real child rendered the one/two/one-cell U8/U9/labeled-pop markers and
accepted continued shell input before clean exit.

The contract was compared with the official
[iTerm2 escape-code documentation](https://iterm2.com/documentation-escape-codes.html),
iTerm2 source paths `VT100Terminal.m`, `iTermCharacterWidth.c`, `ScreenChar.m`,
`VT100ScreenMutableState+TerminalDelegate.m`, and `PTYSession.m`, plus the
official Unicode
[8.0 EastAsianWidth data](https://www.unicode.org/Public/8.0.0/ucd/EastAsianWidth.txt)
and
[9.0 EastAsianWidth data](https://www.unicode.org/Public/9.0.0/ucd/EastAsianWidth.txt).
