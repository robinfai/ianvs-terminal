# T-303 Shell Hook Lifecycle Adapter

## Goal

将 `TerminalSessionShellHookEvent` 转成 Command Center lifecycle event。

## Scope

- 在 app 层新增 shell hook adapter。
- 将 `preexec`、`command_finished`、`precmd.pwd` 或 cwd payload 映射为 lifecycle event。
- 为未知 hook 或字段缺失生成可诊断的 ignored / unavailable 结果。

## Non-goals

- 不修改 `TerminalSessionShellHookEvent`。
- 不修改 PTY / FFI / native wire schema。
- 不实现 history repository、search overlay 或 block renderer。
- 不做 shell hook 安装脚本或跨 shell hook 补丁。
- 不绕过 terminal input policy。

## Files In Scope

- `example/lib/features/command_center/shell_hook_lifecycle_adapter.dart`
- `example/test/command_center/shell_hook_lifecycle_adapter_test.dart`
- 只读参考：`packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart`

## Functional Acceptance

- `preexec` 创建 command start event。
- `command_finished` 创建 command finish event，并携带 command、cwd 和 exitCode。
- `precmd.pwd` 或 cwd payload 更新 current cwd。
- 未知 hook 被忽略，不抛异常。
- 缺少关键字段时返回明确 unavailable / ignored reason，供后续 action availability 使用。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/command_center/shell_hook_lifecycle_adapter_test.dart
```

## Manual QA

纯 adapter 任务，不改变 UI 或真实 shell hook 发送路径；无需人工 UI QA。

## Done When

- 后续 reducer 不直接解析 raw shell hook payload。
- adapter 对已知 hook、未知 hook 和字段缺失都有测试。
- package 层事件 schema 保持不变。

## Risks / Follow-ups

- 不同 shell 的 hook 命名差异需要通过 `T-304` 的降级状态表达。
- 如果后续需要新增 package-level 中性 event，应另写 focused task。
