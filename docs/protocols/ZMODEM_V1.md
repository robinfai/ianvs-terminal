# ZMODEM transfer v1

ZMODEM v1 adds opt-in file receive and send to a live terminal session. The
native session owns protocol detection, wire bytes and file handles. Transfer
payload never crosses the Dart boundary and is never fed to the VT parser,
scrollback, terminal frames or session recording.

## Flow

1. The native reader validates an initial ZMODEM header before switching the
   session from terminal mode to transfer mode.
2. Native emits metadata-only events. The product asks the user to choose a
   receive directory or source files.
3. Dart responds with one of the session commands below, correlated by the
   opaque decimal-string `transferId`.
4. Native runs the transfer directly against the PTY writer, emits bounded
   progress events and restores normal terminal routing on completion, failure
   or cancellation.

While a transfer is active, ordinary terminal input is rejected. A transfer
waiting for authorization expires after five minutes; an active transfer with
no protocol progress expires after a hard 60 seconds. Unrecognized/raw peer
noise does not renew that deadline. Raw bytes belonging to an incomplete legal
subpacket postpone only the short retransmission timer, so a slowly delivered
4 KiB/8 KiB subpacket is not corrupted by a premature retry; they never extend
the independent hard deadline. Initial ZHEX detection ignores in-band raw or
parity-marked XON/XOFF while retaining the original wire bytes.

Protocol-state, deferred-input and recording locks are released before PTY
writes. One per-session writer actor is the only production PTY write path.
Its FIFO is bounded to 1 MiB by queued bytes; ordinary input, protocol output
and cancellation control bytes share the same ordering boundary. Terminal
success is not published until final protocol wire such as sender `OO` is
confirmed written. Receiver-side closing `ZFIN` is also confirmed at the PTY
writer boundary. If the peer omits the optional final `OO`, native retransmits
`ZFIN` for a bounded brief interval and then completes the already-finished
batch. Cancellation advances the writer generation, invalidates every older
queued protocol job, then places CAN in order. It waits only for the bounded
writer watchdog when CAN can still be ordered. If a protocol write is already
blocked inside the writer actor, cancellation tears down the transport and
publishes the cancelled terminal state immediately instead of waiting for that
syscall.
The first writer-actor I/O error atomically closes the transport and drops the
public queue sender before the failed job is resolved. Already queued jobs are
drained only to return `io_error`; no later byte is written, and one ordered
terminal failure is published after any earlier detection/start event.
Closing a session does not wait without bound for the reader or writer thread;
the actor holds no strong session reference while writing, and real PTY teardown
is requested so an ordinary blocked write can be interrupted.

After send authorization, native enters a cancelable `PreparingSend` phase.
File metadata checks, no-follow opens and complete snapshots all run in
background work, so a network filesystem cannot block the product request/UI
thread. Preparation has no inherited five-minute authorization cutoff; its
60-second no-progress deadline is renewed only by real snapshot or protocol
progress. Worker messages carry monotonic timestamps; progress or completion
that occurred only after the prior deadline cannot revive an expired
preparation between timer-pump ticks. Cancellation remains available while the
snapshot is being prepared.
Snapshot work checks cancellation every 64 KiB; a filesystem syscall already
executing may finish later, but it no longer owns session state and a
process-wide admission cap prevents repeatedly blocked filesystems from
creating unbounded workers.

Receive authorization similarly enters a cancelable background preparation
phase. Stable directory opening, collision scans and hidden staging-file
creation do not run while protocol/session locks are held. The same
process-wide worker admission cap bounds send and receive preparation; a
60-second hard deadline still applies while preparation is stalled, and a
late directory/staging completion cannot reset that expired deadline.

Final receive publication also runs outside the protocol/session lock under
the same process-wide bounded-worker admission cap. The worker owns stable
file and directory descriptors until it returns, so an SSH EOF cannot discard
its durable result or recovery authority. If a filesystem publication syscall
remains blocked for 60 seconds, native advances the cancellation epoch and
allows the session to close without waiting for that syscall. The bounded late
worker remains the sole file authority: a late failure registers its hidden
recovery entry for normal expiry cleanup, while a late success has no path back
into the already-closed session event queue.

