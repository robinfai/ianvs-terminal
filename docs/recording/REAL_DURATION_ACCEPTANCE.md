> Historical branch evidence (September 2026). These results do not validate
> the November 2026 integration with current main; see the integration PR for
> fresh verification and platform coverage.

# Real-duration application recording acceptance

Current release duration: the user changed the requirement on 2026-09-27 to
approximately two actual hours (“测两个小时差不多了，不用跑完25小时”).
The 25-hour runner below remains available for future extended testing. Its
original reports must not be rewritten as passed when stopped early; preserve
them and report the revised-duration verification separately. File integrity,
resource review, search/seek and new-process replay still require evidence.

The executable entrypoint is `tools/ssh_boundary_lab/recording_soak.py`. It runs
the production Flutter application, native core, session controller and recording
library in an isolated Release integration-test application. It creates a local
Bash session and an SSH session against task-owned OpenSSH containers. It does
not use the SSH prototype injection helpers.

## Run

Use a dedicated, already running Docker context with the boundary-lab image from
`tools/ssh_boundary_lab/`. The output directory must not exist. Run from the
repository root and do not build another macOS target until this runner finishes
its build/copy phase.

```bash
python3 tools/ssh_boundary_lab/recording_soak.py --probe --seconds 120 \
  --context colima-ianvs-recording-acceptance \
  --output build/recording_bench/adaptive/soak-probe-new

python3 tools/ssh_boundary_lab/recording_soak.py --probe --crash-probe --seconds 120 \
  --context colima-ianvs-recording-acceptance \
  --output build/recording_bench/adaptive/crash-probe-new

python3 tools/ssh_boundary_lab/recording_soak.py --seconds 90000 \
  --context colima-ianvs-recording-acceptance \
  --output build/recording_bench/adaptive/soak-25h-new
```

The default duration is 90,000 actual seconds (25 hours), plus baseline and
verification. There is no accelerated clock. A short probe cannot qualify as
long-duration acceptance. The runner copies the signed app into its output
directory and verifies its signature before launch. It removes `IANVS_CORE_LIB`
from the child environment so the embedded Release core is used. Git revision,
source and binary hashes, OS/hardware, image identity, build and launch arguments
are retained in `runner.json`.

## Work and observations

- A baseline cycle runs the same shell, sustained-output, TUI and idle workloads
  without recording. Recording then runs all four phases repeatedly, alternating
  the foreground local/SSH session. Production refresh scheduling remains active;
  the workload loop does not force widget pumps or manual runtime refreshes.
- Shell commands preserve quoted Unicode. Output phases emit repeated 120-line
  bursts. TUI phases redraw an alternate screen with 20 frames at 50 ms intervals.
  Full-duration phases last 60 seconds each; probe phases last 10 seconds.
- Both sessions record continuously. Before the repeated phases, the SSH session
  traverses `a -> b -> c -> b -> a`; saved commands must match each actual host.
  Cross-recording search must also locate the nested host. Every approximately ten seconds,
  `metrics.jsonl` and `heartbeat.json` record elapsed monotonic/UTC time, process
  RSS/peak RSS, cumulative CPU time and CPU percentage from `ps`, total library
  bytes, free disk and each writer's written/committed progress.
- Fixed-size histograms record build/raster times, workload completion time and
  short echo-command dispatch-to-visible-marker latency. The latter excludes the
  workload's execution time and does not claim physical keyboard-to-pixel latency.
  Marker readiness is polled every 20 ms, so timings include that detection
  interval, the test harness and metrics-collection overhead. The reported
  uncommitted timeline span can include an idle interval; it is not the wall-clock
  age of the oldest pending disk write.
- At completion, both captures must finish, be protected by Keep and have at
  least the requested duration. Each file is opened, sought at 13 distributed
  offsets and searched for actual hook commands from the recording workloads.
  Searches require the actual local/SSH host as well as the command marker.
  Open/seek/search durations are retained in `result.json`. Command markers are
  independent simple commands: the current Bash DEBUG adapter may report only
  the first simple command of a compound input line. This runner does not claim
  complete shell source-line capture or validate every nested host transition.

