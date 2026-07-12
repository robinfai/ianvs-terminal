# Kitty OSC 72 drag-and-drop target subset

Ianvs implements a bounded, macOS target-side subset of Kitty's OSC 72 drag
and drop protocol. The normative source is the
[Kitty drag-and-drop protocol](https://sw.kovidgoyal.net/kitty/dnd-protocol/),
added in Kitty 0.47.0.

## Supported target flow

- `t=q` receives a correlated `t=q` response. Its optional payload is
  `drop=1:offer=0`, explicitly advertising the target-only product scope.
- `t=a` registers the active pane as a native macOS drop destination. `t=A`
  unregisters it. The optional `i` multiplexer identity is echoed in events.
- An empty MIME list defaults to `text/plain` and `text/uri-list`. Requested
  private MIME types map to same-named macOS pasteboard types.
- Native enter/update events produce `t=m` with cell and pixel coordinates,
  available MIME types and copy/move operations. The OS reports acceptance only
  after the child replies with `t=m:o=1|2` and an allowed MIME list.
- A user drop produces `t=M`. Indexed `t=r:x=...` requests receive Base64 data
  in packets whose encoded payload is at most 4 KiB, followed by an empty
  `m=0` packet. Completion/cancel releases all cached pasteboard data.
- Malformed, expired or out-of-range requests receive bounded POSIX error
  responses. RIS, session exit, `t=A`, or an error removes product state.

Only the active pane can own the native target. Switching panes re-registers
the target from that pane's last accepted `t=a` state; background output cannot
silently take over the window's drop destination.

## Security and resource limits

OSC 72 parsing is a separate capability and defaults off in the reusable
terminal package. The macOS example enables it only because it installs the
native bridge. VT220 and the legacy insecure-sequence switch deny it.

- metadata: 1 KiB per packet;
- encoded payload: 4 KiB per packet;
- MIME list: 64 entries, 256 UTF-8 bytes each;
- cached user-drop data: 64 MiB total;
- native-to-Dart reads: 3,072 raw bytes, producing at most 4,096 Base64 bytes;
- all event queues retain payload-aware byte accounting;
- diagnostics and errors never log dropped data or file contents.

Data exists only after a user-driven OS drop. A child escape sequence cannot
open Finder, synthesize a drag, choose a host path or read an arbitrary file.

## Deliberately unsupported

Outgoing/source drags (`t=o/p/P/e/E/k`), drag images, pre-sent source data,
remote-machine file reads, URI sub-item reads, directory handles and recursive
file transfer are not authorized. Remote `x/y/Y` data requests return an error
instead of being reinterpreted as local MIME reads. Since Ianvs cannot start a
source drag in this subset, a malicious program cannot create and drop its own
file offer back into the same window.

This is not advertised as full bidirectional OSC 72. Expanding it requires a
separate UX and security review for source ownership, same-window provenance,
remote filesystem permission, symlinks, directory traversal, cancellation and
large-transfer quotas.

## Evidence

Automated evidence covers capability default/VT220 denial, 32-bit metadata,
BEL/ST and every byte split, exact/oversized payloads, mirrored corpus and
semantic query probes, native real PTY delivery, typed Dart routing, active-pane
ownership, MIME defaults/bounds, cell/pixel geometry, OS decision mapping,
Base64 chunk/end markers, error cleanup, URI-list encoding, native read bounds,
macOS Debug compilation, RunnerTests and an application-level real-PTY
query/register/unregister lifecycle. The repository-wide gate passed with
1,628 vendored tests, 459 native session tests, 922 grouped example tests, 125
complete Widget tests, four macOS smoke tests, 22 real-PTY tests and 12 native
RunnerTests. Computer Use visibly confirmed the production child query and
exact `drop=1:offer=0` response; the tool cannot hold a Finder drag across the
asynchronous negotiation round trip, so native cursor feedback is not claimed
as visual evidence.
