# T-381 Selected Block Copy Command Actions

## Goal

让 selected block action sheet 支持复制命令本身，以及一次复制命令和输出。

## Scope

- 在 selected block action sheet 增加 `Copy block command`。
- 在 selected block action sheet 增加 `Copy command and output`。
- 复用 `CommandBlockActionReducer.copyCommand` 和 `CommandBlockActionReducer.copyBoth`。
- action sheet 改为可滚动，避免动作项增加后在较小视口溢出。
- 增加 widget regression 覆盖两个复制入口，确认不会写入 shell。

## Non-goals

- 不改变 action search 的 block action 行为。
- 不实现 scoped search、save output 或 review entrypoint。
- 不改变 selected block 的来源和持久化策略。

## Files In Scope

- `example/lib/features/shell/shell_screen_state_context_chips.dart`
- `example/test/widget_test.dart`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`
- `docs/tasks/command-center/T-380-selected-block-context-actions.md`

## Functional Acceptance

- 点击 `Block <command>` chip 打开 action sheet 后，可以选择 `Copy block command`。
- `Copy block command` 将 trimmed command 写入 clipboard，不写 shell。
- 可以选择 `Copy command and output`。
- `Copy command and output` 将 command 和 output 以换行拼接后写入 clipboard，不写 shell。
- sheet 内容超过可用高度时可以滚动，不触发布局 overflow。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart --plain-name "selected block chip can copy command and output together"
flutter test test/widget_test.dart --plain-name "selected block chip opens block actions without shell write"
flutter test test/widget_test.dart --plain-name "selected block chip can reinput and rerun block command"
```

## Manual QA

- 运行失败命令并点击 `Last exit` chip。
- 点击 `Block <command>` chip。
- 分别执行 `Copy block command` 和 `Copy command and output`。
- 确认 clipboard 内容正确，终端没有收到写入。
- 在较小窗口高度下打开 sheet，确认动作列表可滚动。

## Done When

- selected block sheet 显示两个复制命令类入口。
- 复制命令和复制命令加输出都有 widget regression。
- 验证门包含新 regression。

## Risks / Follow-ups

- scoped search、save output 和 review entrypoint 仍需要独立 action dispatch。
