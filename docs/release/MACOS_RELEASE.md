# macOS releases and updates

Trail uses Sparkle 2.10.0 (pinned exactly), Developer ID signing, Apple
notarization, signed update archives and a signed appcast. GitHub Releases hosts
both the app and the feed. This release requires macOS 14 or later under the project
[latest-four-major-versions policy](../APPLE_PLATFORM_COMPATIBILITY.md). The menu **Trail → Check for Updates…** opens Sparkle's
standard UI. Release clients check daily; automatic download/install is disabled.
Installation restarts the application through its existing confirmation and Dart
shutdown/save handshake. Development builds and builds without an update key do
not contact the release feed.

## Main branch and versioning

The repository ruleset `main requires pull requests` targets `refs/heads/main`,
requires PRs, prohibits force pushes and deletion, and has no bypass actors.
It requires resolving review threads, but no mandatory second reviewer, so the
owner can merge their own PRs. Ruleset ID: `23715048`.

`macos-release.yml` runs on a push to protected main (a PR merge), or a manual run
on main. Each merged revision is versioned `1.1.<git rev-list --count HEAD>`;
its build number is that same commit count. Full git history and no history
rewrites are required. No version-bump commits or writes to main are needed.
This series follows the existing `v1.0.0` release; it does not change iOS versions.

Publication is serialized. Already-published or superseded versions are skipped.
A draft release is populated with all assets before being made public/latest.
Reruns can resume only a draft targeting the same commit. The stable feed URL is:

`https://github.com/robinfai/ianvs-terminal/releases/latest/download/appcast.xml`

Do not mark unrelated releases or releases without a signed appcast as latest.
Do not replace published assets or rewrite tags. To roll back code, merge a revert
PR to produce a higher version number. Existing clients without Sparkle need one
manual installation of the first updater-enabled release.

## One-time credentials

Configure in **Settings → Secrets and variables → Actions**. Never commit keys.
The workflow fails before building/publishing if credentials are missing; it does
not silently downgrade public releases to ad-hoc or Apple Development signing.

Repository secrets:

| Name | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | Base64 of the exported Developer ID Application certificate **and private key** |
| `MACOS_CERTIFICATE_PASSWORD` | Password protecting that P12 |
| `NOTARY_API_KEY_BASE64` | Base64 of the Apple notarization-compatible App Store Connect API `.p8` key |
| `SPARKLE_PRIVATE_KEY` | Base64 32-byte Ed25519 seed exported by Sparkle `generate_keys -x`; this is the file's text, not base64 encoded a second time |

Repository variables:

| Name | Value |
| --- | --- |
| `MACOS_SIGNING_IDENTITY` | Exact identity, e.g. `Developer ID Application: Name (TEAMID)` |
| `NOTARY_KEY_ID` | Apple API key ID |
| `NOTARY_ISSUER_ID` | Apple API issuer ID (team API key) |
| `SPARKLE_PUBLIC_KEY` | Public key corresponding to `SPARKLE_PRIVATE_KEY` |

Use Sparkle's `generate_keys --account trail-production` once, then export and
back up the key securely. Keep this key across releases. Production CI verifies
that the public/private keys match before building. Certificates are imported
into a temporary runner keychain, signing files have restricted permissions, and
the keychain/files are deleted at job completion.

## Release validation

The workflow builds a universal app, signs nested Mach-O binaries and bundles
inside-out, verifies both architectures, submits to Apple, requires `Accepted`,
staples the ticket, runs Gatekeeper assessment, then packages/signs the final
archive bytes. It uploads the ZIP, signed `appcast.xml`, and `SHA256SUMS`.
The ZIP can be extracted and Trail.app moved to Applications for first install.

PR checks run release helper tests, real EdDSA validation/tampering tests, build
the macOS client, and run RunnerTests (including safe shutdown and update config).
The existing general Verify workflow remains separate.

## Isolated end-to-end acceptance

Run on a Mac with a graphical login. This uses temporary test keys and an ad-hoc
signed copy, and does **not** establish production notarization/Gatekeeper success.

```sh
# From the repository root:
bash tools/release/fetch_sparkle.sh /tmp/trail-sparkle
(cd example && flutter build macos --release)
bash tools/release/prepare_update_test.sh \
  example/build/macos/Build/Products/Release/Trail.app \
  /tmp/trail-update-fixture /tmp/trail-sparkle/bin 9123
python3 -m http.server 9123 --bind 127.0.0.1 \
  --directory /tmp/trail-update-fixture/downloads
```

Open `/tmp/trail-update-fixture/installed/Trail Update Test.app`. Its bundle ID is
`work.ianvs.trail.update-test`, separating application support and preferences from
Trail. Only this test identity accepts an HTTP loopback feed. All other feeds must
use HTTPS. The fixture starts at build 900001 and offers build 900002.

1. Select **Check for Updates…**; verify the offered version is 9.0.900002.
2. Download; request Install and Relaunch. Cancel the Trail quit confirmation;
   verify the old client remains running and has not been replaced.
3. Retry and confirm quit; verify the app restarts and the installed bundle's
   `CFBundleVersion` is 900002. Check again; it must report up to date.
4. For a fresh fixture, alter a byte in the ZIP after signing. Download must fail
   verification and the installed build must remain 900001. Also test an altered
   signed feed and unavailable server; neither may report an update as installed.
5. Repeat an old-to-new upgrade with real notarized releases from GitHub on a Mac
   with normal Gatekeeper settings before calling production updates verified.

Keep the test private key out of evidence/PR attachments. Stop the loopback server
and close the test client after acceptance.
