# macOS release/update verification — 2026-09-20

## Verified

- Repository ruleset `23715048` is active for `refs/heads/main`: PRs required,
  deletion/force pushes prohibited, no bypass actors.
- The local universal release build succeeds and embeds Sparkle 2.10.0.
  `LSMinimumSystemVersion` is `14.0`; Xcode resolves the iOS target to `17.0`.
- Eight Python release tests and real EdDSA matching/mismatched-key and
  archive-tampering checks pass.
- [Update CI on d0fef222](https://github.com/robinfai/ianvs-terminal/actions/runs/35499238448)
  passed the complete macOS build and native configuration/shutdown tests.
- [MySQL and SSH CI on d0fef222](https://github.com/robinfai/ianvs-terminal/actions/runs/35499238447)
  passed after the GORM quoting and Rust type/argument cleanup. Local Rust 1.88
  strict Clippy, 390 native unit tests, SQLite race tests, and source-mirror
  validation also passed.

## Actual old-to-new update acceptance

The full client was tested on macOS 27.0, using isolated bundle ID
`work.ianvs.trail.update-test`, ephemeral Ed25519 keys, ad-hoc code signing, and a
loopback HTTP feed. This does not modify `/Applications/Trail.app` or its data.

| Scenario | Observed result |
| --- | --- |
| Check from build 900001 | UI offered 9.0.900002; signed feed fetched successfully |
| Download | Reached Ready to Install after archive verification |
| Install and Relaunch → Cancel | Quit confirmation was shown; same process remained running at build 900001 |
| Recheck and retry → Quit | Existing save/termination handshake completed; installed bundle became 900002 and a new process launched from that same path |
| Check from restarted build 900002 | UI displayed “You’re up to date!”; native result was `SUNoUpdateError` 1001 with `OnLatestVersion` reason 1 |
| Change one ZIP byte, preserve length | Sparkle rejected the EdDSA signature before extraction; installed build stayed 900001 |
| Change signed appcast text, preserve length | Sparkle rejected the appcast signature; no subsequent ZIP request; installed build stayed 900001 |

During acceptance, the original synchronous installation action remained on the
accessibility call stack while AppDelegate ran its modal quit confirmation.
The updater now postpones relaunch until the next main-queue turn, so the button
action returns before entering that confirmation. Cancel, retry, install and
relaunch were then exercised successfully through the actual UI. AppDelegate's
existing quit/save protection is unchanged. A native regression test checks that
the relaunch handler is deferred, and updater logs record result codes without
URLs, file paths or error userInfo.

## Remaining release limits

- No Developer ID Application identity is installed locally; Actions release
  secrets/variables are empty. Apple notarization, a public GitHub Release, and
  an old-to-new upgrade between real notarized releases remain unverified.
- The general Flutter verification job now passes the previous Clippy gate but
  fails `session_frame_diff_defers_split_inline_clear_until_repaint`
  (`native/core/tests/session_test.rs:18691`; 525 other session tests passed).
  No checks have been waived. This terminal repaint failure is separate from
  the passing updater checks and acceptance described above.
- The four-version policy defines required coverage, not completed testing on
  four operating systems. iOS runtime acceptance has not been performed here.

See [release setup](MACOS_RELEASE.md) for credentials and reproducible isolated
acceptance steps, and [platform policy](../APPLE_PLATFORM_COMPATIBILITY.md) for
current supported versions. Never attach temporary private keys to the PR.

## Merge preparation — 2026-09-24

Main commit `ffac7a02` was merged into this branch. Its shared GORM column
predicate and SSH options refactor supersede the equivalent fixes previously
made here. Its terminal test synchronization also replaces the elapsed-time
assumptions behind the earlier animation failure. The remaining PR diff is
limited to the updater, release tooling, and Apple compatibility policy.

Source-mirror verification, eight release metadata tests, shell syntax and
Apple project/plist checks pass after conflict resolution. Updated CI must
validate the integrated revision. Production signing and notarization still
require the credentials documented above.
