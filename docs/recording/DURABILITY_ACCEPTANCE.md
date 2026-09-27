# Recording failure and durability acceptance

The production implementation under test is `4250a384`. Subsequent changes in
this checkpoint add acceptance tooling and documentation only. The full
`make verify` for that implementation passed before its frozen Release binary
started the 90,000-second application run.

## Evidence and limits

| Failure | Observed outcome | Scope |
| --- | --- | --- |
| macOS application SIGKILL | New-process UI recovery retained every acknowledged record; conservative tail upper bounds were 0.131 s for SSH and 0.398 s locally | Actual Release application, local and SSH recordings; not OS/power failure |
| macOS APFS volume full | Actual OS error 28, settled failed writer, finish rejected; six verified records recovered, including both acknowledged records | Real filesystem ENOSPC on an owned 128 MiB image |
| Linux guest kernel crash | New boot identity; all 50 acknowledged records, the structured screen and image recovered; files unchanged | Native core on an isolated Linux/ext4 guest; not macOS hardware power loss |
| macOS APFS volume disconnected | Actual OS error 5, settled failed writer, finish rejected; both acknowledged records recovered | Forced ejection of the owned image; not a power-loss simulation |

The final APFS runs used macOS 27.0 and the production `BackgroundWriter` and
`ContainerReader`. Both preserved the initial structured screen, command and
retained RGBA image. Recovery did not rewrite the primary file or assets. The
full-volume case was correctly classified as a damaged tail, and the disconnected
volume as interrupted. Observing failure took approximately 191 ms and 13 ms
respectively inside the native fixture; these are not application UI latency
measurements. APFS fixture timestamps are synthetic and do not measure tail-loss
duration. Application SIGKILL measurements use actual clocks.

Machine-readable artifacts are under:

- `build/recording_bench/adaptive/process-kill-reopen-probe/`
- `build/recording_bench/adaptive/filesystem-final/apfs-full/`
- `build/recording_bench/adaptive/filesystem-final/apfs-disconnect/`
- `build/recording_bench/adaptive/system-failure/system-failure-direct/`
- `build/recording_bench/adaptive/acceptance-audit.json`

## Reproduce the macOS filesystem cases

Build the helper, then use a different new output directory for each run:

```bash
cargo build --locked --manifest-path native/core/Cargo.toml --example sampled_recording_durability_probe
python3 tools/recording_bench/filesystem-acceptance.py --case full --output build/recording_bench/adaptive/filesystem-full-new
python3 tools/recording_bench/filesystem-acceptance.py --case disconnect --output build/recording_bench/adaptive/filesystem-disconnect-new
```

The runner requires at least 2 GiB free before creating a bounded 128 MiB APFS
image. It only fills or disconnects that new image. Device identity comes from
the attach result for that image; cleanup never selects an existing user volume.
The output directory must not exist. Reports, the image, the recovered bundle,
probe/source hashes and command logs are retained even on failure. The native
helper does not mount volumes, signal processes or crash an OS by itself.

## Guest-system case

A separate task-owned Colima guest used Linux 6.8 and local ext4 (`/dev/vda1`),
with only its dedicated temporary directory shared from macOS. The existing SSH
long-run VM was not stopped or rebooted. The same production Rust source was
compiled using Rust 1.90.0; only the rlib was linked into the acceptance helper.
The first full-library link exhausted the 2 GiB guest's memory, so that failed
build was retained rather than treated as a product failure or accepted evidence.

The helper's `stream` mode writes on actual monotonic time and reports committed
progress to the macOS controller. After observing progress at 13.074 s and a
committed prefix at 9.983 s, the controller checked the guest ownership marker
and boot identity before triggering [Linux SysRq `c`](https://docs.kernel.org/admin-guide/sysrq.html).
The guest restarted with a different boot identity. A new reader recovered exactly
50 records, including all 50 acknowledged records; the screen and retained image
matched. Hashes of every bundle file were unchanged by recovery.

The 3.090 s difference is measured from the last host-observed checkpoint to the
recovered prefix. It is not an exact or conservative crash-time tail-loss bound,
because the SSH injection round trip includes reboot latency. The ten-second
application SIGKILL upper bounds above remain the separate precisely timed case.
This guest experiment establishes controlled system-crash behavior on Linux/ext4,
not physical-drive power-loss behavior or macOS kernel-crash coverage.

The first recovery controller hit stale Docker forwarding after the guest reboot;
a follow-up also found the Docker data-volume startup differed on guest reboot.
Those unsuccessful harness reports are retained. The accepted `system-failure-direct`
run executes the already-built helper directly in the guest, independent of Docker
at runtime, and passed the complete crash/restart/read-only recovery sequence.
Source hashes, the controller, build logs, platform identity, primary-file hashes
and recovered-bundle archive are retained under the system-failure artifact root.
The disposable guest is stopped after evidence collection; its data is preserved.

## Interpretation

These cases supplement existing bounded-queue, commit-acknowledgement, asset
ordering, interruption and read-only recovery tests. They do not establish
physical-device power-loss durability or a guarantee across every storage stack.
The more-than-24-hour continuous capture and whole-application resource review
remain separate acceptance requirements.
