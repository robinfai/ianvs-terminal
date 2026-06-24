# T-307 Command History Privacy Filter

## Goal

增加 sensitive command filter、disable history 和 clear history 策略。

## Scope

- 过滤明显包含 password、token、private key 或 secret 的命令。
- 支持用户关闭 history 后不写入 repository。
- 支持 clear history 意图。
- 为过滤结果提供可解释 reason。

## Non-goals

- 不实现设置 UI。
- 不做云端同步或远程历史。
- 不解析自然语言意图。
- 不执行命令。
- 不修改 terminal renderer 或 input policy。

## Files In Scope

- `example/lib/features/command_center/command_history_privacy_filter.dart`
- `example/test/command_center/command_history_privacy_filter_test.dart`

## Functional Acceptance

- 明显 secret 命令不保存。
- 禁用 history 时不写入 repository。
- clear history 删除 local history，并可被 repository 调用。
- 过滤 reason 能被 diagnostics 或 UI 使用。
- 普通常用命令不会被过度过滤。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/command_center/command_history_privacy_filter_test.dart
```

## Manual QA

纯策略任务，不改变 UI；无需人工 UI QA。

## Done When

- Repository 保存前必须经过 privacy filter。
- sensitive、disabled、clear 和 allowed 路径都有测试。
- 过滤策略保持保守，不保存明显 secret。

## Risks / Follow-ups

- 过滤规则需要可维护，避免误删大量普通命令。
- 如果后续增加设置 UI，需要把 disabled/clear 操作接入同一策略。
