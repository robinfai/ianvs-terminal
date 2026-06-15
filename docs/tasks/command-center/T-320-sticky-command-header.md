# T-320 Sticky Command Header

## Goal

为长输出 command block 提供 sticky header。

## Scope

- 基于可见 viewport 计算当前 command block header。
- 处理 alt-buffer、pager 和 fullscreen app 的禁用或延迟显示。
- 为失败状态、当前 cwd、exit code 和 duration 提供可访问呈现。
- 将 header 作为 overlay 呈现，不写入 scrollback。

## Non-goals

- 不实现 command block range 基础模型。
- 不实现 command search overlay。
- 不把 header 写入 terminal 文本。
- 不改变真实终端复制结果。
- 不重写 renderer。

## Files In Scope

- `example/lib/features/command_center/sticky_command_header.dart`
- `example/test/command_center/sticky_command_header_test.dart`
- 必要的 `example/lib/features/shell/` overlay wiring

## Functional Acceptance

- 长输出滚动时显示当前 command header。
- alt-buffer/fullscreen app 不显示误导 header。
- 失败状态不能只靠颜色表达，必须包含 exit code 或 failed 文本。
- Header 不写入 scrollback，不影响真实 terminal selection copy。
- 计算基于可见范围，避免扫描整段 scrollback。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/command_center/sticky_command_header_test.dart
```

## Manual QA

- 运行长输出命令并滚动。
- 运行失败命令并确认 header 状态。
- 进入 `less` 或 `vim` 这类 alt-buffer / fullscreen app，确认 header 不误导显示。
- 复制 terminal 文本，确认不包含 header 文案。

## Done When

- Sticky header 能提升长输出 block 可读性。
- Header 不遮挡或污染 terminal 内容。
- alt-buffer、失败状态和复制行为有验证。

## Risks / Follow-ups

- 视觉 polish 可后续调整，但 scrollback 和 selection 语义不能放宽。
- 大 scrollback 性能需要在 `T-322` 验证门持续覆盖。