Unpublished receive-file cleanup also leaves protocol state before filesystem
close/unlink. A single process-wide cleanup worker performs that work. One
process-wide receive pool bounds active receive files, retained recovery files
and cleanup jobs together to 256 files, 16 GiB of received/staged data and
1,024 retained file descriptors.

## Runtime surface

Runtime Capabilities advertises the independently selectable feature ids
`zmodem.receive.v1` and `zmodem.send.v1`. They are currently advertised on
macOS and Linux. Receive requires stable Unix directory-descriptor operations;
send requires an atomic `O_NOFOLLOW` regular-file open. Other builds omit both
ids and fail authorization closed with `unsupported_platform`.

Native events are:

- `zmodem_detected`
- `zmodem_file_offer`
- `zmodem_started`
- `zmodem_progress`
- `zmodem_file_completed`
- `zmodem_file_skipped`
- `zmodem_completed`
- `zmodem_failed`
- `zmodem_cancelled`

`zmodem_deferred_write_failed` is a separate diagnostic, not a transfer event.
It reports `source`, a bounded `reason`, and queued/completed chunk and byte
counts when ordinary PTY writes held behind a transfer could not be confirmed.
Dart publishes a validated
`TerminalSessionZmodemDeferredWriteFailedDiagnostic` on
`TerminalRuntimeController.zmodemDeferredWriteFailures`. It never terminates or
otherwise mutates Dart's native transfer identity; the product does persist it
as the visible session error, removes any earlier success notice, and prevents
a same-batch `zmodem_completed` event from hiding the delivery failure.

All events contain `source: "zmodem"` and a string `transferId`. Depending on
the event they also contain `direction`, a display-only `filename`, byte and
file counts, or a bounded failure `reason`. `zmodem_file_skipped` is a
non-terminal per-file event: `skippedFiles` increases and the remaining batch
continues. The terminal `zmodem_completed` event reports both `completedFiles`
and `skippedFiles`. A receive-side `publish_failed` event can additionally
report a safe `recoverablePartialName` basename and `stagingPreserved: true`.
When available it also carries an opaque, 32-hex-character `recoveryToken`.
Native generates this as an unguessable 128-bit capability and atomically
binds its owner session before exposing the failure event; cross-session
resolution fails closed. Registration atomically creates a one-hour,
owner-bound native fallback tombstone, so resolution remains available after
the originating session exits or closes even when close races publication.
Resolving a recovery grants that entry a five-minute Reveal lease so the timed
sweeper and capacity pressure cannot remove it between path resolution and the
subsequent consume request. At the bounded capacity edge, inserting a new
recovery entry evicts the oldest non-leased entry and then replaces only the
corresponding now-orphaned tombstone; registration fails closed if every entry
is leased.
The recovery registry is pruned by a timed background sweep even if no later
request arrives. Expiry and capacity eviction schedule descriptor-checked deletion of
the hidden staging file. Reveal resolves the current path first and consumes
the token only after the platform confirms that it handled the reveal request;
successful consume transfers authority for that path to the user and releases
native handles without deleting the revealed file. Discard is a distinct
destructive operation that requires explicit product confirmation, releases
the handles and schedules permanent deletion. Both
tokens are single-use.
Dart validates the token and removes
both it and any legacy absolute staging path from the event's public
`rawPayload`. Diagnostic projection removes filenames, recovery tokens and
local paths.
The product retains a persistent Reveal/Discard banner for each preserved file;
the recovery action does not disappear with a transient Snackbar. The banner
includes the originating session label and stable session ID, including when
the fallback belongs to an inactive or already-closed session.

