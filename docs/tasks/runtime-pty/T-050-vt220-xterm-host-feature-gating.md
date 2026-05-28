# T-050 VT220 / xterm Host-Feature Gating

## Goal

为最近引入的 terminal emulation 分流补齐回归护栏，证明 VT220 与默认 xterm profile 在 host-feature 暴露边界上保持明确分离。

## Scope

- `native/core/tests/session_test.rs`
- `example/test/ffi/ianvs_core_test.dart`
- `docs/TESTING.md`
- `docs/tasks/runtime-pty/T-050-vt220-xterm-host-feature-gating.md`

## Non-goals

- 不新增或修改 FFI 导出
- 不改变 VT220 / xterm 运行时行为，只补测试护栏
- 不把 `char_protected` 升级成新的 Flutter/UI 契约
- 不扩展成完整 `vttest` 手工矩阵

## Files In Scope

- `native/core/tests/session_test.rs`
- `example/test/ffi/ianvs_core_test.dart`
- `docs/TESTING.md`

## Functional Acceptance

- VT220 profile 继续返回 VT220 DA 响应
- VT220 profile 不暴露 xterm-only host features：`window_title`、`window_icon_name`、OSC 52 copy/paste 事件
- 默认 xterm profile 继续保留这些 host features
- VT220 既有 keyboard / paste contract 不回归

## Verification Commands

```bash
cd native/core
cargo fmt --check
cargo test

cd example
flutter analyze
flutter test test/ffi/ianvs_core_test.dart
flutter test test/terminal_input_controller_test.dart
```

## Manual QA

1. 在 GUI 中创建一个 VT220 profile，并打开一个本地 shell tab
2. 在 VT220 tab 里发送 OSC title / icon / OSC 52 命令，确认 shell 仍可交互，但 app chrome / clipboard callback 不响应这些 xterm-only host features
3. 切回默认 xterm profile，重复同样命令，确认 title / icon / clipboard callback 继续可用
4. 再次确认 VT220 profile 下普通键盘输入与 paste 行为没有异常

## Done When

- VT220 / xterm host-feature gating 在 Rust 和 Flutter FFI 测试层都有显式护栏
- `docs/TESTING.md` 已同步这类改动的验证入口
- 没有把 `char_protected` 或其他新契约顺手带进 Flutter/UI

## Risks / Follow-ups

- `char_protected` 目前仍是内部状态；若后续确实需要 UI 消费，应新开任务单独设计契约
- 更完整的 VT220 兼容性仍依赖 `vttest` 等手工矩阵，留给 `T-052`
