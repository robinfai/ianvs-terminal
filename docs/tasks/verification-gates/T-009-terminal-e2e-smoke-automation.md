# T-009 Terminal 端到端 Smoke 自动化

## Goal

为 `ianvs terminal` 补一条最小可运行的 Flutter integration_test 冒烟链路，减少对人工 GUI 介入的依赖。

## Scope

- `example/pubspec.yaml`
  - 增加 `integration_test` 开发依赖。
- `example/integration_test/ianvs_smoke_test.dart`
  - 增加最小启动/开 tab 冒烟用例。
- `example/test/support/memory_profile_repository.dart`
  - 抽出测试内存 profile 仓储供 widget/integration 测试复用。
- `example/test/widget_test.dart`
  - 复用新的测试支持类，保持现有 widget 冒烟语义。
- `docs/TESTING.md`
  - 补充自动化 smoke 命令与适用范围。

## Non-goals

- 不尝试在本任务里自动化真实 PTY 命令执行（如 `pwd`/`ls`）。
- 不替代所有手工 smoke；高风险输入、剪贴板、滚动、resize 仍保留人工兜底。
- 不引入第三方 E2E 框架或新的运行时依赖。
- 不修改 Rust core、FFI 协议或 terminal 渲染架构。

## Files In Scope

- `example/pubspec.yaml`
- `example/integration_test/ianvs_smoke_test.dart`
- `example/test/support/memory_profile_repository.dart`
- `example/test/widget_test.dart`
- `docs/TESTING.md`

## Functional Acceptance

- 仓库可通过 Flutter 官方 `integration_test` 运行一条自动化 smoke 用例。
- smoke 用例至少能验证应用启动后存在 terminal UI，并可创建额外 tab。
- 现有 widget test 仍通过，且复用测试 profile 仓储而不重复定义。
- `docs/TESTING.md` 明确记录该自动化 smoke 命令。

## Verification Commands

参考 [TESTING.md](../../TESTING.md)：

```bash
cd example
flutter analyze
flutter test
flutter test integration_test/ianvs_smoke_test.dart
```

## Manual QA

1. 如环境允许，仍可执行 `flutter run -d macos` 做一轮人工 GUI smoke。
2. 对输入、复制粘贴、滚动、resize 等高风险终端行为，继续按 `docs/TESTING.md` 的人工清单执行。

## Done When

- 最小 integration_test smoke 路径可运行并通过。
- 相关文档已更新，明确哪些验证已自动化、哪些仍需人工兜底。
- 未超出 Scope / Non-goals。

## Risks / Follow-ups

- 当前 integration_test 只覆盖“启动 + tab 创建”级别 smoke，不覆盖真实 shell 命令往返。
- 若后续要自动化更多 terminal 交互，可能需要继续抽象 test-only 注入点或稳定的 fake session 行为。
