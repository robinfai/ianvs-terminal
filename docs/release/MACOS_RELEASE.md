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

`macos-release.yml` supports two modes on main:

- Manual **Run workflow** publishes the requested version (default `0.1.0`) as a
  GitHub Pre-release, never Latest. Add `docs/release/<version>.md` first.
- Pushes to main publish the existing stable `1.1.<commit count>` series only
  when `MACOS_RELEASE_ENABLED=true`. Leave this variable unset during testing.

Both modes require valid signing, notarization, and Sparkle credentials. The
separate Verify workflow still runs its applicable build and test gates.

Each merged revision is versioned `1.1.<git rev-list --count HEAD>`;
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
Free Apple accounts (Personal Teams) can be used for local development, but do
not meet Apple's [Developer ID requirements](https://developer.apple.com/developer-id/)
for the certificate and notarization required by this
production pipeline. Leave `MACOS_RELEASE_ENABLED` unset until a suitable Apple
Developer Program membership and all credentials below are ready. Sparkle keys
are generated separately and do not replace Apple's signing credentials.

After configuring credentials, manually publish a prerelease from Actions.
Set `MACOS_RELEASE_ENABLED=true` only when automatic stable publication is desired;
remove it or set it to `false` to disable automatic publication.
Once enabled, the workflow still fails before building/publishing if credentials
are missing. It does not silently downgrade public releases to ad-hoc or Apple
Development signing.

Repository secrets:

| Name | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | Base64 of the exported Developer ID Application certificate **and private key** |
| `MACOS_CERTIFICATE_PASSWORD` | Password protecting that P12 |
| `NOTARY_API_KEY_BASE64` | Optional: base64 of a team App Store Connect API `.p8` key; takes precedence over Apple account authentication |
| `APPLE_ID` | Developer Apple account email, when not using an API key |
| `APPLE_APP_SPECIFIC_PASSWORD` | Apple app-specific password, when not using an API key |
| `SPARKLE_PRIVATE_KEY` | Base64 32-byte Ed25519 seed exported by Sparkle `generate_keys -x`; this is the file's text, not base64 encoded a second time |

Repository variables:

| Name | Value |
| --- | --- |
| `MACOS_RELEASE_ENABLED` | Set to `true` to enable automatic or stable publication; manual prereleases do not require it |
| `MACOS_SIGNING_IDENTITY` | Exact identity, e.g. `Developer ID Application: Name (TEAMID)` |
| `APPLE_TEAM_ID` | Developer Team ID, when using Apple account authentication |
| `NOTARY_KEY_ID` | Apple API key ID (API key mode only) |
| `NOTARY_ISSUER_ID` | Apple API issuer ID (API key mode only) |
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

## 0.1.0 测试版与跨项目凭据复用

同一 Apple Developer 团队的 Developer ID Application 证书可用于 Trail 和
Linefold，无需为每个 app 重新申请证书。保留 Trail 自己的 bundle ID、entitlements
和 Sparkle 密钥。不要复制 Linefold 的 Quick Look 签名逻辑或更新密钥。

可从本机加密 P12 复用证书与导出密码。GitHub repository Secrets 不能读回，
也不会自动共享到其他仓库；需将 Apple 登录邮箱、专用密码分别保存至本仓库
`APPLE_ID`、`APPLE_APP_SPECIFIC_PASSWORD`。不要提交私钥或把密码发送到聊天。

配置完成且工作流合并 main 后：

```sh
gh workflow run macos-release.yml --repo robinfai/ianvs-terminal --ref main -f version=0.1.0
```

该操作签名、公证并发布 `v0.1.0`，产物为 universal ZIP、签名 appcast 和 SHA256SUMS。
不会替换已有 `v1.0.0` 的 Latest 状态。测试版从自己的版本固定 appcast 检查更新；
后续正式版需手动安装一次以切换到 stable feed。发布后仍需在真实 macOS 上下载、
解压、启动并验证终端功能。CI 成功不代表支持窗口内所有系统版本均已实测。

参考：[Apple Developer ID](https://developer.apple.com/developer-id/)、
[Apple 公证](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)、
[GitHub CI 证书](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)。
