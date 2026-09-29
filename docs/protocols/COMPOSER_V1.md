# Composer V1

All operations use the correlated [Session Request/Response V1](SESSION_REQUEST_RESPONSE_V1.md)
envelope and closed payloads (unknown or missing fields are rejected). There are
no additional exported symbols. Capability ids describe compiled operations, not
proof that a session has a usable shell adapter.

## Pure completion

`completion.query` accepts exactly this payload:

```json
{"schemaVersion":1,"sessionEpoch":1,"targetId":"7","contextRevision":1,"editorRevision":2,"selectionRevision":3,"catalogRevision":"ianvs-20260929-v1","policyRevision":0,"text":"git che --help","cursorUtf16":7,"dialect":"zsh"}
```

The target must equal the envelope session id. Versions/revisions/epochs are
unsigned integers; text is at most 65,536 UTF-8 bytes, the target is 1–256 bytes,
and cursorUtf16 must be an extended grapheme boundary. Dialect is one of zsh,
bash, fish or generic. Controls other than tab/newline are rejected. Selection
and IME composition stay in Dart; only a collapsed selection with no composition
can query or accept. Nested expressions, substitutions and redirects return
`unsupported_context`, with no evaluation.

Response payload keys: `schemaVersion`, `query` (exact identity echo), `status`
(`ok` or `unsupported_context`), `items`. An item has exactly `itemId`, `label`,
`detail`, `kind`, `source`, `replaceStartUtf16`, `replaceEndUtf16`, `newText`,
`finalCursorUtf16`, `riskHint`. Replacement is a half-open range in the queried
text; it includes the complete active token but preserves subsequent arguments.
No append-at-current-cursor fallback is allowed. Dart requires exact identity,
valid grapheme boundaries, a cursor inside the inserted text, and no insertion
controls. A batch is limited to 100 items / 256 KiB. Candidate selection survives
incremental updates only by item id. Accepting a candidate only edits the draft.

For local zsh, the host also passes its authenticated, in-memory alias snapshot
to the pure matcher. Alias names appear only in command position, with kind
`alias`, source `shell:zsh`, and the shell definition as display-only detail.
An alias shadows a catalog command with the same name. Acceptance inserts the
literal alias name; definitions are never evaluated or expanded for argument
completion. No filesystem or subprocess is involved in this enrichment.

## Optional local suggestions

`completion.local_start`: `{query, lease, policy: {files: bool, scripts: bool}}`.
A matching authenticated ready lease and explicit true policy are required.
Cwd comes exclusively from that bound shell channel. Results: `{status}` where
status is denied/unsupported/busy/unavailable, or `{status:"pending",jobId}`.
`completion.local_poll` and `completion.local_cancel` accept exactly `{jobId}`
(a decimal u64 string, at most 20 bytes). Poll returns pending/cancelled, or
`{status:"complete",batch}` in the same completion-batch shape. Context change
invalidates the job; cancel is idempotent. No host pathname enters diagnostics.

Automatic menus/local IO start disabled; static results can appear as inline
suggestions without opening a menu. History suggestions take precedence.
Tab grants local permissions for that exact live request without changing the
session-only automatic-suggestions switch. A unique final result is inserted;
multiple results open for selection and a subsequent Tab accepts the selection.
Edits, context changes and cancellation revoke the request's permissions.
The worker reads the explicitly requested directory: relative and parent paths
resolve against the bound shell's cwd, absolute paths remain absolute, and an
unquoted `~/` uses that shell's authenticated HOME. There is no GUI-process cwd
or HOME fallback, recursive traversal, or implicit ancestor search. Directory
and file symlinks are completed according to their resolved type; broken links
are skipped. Quoted/escaped tildes stay literal, and named-user/named-directory
tilde expansion is unsupported. Acceptance preserves an expandable `~/` outside
any quoted suffix, including spaces and Unicode. Script
names come from the regular, no-follow `package.json` in that exact cwd; script
bodies are never exposed or executed. No ancestor search, process or network API
is used. Cwd-changing command prefixes and multi-command expressions disable
local IO because their effective cwd cannot be established without execution.