After the first app process exits safely, the same frozen binary starts in
reopen-only mode. A new PID opens both library entries through the actual UI,
seeks to each final marker, checks Keep/host/duration and verifies SSH replay
does not create an SSH session. `reopen-result.json` and separate stdout/stderr
logs are required before the runner reports success.

The runner uses `caffeinate -i` to inhibit idle system sleep only while the owned
app runs. A heartbeat gap of two minutes or more fails continuity acceptance.
At least 5 GiB free is required before the build; less than 2 GiB free or more
than 10 GiB of test library data fails the running test. Failures preserve files
and reports. Normal completion, interruption and timeout clean up the owned
process group and fixture containers/network/keys; they do not remove reports.

## Review the results

The read-only reviewer summarizes each workload's RSS, CPU derived from cumulative
process time, hourly RSS distribution, histogram percentile upper bounds and
open/seek/search measurements:

```bash
python3 -B tools/recording_bench/review-soak.py \
  build/recording_bench/adaptive/soak-25h-new --require-duration \
  > build/recording_bench/adaptive/soak-25h-new/resource-review.json
python3 -B tools/tests/test_recording_resource_review.py
```

Without `--require-duration`, partial runs produce observations with explicit
failed/missing checks. With that option, incomplete, short, superseded or internally
inconsistent evidence exits nonzero. The reviewer checks actual monotonic/UTC
duration, heartbeat coverage, stable PID/writer identity and increasing progress,
matching source revisions, new-process reopen and reported fixture cleanup.
It consumes the runner's unchanged-file hash report; it does not rehash live files.
A successful duration check still requires human/model review of resource and
latency trends against the baseline; it does not invent performance thresholds.
Phase CPU comparisons omit intervals crossing workload boundaries. Histogram
quantiles are bucket upper bounds. File timings do not establish an OS-cold cache.
Tests use clearly synthetic, temporary data to reject malformed and incomplete
reports; they never establish actual-duration acceptance.

## Interpretation

Only a successful Release run with measured recording time strictly greater
than 86,400 seconds can establish the duration requirement. Inspect both
`runner.json` and `result.json`, the heartbeat history and resource trends.
Successful short runs establish fixture/pipeline operation, not bounded behavior
over a day. Resource and latency measurements are evidence for evaluating gates;
this runner does not invent numeric performance acceptance thresholds.

Without `--crash-probe`, the new-process reopen phase covers a clean exit.
With `--probe --crash-probe`, the runner validates the owned app PID/executable
and sends SIGKILL during sustained logs after both writers acknowledge committed
records. It preserves the observed progress and kill time, then starts a new app
process. Recovery must retain every acknowledged record, classify each file as
interrupted/damaged-tail, and place its verified prefix within ten seconds of the
observed kill. This conservative upper bound includes metadata/start overhead.
The UI must display the recovered frames without starting SSH. Both modes compare
primary-file SHA-256 before and after recovery/replay. The crash mode is always
non-qualifying for the duration requirement.

Process-kill acceptance does not establish system/power-loss durability.
Separate real APFS full/disconnect and Linux guest-kernel crash evidence is recorded
in [durability acceptance](DURABILITY_ACCEPTANCE.md), including its platform and
timing limits. See the [delivery task](../tasks/adaptive-session-recording.md)
for remaining acceptance.


## User-revised duration result — 2026-09-27

The user requested approximately two hours instead of 25. The frozen production
implementation at `6c232b9b` captured local Bash and SSH continuously from
02:02:17 UTC until approximately 03:57:00 UTC: **1 h 54 min 43 s**. Both finished
files were safely saved. The last local command timed out following external
native-menu inspection; its cause was unresolved at initial review (resolved below). The original application
and runner reports remain failed. This is not evidence of 7,200 full seconds or
day-long stability, and the run was not stopped by a planned user-close action.

