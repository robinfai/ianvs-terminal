# Example CI: one runner, bounded test concurrency

The Example check uses one `macos-26` job and one Flutter invocation:

```sh
flutter test --no-pub --reporter=expanded --concurrency=2 <discovered files>
```

Flutter schedules up to two test processes internally. Two independent Flutter
launchers in the same checkout are not used: different `TMPDIR` values do not
isolate `.dart_tool`, test assets or Native Hook outputs. Test discovery retains
all regular `*_test.dart` files except `test/design/**` (a separate blocking
visual gate) and the externally provisioned `cat_log_benchmark_test.dart`.
The local full-suite shell entrypoint and other CI jobs remain unchanged.

## Dependency preparation and failure handling

After the Cargo dependency cache is restored, the Example job verifies the
canonical and packaged core manifests with `cargo fetch --locked --offline`
for the installed Rust host triple. If the cache is incomplete, it fetches
locked dependencies online. There are at most three online attempts per
manifest, each bounded to 120 seconds; only transient network failures/timeouts
are retried, with 5/10-second backoff. The workflow also limits the entire
preparation step to ten minutes. Invalid manifests/lockfiles, certificate and
checksum errors are not retried. TLS checking and registry selection are unchanged.

Only after preparation succeeds do the Debug prebuild and Flutter test steps
run with `CARGO_NET_OFFLINE=true`. This is Cargo offline mode, not a claim that
every Flutter operation is network-free. Test processes and builds are never
retried or allowed to fail silently. Any nonzero test exit fails the Example
job and the existing required aggregate check.

The Debug prebuild is retained for existing FFI tests. It does **not** replace
the release-mode native build in the package hook's own output directory.
This change does not reuse signed apps or bypass native source invalidation.

## Diagnostics and verification

`example-test-diagnostics` retains `flutter.log`, `test-files.json` and
`summary.json` for seven days, including failed test runs. Logs are streamed
live and preserved in full. SIGINT/SIGTERM cancels the test process group.
The summary duration includes any Native Hook build triggered by `flutter test`;
it is not a pure-test benchmark. Compare successful workflow wall time, queue
time, Example execution time and runner-minutes separately.

Run the focused orchestration tests without Flutter/Xcode:

```sh
python3 -m unittest discover -s tools/ci -p 'test_example_execution.py' -v
```

These use mocked dependency fetches and real subprocess fixtures. They validate
orchestration, not product behavior. A successful macOS GitHub Actions run is
still required before merging or making performance claims. Persistent DNS or
registry outages remain hard failures after the bounded fetch retries.
