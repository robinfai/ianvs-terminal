# Verification scope and CI cost

## Pull requests

The existing required-check names are unchanged. There is no workflow-level
path filter: the checks still report a result even for documentation-only PRs.

- Visual baselines remain a blocking step. Once that step succeeds, the
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
  including the Flutter repository suite and its documentation contracts, are
  unchanged; docs-only CI is therefore not yet a two-minute pipeline.

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
when the separate visual gate has already passed. Both accept only `0` or `1`.

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
now: their removal has not been justified by phase measurements. A subsequent
change can use those measurements to isolate/shard the actual slow suite.

Do not compare an early-failing run against a fully successful run as a speedup.
Record successful-run wall time, job/phase time and runner time separately.
This first pass does not claim a measured 10-20 minute PR gate. CI/config changes
(including this optimization PR itself) deliberately take the full Apple path.
