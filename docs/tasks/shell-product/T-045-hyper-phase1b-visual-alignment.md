# T-045 Hyper-inspired Phase 1B Visual Alignment

## Goal

在保持 Phase 1A 稳定 shell 布局与既有 terminal 语义不变的前提下，补一轮更系统的视觉对齐：

- session tabs panel 具备统一 shell panel 视觉语言
- empty-state 与 workspace banner 共享同一套 surface 语言
- labels / spacing / hierarchy 更一致

## Scope

- `example/lib/features/shell/shell_screen.dart`
- `example/test/shell/shell_screen_phase1b_test.dart`
- `docs/tasks/shell-product/T-045-hyper-phase1b-visual-alignment.md`

## Non-goals

- 不增加 command launcher / shortcut model
- 不改动 Rust PTY/core
- 不改变 selection / copy-paste / scroll / resize / exit / focus 行为
- 不引入新依赖

## Functional Acceptance

- active session 时显示独立 `Session tabs` panel
- empty-state 具备命名 shell panel，而不是只是一段裸文本
- workspace banner / tabs panel / empty-state panel 共享统一 panel 视觉语言
- 现有 widget/integration regression 全绿

## Verification Commands

```bash
cd example
flutter analyze
flutter test test/shell/shell_screen_phase1a_test.dart
flutter test test/shell/shell_screen_phase1b_test.dart
flutter test test/widget_test.dart
flutter test integration_test/ianvs_smoke_test.dart
```

## Risks / Follow-ups

- 本任务只做视觉系统对齐，不新增动作面或快捷键
- 下一阶段自然延续到：
  - Phase 2A command launcher surface only
