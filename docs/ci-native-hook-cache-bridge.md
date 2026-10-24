# Native Hook cache environment bridge

## Why Verify #276 recorded zero requests

The cache installer and configuration steps were present in the existing
`cache-rust` composite. However, Flutter 3.44.2 pins `hooks_runner` 1.1.1, and
Dart Hooks run in a semi-hermetic environment. `PATH` is forwarded, whereas the
parent's `RUSTC_WRAPPER`, GitHub job identity, sccache settings and custom pilot
flags are not automatically inherited. Copying `Platform.environment` inside
our Hook cannot recover values already removed by the runner.

Consequently, exporting the wrapper to `GITHUB_ENV` was not sufficient. A green
product suite with zero sccache requests is not a successful cache experiment.

Primary references:

- https://github.com/flutter/flutter/blob/3.44.2/packages/flutter_tools/pubspec.yaml
- https://pub.dev/documentation/hooks/latest/hooks/#environment
- https://github.com/mozilla/sccache/blob/v0.16.0/src/commands.rs
- https://github.com/mozilla/sccache/blob/v0.16.0/src/config.rs

## Transport and unchanged admission policy

`native_hook_cache_bridge.py bootstrap` runs the existing toolchain configuration,
then generates a job-private Cargo shim, compiler wrapper and runtime file.
`GITHUB_PATH` adds the shim directory before the next Flutter/Dart invocation.
The shim uses the runner's supported PATH propagation, not a patched SDK or a
change to either product Hook.

Only recognized repository-local Hook Cargo target paths restore an explicit
allowlist of non-secret pilot settings. Unknown paths, Debug prebuilds and clean
ABI targets directly execute the original Cargo. The original Cargo proxy path
is retained without resolving its symlink to `rustup`. Explicitly disabled calls,
other jobs, existing foreign wrappers and symlink escapes cannot silently opt in.

The original `native_hook_cache.compiler_command` remains the admission authority:
only registry-source lib/rlib compilations are cacheable. Product, path, vendor,
git, build-script, proc-macro and final-library compilations remain excluded.
No compiler flags or manifest/target arguments are rewritten; there are no
compilation retries, test skips, shared target directories or copied dylibs.
Both invocation boundaries use `exec` to preserve outputs, failure statuses and
signals. No new job, shard, test concurrency or Apple scope change is introduced.

The bridge hashes its own implementation into the existing toolchain/Hook epoch.
Runtime settings live under RUNNER_TEMP with directory mode 0700 and file mode
0600. No runtime token, cache endpoint credential or arbitrary parent environment
is serialized. sccache's credential-bearing daemon is explicitly started by the
parent setup process on a fresh, job-private Unix socket. The same socket is
exported to clients and statistics readers. Idle timeout is disabled for this
job; the pinned action's post step retains its statistics/cleanup role.

Important: sccache v0.16.0 `--show-stats` can return empty statistics without
starting a server. Setup therefore calls `--start-server`, requires its socket
to exist, then checks initial counters. It never stops or resets another daemon.

## Real compilation acceptance gate

After the unchanged repository verification, `Require real Native Hook compiler
cache requests` checks actual invocation records from this job. It requires
Cargo bridge and eligible registry compiler events for both `ianvs_pty` and
`ianvs_terminal_core`, positive sccache compile/executed requests, and positive
Rust hits or misses. A cold run may pass with misses and zero hits. No fabricated
crate or synthetic prewarm contributes to these counters.

Missing records, unavailable counters, zero requests or only non-cacheable
requests fail this additional gate. Earlier product failures remain failures.
The gate runs after failures when dependencies resolved, but not after cancellation.
The existing always-uploaded `flutter-native-phase-diagnostics` artifact includes
`compiler-cache/bridge-events.jsonl` and `compiler-cache/usage.json`. Events contain
bounded decisions and presence booleans, not compiler arguments or environment
values. This supplements, rather than sums, the existing nested phase snapshots.

A passing routing gate is NOT proof of stable performance gains. Compare matched
cold/warm full successful runs, Flutter phases, queue delay, whole-workflow wall
time and macOS runner-minutes before accepting the performance experiment.

## Validation and rollback

Run `python3 -m unittest discover -s tools/ci -p 'test_native_hook_cache*.py'`.
New bridge tests explicitly use Python fixtures and subprocess stand-ins. They
exercise generated scripts under a stripped environment, quoting, failure exits,
SIGTERM, source/link exclusions, disabled/wrong-job paths, secret filtering,
namespace invalidation, concurrent diagnostic appends and zero-request rejection.
They do not claim to execute real Cargo, Flutter or Xcode. The real product
compilation gate must pass in GitHub Actions.

Setting the existing repository variable `IANVS_NATIVE_HOOK_CACHE=off` skips all
three cache setup steps and the new usage gate on a fresh runner. Product tests,
clean ABI builds and the strict aggregate gate continue unchanged. Existing
non-flutter jobs never install this bridge.
