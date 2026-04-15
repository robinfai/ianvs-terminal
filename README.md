# flutterm

`flutterm` 是一个桌面 terminal MVP。

当前路线：

- Flutter 负责 GUI 和 terminal viewport
- Rust 负责 PTY、terminal state 和 FFI
- 首版只做 `macOS + local shell`
- 先验证产品与工程路径，再决定是否升级 renderer

## 当前状态

目前已经打通：

- Flutter app 启动
- Rust 动态库加载
- 本地 PTY shell 创建
- terminal frame diff 渲染
- 多 tab 与 profile 持久化
- `flutter run -d macos` 可运行

## 快速开始

```bash
cd app
flutter analyze
flutter test
flutter run -d macos
```

```bash
cd native/core
cargo fmt --check
cargo test
```

## 文档入口

- 工作入口： [docs/README.md](/Users/robinfai/personal/flutterm/docs/README.md)
- 稳定设计： [docs/ARCHITECTURE.md](/Users/robinfai/personal/flutterm/docs/ARCHITECTURE.md)
- 路线图： [docs/ROADMAP.md](/Users/robinfai/personal/flutterm/docs/ROADMAP.md)
- 全局验收： [docs/ACCEPTANCE.md](/Users/robinfai/personal/flutterm/docs/ACCEPTANCE.md)
- 测试命令： [docs/TESTING.md](/Users/robinfai/personal/flutterm/docs/TESTING.md)
- 已知边界： [docs/KNOWN_ISSUES.md](/Users/robinfai/personal/flutterm/docs/KNOWN_ISSUES.md)
- 任务模板： [docs/tasks/TEMPLATE.md](/Users/robinfai/personal/flutterm/docs/tasks/TEMPLATE.md)

## 当前范围

已纳入：

- macOS
- local shell
- 多 tab
- profile 持久化
- FFI 动态库加载
- 基础输入
- 鼠标线性选区
- 复制 / 粘贴
- scrollback 滚动
- resize

暂不纳入：

- SSH
- split pane
- 全文搜索
- sync
- 插件系统
- native renderer
- `wgpu` renderer
