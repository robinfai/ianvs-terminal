# macOS 开发环境隔离

运行 `make run-macos`（或在 example 下运行 `flutter run -d macos`）。

- macOS Debug/Profile 使用 `Ianvs Terminal Development`，Bundle ID 为 `dev.ianvs.terminal.development`。Release 保持原来的配置。
- 开发主密钥使用本机 login Keychain，service/accountName 为 `dev.ianvs.terminal.development`，item 为 `ianvs.development.master-key.v1`。不启用 iCloud 同步，也不读取、迁移或删除正式版历史 Keychain 条目。
- 开发数据位于该应用 Application Support 下的 `development` 子目录；配置、数据库及加密凭据文件均与正式版隔离。
- 首次启动自动选择 Local。Xcode 从当前 backend 源码构建并打包 `ianvs-api`；应用启动它作为独立子进程，监听随机 loopback 端口。每次启动产生独立 Bearer token，数据库密钥保持不变。
- 已保存的开发服务配置仍受尊重；可在开发版设置中更改。已有开发数据库但缺失开发密钥时停止启动，避免生成无法解密旧数据的新密钥。

## 验证

在 example 目录运行：

```sh
flutter test test/startup/app_environment_test.dart test/data/services/portable_master_key_test.dart test/data/services/data_api_local_credentials_test.dart test/startup/app_startup_coordinator_test.dart
flutter test integration_test/macos_development_environment_test.dart -d macos
flutter analyze --no-pub
```

48 项单元/启动回归通过。真实 macOS 集成测试使用开发 Keychain 和临时隔离数据库，通过完整启动协调器两次启动捆绑服务端，验证加密资源写入、重启后解密读取、删除，以及 Bearer 更新与主密钥复用。测试保留开发主密钥，清理自己创建的临时数据库；不访问正式版密钥。

正常 `lib/main.dart` 开发入口也已通过界面验证：设置页显示“内置本地服务 / 运行中”，并明确显示开发密钥仅存于本机、不同步 iCloud、不与正式版共享。应用以唯一名称 `Ianvs Terminal Development` 保持运行，便于与旧的同名测试窗口区分。静态分析无问题。
