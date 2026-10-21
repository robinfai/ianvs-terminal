# Verification scope and CI cost

## Pull requests

The existing required-check names are unchanged. There is no workflow-level
path filter: the checks still report a result even for documentation-only PRs.

- Visual baselines remain a blocking step. Once that step has run (pass or fail), the
  repository script excludes `example/test/design/**` from its second test
  discovery pass. Local script invocations still include those tests by default.
- Shared Dart UI/test changes and backend changes retain all six macOS Flutter
  integrations, one Debug build/signature check, native Xcode tests, both iOS
  simulator acceptance suites and simulator C ABI verification. They omit macOS
  Release/incremental rebuilds and the iOS device Release build for that PR.
- Native code, packages, dependency manifests/locks, assets, build tools,
  workflows and unknown paths require full Apple verification before merge.
- A platform-only change runs that platform's full checks, not the other Apple
  app build. A docs-only change skips Apple toolchain setup/builds. Other jobs,
  including the Flutter repository suite and its documentation contracts, retain their
  coverage; docs-only CI is therefore not yet a two-minute pipeline.

`tools/ci/apple_verification_scope.py` compares the tested PR merge tree to its
first parent and validates both parents against the event. A depth-two checkout
is sufficient. It uses a NUL-delimited diff with rename detection disabled, so a
move out of a sensitive directory still selects full verification. Missing
history, unexpected checkout shape, malformed event or an empty diff selects
full verification. A planner/test process failure fails the existing job; it
cannot silently green a skipped required check.

## Full verification

Main pushes, manual `workflow_dispatch` and the nightly schedule always retain
full Apple checks, including repeated Debug/Release signing/packaging checks and
iOS arm64 device exports. The nightly cron is `23 18 * * *` UTC (02:23 Asia/Singapore);
GitHub may delay scheduled runs. The actual publishing workflow is unchanged.
Scheduled verification does not publish a release. Event types have independent
concurrency groups so a scheduled run cannot cancel a main-push verification.

Local scripts default to full coverage. `VERIFY_APPLE_FULL=0` is an explicit
Debug-only override; `VERIFY_FLUTTER_TERMINAL_SKIP_DESIGN_TESTS=1` is intended only
when an independent blocking visual gate has already run. A failed gate must
remain failed; this flag is not a way to ignore a visual regression. Both accept only `0` or `1`.

## Validation and remaining work

Run the dependency-free policy/script tests with:

```sh
python3 -m unittest discover -s tools/ci -p 'test_*.py' -v
bash -n tools/verify_flutter_terminal.sh
bash -n tools/verify_macos_app.sh
bash -n tools/verify_ios_simulator.sh
```

The script tests execute the real shell entrypoints with toolchain stubs. They
verify test selection, full/Debug build counts and failure propagation; they do
not substitute for native macOS/iOS or Flutter execution. iOS guard placement
also has a source-contract test.

The repository script now reports elapsed time for each Rust, Go, Dart,
Flutter, contract and performance phase. Keep the small performance smoke,
Go default-store and MySQL race tests, SSH/ZMODEM and vendored Rust checks for
now: their removal has not been justified by phase measurements. The independent suites below remove the native/Dart serial dependency without
removing those checks.

Do not compare an early-failing run against a fully successful run as a speedup.
Record successful-run wall time, job/phase time and runner time separately.
These changes do not claim a measured 10-20 minute PR gate. CI/config changes
(including this optimization PR itself) deliberately take the full Apple path.

## Independent repository suites

`VERIFY_FLUTTER_TERMINAL_SUITE` accepts only `all` (default), `native`, or
`flutter`. The default local entrypoint still performs the original complete
verification. In CI the same script is selected twice on independent macOS-26
runners:

| Job | Coverage |
| --- | --- |
| Rust and Go checks | Completion core, zsh PTY matrix, Go default-store race, both vendored crates, application Rust core and packaged ABI contracts. Serial Rust test settings are retained. |
| Dart and Flutter checks | Native FFI build, generated/sync/protocol contracts, format/analyze, all package tests, repository contracts, performance smoke and Example tests. Visual baselines remain a separate blocking step in this job. |

The old `Flutter terminal (macos-26)` check is now a small aggregation job. It
requires **both** independent jobs to report `success`; failure, cancellation,
skipping and missing results all fail. The individual jobs have no dependency
on each other. No test has `continue-on-error`, and no platform coverage moves
from macOS to Linux. The native job does not install Flutter.

After dependency setup succeeds, the archive and repository verification steps
run even if the visual comparison fails. That visual step stays failed, so the
job and aggregation remain red. The already-executed design suite is excluded
from the second discovery pass for both passing and failing visual results.
This exposes additional failures in the same run without re-running the same
visual comparison.

Failure images are still uploaded on ordinary PRs. Generating a second set of
baseline candidates is optional diagnostic work: use manual `workflow_dispatch`
with `render_baseline_candidates=true`. Generated candidates are never committed
or accepted automatically. The manual run retains the failed visual gate.

## Rust dependency cache

The repository-owned `.github/actions/cache-rust` composite uses
`Swatinem/rust-cache` 2.9.3 pinned to commit
`d1527c8f67ef9af357290475d4af4b0fab8f12e0`. It is used by the two repository
suites and by the macOS/iOS app jobs, after Rust installation. Its key includes
runner OS/architecture and the Xcode version/build; the action also includes
Rust/compiler environment and Cargo manifests/locks. Job isolation remains
on. Apple SDK/deployment-target variables are included in the environment key.

Only Cargo dependency caches and the declared Cargo target directories are
eligible. Workspace crates and Cargo-installed executables are not cached.
No Flutter SDK cache switch is enabled, and no Xcode DerivedData, signed apps,
credentials, test reports or golden baselines are added to the cache. Product
builds and tests still run on cache hits. Dependency caches may be saved even
when a later product test fails; GitHub's branch/PR cache scoping still applies.
A cold run or unavailable cache cannot be assumed to provide any acceleration.

## Measuring the second pass

Splitting the suites adds one macOS runner and an Ubuntu aggregation job. It
reduces serial work, but may increase runner minutes and queueing. Compare
successful runs with similar changes, cache conditions and runner images;
record queue delay separately from execution time. Do not substitute a sum of
job durations for elapsed workflow time, or subtract overlapping parallel work.

`test_parallel_verification.py` executes the real script with toolchain stubs
and checks that the multiset of commands in `native` plus `flutter` equals
`all`, including failure propagation and newly discovered Example tests. It
also executes the exact aggregation shell step for 25 result combinations and
checks the blocking visual step, manual diagnostics and immutable cache pin.
These orchestration tests do not establish that Flutter, Rust or native Apple
product tests pass. Existing product failures are not hidden by the CI changes.
