# ianvs terminal

`ianvs terminal` 现在按 workspace 组织：

- `packages/ianvs_pty`：PTY 会话传输和 FFI 包装
- `packages/ianvs_terminal`：session runtime、viewport、输入/选区/滚动适配
- `example/`：tab、窗口壳、菜单、profile 编辑和 demo 流程
- `native/core`：Rust PTY / VT core，当前仍作为 `ianvs_pty` 背后的原生实现

`example/` 不再定义终端能力；共享终端能力统一从 package 暴露。app 侧通过 `example/lib/features/terminal/terminal.dart` 和 `example/lib/features/pty/pty.dart` 收口 package 依赖，平台剪贴板桥接留在 `example/lib/platform/clipboard_bridge.dart`。`example` 目录里的 Flutter package 现阶段仍保留 `name: app`，用于稳定既有 `package:app/...` import 面；macOS bundle identity 由 Runner project 的 Ianvs Terminal 元数据单独维护。

## 快速开始

仓库根目录提供常用命令入口；运行 `make help` 查看开发、验证和 macOS
构建/安装命令。默认安装目录是 `/Applications`，可通过 `INSTALL_DIR` 覆盖。

```bash
make bootstrap
make analyze
make test
make run
make install
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
├── docs/
└── tools/
```

## 文档入口

- 仓库边界： [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- 当前执行目标： [docs/CURRENT_EXECUTION_TARGET.md](docs/CURRENT_EXECUTION_TARGET.md)
- 测试命令： [docs/TESTING.md](docs/TESTING.md)
- Local terminal P0-P5 最终验证 handoff： [docs/LOCAL_TERMINAL_FINAL_VERIFICATION_HANDOFF_2026-05.md](docs/LOCAL_TERMINAL_FINAL_VERIFICATION_HANDOFF_2026-05.md)
- Local terminal 当前验证阻塞状态： [docs/LOCAL_TERMINAL_VERIFICATION_BLOCKED_STATE_2026-05.md](docs/LOCAL_TERMINAL_VERIFICATION_BLOCKED_STATE_2026-05.md)
- Local terminal 验证 helper 索引： [docs/LOCAL_TERMINAL_VERIFICATION_HELPER_INDEX_2026-05.md](docs/LOCAL_TERMINAL_VERIFICATION_HELPER_INDEX_2026-05.md)
- 文档总览： [docs/README.md](docs/README.md)
- 任务索引： [docs/tasks/README.md](docs/tasks/README.md)
