# Kitty OSC 22 mouse-pointer shapes

Status: supported.

Normative upstream syntax: [Kitty mouse pointer shapes](https://sw.kovidgoyal.net/kitty/pointer-shapes/).

## Wire grammar

Ianvs accepts the following BEL- or ST-terminated forms:

```text
OSC 22 ; shape ST
OSC 22 ; =shape ST
OSC 22 ; >shape,shape ST
OSC 22 ; < ST
OSC 22 ; ?name,name ST
```

An omitted operation is `=`. Direct set replaces the current top entry or
creates it when the active stack is empty. An empty direct value selects no
protocol-specified shape. `>` pushes every valid comma-separated shape in
order, and `<` pops exactly one entry while ignoring any supplied names.

Queries return one comma-separated answer per name in one `OSC 22` reply:

- `__current__`: the active stack top or `0`;
- `__default__`: `text`, the normal Ianvs terminal-surface pointer;
- `__grabbed__`: `default`, the fallback while mouse reporting is active;
- a canonical supported name: `1`;
- an unknown or malformed name: `0`.

## Shape and stack support

All 30 canonical Kitty/CSS names are supported:

```text
alias cell copy crosshair default e-resize ew-resize grab grabbing help move
n-resize ne-resize nesw-resize no-drop not-allowed ns-resize nw-resize
nwse-resize pointer progress s-resize se-resize sw-resize text vertical-text
w-resize wait zoom-in zoom-out
```

Ianvs also accepts Kitty's practical xterm/X11 set aliases, including
`left_ptr`, `xterm`, `hand2`, `watch`, resize aliases and drag-and-drop aliases.
Queries advertise only the canonical names, matching the published protocol.

Primary and alternate screens own independent 32-entry stacks, exceeding the
required minimum depth of 16. Pushing at capacity evicts the oldest entry.
Screen switches reveal the target screen's prior top without copying state.
Snapshot capture/restore retains both stacks; RIS empties both.

## Product mapping

The native frame exports the canonical active shape through additive JSON
`pointer_shape` and protobuf field 23. Dart validates it as
`TerminalPointerShape`, and the Flutter viewport maps every value to its
corresponding `SystemMouseCursors` shape. The requested shape applies whether
mouse reporting is off or active. With no requested shape, Ianvs uses text for
normal terminal interaction and the basic arrow while mouse reporting is
active. Link hover may temporarily use the click pointer, as permitted by the
protocol.

## Bounds, policy and evidence

OSC 22 remains appearance-only: it cannot open a URL, move the host pointer,
capture input or authorize another host action. The existing 4 KiB appearance
admission gate applies before dispatch; replies are capped at 4 KiB; individual
names are capped at 64 ASCII bytes and restricted to `a-z0-9_-`. Appearance
policy denial and VT220 consume the sequence without mutation or reply.

Automated evidence covers all names, direct set, reset, push/pop, overflow
eviction, aliases, unknown values, queries, BEL/ST, every byte split,
primary/alternate screens, snapshot/RIS, appearance denial, shared corpus,
semantic probes, native real PTY, VT220, JSON/protobuf parity, Dart validation,
all Flutter cursor mappings and macOS real PTY.
