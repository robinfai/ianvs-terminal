# T-327 Command History Persistence Wiring

## Goal

把 Command Center runtime 的 session command history 同步到本地 global history repository，让 `Ctrl-R` search 能同时使用当前 session 历史和已落盘历史。

## Scope

- 增加 history persistence wiring helper。
- ShellScreen 启动时加载 local global command history。
- `command_finished` shell hook 更新 runtime 后，异步保存当前 session 的 command history。
- `Ctrl-R` command search controller 构建时合并 global history 和 session history。
- 保存继续复用 repository privacy filter、trim、dedupe 和 corrupt-file fallback。

## Non-goals

- 不实现 cloud sync、remote history、共享历史或插件历史源。
- 不新增 history 设置 UI。
- 不实现 saved commands。
- 不改变 ordinary terminal input。
- 不把 history persistence 下沉到 `packages/ianvs_terminal`。

## Files In Scope

- `example/lib/features/command_center/command_history_persistence_wiring.dart`
- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/shell/shell_screen_state_command_history.dart`
- `example/lib/features/shell/shell_screen_state_command_search.dart`
- `example/lib/features/shell/shell_screen_state_events.dart`
- `example/test/command_center/command_history_persistence_wiring_test.dart`

## Functional Acceptance

- 指定 session 的 runtime history 会合并进 global history。
- 其他 session 的 history 不会被误写入当前同步。
- ShellScreen 加载 global history 后，command search 使用 global + session history。
- `command_finished` 后触发异步保存。
- 保存失败不打断 terminal event handling。
- 隐私过滤、去重和 limit 行为仍由 repository 保证。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test \
  test/command_center/command_history_persistence_wiring_test.dart \
  test/command_center/global_command_history_repository_test.dart \
  test/command_center/command_search_shell_wiring_test.dart \
  test/shell/shell_screen_architecture_test.dart
```

## Manual QA

- 启动 app，运行一条命令并等 shell hook 完成。
- 关闭并重新打开 app。
- 按 `Ctrl-R`，确认刚才的命令仍可搜索。
- 尝试明显敏感命令，确认不会被写入本地历史。

## Done When

- Command Search 不再只有 session-local history。
- 本地 global history 与 runtime history 有真实 ShellScreen 接线。
- 后续 saved commands 和 `/` action search 可以复用同一 search/history 基座。

## Risks / Follow-ups

- 当前保存是 ShellScreen 私有异步链，后续如果 history 设置 UI 增加 clear/disable，需要把 repository intent 接入配置。
- 如果 command hook 高频触发导致保存过于频繁，需要加入 debounce 或 batch flush。
- 对历史文件迁移仍只支持 v1 JSON schema。
