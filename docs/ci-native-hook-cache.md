# Native Hook compiler-cache pilot

This pilot follows the successful diagnostic baseline at `86fdbe6`. It is an
experiment, not a measured speedup. Compare complete successful runs, including
queue time, setup time and runner-minutes; do not compare an early failure with
a successful run.

## Scope and correctness boundary

Only the existing `flutter-checks` job opts in, through the existing
`.github/actions/cache-rust/action.yml` composite action. No job, shard, test,
Apple verification scope, branch-protection check or concurrency setting changes.
Example remains one Flutter invocation with concurrency 2. Other callers of the
composite keep their previous cache/build behavior.

The pilot installs `sccache` **v0.16.0** using the commit-pinned Mozilla action
**v0.0.11**. Its setup verifies the downloaded release checksum and exports the
GitHub cache v2 runtime connection. It uses the GitHub Actions cache backend;
no external cache account or new credential is required.

A generated `RUSTC_WRAPPER` delegates to `tools/ci/native_hook_cache.py`. It only
routes **registry-source `lib`/`rlib` compilations inside recognized Native Hook
Cargo target directories** through sccache. Unknown configurations go directly
to rustc. Project sources, vendored/path/git crates, build scripts, proc macros,
executables, static libraries and dynamic-library linking bypass this new cache.
The existing Cargo cache is unchanged. This is deliberately a cross-run pilot,
not an attempt to force reuse across different source/configuration directories.

Cargo and the Hook still run normally. There is no `cache-hit` test skip, no
restored `.dart_tool` Hook state, no copied final dylib, and no shared target
directory. The canonical and packaged source trees still have their own Hook
outputs. The two clean ABI builds and native Debug prebuild also bypass the new
compiler cache. Their commands and verification remain unchanged.

The cache namespace identifies Rust/Cargo, Flutter, Xcode, SDK, Clang, host
architecture, the pub lock and Hook implementation. Each eligible compiler call
adds a hashed `CARGO_IANVS_NATIVE_CACHE_CONTEXT` identifying the canonical or
packaged Hook, Hook configuration and effective Apple compiler environment,
including the deployment target. sccache v0.16 hashes `CARGO_*` variables for Rust,
in addition to source/dependency contents and compiler arguments (including target
and optimization flags). Its C-only custom cache-buster is not used for Rust.
Compiler arguments and optimization profiles are not rewritten.

Only a sccache server I/O error may fall back to the local compiler via its
supported setting. Compiler failures are not retried or converted to success.
The wrapper uses `exec`, preserving exit status and signals. Cache/tool setup
errors remain visible failures, rather than silently disabling verification.

## Evidence and acceptance

Existing `CI_NATIVE_PHASE` records retain their Native Hook attribution and gain
numeric sccache counter snapshots before/after each phase while the pilot is on.
Snapshots are process-wide: nested parent/child ranges overlap and must not be
summed. Missing statistics are explicitly unavailable, not zero hits. Counts do
not turn an individual Hook's `cache_status: unknown` into a claimed cache hit.

The existing `flutter-native-phase-diagnostics` artifact includes the phase
records and `compiler-cache/configuration.json`, with seven-day retention. Raw
cache URLs, runtime tokens and arbitrary environment variables are not recorded.
The Mozilla action also prints aggregate sccache statistics in its post step.

Acceptance requires a full green CI run followed by a comparable warm-cache run.
Inspect Golden, Dart PTY and Standalone Core phase durations, eligible compiler
requests, hits/misses/errors, total Flutter-job time and whole-workflow wall time.
A first cold run may be slower due to cache population and network overhead.
Zero requests means the routing or environment propagation needs investigation;
it is not proof that compilation disappeared. A warm-cache speedup remains
unproven until these runs finish. Do not extrapolate a Flutter improvement past
the parallel macOS App job's critical path.

Local validation uses Python fixtures and real subprocess stand-ins, not real
macOS/Rust/Flutter compilation. Run:

```sh
python3 -m unittest discover -s tools/ci -p 'test_native_hook_cache.py'
```

## Rollback

Set repository Actions variable `IANVS_NATIVE_HOOK_CACHE` to `off` to skip the
three experimental setup steps. The next fresh runner uses the original Hook
and Cargo paths and emits no compiler-cache snapshots. The standard tests and
strict summary gate still run. Alternatively revert the pilot commit. Do not
change `CARGO_TARGET_DIR`, copy a dylib, or loosen a test to make a cache run pass.
