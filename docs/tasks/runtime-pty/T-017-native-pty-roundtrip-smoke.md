# T-017 Native PTY 命令往返 Smoke

## Goal

补一条最小 Rust core 自动化测试，验证交互式本地 shell session 能接收输入并产生命令输出。

## Scope

- `native/core/tests/session_test.rs`
  - 增加一条交互式 shell roundtrip 测试。
- `docs/tasks/runtime-pty/T-017-native-pty-roundtrip-smoke.md`
  - 记录本次任务范围、验收、验证与风险。

## Non-goals

- 不改动 Flutter UI、terminal renderer、tab 管理或剪贴板交互。
- 不扩展到复杂 shell 脚本、多命令流水线、长时间交互会话或性能基准。
- 不修改 FFI 接口设计或 session 生命周期架构。
- 不覆盖 SSH、split pane、跨平台 PTY 行为。

## Files In Scope

- `native/core/tests/session_test.rs`
- `docs/tasks/runtime-pty/T-017-native-pty-roundtrip-smoke.md`

## Functional Acceptance

- 测试以交互式本地 shell profile 创建 session。
- 测试通过 `write_session` 写入一条命令。
- session 产生的 frame diff 中能观察到对应命令输出。
- 该测试证明 PTY 至少具备“输入 -> shell 执行 -> 输出”最小往返能力。

## Verification Commands

参考 [TESTING.md](../../TESTING.md)：

```bash
cd native/core
cargo fmt --check
cargo test
```

## Manual QA

本次主要补 Rust core 自动化回归，不直接改 GUI 路径；手工 GUI smoke 不作为本任务关闭前置条件。

## Done When

- 新增 roundtrip 测试通过。
- `cargo fmt --check` 与 `cargo test` 通过。
- 未超出 Scope / Non-goals。

## Risks / Follow-ups

- 当前测试只覆盖单条命令往返，不覆盖复杂交互、提示符差异或长会话稳定性。
- 若后续要从 Flutter 侧验证真实 PTY 回显，可在此基础上再补上游自动化任务。
