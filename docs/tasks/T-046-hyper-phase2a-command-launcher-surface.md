# T-046 Hyper-inspired Phase 2A Command Launcher Surface

## Goal

在 Phase 1A / 1B shell chrome 已稳定的前提下，只补一个明显的 top actions launcher surface，提升动作可发现性，同时保持 deterministic open / close 与 focus-safe 行为。

## Scope

- `example/lib/features/shell/shell_screen.dart`
- `example/test/shell/shell_screen_phase2a_test.dart`
- `example/test/widget_test.dart`
- `example/integration_test/flutterm_smoke_test.dart`
- `docs/TESTING.md`
- `docs/tasks/T-046-hyper-phase2a-command-launcher-surface.md`

## Non-goals

- 不扩展成通用 command palette / shortcut platform
- 不改动 Rust PTY/core
- 不引入新依赖
- 不改变既有 selection / copy-paste / scroll / resize / exit contract
- 不新增超出 top actions 的 scope / plugin / profile management surface

## Functional Acceptance

- active shell surface 上有一个明显且可预测的 launcher 入口
- launcher 只暴露 top actions，不扩展到更广的命令体系
- launcher 打开 / 关闭路径 deterministic
- launcher 打开时不会把交互事件泄漏到 terminal input
- launcher 关闭后 active terminal viewport 恢复可交互状态；若无 active session，不制造虚假的 focus 恢复路径
- 现有 terminal interaction regression 保持为绿

## Verification Commands

```bash
cd example
flutter analyze
flutter test test/shell/shell_screen_phase2a_test.dart
flutter test test/widget_test.dart
flutter test integration_test/flutterm_smoke_test.dart
```

## Manual QA

1. 启动 app 并确认 launcher 入口在 active shell surface 上可见
2. 打开 launcher，确认 terminal 不会收到误输入
3. 关闭 launcher，确认 active terminal viewport 立即恢复可交互
4. 通过 launcher 执行 top action，确认既有 tab / terminal contract 不回归
5. 若进入 empty-state，确认不会残留失焦或无法恢复的 launcher 状态

## Done When

- top actions launcher surface 已落地且范围仍然最小
- 自动化回归覆盖 launcher open / close / focus-safe 路径
- `docs/TESTING.md` 已同步 launcher surface 的验证要求
- 相关 Flutter 验证命令全部通过

## Risks / Follow-ups

- 若 launcher 实现需要额外 focus restoration hook，必须保持 Flutter-only 并先证明现有 terminal contract 不足以覆盖
- 更广的 shortcut model / command palette 需要单独 Phase 2B 任务，不在本任务内追加