Dart exposes these as `TerminalSessionZmodemEvent` values on the additive
`TerminalRuntimeController.zmodemEvents` stream. They intentionally do not
extend the public sealed `TerminalSessionEvent` hierarchy: keeping the existing
hierarchy closed preserves exhaustive switches compiled by package clients.
After a runtime-event gap that lost every native transfer event on a backend
advertising either ZMODEM capability, Dart may also
emit the local-only `zmodem_reconciliation_required` state. It carries an
opaque local transfer identity, keeps ordinary input paused and gives the
product a visible Cancel/retry path until native reconciliation succeeds or an
authoritative native event replaces it. This local recovery marker intentionally
does not add a public enum case: `TerminalSessionZmodemEvent.kind` is `null` and
clients can query the additive `isReconciliationRequired` getter, preserving
source compatibility for exhaustive switches over `TerminalZmodemEventKind`.
Receive offers also expose `modificationTimeSeconds`; zero or missing metadata
projects as `null`, while a valid value is shown by the macOS product in UTC.

The current example product has a macOS runner and native ZMODEM file dialogs.
The Linux core capability remains available to headless/integrating clients,
but the example does not advertise product dialogs on Linux until a Linux
runner implements them.
When an authorization request or terminal result belongs to an inactive tab or
split pane, the example sets its existing new-output attention marker and, when
activity notifications are enabled, sends a session-scoped system notification.
An inactive authorization request is cancelled instead of opening a picker.

The product responds through the existing Session Request JSON channel:

```json
{"kind":"terminal.zmodem.accept_receive","transferId":"1","destination":"/absolute/directory"}
{"kind":"terminal.zmodem.accept_send","transferId":"2","files":["/absolute/file"]}
{"kind":"terminal.zmodem.cancel","transferId":"2"}
{"kind":"terminal.zmodem.cancel_active"}
{"kind":"terminal.zmodem.resolve_recovery","recoveryToken":"0123456789abcdef0123456789abcdef"}
{"kind":"terminal.zmodem.consume_recovery","recoveryToken":"0123456789abcdef0123456789abcdef"}
{"kind":"terminal.zmodem.dismiss_recovery","recoveryToken":"0123456789abcdef0123456789abcdef"}
```

Stale or cross-session transfer ids fail closed. Recovery resolution also
fails closed for malformed tokens. A valid resolution response explicitly
distinguishes `{ "available": false }` from
`{ "available": true, "path": "/current/absolute/partial" }`; transport or
malformed-response failures remain retryable in Dart and do not consume the
token. A successful `cancel_active` response includes `reconciled: true` and an
`outcome` of `cancelled`, `draining`, or `idle`. Only `cancelled` proves that
this request cancelled an active transfer. `draining` keeps the input lock
until its authoritative terminal event. After an event-sequence gap, `idle`
proves there is no active or draining native transfer; absent a matching
terminal survivor in the already-polled batch, Dart clears a stale known lock
or avoids creating an unknown one and reports `event_sequence_gap` locally.
`cancel_active` is used after an event-sequence gap when Dart can no
longer trust its remembered transfer id. A backend that advertises neither
ZMODEM capability cannot acquire this synthetic lock. The runtime retains its
known or synthetic input lock unless the post-poll response reports `idle`.
Even a matching terminal survivor cannot prove that a successor detection was
not among the dropped events; `cancelled`, `draining`, missing, and malformed
responses therefore move that authority to the synthetic lock until a later
gap-free terminal event or `idle` reconciliation. A product Cancel retries the id-free command
after an id-bound response failure. Once an id-bound cancellation is accepted,
repeated Cancel actions are idempotent during the native drain window and the
product disables the action while displaying `Cancelling…`. A cancellation
that races a short native state transition returns a retryable busy response;
it never authorizes itself from a changing transfer-id snapshot. During receive
publication, the no-replace filesystem commit and its
`zmodem_file_completed` queue insertion share one cancellation linearization
interval: Cancel cannot report success after the file becomes visible but
before the UI-observable completion event is ordered. Drain-to-idle, deferred
ordinary-input flush, commit-phase reopening, and the next reader/write pass
are serialized so a later transfer cannot inherit cancelled state or overtake
previously deferred input.

