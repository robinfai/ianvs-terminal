# T-047 Hyper-inspired Phase 2B Shortcut Model and Action Scoping

## Goal

在 Phase 2A launcher surface 已稳定的前提下，补最小可用的 shortcut model 与 action scoping：明确区分 app actions 和 session actions，只增加 launcher 入口 / top action access 所需的 app-scoped shortcuts，并保持 deterministic focus return 与 no-input-leak 行为。

## Scope

- `app/lib/features/shell/shell_screen.dart`
- `app/test/shell/shell_screen_phase2b_test.dart`
- `app/test/widget_test.dart`
- `app/integration_test/flutterm_smoke_test.dart`
- `docs/TESTING.md`
- `docs/tasks/T-047-hyper-phase2b-shortcut-model-and-action-scoping.md`

## Non-goals

- 不扩展成通用 command palette / shortcut platform
- 不改动 Rust PTY/core
- 不引入新依赖
- 不改变既有 selection / copy-paste / scroll / resize / exit contract
- 不新增超出 launcher 入口 / top action access 的 app-wide shortcut surface

## Functional Acceptance

- launcher 内 app actions / session actions 的 scope 显式可见
- app-scoped shortcuts 仅覆盖 launcher 入口与 top action access
- shortcut invocation deterministic，不会把触发按键泄漏到 terminal input
- launcher 关闭后 active terminal viewport 恢复可交互状态；若无 active session，不制造虚假的 focus 恢复路径
- session-scoped copy / paste 与既有 terminal keyboard contract 保持一致
- 现有 terminal interaction regression 保持为绿

## Verification Commands

```bash
cd /Users/robinfai/personal/flutterm/app
flutter analyze
flutter test test/shell/shell_screen_phase2b_test.dart
flutter test test/widget_test.dart
flutter test integration_test/flutterm_smoke_test.dart
```

## Manual QA

1. 启动 app 并确认 launcher 入口在 active shell surface 上可见
2. 用 app-scoped shortcut 打开 launcher，确认 terminal 不会收到误输入
3. 检查 launcher 中 app actions 与 session actions 的 scope 文案是否明确
4. 执行 launcher close / new-tab 等 app-scoped action，确认 focus return deterministic
5. 触发 session-scoped copy / paste 路径，确认不会和 terminal keyboard contract 冲突

## Done When

- Phase 2B shortcut scope / action-scoping surface 已落地且范围仍然最小
- 自动化回归覆盖 app-vs-session action scope、shortcut conflict handling、focus return、no-input-leak 路径
- `docs/TESTING.md` 已同步 Phase 2B 验证要求
- 相关 Flutter 验证命令全部通过

## Risks / Follow-ups

- 若 deterministic focus return 需要额外 terminal viewport focus restoration hook，必须保持 Flutter-only 并先证明现有 contract 不足
- 若后续要扩展到更广的 command palette / shortcut platform，必须新开任务并重新定义 scope / conflict model
