# Recording storage proposal

Status: proposed, not implemented. This consolidates the useful design questions
from the September 2026 storage experiments. It is not a supported file format,
performance promise, or replacement for [FORMAT_CURRENT.md](FORMAT_CURRENT.md).
The product still uses current schema 1 NDJSON and bounded native capture.

## Problem and format decision

The current capture budget is a whole-recording limit, not a writer queue.
Compressing only at stop cannot make capture longer. Saving, opening, indexing,
and seeking also need bounded streaming work; moving whole-file processing to
an isolate alone does not remove its peak memory cost.

Choose the fidelity requirement before the storage representation:

- Complete output history needs the original output bytes, order, and timing.
  A compact event stream with independent compressed chunks is the candidate.
- Visual playback of repetitive TUI redraws may benefit from storage-specific
  FrameDiff encoding, line deduplication, changed-field masks, and keyframes.
- Sampling at 10–30 Hz is a separate fidelity tradeoff. It can omit intermediate
  screens and lines that scroll out between samples; it is not lossless log
  compression. Do not compare it with complete event history as equivalent data.

The earlier synthetic and macOS `top` probes justify comparing both routes,
not selecting one universal winner. They do not establish mobile performance,
random-seek latency, image fidelity, or a production compression ratio. Do not
switch formats by program name: one session can move between shell, logs, and TUI.
Avoid storing two complete histories by default without measuring their cost.

## Candidate implementation

1. Measure capture/queue/asset bytes, overflow feedback, save/open peak memory,
   first-frame time, and seek cost before fixing budgets or latency targets.
2. Prototype a versioned container with metadata, independent Zstd event chunks,
   time/sequence directory, checksums, and a finalized footer. Container version,
   event schema, and snapshot format must remain separate contracts. Test roughly
   256 KiB–1 MiB chunks; these are starting points, not chosen product defaults.
3. Write from a bounded native background queue while recording. Bound all
   sessions together; handle disk-full, queue-full, cancellation, and crashes
   explicitly. An incomplete but verified prefix must be distinguishable from
   a finalized recording. Retain existing handoff/path ownership and atomic
   commit responsibilities instead of adding a second recovery system.
4. Read, search, and replay incrementally with cancellable asynchronous seek.
   UTF-8, ANSI, and search matching need state across event/chunk boundaries.
   A compressed chunk can be independently decoded without being independently
   replayable: earlier parser and terminal state still matter.
5. Define persistent restoration state only if cold seek requires it. Event
   replay needs versioned terminal/parser state, screens, scrollback, modes,
   and assets; pure FrameDiff playback instead needs a complete render keyframe.
   Do not serialize Rust memory layouts. Indexing alone cannot skip prior state.
6. Collect graphics at recording start and as versions appear, before cache
   eviction. Reuse content identity, compare lossless RGBA compression against
   alternatives, and verify decoded pixels. Do not remove image protocol bytes
   until an explicit asset replay contract preserves their effect.

Instant replay is a separate in-memory optimization: share immutable rows and
assets, keep bounded keyframe/delta groups, apply every incoming frame before
sampling, and preserve a usable base when evicting old history.

## Correctness gate and open issue

The earlier `scroll_burst` experiment reported a delta-versus-snapshot mismatch
when 8,000 scrollback lines were exhausted: a negative viewport shift left
retained rows offset by one. This remains a reproduction question for the
current engine; historical measurements are not proof that it still fails or
has been fixed. A 40,000-line benchmark avoids that boundary and cannot close it.
Keep the 8,000-line check in any FrameDiff storage evaluation:

```bash
python3 tools/recording_bench/scenario-storage-benchmark.py \
  --only scroll_burst --scrollback 8000 \
  --output build/recording_bench/scrollback-boundary
```

Before adoption, validate event byte/time roundtrips, Unicode/control sequences
split across chunks, resize, alternate screen, nonempty initial state, semantic
ordering, input redaction, image versions, and seek-versus-from-start equivalence.
Historical input and host side effects must never execute during replay.
Exercise truncated chunks/footer, corrupt lengths/checksums, incompatible state,
disk/queue exhaustion, and restart recovery. Bound decoded sizes as well as
compressed sizes.

Compare full-fidelity and sampled modes separately, counting indexes, keyframes,
assets, and retained offscreen history. Report bytes, write CPU, queue/peak RSS,
stop latency, cold/warm first frame, seek P50/P95, UI responsiveness, and device
power on representative workloads. Fixed numeric targets need a device and
workload specification before becoming acceptance criteria.

## Scope of a future implementation

Canonical ownership remains in `native/core`, `packages/ianvs_terminal`, and
`example/lib/features/recording` with session and replay UI integration.
Regenerate `ianvs_terminal_core` through the existing sync tool. Only after an
implementation and its gates pass should the current-format document change.
Any future NDJSON import/export or migration policy must be explicit, preserve
the source until verification, and reject unsupported mandatory capabilities.

Reusable experiments and their limitations are documented in
[tools/recording_bench/README.md](../../tools/recording_bench/README.md).
Generated results belong in ignored `build/recording_bench/`, not in `docs/`.
