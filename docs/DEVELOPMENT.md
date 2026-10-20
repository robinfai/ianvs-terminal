# macOS 开发环境隔离

运行 `make run-macos`（或在 example 下运行 `flutter run -d macos`）。

- macOS Debug/Profile 使用 `Trail Development`，Bundle ID 为 `work.ianvs.trail.development`。Release 使用 `Trail` / `work.ianvs.trail`。
- 开发版运行时不访问 Keychain。主密钥和 AI 配置（含 API key）保存在开发数据目录的 `secrets` 下，目录权限 `0700`、文件权限 `0600`，以原子替换方式写入。这是本机明文开发存储，不用于正式版；SSH 凭据和远程服务令牌仍由该主密钥加密。
- 开发数据位于该应用 Application Support 下的 `development-file-v1` 子目录；配置、数据库及凭据均与正式版隔离。旧 `development` 目录及其 Keychain 条目原样保留，不自动读取或迁移；首次切换到文件存储会使用新的开发配置，AI 配置也需重新填写。不得把旧加密数据库直接复制到新目录并配用新密钥。
- 首次启动自动选择 Local。Xcode 从当前 backend 源码构建并打包 `ianvs-api`；应用启动它作为独立子进程，监听随机 loopback 端口。每次启动产生独立 Bearer token，数据库密钥保持不变。
- 已保存的开发服务配置仍受尊重；可在开发版设置中更改。已有开发数据库但缺失开发密钥时，不启动无法解密旧数据的内置服务，也不会为该数据库生成替代密钥。

## Apple 开发签名

工程文件中的 `DEVELOPMENT_TEAM` 保持为空。`make install-iphone-physical` 和
`make build-macos` 调用签名构建脚本，在构建时生成临时 `.xcconfig`，写入团队
ID，再通过 `XCODE_XCCONFIG_FILE` 传给 Xcode；构建结束后删除临时文件。

未设置 `IANVS_APPLE_TEAM` 时，脚本从本机钥匙串的 Apple Development 证书中
读取团队 ID。多团队环境或 CI 可以显式指定（将示例替换为自己的 10 位 Team ID）：

```sh
IANVS_APPLE_TEAM=ABCDE12345 make install-iphone-physical
IANVS_APPLE_TEAM=ABCDE12345 make build-macos
```

CI 可将 `IANVS_APPLE_TEAM` 配置为环境变量。对应团队的开发证书、私钥和所需
描述文件仍需在构建机上可用；该变量只选择团队，不提供签名凭据。该设置由仓库
脚本读取，直接在 Xcode 中点击 Run 不会执行这套注入流程。

## 验证

在 example 目录运行：

```sh
flutter test test/startup/development_secret_storage_test.dart test/startup/app_environment_test.dart test/data/services/portable_master_key_test.dart test/data/services/data_api_local_credentials_test.dart test/startup/app_startup_coordinator_test.dart
flutter test integration_test/macos_development_environment_test.dart -d macos
flutter analyze --no-pub
```

2026-10-01 在 macOS 27.0.1（26A434）验证：61 项相关单元测试通过；真实 macOS 集成测试连续启动两次、解密数据库及恢复 AI 配置成功，拦截统计的 Keychain 调用为 0；本次文件静态分析通过。另以正常启动流程打开开发版终端和 AI 设置，无钥匙串提示、无 Dart 运行时错误。其他支持版本未在本次实测。
