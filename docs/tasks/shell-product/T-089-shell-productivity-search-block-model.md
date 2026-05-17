# T-089 Shell Productivity Search And Block Model

## Goal

补齐 P3 的 scrollback search、block scoped search、next/previous match 和 clear search 的纯模型能力，为后续 UI/action 接入做准备。

## Scope

- `example/lib/features/productivity/shell_productivity_models.dart`
- `example/test/productivity/shell_productivity_models_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P3_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不实现 terminal renderer 高亮
- 不扫描真实 scrollback 内容
- 不接入 command palette
- 不改 selection 行为
- 不引入 Warp 风格完整 block UI

## Current Progress

- 已新增 `ShellCommandBlock`。
- 已新增 `ShellSearchMatch`。
- 已新增 `ShellSearchState`。
- search state 已支持 next/previous match、clear、scoped block filtering。
- command block 已支持 row containment。
- 已补充 search cycle、block scope 和 command block containment 测试。

## Functional Acceptance

- 普通 search state 可以在多个 match 间循环。
- clear search 会回到 inactive state。
- search 可以按 command block id 过滤。
- command block 能判断 row 是否属于 block。
- 本任务不要求视觉重做或 renderer 改造。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/productivity/shell_productivity_models_test.dart
flutter analyze
```

## Manual QA

本任务只新增纯模型，不接入 UI；无需人工 UI 验收。

## Done When

- P3 search/block 的基础状态语义可复用。
- 后续 action 接入不需要重新定义 search lifecycle。

## Risks / Follow-ups

- 后续需要将真实 scrollback search 结果映射为 `ShellSearchMatch`。
- 后续需要定义 search highlight 与 selection 的交互边界。
