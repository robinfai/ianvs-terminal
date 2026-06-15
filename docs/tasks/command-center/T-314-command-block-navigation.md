# T-314 Command Block Navigation

## Goal

支持 previous/next block 和 last failed block 导航。

## Scope

- 定义 block navigation reducer/controller。
- 管理 selected block state。
- 为无目标、range 缺失和 shell integration unavailable 提供 disabled reason。
- 产出 scroll-to-block intent，不直接操作 viewport。

## Non-goals

- 不实现真实 viewport scroll wiring。
- 不实现 block action menu。
- 不写入 PTY。
- 不改变 terminal selection 行为。
- 不实现 Agent / AI explain 或 fix。

## Files In Scope

- `example/lib/features/command_center/command_block_navigation.dart`
- `example/test/command_center/command_block_navigation_test.dart`

## Functional Acceptance

- 能定位上一条 block。
- 能定位下一条 block。
- 能定位最近失败 block。
- 无目标时给 disabled reason。
- 只读浏览可导航但不写 PTY。
- 多 session/pane 导航互不串扰。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/command_center/command_block_navigation_test.dart
```

## Manual QA

本任务为模型/控制器，可不做 UI QA。真实 scroll-to-row 行为在后续 UI/wiring 任务中手测。

## Done When

- Shell action registry 可接入 block navigation intent。
- previous、next、last failed 和 disabled reason 有测试。
- Navigation 不拥有 viewport controller。

## Risks / Follow-ups

- 真实 viewport scrolling 需要后续任务验证 scrollback、selection 和 return-to-bottom 行为。
- last failed block 依赖 lifecycle exitCode 准确性。
