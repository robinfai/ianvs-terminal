# iTerm2 OSC 1337 annotation contract

Ianvs supports the visible and hidden iTerm2 annotation forms documented by
the [official proprietary escape-code reference](https://iterm2.com/documentation-escape-codes.html):

```text
OSC 1337 ; AddAnnotation=[message] ST
OSC 1337 ; AddAnnotation=[length]|[message] ST
OSC 1337 ; AddAnnotation=[message]|[length]|[x]|[y] ST

OSC 1337 ; AddHiddenAnnotation=[message] ST
OSC 1337 ; AddHiddenAnnotation=[length]|[message] ST
OSC 1337 ; AddHiddenAnnotation=[message]|[length]|[x]|[y] ST
```

BEL and ST are accepted terminators. The legacy `AddNote` and
`AddHiddenNote` names are aliases. A visible annotation opens the annotation
sheet immediately only when its session is the active pane. A hidden annotation
updates the bounded session badge/list without opening UI. Inactive-pane visible
annotations are retained but do not steal focus.

## Range semantics

- The one-part form starts at the cursor and uses iTerm2's default length of
  `columns - cursor column - 1`.
- The two-part form is `length|message` and starts at the cursor.
- The four-part form is `message|length|x|y`. Coordinates are zero-based and
  clamped to the current grid, matching iTerm2's implementation.
- Length is a half-open cell count. Ranges may wrap across rows, but must fit in
  the current screen. Zero-length, malformed, overflowing, or off-screen ranges
  are ignored.
- The native event carries global absolute coordinates and retained-buffer
  coordinates. It also resolves the selected terminal text after processing the
  same PTY read. The product retries selection extraction on at most 16 later
  frames when an OSC boundary arrives before its target text.
- Alternate-screen annotations remain zero-based against the transient grid;
  discarded alternate-screen rows never shift their exported coordinates.

Annotations reuse Ianvs's existing per-session annotation list, badge, removal,
live-sheet updates, and reset/close cleanup behavior. At most 80 product
annotations are retained.
Annotation messages are capped at 1,024 Unicode scalar values; ranges are capped
at 4,096 cells. The complete OSC is also subject to the 16 KiB shell-metadata
ingress ceiling.

## Safety and compatibility

Annotations are terminal-local metadata, not host actions. They cannot access
files, clipboard data, URLs, processes, profiles, notifications, or operating-
system UI. Metadata capability denial and VT220 profiles consume the command
without emitting an annotation, while subsequent printable text remains normal
terminal output.

Diagnostics retain only source, visibility, range, and size/count metadata.
They never copy the note or selected terminal text. The Dart event is additive
JSON; no frame or protobuf schema changes are required, and no reply is sent to
the child process.

`Block` / `UpdateBlock` are not claimed by this contract. Accurate folding
requires non-contiguous retained-row virtualization across rendering, scrolling,
selection, search, graphics, resize, and replay. They remain a dedicated future
foundation phase rather than being approximated with blank rows or metadata-
only events.