## File authority and limits

- Receive is supported on macOS and Linux, where native holds a stable Unix
  directory file descriptor and performs child operations relative to that
  handle. Other platforms are rejected rather than falling back to path-based
  checks vulnerable to replacement races. Authorization requires an existing
  absolute directory. Remote names are flattened to a safe basename and capped
  at 240 UTF-8 bytes after collision suffixing.
  Names ending in a space or dot, or containing C0/DEL or Unicode
  bidirectional-formatting controls (`U+061C`, `U+200E`-`U+200F`,
  `U+202A`-`U+202E`, `U+2066`-`U+2069`), are rejected before Dart displays the
  name or authorizes a destination.
- Received content is written to a hidden mode-0600 partial file, flushed and
  synchronized, then temporarily changed to mode 0400. Before publication,
  native creates an unexposed same-directory hard link to that read-only inode
  as constant-time rollback authority. This uses ordinary POSIX link semantics
  and does not depend on APFS clonefile, Linux `FICLONE`, or copy-on-write
  filesystem support. The staging name is then moved to a non-overwriting final
  name with one same-directory atomic operation
  (`renameatx_np(RENAME_EXCL)` on macOS or
  `renameat2(RENAME_NOREPLACE)` on Linux). That operation creates the final
  name and removes the staging name together; there is no separate
  check-then-unlink publication window and no full-file verification read. If
  the pre-publication hard link cannot be created, publication fails closed and
  retains the original staging file. Native opens and synchronizes the
  published inode and retains that verified handle while synchronizing the
  selected directory descriptor. It then removes the verified rollback link
  while both names remain mode 0400, restores the final inode to mode 0600, and
  revalidates the trusted pre-chmod size and mtime plus final-name identity and
  mode. Unix ctime is deliberately allowed to change because link removal and
  chmod necessarily update it; the trusted size/mtime baseline is never reset
  from post-chmod metadata. A replacement before this completion point fails
  closed. Any earlier post-publication verification or durability failure
  first removes the verified final public alias while the inode remains
  read-only, then transfers sole recovery authority to the already-created
  hidden hard link in constant time. The public name and recovery name
  therefore never remain as mutable aliases of the same inode, and a later
  replacement at the public name cannot change the preserved bytes. This path
  never copies a file of up to 4 GiB while the protocol commit is locked. If
  recovery registration itself fails, native schedules descriptor-checked
  deletion of every known staging/backup alias and reports a generic I/O
  failure rather than claiming that recovery was preserved. Name collisions receive
  a numeric suffix. If publication fails after the complete file has been synchronized,
  including a directory-sync failure after the final name becomes visible,
  native preserves the staging file and reports
  only its safe basename plus an opaque recovery token. The product never joins
  that basename to the previously selected directory. Only an explicit Reveal
  action resolves the token through native's retained directory descriptor,
  obtaining the file's current absolute path immediately before calling the
  platform reveal bridge. Resolution failure produces a generic unavailable
  message and does not display the token or any stale/raw path. Expiry and
  confirmed discard move the candidate to a fresh random quarantine basename,
  verify it against the retained descriptor, and then unlink it.
  POSIX does not provide an unlink-if-inode-still-matches primitive: the
  selected destination is therefore trusted not to be concurrently mutated by
  a hostile process running as the same OS user. Stable dirfds, no-follow
  opens, random names and descriptor checks prevent path redirection and
  ordinary accidental replacement; they are not a security boundary against a
  same-UID watcher that can chmod or replace entries between syscalls.
- Send accepts absolute, regular, non-symbolic-link files only on macOS and
  Linux. Selection validation and snapshotting occur in the cancelable worker;
  unsupported platforms do not advertise the capability. The worker sends
  from a pathless mode-0600 snapshot and rejects a source whose size, mtime, or
  Unix ctime changes while copying, including same-size rewrites that restore
  the original mtime.
