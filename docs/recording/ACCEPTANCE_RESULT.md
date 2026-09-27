# Recording delivery acceptance — 2026-09-27

Status: **accepted for the four agreed batches on the user-revised duration scope**.
Production implementation: `6c232b9b`. The user explicitly replaced the 25-hour
run with approximately two hours. Actual continuous local/SSH capture was
**1 h 54 min 43 s**; the implementation has no two-hour recording limit.

The complete `make verify` passed on that production revision. Later changes
only affect acceptance tools and documentation; source comparison and the
embedded native-core hash confirm the tested production implementation is unchanged.
The final workload timeout was reproduced as external test input interference,
then a 185.837-second control completed capture, normal save, searches and
new-process UI replay. Failed original reports remain failed and are preserved.

## Requirement audit

Artifact paths below are relative to `build/recording_bench/adaptive/`.
The full gate includes the named native/application suites and actual macOS UI tests.

| Requirement | Evidence checked | Outcome |
| --- | --- | --- |
| Apply every live delta; adaptive rate; keyframes based on stored state | `sampled_recording_test.rs`: independent VT snapshots, 8,000-line eviction, Unicode, metadata/graphics, pressure and cold seek; `results.json` | Passed |
| Independent ordered hook timeline, observed arguments/context | Native timeline/session tests; installed Bash/Zsh tests; `ssh-product-hosts/`; nested a→b→c→b→a host searches | Passed with Bash hook limit below |
| Manual capture per session; complete visible state at start | `macos-ui/run-KvTJbI/result.json`; mid-TUI/style/image/resize player checks in its maintained UI scenario | Passed |
| Bounded queues, background writes, assets and cancellable file work | Native storage/file/request suites, Dart cancellation/ownership tests; `file-results.json`; real RSS trend | Passed |
| Stop, restart, pure replay, seek and command navigation | `soak-25h-ui-final/reopen-result.json`; 13 seeks per file and actual player/native final-screen equality; `menu-cancel-control/` | Passed |
| Commands, retained screen text, cross-file search, host/date filters | Native search tests, `sampled_recording_search_controller_test.dart`, surface tests, long-file searches and nested-host control | Passed |
| Age/capacity retention; Keep, reader and writer protection | `macos-retention/run-sEhFuz/result.json`; explicit-timestamp age boundary tests; persisted settings and budget-rejection input | Passed |
| Safe external import and untouched old NDJSON | `sampled_recording_import_test.dart`, shell import tests and library ownership/legacy tests in full gate | Passed |
| Process recovery within ten-second target | `process-kill-reopen-probe/`: all acknowledged records; conservative tail bounds 0.398 s local / 0.131 s SSH | Passed |
| Disk failure, visible error, continued input and retry | `macos-disk-full/run-nXERGi/result.json`; APFS full/disconnect reports; 17 lifecycle regressions | Passed |
| System-failure recovery | `system-failure/system-failure-direct/result.json`: Linux/ext4 guest kernel crash, new boot ID, 50 acknowledged records and assets unchanged | Passed within stated platform scope |
| Actual shell/log/TUI/idle and SSH duration, resources and responsiveness | Two 6,883-second files, continuous metrics, resource review and independent replay in `soak-25h-ui-final/` | Accepted under user's approximate-duration request |
| Resolve final workload timeout | `input-diagnostic-probe/result.json`: Escape delivered before next accepted p-prefixed command; real Bash PTY regression; menu Cancel control passes completely | External test interference reproduced and removed |
| Final integration and packaging gate | `ui-final-gate.json`, `ui-final-make-verify.log`: native, Dart, app, real PTY, recording UI, Keychain, packaging/signature and Xcode tests | Passed |

## Observed performance and limits

- First seven complete quarter-hour RSS medians: 275.66–282.27 MiB, without
  sustained growth; process peak 303.94 MiB; library size 257.86 MiB.
- Cached opens about 7 ms; 13 seeks per long recording took 0.58–6.62 ms.
  First searches including index preparation took 8.97–12.41 s; later searches
  took 3.37–66.11 ms. Filesystem caches were not deliberately purged.
- Successful runtime echo-to-frame P95 bounds were 50 ms locally and 50–100 ms
  over SSH across ordinary phases. These are not physical keyboard-to-pixel
  measurements. The failed externally contaminated command is not hidden by
  those percentiles. Baseline load differences prevent a causal CPU-overhead claim.
- Actual application validation used macOS 27.0 arm64. Local Fish was absent;
  SSH fixtures covered Bash/Zsh/Fish. Other supported OS versions are not claimed
  as tested. Linux guest crash evidence does not establish macOS hardware power loss.
- Bash DEBUG hooks can expose only the first simple command of a compound line.
  Replay/search preserve observed hooks and sampled output, not raw input or
  unsampled text. No 24-hour endurance claim is made.

The full evidence disposition is `soak-25h-ui-final/final-acceptance.json` and
`acceptance-audit.json`. The independent file review does not rewrite the original
failed capture/runner reports. Historical checkpoints in the task document remain
as history; the [final resolution](REAL_DURATION_ACCEPTANCE.md#input-interference-resolution--2026-09-27)
supersedes their pending status.
