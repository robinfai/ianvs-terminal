# Compatibility Baseline Known Issues

The repository-wide canonical list remains [docs/KNOWN_ISSUES.md](../KNOWN_ISSUES.md). This file
records only the compatibility evidence boundaries exposed by Iteration 01.

| Issue | Current evidence | Consequence | Follow-up |
| --- | --- | --- | --- |
| macOS-only product baseline | macOS app runner, real PTY integration and XCTest exist; Linux/Windows runners do not | No cross-platform compatibility claim | Keep Linux/Windows matrix cells `Unknown` until real runners and PTY tests exist |
| External `vttest` is not guaranteed on a developer host | This host has Homebrew `vttest` 20251205 and passed `tools/vttest_gui_nightly.sh --release-gate` on 2026-07-21; the script still reports missing prerequisites elsewhere | A missing binary on another host is a blocked supplemental gate, not a product pass or failure | Install `vttest` and run the GUI gate when a full external TUI sweep is required |
| Truncated transcript cannot be fully replayed on resize | transcript is capped at 262,144 bytes; debug stats expose truncation and skipped replay | Resize still returns a snapshot but cannot reconstruct history that was discarded | Track with `transcript_truncated` and `resize_replay_skipped_truncated_count`; do not infer full reflow fidelity |
| Font and DPI fidelity is host dependent | Unicode cell widths are automated; real glyph availability and rasterization are not | Missing Powerline/Nerd/emoji glyphs or display changes can still produce visual defects | Run [MANUAL_VERIFICATION.md](MANUAL_VERIFICATION.md) after font/rendering changes |
| Physical keyboard, IME and pointing-device combinations are not exhaustive | Encoder and widget tests cover known paths | Hardware/layout-specific behavior can remain unobserved | Run representative keyboard, IME and trackpad checks on release candidates |
| Kitty POSIX shared-memory tests depend on host support | ordinary verify can explicitly skip unsupported `shm_open`; strict mode is opt-in | Default verification does not prove this transport on every host | Use `IANVS_REQUIRE_POSIX_SHM_TESTS=1` on a compatible nightly host |
| Cross-machine performance comparisons are not normalized | CI smoke and nightly resource gates exist | A pass is local regression evidence, not a universal performance guarantee | Record host metadata and build a historical cross-machine baseline |
| SSH/remote shell lifecycle is absent | current product supports local shell only | Remote compatibility is not established | Deferred beyond the foundation baseline |

## Observability added by the baseline

`take_session_debug_stats_json` exposes:

- `transcript_bytes`
- `transcript_truncated`
- `resize_replay_count`
- `resize_replay_bytes`
- `resize_replay_micros`
- `resize_replay_skipped_truncated_count`

These are cumulative session diagnostics. Elapsed microseconds may be zero for a very short replay
on a coarse timer; field presence and replay counters are the stable contract.
