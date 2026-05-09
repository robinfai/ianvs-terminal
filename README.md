# flutterm

`flutterm` 现在按 workspace 组织：

- `packages/flutterm_pty`：PTY 会话传输和 FFI 包装
- `packages/flutterm_terminal`：session runtime、viewport、输入/选区/滚动适配
- `example/`：tab、窗口壳、菜单、profile 编辑和 demo 流程
- `native/core`：Rust PTY / VT core，当前仍作为 `flutterm_pty` 背后的原生实现

`example/` 不再定义终端能力；共享终端能力统一从 package 暴露。`example` 目录里的 Flutter package 现阶段仍保留 `name: app`，只是为了不顺手扩大平台工程改动面。

## 快速开始

```bash
dart pub get
```

```bash
cd example
flutter analyze
flutter test
flutter run -d macos
```

```bash
cd native/core
cargo fmt --check
cargo test
```

## 工作区结构

```text
flutterm/
├── example/
├── packages/
│   ├── flutterm_pty/
│   └── flutterm_terminal/
├── native/core/
├── docs/
└── tools/
```

## 文档入口

- 仓库边界： [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- 测试命令： [docs/TESTING.md](docs/TESTING.md)
- 文档总览： [docs/README.md](docs/README.md)
- 任务索引： [docs/tasks/README.md](docs/tasks/README.md)
