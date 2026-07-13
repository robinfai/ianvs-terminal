# iTerm2 OSC 1337 clipboard-write contract

Ianvs supports both iTerm2 text clipboard-write forms documented by the
[official proprietary escape-code reference](https://iterm2.com/documentation-escape-codes.html):

```text
OSC 1337 ; CopyToClipboard=[pasteboard] ST
<terminal output to copy>
OSC 1337 ; EndCopy ST

OSC 1337 ; Copy=:[base64 UTF-8 text] ST
```

BEL and ST terminate every OSC command. The streaming form copies the exact
bounded byte stream received from the PTY between the two commands while that
same output continues through normal terminal rendering. Consequently, PTY
output processing such as `LF` to `CRLF` translation is reflected in the copied
text. Interior control sequences are retained rather than reconstructed from
rendered cells.

The direct `Copy=:` form decodes one Base64 UTF-8 value and targets the general
clipboard. Invalid Base64 and invalid UTF-8 never reach the system clipboard.

## Pasteboard targets

- An empty value, `rule`, `ruler`, `general`, `clipboard`, and unknown bounded
  names use the general clipboard, matching iTerm2's default behavior.
- `find` uses the macOS find pasteboard.
- `font` uses the macOS font pasteboard.
- Named pasteboards are macOS-only. A platform without the named bridge fails
  closed instead of silently writing to the wrong clipboard.

Starting a new streaming capture replaces any unfinished capture. A stray
`EndCopy` is ignored. RIS and session close discard unfinished data.

## Bounds and authorization

- `CopyToClipboard`, `EndCopy`, and `Copy=:` are classified as clipboard-write
  capability, not generic OSC or file transfer.
- The complete direct OSC has a 4 MiB wire-ingress limit. Decoded text also
  passes the existing 4 MiB OSC 52 text limit.
- Streaming capture retains at most 4 MiB of received bytes. An oversized
  capture is discarded and surfaces as invalid payload when `EndCopy` arrives.
- VT220 profiles and explicit clipboard-write capability denial consume the
  commands without producing a host event. The text between denied streaming
  commands remains ordinary visible terminal output.
- The native layer emits a typed `clipboard_copy` request tagged
  `protocol=iterm1337`; it never writes a pasteboard directly. Dart reuses the
  existing OSC 52 allow/profile/ask/deny policy, bounded preview, stale-session
  checks, and product feedback before invoking the platform bridge.

Diagnostics retain protocol, mode, selection, and encoded byte counts only;
clipboard text is not copied into diagnostic payloads. The protocol sends no
reply to the child process.
