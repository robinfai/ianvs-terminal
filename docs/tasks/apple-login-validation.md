# Apple login and TestFlight launch validation

The release archive previously stripped the process symbols used by Dart FFI.
`Runner` now uses `-export_dynamic`, the existing explicit Ianvs export list,
and `STRIP_STYLE=non-global`. `tools/verify_ios_native_exports.sh` checks the
actual dyld export trie; the full iOS verification gate now checks an archive
as well as ordinary builds. Build 2 fails this check; build 3's archive and
App Store export both pass all 26 expected symbols. This is binary validation,
not a claim of physical-device runtime validation.

Apple login deployment requires the server `apple_client_ids` configuration,
Apple App ID capability and matching provisioning profiles. Native consent,
hide-my-email, user cancellation and historical account binding must be tested
with the configured server and a signed internal TestFlight app on a physical
Apple device before a public release. Local tests use synthetic signed identities and
exercise signature/claim rejection, nonce replay, linking conflicts and the
existing authentication transaction; they do not impersonate real Apple users.

Local validation on 2026-10-31: Go `go test ./...`, Flutter analysis, 123
selected Flutter tests, and an unsigned iOS Release device build (iOS SDK 27).
The build targets iOS 17+, but no claim is made that all supported OS versions
have been exercised on physical devices.

Backend deployed through `ssh cloud` on 2026-10-31 as
`ianvs-api:apple-login-20261031` (image `b0ba814e660d`). A separate database
copy passed startup, integrity, Apple challenge, forged-token rejection and
password-authentication rejection checks before cutover. Both copies contained
the original five users. Public HTTPS health and Apple challenge requests now
return 200, and an invalid identity token returns 401.

Production enables `apple_client_ids: [work.ianvs.trail]` and preserves
`allow_registration: false`: an unlinked Apple identity must first bind an
existing account. Backups are in
`/var/backups/ianvs-api/apple-login-20261031` on cloud, including original config
and the stopped-database snapshot `ianvs-before-cutover.db`. The previous
container is retained as `ianvs-api-before-apple-20261031`. Rollback requires
stopping the new container, restoring the original configuration, and restoring
the previous container name and starting it; do not replace the live database
with an old snapshot without assessing newer user writes.

Apple Developer Sign In with Apple capability was enabled with user confirmation.
The combined build 0.1.0 (4) was archived, exported and uploaded successfully at
19:17 CST on 2026-10-31. Both archive and distribution IPA pass all 26 dynamic
export checks; the distribution signature and embedded profile include Apple
sign-in `Default`, and `get-task-allow` is false. Local exported IPA SHA-256:
`e9528e25f218a8b6183f707ed0aa7bba52742929d22c51bc4bab8d374fe2bd42`.
Apple processing completed successfully. The user explicitly confirmed the
export encryption answers (standard encryption outside Apple's OS; no France
distribution for this internal test), which were submitted successfully.
Build 4 was added to Trail Internal. App Store Connect shows its existing tester
has installed 0.1.0 (4) on iPhone 17 / iOS 27.0.1. Installation status alone does
not verify startup or the native Apple login/binding flow. Startup-only build 3
was not uploaded, as requested.

