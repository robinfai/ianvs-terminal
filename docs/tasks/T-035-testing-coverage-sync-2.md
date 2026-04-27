# T-035 测试覆盖清单二次同步

## Goal

再次同步 `docs/TESTING.md` 的自动化覆盖清单，使其与最近新增的 widget / Flutter FFI / Rust 回归测试保持一致。

## Scope

- `docs/TESTING.md`
  - 更新“当前覆盖范围 / 当前未覆盖”。
- `docs/tasks/T-035-testing-coverage-sync-2.md`
  - 记录本次任务范围、验收、验证与风险。

## Non-goals

- 不新增任何产品行为或测试代码。
- 不修改 Rust core、Flutter UI、FFI 协议或 session 生命周期逻辑。
- 不扩展为架构文档或路线图重写。

## Files In Scope

- `docs/TESTING.md`
- `docs/tasks/T-035-testing-coverage-sync-2.md`

## Functional Acceptance

- `docs/TESTING.md` 的自动化覆盖范围与当前仓库已有测试一致。
- “未覆盖”列表不再包含已经落地的能力。
- 文档仍保持简洁、可执行，不发散到实现细节。

## Verification Commands

```bash
cd example
flutter analyze
flutter test test/widget_test.dart
flutter test test/terminal/selection_controller_test.dart
flutter test test/ffi/flutterm_core_test.dart

cd native/core
cargo fmt --check
cargo test
```

## Manual QA

本次仅同步文档，不新增 GUI 行为；无需额外手工步骤。

## Done When

- `docs/TESTING.md` 已与当前自动化能力对齐。
- 相关验证命令通过。
- 未超出 Scope / Non-goals。

## Risks / Follow-ups

- 覆盖清单会随新任务继续变化，后续应在同类任务完成时顺手同步，避免再次漂移。