Budgets: 2 workers globally, 1 live job per session, 512 scanned entries, 60
results, 96 KiB serialized local items, 256 KiB package.json, 150 ms cooperative
worker deadline and 300 ms UI wait. There is no persistent cache. Cancellation
is checked between filesystem calls. A kernel filesystem call on a stalled
mount cannot be preempted safely; it retains its worker slot until returning,
so further work is refused instead of spawning unbounded threads. Static
completion and draft editing remain available.

## Shell ownership and submission

`composer.state` accepts `{}`. Payload: `{state,lease,cwd,dialect,submissionId,outcome}`.
An authenticated local zsh adapter additionally returns `home`, `history` (newest first)
and `historyRevision` (changes only when the complete snapshot changes).
The ready frame carries cwd and HOME together. Missing or invalid HOME disables
only tilde completion. Each path is limited to 4 KiB; the private receive buffer
is bounded at 48 KiB to accommodate paths, history and aliases.
States: draft, ready, submitting, running, suspended. A missing adapter returns
draft, null lease, empty cwd, generic dialect and none outcome. The UI additionally
holds an unknown state after an ambiguous result. Polling ready cannot unlock it.

`composer.submit` accepts `{lease,submissionId,text}`. IDs are 1–80 ASCII
alphanumeric/hyphen bytes. Text is nonempty, at most 65,536 UTF-8 bytes and has no
controls except tab/newline. The exact current ready lease is consumed once.
Outcomes are pending, accepted, rejected, unknown. The current submission and the
last 64 acknowledged ids are idempotent; old lease tokens are always rejected.
Submission IDs must remain unique for the session lifetime. An accepted response
means ZLE accepted the line, not that the command finished or succeeded.

The local macOS zsh bootstrap opens a private Unix socket in a 0700 temporary
directory. A random nonce authenticates a separate channel, and ZLE grants a
monotonic lease only at top-level, empty, nonrecursive line editing. PTY output,
OSC 7/133 and screen contents never create that lease. Raw input revokes it.
The trusted boundary includes the user's shell startup files and plugins; this
is not a sandbox against hostile processes with the same OS user.

At each empty top-level prompt the adapter reads the shell's `history` and
ordinary `aliases` parameters over the same private channel. History examines
the newest 200 events, publishes at most 100 commands / 8 KiB total, and skips
leading whitespace and commands over 4 KiB. Alias snapshots are at most 64
entries / 2 KiB total, with 128-byte names and 1 KiB definitions. Each snapshot
is committed atomically. Invalid display controls are ignored; invalid frames
or exceeded budgets close the channel. Normal history permits tab/newline.
No separate history file is opened, written, or scraped from terminal output.
The editor retains history only in its session's memory and deduplicates it.

The history overlay filters by all whitespace-separated input words, case
insensitively; oldest entries are above newest entries. Esc and Down beyond the
newest result restore the exact pre-search draft and selection. Accepting a
history item edits the draft and can be undone; it does not submit. The editor's
ghost suffix is painted separately from `TextEditingValue`, clipboard and
submission. It is suppressed for selections, composition, nonterminal cursor
positions, menus and inactive/running sessions. Right/Ctrl+F/Ctrl+E accept the
suffix, Ctrl+Right accepts the next whitespace-delimited part.

ZLE's fd callback cannot itself leave its input read loop. The adapter therefore
prepares the payload on the private channel, temporarily binds NUL in its active
keymap, and acknowledges preparation. Only then does native emit one NUL wake
byte. The actual commit widget rechecks context and epoch, assigns literal
BUFFER and calls builtin `.accept-line`. No Ctrl-U, blind Enter or evaluated
helper command is injected. Existing custom NUL bindings cause rejection;
default bindings are restored on commit, raw interaction and disconnect.
This deliberately bypasses custom accept-line wrappers. The adapter descriptor
is close-on-exec; nested executables do not receive the private socket.

The native deadline is 1.5 s. A timeout or raw-input race closes the channel,
restores the keymap on EOF and prevents a late wake. An already-sent wake may
have executed; unknown is never retried automatically. The UI preserves the
submission and any newer draft. A fresh shell session is needed after channel
failure. Acknowledgement clears only the submitted editor revision. Drafts,
candidates, request payloads and private channel data are not separately logged
or persisted. Normal terminal echo/output still follows existing recording policy.
