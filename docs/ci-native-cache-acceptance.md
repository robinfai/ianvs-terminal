# Real Native Hook cache acceptance

This supplements (not replaces) the complete Verify workflow. It is a correctness
experiment, not a timing benchmark. The dedicated `Native cache acceptance`
workflow only runs for PRs changing the cache/Hook/acceptance implementation,
or on manual dispatch. It adds one macOS runner to those acceptance runs, not to
ordinary UI/documentation PRs. Its job ID is `flutter-checks` because the unchanged
cache pilot deliberately admits that ID; its visible check name is distinct.

## What executes

On a real macOS runner, use the existing pinned toolchain, scoped PATH bridge,
registry-only compiler admission, and locked dependency preparation. Create a
throw-away Git worktree at the checked-out revision. Append the same test-only
exported function to the canonical and packaged source copies, never to the PR's
product sources. For each source tree execute four locked Release builds:

1. Disable the cache. Build into an empty target and load the new dylib; expect
   marker 101 and zero new compiler-cache requests.
2. Enable the cache. Again build into an empty target; expect marker 101 and
   actual compiler-cache requests. This populates the isolated acceptance scope.
3. Change source marker to 202, clear only that allocated target, rebuild with
   caching, and load in a new Python process. Require marker 202 and actual cache
   hits for dependencies. No final library or Cargo target is restored.
4. Add the real Rust compiler flag `--cfg=ianvs_ci_cache_probe`, clear the target,
   rebuild, and load in a new process. Require marker 1202 and compiler cache
   misses. Cache context/arguments cannot silently reuse an old result.

Both canonical and packaged sources must pass all four cases. Each dylib load
uses a fresh process to avoid dyld image reuse. Rust library admission remains
unchanged: product/path/vendor crates and final linking are not cached. The
acceptance uses the host target and an explicit macOS deployment target of 13.0;
it does not claim coverage of every SDK, deployment target, or Flutter Hook
invalidation path. Ordinary Verify still supplies real Flutter integration,
Golden, PTY, package, macOS/iOS, and repository checks.

Compile/test failures are not retried. Cache errors, missing statistics, counter
resets, unexpected old runtime values, modified Cargo locks, or cleanup failures
fail acceptance. Build concurrency remains two. Full logs and a machine-readable
summary are uploaded as `native-cache-real-acceptance` for seven days.

## Merge gate for PR #15

Require a new complete Verify AND this real acceptance workflow to succeed on the
same final PR head. Check `summary.json`: `passed=true`, eight distinct successful
(package, case) pairs, expected observed values, and the matching `pr_head_sha`.
Do not count carried-forward results from a single-job rerun as a new complete
Verify. Do not merge a newer, unverified head. No required check may be bypassed.

The historical same-head Flutter measurements (37m06s zero-hit sample, 28m48s and
22m20s later samples) are job execution times, not complete-workflow times or a
stable average. Acceptance duration must not be used as a performance comparison.
After merge, main must build its own cache and complete its push-triggered Verify;
PR cache reuse does not establish main's warm performance.

Local Python tests validate orchestration only. They cannot prove the eight real
macOS builds passed; those results must come from GitHub Actions.
