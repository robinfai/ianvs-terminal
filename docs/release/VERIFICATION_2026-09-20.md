# macOS release/update verification — 2026-09-20

## Verified

- Repository ruleset `23715048` is active for `refs/heads/main`, requires PRs,
  prohibits deletion and force pushes, and has no bypass actors.
- [macOS Update Checks run 35494009360](https://github.com/robinfai/ianvs-terminal/actions/runs/35494009360)
  passed on commit `fbc49fcb`: eight Python release tests, real EdDSA key-match
  and archive-tampering checks, complete macOS debug build with embedded Sparkle,
  and RunnerTests covering update configuration and safe shutdown.
- The local universal release build succeeds, embeds Sparkle 2.10.0, and after
  the compatibility-policy update reports `LSMinimumSystemVersion = 14.0`.
  Xcode resolves the iOS deployment target to `17.0`.
- An isolated ad-hoc signed `work.ianvs.trail.update-test` client at build
  `900001` fetched a locally signed appcast, displayed version `9.0.900002`,
  downloaded the signed ZIP, and reached **Ready to Install / Install and Relaunch**.
  The test used an independent application-support directory and temporary keys.

## Not yet verified / release blockers

- The UI automation could not reliably inspect the multiple update/quit windows.
  Cancellation, installation/relaunch to build `900002`, subsequent up-to-date
  checking, and GUI handling of corrupted archives/feeds remain unverified.
  No successful installation is claimed. Unconfirmed window-focus changes were
  removed; the existing AppDelegate termination handshake is retained.
- No Developer ID Application identity was available locally; repository Actions
  release secrets and variables were empty when checked. Production signing,
  Apple notarization, public GitHub release publication and a real old-to-new
  notarized client upgrade therefore have not been exercised.
- The general Verify workflow already fails on main, independently of this work:
  Rust clippy flags type complexity/argument count, and the MySQL auth contracts
  fail on an unquoted `key` column in DELETE statements. This change does not
  alter those sources or waive their checks.
- The four-version policy defines required coverage; it does not claim all four
  systems were tested. Local iOS simulator runtimes are 18.4 and 26.3.1; no iOS
  runtime acceptance or four-OS compatibility matrix was performed in this task.

See [release setup](MACOS_RELEASE.md) for credentials and reproducible isolated
acceptance steps, and [platform policy](../APPLE_PLATFORM_COMPATIBILITY.md) for
current supported versions. Never attach the temporary private keys to a PR.
