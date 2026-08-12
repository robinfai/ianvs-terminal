# ianvs terminal

`ianvs terminal` 现在按 package 与 host 边界组织：

- `packages/ianvs_pty`：PTY 会话传输和 FFI 包装
- `packages/ianvs_terminal`：session runtime、viewport、输入/选区/滚动适配和可选的 Flutter 嵌入组件
- `packages/ianvs_terminal_core`：面向第三方应用发布的 standalone current-only package
- `example/`：tab、窗口壳、菜单、profile 编辑和 demo 流程
- `native/core`：Rust PTY / VT core，当前仍作为 `ianvs_pty` 背后的原生实现
- `backend/`：Go + GORM 数据 API，本地使用 SQLite、远程可切换 MySQL

`example/` 不再定义终端能力；共享终端能力统一从 package 暴露。app 侧通过 `example/lib/features/terminal/terminal.dart` 和 `example/lib/features/pty/pty.dart` 收口 package 依赖，平台剪贴板桥接留在 `example/lib/platform/clipboard_bridge.dart`。`example` 目录里的 Flutter package 现阶段仍保留 `name: app`，用于稳定既有 `package:app/...` import 面；macOS bundle identity 由 Runner project 的 Ianvs Terminal 元数据单独维护。

第三方 Flutter 应用应依赖可发布的 `ianvs_terminal_core`。macOS 原生库由 package 的
CodeAsset build hook 自动编译并随应用打包；宿主 Xcode 工程不得再复制 Rust 构建或 dylib
拷贝 phase。具体依赖、`TerminalSessionHandle.runtimeSignals` 和嵌入生命周期示例见
[packages/ianvs_terminal_core/README.md](packages/ianvs_terminal_core/README.md)。

## 快速开始

仓库根目录提供常用命令入口；运行 `make help` 查看开发、验证和 macOS
构建/安装命令。默认安装目录是 `/Applications`，可通过 `INSTALL_DIR` 覆盖。

```bash
make bootstrap
make analyze
make test
make run
make install
make backend-test
```

```bash
dart pub get
```

```bash
cd example
flutter analyze --fatal-infos
flutter test
flutter run -d macos
```

数据 API 不读取进程环境变量或 `dart-define`。macOS 首次启动可选择三种能力边界：跳过后进入“本地终端”模式，不启动任何 API 进程，只提供本地 shell 与 `~/.ssh/config` 主机；“本地 API”会启动应用包内的 sidecar，离线保存配置并开放自定义 SSH；“远程 API”在此基础上提供跨设备同步。iOS 必须完成远程 HTTP API 登录，成功前不会进入终端。远程基础 URL 不允许携带用户名、密码、query 或 fragment，公网服务必须使用 HTTPS（仅回环开发地址可使用 HTTP）。后续可通过 **Defaults & appearance → Data service** 修改模式；从本地 API 切换到远程 API 是显式导出/合并操作，成功提交远程配置前不会删除本地数据或静默切换。非敏感配置保存在应用支持目录的 `data-api/configuration.json`，凭据仅保存在平台凭据保险库中。

```bash
cd native/core
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test
```

## 工作区结构

```text
ianvs terminal/
├── example/
├── packages/
│   ├── ianvs_pty/
│   ├── ianvs_terminal/
│   └── ianvs_terminal_core/
├── native/core/
├── backend/
├── docs/
└── tools/
```

## 文档入口

- 产品范围： [docs/TERMINAL_PRODUCT_SCOPE.md](docs/TERMINAL_PRODUCT_SCOPE.md)
- 仓库边界： [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- 当前执行目标： [docs/CURRENT_EXECUTION_TARGET.md](docs/CURRENT_EXECUTION_TARGET.md)
- 测试命令： [docs/TESTING.md](docs/TESTING.md)
- Local terminal P0-P5 最终验证 handoff： [docs/LOCAL_TERMINAL_FINAL_VERIFICATION_HANDOFF_2026-05.md](docs/LOCAL_TERMINAL_FINAL_VERIFICATION_HANDOFF_2026-05.md)
- Local terminal 当前验证阻塞状态： [docs/LOCAL_TERMINAL_VERIFICATION_BLOCKED_STATE_2026-05.md](docs/LOCAL_TERMINAL_VERIFICATION_BLOCKED_STATE_2026-05.md)
- Local terminal 验证 helper 索引： [docs/LOCAL_TERMINAL_VERIFICATION_HELPER_INDEX_2026-05.md](docs/LOCAL_TERMINAL_VERIFICATION_HELPER_INDEX_2026-05.md)
- 文档总览： [docs/README.md](docs/README.md)
- 任务索引： [docs/tasks/README.md](docs/tasks/README.md)
