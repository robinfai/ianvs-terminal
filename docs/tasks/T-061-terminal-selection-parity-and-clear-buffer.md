# T-061 Terminal 选择对齐与 Buffer 清空

## Goal

把 terminal 选择行为再往 xterm 对齐一档，并修正选择时的自动滚动行为：

- 双击按词选中，并支持双击后按词扩展拖选
- 拖选时只有鼠标越出 terminal 视口后才自动滚动

`Cmd+K` / 非 macOS 的 `Ctrl+K` 清空链路已在同日回退，原因是当前实现没有 prompt/readline 语义，无法稳定覆盖多行 `PS1`、`PS2` 和 wrapped input。

## Scope

- `packages/flutterm_terminal/lib/src/terminal/terminal_viewport.dart`
  - 本地点击序列跟踪、按词选中、按词扩展拖选、越界后才自动滚动、拖选/双击时抑制链接打开
- `packages/flutterm_terminal/lib/src/terminal/selection_controller.dart`
  - 增加绝对坐标选区写入入口，供内部按词选区使用
- `packages/flutterm_terminal/lib/src/terminal/terminal_input_controller.dart`
  - 保持 shell 快捷键让出逻辑只覆盖仍然生效的组合键
- `example/test/terminal/render_terminal_viewport_test.dart`
  - 覆盖双击选词、wrapped 选词、按词扩展、越界自动滚动、link 抑制
- `docs/tasks/T-061-terminal-selection-parity-and-clear-buffer.md`

## Non-goals

- 不做三击整行
- 不新增 `wordSeparator` 配置项
- 不改变公开 `SelectionMode` 的 `linear` / `block` 语义
- 不重新引入 `Cmd+K` / `Ctrl+K` 的本地清空能力
- 不把 shell 清空行为降级成给子进程发送 `clear`、`Ctrl+L` 或其他输入字节

## Functional Acceptance

- 双击非空白内容时按 xterm 默认 `wordSeparator` 选词，双击空白时选中连续空白
- 词边界可以跨 wrapped 逻辑行继续向上/向下延伸
- 双击后拖动会按词扩展，而不是退回单字符拖选
- 单击链接仍然可打开，但双击和拖选序列不会触发链接打开
- 鼠标停在 terminal 第一行或最后一行的视口内侧时不自动滚动，只有越出视口矩形后才开始滚
- 当前代码中不存在 `Cmd+K` / `Ctrl+K` 的本地 terminal 清空链路

## Verification Commands

```bash
cd native/core
cargo fmt --check
cargo test

cd packages/flutterm_pty
dart test

cd packages/flutterm_terminal
flutter test

cd example
flutter analyze
flutter test
flutter test integration_test/flutterm_smoke_test.dart

cd /Users/robinfai/personal/flutterm
./tools/verify_flutter_terminal.sh
```

## Completion Record

- 完成时间：`2026-04-27 16:59 CST / 2026-04-27T08:59:22Z`
- 回退时间：`2026-04-27`
- 实际验证链：
  - `cd native/core && cargo fmt --check`
  - `cd native/core && cargo test`
  - `cd packages/flutterm_pty && dart test`
  - `cd packages/flutterm_terminal && flutter test`
  - `cd example && flutter analyze`
  - `cd example && flutter test`
  - `cd example && flutter test integration_test/flutterm_smoke_test.dart`
  - `./tools/verify_flutter_terminal.sh`
- 结果：上述验证全部通过

## Risks / Follow-ups

- 当前按词选中只对齐到“双击选词 + 双击后按词扩展拖选”；如果后续要做三击整行，需要单开任务补点击序列优先级和回归面。
- 如果后续还要恢复 `Cmd+K` / `Ctrl+K`，需要先补 prompt/readline 边界能力，再决定是做 prompt-aware clear、shell integration，还是显式退回到 shell redraw 方案。
