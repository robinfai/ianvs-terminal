# Real-duration application recording acceptance

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
- Both sessions record continuously. Every approximately ten seconds,
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
  Open/seek/search durations are retained in `result.json`. Command markers are
  independent simple commands: the current Bash DEBUG adapter may report only
  the first simple command of a compound input line. This runner does not claim
  complete shell source-line capture or validate every nested host transition.

The runner uses `caffeinate -i` to inhibit idle system sleep only while the owned
app runs. A heartbeat gap of two minutes or more fails continuity acceptance.
At least 5 GiB free is required before the build; less than 2 GiB free or more
than 10 GiB of test library data fails the running test. Failures preserve files
and reports. Normal completion, interruption and timeout clean up the owned
process group and fixture containers/network/keys; they do not remove reports.

## Interpretation

Only a successful Release run with measured recording time strictly greater
than 86,400 seconds can establish the duration requirement. Inspect both
`runner.json` and `result.json`, the heartbeat history and resource trends.
Successful short runs establish fixture/pipeline operation, not bounded behavior
over a day. Resource and latency measurements are evidence for evaluating gates;
this runner does not invent numeric performance acceptance thresholds.

Restart/reopen after application death, controlled process failure, filesystem
failure and system/power-loss durability require separate evidence. Stopping and
opening within the same app process does not cover those cases. See the
[delivery task](../tasks/adaptive-session-recording.md) for remaining acceptance.
