# macOS 0.1.0 → 0.1.1 verification

## Scope

Verify the real GitHub/Sparkle Developer ID distribution path. The baseline is
the published, unmodified Trail 0.1.0 (896), with its HTTPS test-channel feed.
An ad-hoc fixture or a passing build alone does not establish a successful
production-signed upgrade.

## Login and release prerequisites

- Release source: `9bfad0d956135f56d8ae743fb89f486e8c32ab14`.
- macOS Apple login uses `ASWebAuthenticationSession`, directly authorizes with
  Apple, and returns to the app. Developer ID builds do not request the
  unsupported native Apple sign-in entitlement. iOS retains native sign-in.
- The HTTPS callback verifies Apple's ID token and nonce. The app retrieves
  the result once using a separate secret; callback URLs contain no ID token.
- The test backend runs `ianvs-api:9bfad0d9`. A real macOS login returned to
  the client and showed the signed-in account and linked Apple identity.
- Local macOS native tests: 37 passed, 0 failed; Flutter authentication tests:
  11 passed; focused Dart analysis and backend Go tests passed.
- [macOS Update Checks](https://github.com/robinfai/ianvs-terminal/actions/runs/41435591857)
  passed on macOS 15. This run precedes the final system-auth change; the 37
  local native tests above cover the final source revision.
- [Signed release workflow](https://github.com/robinfai/ianvs-terminal/actions/runs/41437760510)
  is the release run used for acceptance.

## Device coverage

Local interactive validation uses macOS 27.0.1 (26A434). This does not claim
interactive verification on macOS 14, 15, or 26, or on Intel hardware.

## Upgrade acceptance

- The release workflow succeeded and published v0.1.1 (953). Its test-channel
  appcast now advertises 0.1.1; the original 0.1.0 ZIP checksum is unchanged.
- Cleared only `SULastCheckTime` and launched the original signed 0.1.0. Its
  process logged successful EdDSA verification of the appcast at 20:06:18 local
  time, without first using the manual Check for Updates command.
- A Software Update window is listed in the native Window menu. However,
  automation currently sees only the terminal window. A later manual check and
  quit diagnostic did not expose the update/confirmation dialogs to automation.
  A process sample confirms it is waiting in the quit confirmation's modal loop.
- Installation/relaunch and the resulting installed version are **not yet
  verified**. User assistance bringing the dialog forward is pending. Do not
  describe this as a completed end-to-end upgrade.

## Window activation follow-up

Inspection found that app reopening always selected the terminal main window,
even with a native confirmation or another key window open. The follow-up fix
prioritizes the application's modal window, then its visible key window, and
falls back to the existing main-window selection. The Dart shutdown lookup is
unchanged. This is not included in the already-published 0.1.1 archive.

All 40 local native tests passed, including new regressions for modal priority,
preserving a visible update window, hidden-window fallback, and keeping Flutter
as the shutdown target. Actual old-to-new upgrade acceptance remains pending.
