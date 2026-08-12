# ianvs terminal

`ianvs terminal` 现在按 package 与 host 边界组织：

- `packages/ianvs_pty`：PTY 会话传输和 FFI 包装
- `packages/ianvs_terminal`：session runtime、viewport、输入/选区/滚动适配和可选的 Flutter 嵌入组件
- `example/`：tab、窗口壳、菜单、profile 编辑和 demo 流程
- `native/core`：Rust PTY / VT core，当前仍作为 `ianvs_pty` 背后的原生实现
- `backend/`：Go + GORM 数据 API，本地使用 SQLite、远程可切换 MySQL

`example/` 不再定义终端能力；共享终端能力统一从 package 暴露。app 侧通过 `example/lib/features/terminal/terminal.dart` 和 `example/lib/features/pty/pty.dart` 收口 package 依赖，平台剪贴板桥接留在 `example/lib/platform/clipboard_bridge.dart`。`example` 目录里的 Flutter package 现阶段仍保留 `name: app`，用于稳定既有 `package:app/...` import 面；macOS bundle identity 由 Runner project 的 Ianvs Terminal 元数据单独维护。

第三方 Flutter 应用应使用完整 Git 仓库中的
`packages/ianvs_terminal`。macOS 原生库由 `ianvs_pty` 的 build hook 自动编译并随
应用打包，不需要在宿主 Xcode 工程里复制 Ianvs Terminal 的自定义构建脚本。具体
依赖和生命周期示例见
[packages/ianvs_terminal/README.md](packages/ianvs_terminal/README.md)。

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

数据 API 通过应用内的 **Defaults & appearance → Data service** 配置，不读取进程环境变量或 `dart-define`。默认关闭；macOS 可以选择应用包内的本地 Go API，使用应用支持目录下的 SQLite；所有平台都可以配置无用户名、密码、query 和 fragment 的 `http(s)` 远程基础 URL。配置保存在应用支持目录的 `data-api/configuration.json`，重启应用后生效。iOS 不提供本地 sidecar 选项，未配置远程服务时终端仍可正常使用。

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
│   └── ianvs_terminal/
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
