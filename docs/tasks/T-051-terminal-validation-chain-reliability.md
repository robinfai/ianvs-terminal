# T-051 Terminal Validation Chain Reliability

## Goal

把 Flutter 侧 terminal 验证收敛成稳定、可复跑的 repo 内命令顺序，避免 FFI / integration 测试偶发加载过期 Rust dylib。

## Scope

- `tools/verify_flutter_terminal.sh`
- `example/test/ffi/flutterm_core_test.dart`
- `docs/TESTING.md`
- `docs/tasks/T-051-terminal-validation-chain-reliability.md`

## Non-goals

- 不修改 Rust / Flutter 的公共 ABI
- 不改变产品功能或 terminal 交互行为
- 不替代 `cargo test` 或完整 terminal 主链路验收要求
- 不解决 `flutter run -d macos` 的环境前置台问题

## Files In Scope

- `tools/verify_flutter_terminal.sh`
- `example/test/ffi/flutterm_core_test.dart`
- `docs/TESTING.md`

## Functional Acceptance

- repo 内存在一个固定验证入口，会先产出最新 `libflutterm_core.dylib`，再运行 Flutter-side terminal 验证
- Flutter 侧 PTY / FFI 测试在 dylib 缺失或过期时给出可操作的错误提示，而不是只暴露符号缺失噪音
- resize reflow / scrollback / visible-content repaint 的 app-facing 断言仍留在自动化里，不回退成纯人工 smoke

## Verification Commands

```bash
cd /Users/robinfai/personal/flutterm
./tools/verify_flutter_terminal.sh
```

## Manual QA

本任务只改验证入口与诊断信息，不改变运行态产品行为。

补充检查：

1. 从 repo 根目录执行 `./tools/verify_flutter_terminal.sh`
2. 确认输出顺序固定为：先 build Rust core，再执行 `flutter analyze`、`flutter test`、`integration_test`
3. 若故意移除或替换 dylib，再次运行时应能从错误信息里明确看出需要先刷新 Rust core 产物

## Done When

- Flutter-side terminal 验证有单一推荐入口
- FFI / integration 验证不再依赖人工记忆先 build core
- `docs/TESTING.md` 已把推荐入口和顺序写成权威说明

## Risks / Follow-ups

- 该脚本只覆盖 Flutter 侧 terminal 验证；改 Rust core 时仍需单独执行 `cargo fmt --check` 与 `cargo test`
- 真正的 GUI 手工矩阵与环境风险仍留给 `T-052`