References: [Apple identity verification](https://developer.apple.com/documentation/signinwithapple/verifying-a-user)
and [native Apple authentication](https://developer.apple.com/documentation/signinwithapple/authenticating-users-with-sign-in-with-apple).

Build 0.1.0 (5) was archived and uploaded on 2026-11-01 at 00:22 CST.
It adds Apple sign-in and historical-account linking to initial setup and
startup recovery, reusing the existing authentication transaction. The focused
Flutter suite passed 33 tests, including light/dark iOS login, linking,
cancellation and retry; targeted analysis reported no issues. Archive and
exported IPA both pass all 26 dynamic export checks. The distribution signature
and profile include Apple sign-in `Default`, with `get-task-allow` false;
strict signature verification passes. Exported IPA SHA-256:
`eef25f77ff7b813d59310ce1ccc51f3797cbcbc5826188b068b54d95bc721c07`.
Xcode reports upload succeeded. After browser login was restored, App Store
Connect confirmed processing completed for build 5. The user explicitly
confirmed standard encryption outside Apple OS and no France distribution for
this internal test; those export-compliance answers were saved successfully.
Build 5 was added to Trail Internal. App Store Connect now reports the existing
tester has installed 0.1.0 (5) on iPhone 17 / iOS 27.0.1. Installation status
does not validate Apple consent or historical-account linking.
Physical-device Apple consent and historical-account linking remain for the
user to validate after distribution.

On 2026-11-01, iOS and macOS settings gained persistent account presentation.
Successful authentication stays in the form and shows the canonical account
username and service origin. Stored accounts, including expired sessions, hide
sign-in methods until explicit sign-out. Sign-out uses the existing durable
configuration transition and token cleanup queue; failures before commit retain
the account, while post-commit cleanup warnings retain retry information.
Settings reads expose only non-secret account metadata. Tests cover both Apple
platforms, account reload, historical linking, expired-session recovery,
sign-out failures and deferred cleanup. All 147 selected tests pass and targeted
analysis reports no issues.

The macOS profile-signing workflow now carries Sign in with Apple into its
generated entitlements. A production-identifier (`work.ianvs.trail`) Apple
Development build completed on macOS 27.0.1, and both its signature and embedded
profile contain Apple sign-in `Default`. Strict signature and native-library
checks pass. The final app is at
`example/build/macos/Build/Products/Release/Trail.app`. This is a local development
build, not a notarized public release. Native Apple consent on macOS still
requires user validation. The account-state changes have not been uploaded to
TestFlight; the previously distributed iOS build 5 predates these changes.

The latest account-state changes were archived as iOS 0.1.0 (6) on 2026-11-01.
Archive and exported distribution IPA pass the 26 native-export checks and
strict signature verification. The distribution signature retains Apple sign-in
`Default` and `get-task-allow=false`. Exported IPA SHA-256:
`dafe6e2c0eebb9d0f551b5cb56a3d52472293539c8691582a1d9870e609f9f9e`.
Xcode confirms successful upload at 01:31 CST. App Store Connect processing
completed; export compliance uses the previously confirmed standard encryption
and no France distribution answers. Build 0.1.0 (6) is assigned to Trail Internal
and its group build list confirms Testing (90 days remaining).

The user explicitly authorized terminating the previous macOS process after
normal quit did not finish. The previous installed application is preserved at
`/Applications/Trail-before-apple-login-20261101.app` and in
`/private/tmp/trail-macos-install-20261101/Trail-previous.app`. The latest signed
package was installed to `/Applications/Trail.app` and launched successfully.
Installed executable SHA-256:
`382ecf4101b075f995d543f30f2fb22172ec02a1630fad106603a32607993b27`.
Its data-sync settings show the stored account and service origin, hide the
login form, and expose explicit sign-out. A separate sync-incomplete notice is
visible; successful UI startup is not a claim that synchronization or native
Apple consent has been validated. The app remains on that page for user testing.

### 2026-11-01: on-device sync failure and notification cleanup

Validated on a physical iPhone 17, iOS 27.0.1 (24A446), through iPhone
Mirroring. The development-signed app updates the existing `work.ianvs.trail`
installation without clearing its account or local data. Other supported OS
versions were not physically tested in this pass.

The original failure was `NonCanonicalCurrentTerminalConfigException` while
reading the remote `config/local-terminal`, not an Apple authentication or
cipher failure. A developer-opt-in diagnostic recorded only code locations,
exception types, and schema paths. The only shape differences were missing
`/shellIntegration/sshWrapper` and `/shellIntegration/sshAutoInject` fields.
Both were added within schema version 1 with defaults of `true`; strict
canonical comparison incorrectly rejected older valid documents.

Both the remote adapter and local-first sync now tolerate those two absent
optional fields. Explicit false values remain false; null/invalid values,
unrelated missing fields, unknown fields, and unsupported schemas still fail
validation. Merely reading an older document does not rewrite it. Regression
tests cover the exact missing-field case and explicit invalid values.

The original remote settings were backed up through the existing revisioned
recovery resource before explicit format repair. Sync then surfaced a real
first-sync difference at `/defaultProfileId`: this phone used automatic
selection while the remote document specified a profile. The user stated that
either choice was acceptable for this test data; the phone's automatic
selection was retained. Subsequent sync and app restart no longer showed
failure or conflict.

Notification review and changes:

| Surface | Result |
| --- | --- |
| Sync settings | Hide idle/local-only prose and unconditional conflict explanation; show persistent, resource-specific failures and actual conflicts only. |
| Sync retry | Distinguish auth, network, timeout, TLS, key availability, decryption, format, HTTP rejection, revision, and local-storage failures; retain retry and backup/repair actions. |
| Manual sync success | Briefly change the button to “Sync complete”, then restore “Sync now”; visible inside fullscreen settings, unlike a snackbar behind the dialog. |
| Account panel | Keep account identity and sign-out; remove repeated sign-out instructions, encryption prose, and save boilerplate. Key management details remain in Advanced. |
| Shared notifications | Explicit success/info/failure semantics; passive success/info use 2 seconds, failure uses 8 seconds with dismiss/error styling; passive success does not obscure active failures. |
| Clipboard, saved connections, file/image operations | Short success feedback; failure uses the common error treatment. |
| SFTP, SSH auth, voice input, system notification errors | Keep actionable failures visible and use common failure feedback. |
| AI settings and recording | Short settings-save feedback; remove redundant recording-start toast and duplicate recording-load error toast when an inline error already exists. |
| Master key operations | Successful operation text expires after 2 seconds; failures remain visible. |
| Permission/security confirmations and recovery actions | Retained; these require user action and are not ordinary informational notices. |

The whole example app passes static analysis. Focused suites cover sync,
backup-before-repair and backup failure, adapter compatibility, notification
priority/lifetime, fullscreen success feedback, account settings, clipboard,
SSH prompts, voice input, AI settings, key management, recording, SFTP, and
Data API architecture boundaries. The final phone build disables opt-in
filesystem diagnostics. The iOS native export check (26 symbols) and strict
code-signature verification pass. This is a development-signed device build;
this follow-up did not upload another TestFlight build.

Final device executable SHA-256:
`9aaf6c6cce6769faee5e903bb0830a003bad7e0961d786d3ea5e46b504610197`.
The final installation was launched and the sync settings were revisited:
account identity remained present and repeated manual syncs returned to the
idle action without failure/conflict controls. The fullscreen-dialog feedback
regression test also passes (14 sync-panel tests). Healthy-screen evidence:
`/private/tmp/trail-sync-phone-final-success.png`.