A separate Release verifier with the same native-core hash and unchanged
production source opened both files in a new process. Actual player screens
matched native final frames; 13 seeks per recording, command/screen search and
nested/cross-recording host filters passed. Previously acknowledged records were
preserved, primary hashes were unchanged, and replay created no SSH connection.
The saved-run review branch can inspect a safely saved failed run without changing
its capture result; its minimum file-duration assertion is not a release-duration
acceptance gate.

| Observation | Actual result |
| --- | --- |
| Local / SSH duration | 6,883.085 / 6,883.214 s |
| Continuous metric span / maximum gap | 6,856.750 / 15.367 s |
| First seven quarter-hour RSS medians | 275.66–282.27 MiB; no sustained growth |
| Process peak RSS / library size | 303.94 / 257.86 MiB |
| CPU median, baseline → recording, % of one core | shell 18.70 → 20.66; logs 23.14 → 24.06; TUI 17.36 → 17.45; idle 22.44 → 19.49 |
| Echo-to-visible-marker P95 bounds | local 50 ms; SSH 50–100 ms across ordinary phases |
| Open / seek | about 7 ms / 0.58–6.62 ms |
| First command search, including index preparation | local 8.97 s; SSH 12.41 s |
| Later searches | 3.37–66.11 ms |

The baseline included warm-up and separate VM build activity, so CPU differences
are observations, not a causal overhead estimate. Last-command timeout is excluded
from successful-input histograms and must not be hidden by their percentiles.
The final RSS quarter is partial and affected by external inspection.

A separate 126-second diagnostic reproduced a menu remaining open after Escape;
the exposed native Cancel action closed it. Its capture/file checks passed and
the command timeout did not recur, but external accessibility inspection left a
Flutter test semantics handle active and the runner failed at teardown. This
confirms test interference, not the cause of the original timeout.

Retained artifacts are under `build/recording_bench/adaptive/`: original
`soak-25h-ui-final/result.json` and `runner.json`; independent
`reopen-result.json`; `user-duration-acceptance.json` (strict 7,200-second checks
correctly remain false); `revised-duration-review.json`; and
`menu-diagnostic-probe/`. The initial review left input-timeout diagnosis open. The resolution below
closes that condition; a 25-hour run is no longer required.


## Input interference resolution — 2026-09-27

The same File-menu/Escape action was reproduced with bounded input/backend-error
tracing in `input-diagnostic-probe/`. At 04:19:00.470 UTC the local backend accepted
one byte, `0x1b` (Escape), from the external UI operation. At 04:19:00.890 UTC it
accepted the next `pwd; ... soak_288_local_end` command without a backend error.
That command did not execute or enter Bash history, and the original timeout and
saved-screen signature recurred. The original long run lacks byte-level tracing;
its attribution rests on this controlled reproduction of the same known action.

The installed Bash reports `Esc+p` as `non-incremental-reverse-search-history`.
The next workload begins with `p` (`printf` or `pwd`), so Escape changes shell
editing state and consumes that line as a history query. The maintained real-PTY
test `tools/tests/test_recording_soak_interference.py` proves the command's file
side effect occurs without Escape, is absent with Escape, and fresh input works
after explicitly cancelling shell editing. No recorder or application is involved
in that independent reproduction.

The corrected procedure uses the menu's exposed native **Cancel** action without
sending a key into the session. `menu-cancel-control/` passed 185.837 seconds of
capture, normal stop, file/host search, a new-process actual-player reopen, primary
hash verification and fixture cleanup. Accessibility attaches before WidgetTester
records its initial semantics-handle count using the explicitly requested
`IANVS_RECORDING_WAIT_FOR_START=1` gate and `start.signal`. This prevents the
separate externally acquired semantics handle from being misreported as a test
leak; no teardown assertion was removed or weakened.

No production input or recording change was needed. The original long-run
failure, strict 7,200-second review failure and exploratory failures remain
preserved. The combined duration/resource/file evidence and successful control
satisfy the user's revised acceptance scope, without claiming that the original
25-hour runner passed. See [the final requirement audit](ACCEPTANCE_RESULT.md).
