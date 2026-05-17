# T-107 Local Terminal Graphics Store Planner

## Goal

补齐 P5 graphics/image storage policy 的存储规划层，定义图片 metadata、容量限制和 oldest-first eviction 计划，但不接 renderer 或真实图片缓存。

## Scope

- `example/lib/features/visual/local_terminal_graphics_store.dart`
- `example/test/visual/local_terminal_graphics_store_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P5_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不渲染图片
- 不保存真实图片文件
- 不接 terminal graphics protocol
- 不接 renderer decision point
- 不实现 UI 设置面

## Current Progress

- 已新增 `LocalTerminalGraphicsEntry`。
- 已新增 `LocalTerminalGraphicsEvictionPlan`。
- 已新增 `LocalTerminalGraphicsStorePlanner.planInsert()`。
- planner 支持 disabled reject、single image size reject、within-limit accept、oldest-first eviction。
- 已补充 disabled、within-limit、oldest eviction 测试。

## Functional Acceptance

- graphics storage 默认可关闭。
- 超过单项或总容量限制时有明确 reject/eviction 计划。
- eviction 按 createdAtMillis 从旧到新。
- planner 不依赖 renderer 或真实图片协议。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/visual/local_terminal_graphics_store_test.dart
flutter analyze
```

## Manual QA

本任务只新增存储规划模型，不接 UI；无需人工 UI 验收。

## Done When

- P5 graphics/image storage policy 有可复用容量规划层。
- 后续真实缓存实现可以复用 eviction plan，而不影响 renderer 决策。

## Risks / Follow-ups

- 后续必须继续把 graphics storage 作为 advanced optional feature。
- 后续如果接 terminal graphics protocol，需要独立安全和性能评审。
