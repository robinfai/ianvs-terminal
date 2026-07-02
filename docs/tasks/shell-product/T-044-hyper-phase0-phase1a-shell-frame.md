# T-044 Hyper-inspired Phase 0 / Phase 1A Shell Frame

## Goal

把已批准的 Hyper-inspired 计划推进到第一批可见交付：

- Phase 0：定义 repo-specific 的 Hyper-inspired target / gap / boundaries
- Phase 1A：在不破坏既有 terminal 行为的前提下，给 shell frame 和 empty-state 加最小的产品壳层增强

## Scope

- `docs/HYPER_LIKE_TARGET.md`
- `docs/HYPER_LIKE_GAP_MATRIX.md`
- `docs/DECISIONS/ADR-0001-hyper-phase0-shell-boundaries.md`
- `docs/README.md`
- `example/lib/features/shell/shell_screen.dart`
- `example/test/shell/shell_screen_phase1a_test.dart`
- `example/test/widget_test.dart`
- `example/integration_test/ianvs_terminal_smoke_test.dart`
- `docs/TESTING.md`

## Non-goals

- 不实现 command launcher / shortcut model
- 不扩展到 SSH / split panes / renderer rewrite / plugin system
- 不修改 Rust PTY/core
- 不改变既有 selection / copy-paste / scroll / resize / exit / focus 语义

## Functional Acceptance

- 产出 Hyper-inspired target / gap matrix / shell-boundary ADR
- active session 时 shell 顶部具备最小 workspace chrome 文案
- closing last tab 后 empty-state 有更明确的下一步提示
- 现有 terminal 主链路回归保持为绿

## Verification Commands

```bash
cd example
flutter analyze
flutter test test/shell/shell_screen_phase1a_test.dart
flutter test test/widget_test.dart
flutter test -d macos integration_test/ianvs_terminal_smoke_test.dart
```

## Manual QA

1. 启动 app
2. 观察 active session 顶部 shell chrome
3. 关闭最后一个 tab，确认 empty-state 文案更明确
4. 从 empty-state 通过 `New Tab` 恢复

## Done When

- Phase 0 文档产物存在且可被后续阶段引用
- Phase 1A shell frame / empty-state 的最小增强已落地
- 上述验证命令全部通过

## Risks / Follow-ups

- 本任务只做 Phase 1A 的最小壳层增强，不包含 Phase 1B/2A 的 command surface
- 后续仍需独立推进：
  - Phase 1B visual system alignment
  - Phase 2A command launcher surface
