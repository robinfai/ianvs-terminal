# T-106 Local Terminal Paste Decision

## Goal

补齐 P4 paste runtime 前置决策模型，把 read-only guard、large/multiline confirmation 和 paste history capture 合并成单次 paste 的统一决策结果。

## Scope

- `example/lib/features/policies/local_terminal_paste_decision.dart`
- `example/test/policies/local_terminal_paste_decision_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P4_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不发送真实 paste
- 不读取系统剪贴板
- 不打开 confirmation UI
- 不写入 paste history repository
- 不改 terminal input controller

## Current Progress

- 已新增 `LocalTerminalPasteDecisionKind`。
- 已新增 `LocalTerminalPasteDecision`。
- 已新增 `LocalTerminalPasteDecisionResolver.resolve()`。
- decision 覆盖 send immediately、require confirmation、blocked read-only。
- decision 同时返回是否 capture history。
- 已补充 read-only blocked、multiline confirmation、simple paste tests。

## Functional Acceptance

- read-only 下 paste 被阻止且不 capture history。
- multiline paste 需要 confirmation。
- simple paste 可直接发送并 capture history。
- 决策层不触发真实输入或 UI 副作用。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/policies/local_terminal_paste_decision_test.dart
flutter analyze
```

## Manual QA

本任务只新增决策模型，不接入 UI；无需人工 UI 验收。

## Done When

- P4 paste policy 到 runtime action 的前置决策可复用。
- 后续 paste runtime 接入可以先调用 resolver 再决定发送、确认或阻止。

## Risks / Follow-ups

- 后续需要将 resolver 接入现有 paste 和 advanced paste 路径。
- 后续需要让 confirmation UI 保持 terminal focus 恢复。