- A batch is limited to 256 files and 16 GiB. The same limits are enforced
  process-wide across concurrently active receive and recovery staging files,
  together with a 1,024-FD ceiling. The platform picker returns the
  complete selection; if it contains more than 256 files, the product reports
  the limit and sends no truncated authorization request. An individual file
  is limited to the ZMODEM 32-bit size field.
- Protocol buffering is capped at 256 KiB. Cancellation normally sends the
  conventional eight-CAN abort sequence and removes unpublished partial files.
  Cancellation and publication atomically claim the same commit phase before
  the cancellation epoch advances. If cancel claims idle first, publication is
  impossible; once publication claims the phase, Cancel returns a retryable
  `receive_commit_in_progress` failure instead of falsely reporting success.
  Session close atomically claims the same cancelled phase. If publication
  already owns it, close returns promptly with a retryable busy result and
  retains the native session and event queue; the product asks the user to wait
  for the completion/recovery result before retrying close. This prevents a
  recovery token produced after a final poll from being discarded. A
  publication worker that exceeds the fixed 60-second blocked-I/O watchdog is
  abandoned through a cancellation-epoch transition; a subsequent close can
  then complete while the globally bounded worker retains file authority until
  the syscall returns. Event
  insertion and commit-phase release share a short close gate; close also
  returns busy while an already-queued ZMODEM terminal result has not yet been
  polled. Outside the
  publication interval, close marks the session exited, terminates its
  PTY/child and detaches unfinished worker handles rather than blocking the UI
  on an external filesystem call.
- Ianvs negotiates GNU-compatible `ESCCTL` but fails closed if a peer requires
  `ZRINIT.ESC8`; the vendored engine does not claim incomplete arbitrary 8-bit
  quoting support.

## Interoperability evidence

`native/core/tests/zmodem_ssh_test.rs` exercises both directions through a real
OpenSSH PTY against GNU `lrzsz` 0.12.21rc. The Colima/Docker fixture pins the
Ubuntu image digest, an immutable Ubuntu archive snapshot, and exact `lrzsz`
and `openssh-server` package versions; its SSH probe checks the fixture marker,
both packages, and `rz`/`sz` version strings before evidence is accepted. SSH
host keys are generated when the disposable container starts rather than
being baked into the image; BuildKit receives a fixed `SOURCE_DATE_EPOCH` and
package-script output timestamps are normalized to it, while the
runtime-generated linker cache is excluded from the layer. The explicit
`--ignored --exact` command is in `tools/zmodem_e2e`. GitHub Actions runs this
ignored test explicitly on native amd64 and arm64 Ubuntu runners with Linux
Docker; ordinary local `cargo test` continues to report it as ignored rather
than producing a false pass.
The remote commands refuse hosts without the fixture marker, use independent
`mktemp` directories, and clean those directories before reporting success.

The verified receive path accepts a two-file `sz -e` batch. The send path
negotiates `ZRINIT.ESCCTL` and has been verified against GNU `lrzsz` `rz -bye`
with a two-file batch, including an exact MD5 and byte-size round trip of the
108,277,050-byte macOS installer fixture; the checked
[Colima/OpenSSH evidence](../evidence/ZMODEM_COLIMA_OPENSSH_2026-08-07.md)
records all four file hashes, sizes, mtimes, architecture, image ID and exact
command. CI also exercises an independently generated 8 MiB primary file plus
the deterministic companion. Uploads use one
CRC-bounded subpacket per acknowledgement even when a PTY peer advertises
`CANOVIO`; this avoids GNU lrzsz 0.12.21rc's PTY buffered-window failure while
retaining CRC32 integrity. The OpenSSH fixture disables the client's local
escape character so SSH cannot consume binary input. The fixture
also compares independently computed MD5 and byte-size values after `sz -e`
receive. Both directions require the destination mtime to match the source at whole-second
precision. Missing or zero ZFILE mtime metadata is treated as unavailable, not
as the Unix epoch. Ianvs vendors `zmodem2` 0.7.2 with its focused compatibility
patches documented in `native/vendor/zmodem2/PATCHES.md`.
