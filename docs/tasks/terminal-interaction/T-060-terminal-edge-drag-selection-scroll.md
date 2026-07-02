# T-060 Terminal 边缘拖选自动滚动

## Goal

让 terminal 在主键拖选触达上下边缘时自动滚动，并保持跨 scrollback 的完整选区与复制结果。

## Scope

- `native/core/src/model.rs`
  - 为 frame diff 暴露 `viewport_start_row`，并定义 native selection text 请求模型。
- `native/core/src/session.rs`
  - 增加基于稳定 scrollback 行号的选区文本提取。
- `native/core/src/ffi.rs`
  - 暴露 selection text FFI 入口。
- `native/core/tests/session_test.rs`
  - 增加跨 scrollback、wrapped row、block selection 的 selection text 回归。
- `example/lib/features/terminal/terminal_painter_models.dart`
  - 解析 `viewportStartRow` 并补 `TerminalSelection.toJson()`。
- `example/lib/features/terminal/selection_controller.dart`
  - 把内部行号切换到稳定 scrollback 坐标，并支持映射回当前 viewport。
- `example/lib/features/terminal/render_terminal_viewport.dart`
  - 只负责绘制当前 frame 下的选区，不再直接处理拖选事件。
- `example/lib/features/terminal/terminal_viewport.dart`
  - 在 state 层管理本地拖选、边缘自动滚动、停止条件与 scroll callback。
- `example/lib/features/shell/shell_screen.dart`
  - 复制路径改为 native selection text 优先，frame fallback 兜底。
- `example/lib/ffi/ianvs_core.dart`
  - 增加 selection text 绑定与客户端封装。
- `example/test/support/fake_core_bindings.dart`
  - 为 widget 测试补 selection text 假实现。
- `example/test/terminal/selection_controller_test.dart`
  - 增加非零 `viewportStartRow` 映射与 viewport 裁剪回归。
- `example/test/terminal/render_terminal_viewport_test.dart`
  - 增加上下边缘自动滚动、pointer up 停止、mouse mode 禁用本地自动滚动回归。

## Non-goals

- 不新增依赖。
- 不改变 terminal mouse reporting 协议。
- 不把持续输出下的选区稳定性提升到强一致保证。
- 不补做 `T-059` 之外的真实 trackpad / VT220 / DPI 人工矩阵。

## Files In Scope

- `native/core/src/model.rs`
- `native/core/src/session.rs`
- `native/core/src/ffi.rs`
- `native/core/tests/session_test.rs`
- `example/lib/features/terminal/terminal_painter_models.dart`
- `example/lib/features/terminal/selection_controller.dart`
- `example/lib/features/terminal/render_terminal_viewport.dart`
- `example/lib/features/terminal/terminal_viewport.dart`
- `example/lib/features/shell/shell_screen.dart`
- `example/lib/ffi/ianvs_core.dart`
- `example/test/support/fake_core_bindings.dart`
- `example/test/terminal/selection_controller_test.dart`
- `example/test/terminal/render_terminal_viewport_test.dart`
- `docs/tasks/terminal-interaction/T-060-terminal-edge-drag-selection-scroll.md`

## Functional Acceptance

- 主键拖选进入 terminal 顶部或底部边缘区时，viewport 会按固定节奏自动滚动。
- 自动滚动过程中，选区锚点保持稳定 scrollback 行号，不会因为 viewport 变化把已选历史内容丢掉。
- `Copy selection` 与 `⌘C` 在真实 session 下优先走 native selection text，复制结果包含拖选跨过的 scrollback 内容。
- block selection 与 wrapped row 的既有复制语义不回退。
- terminal mouse mode 开启时，不启用本地拖选自动滚动。

## Verification Commands

参考 [TESTING.md](../../TESTING.md)：

```bash
cd native/core
cargo fmt --check
cargo test

cd example
flutter analyze
flutter test
flutter test -d macos integration_test/ianvs_terminal_smoke_test.dart

cd <repo-root>
./tools/verify_flutter_terminal.sh
```

## Manual QA

1. 运行 `flutter run -d macos`。
2. 在 terminal 输出多于一屏的内容。
3. 从可见区域中部开始主键拖选，并持续拖到顶部边缘，确认 viewport 会继续向历史滚动。
4. 释放鼠标后执行 `Copy selection` 或 `⌘C`，确认复制内容包含滚出的历史行。
5. 再从中部拖到底部边缘，确认 viewport 会回到底部方向。
6. 进入 terminal mouse mode 的程序后重复拖动，确认不再触发本地选区自动滚动。

## Done When

- 边缘拖选自动滚动已实现。
- 复制路径可正确覆盖跨 scrollback 选区。
- Rust、Dart、widget 与 integration 验证通过。
- 没有超出 Scope / Non-goals。

## Risks / Follow-ups

- 持续输出期间，选区仍是尽力跟随当前 viewport；若后续需要强一致 transcript 选区，应单开任务设计更稳定的数据模型。
- 当前自动化只覆盖 widget 级鼠标拖选，不替代 `T-059` 的真实 trackpad / DPI / VT220 人工矩阵。
