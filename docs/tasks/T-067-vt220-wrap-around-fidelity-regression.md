# T-067 VT220 Wrap-Around Fidelity Regression

## Goal

把 `vttest` 暴露出的 VT220 wrap-around 失败收成可自动回归的 bugfix，
确保连续满宽输出不会出现中间短行。

## Scope

- 锁定 VT220 profile 下的 wrap-around 失效场景。
- 同时补 native/core 和 Flutter/render 两层护栏。
- 必要时修正 core 或 viewport 实现，但只围绕 wrap-around 正确性。

## Non-goals

- 不扩展成完整 `vttest` 自动化套件。
- 不顺手修改 title / clipboard / OSC host-feature gating。
- 不把 resize / DPI / glyph fidelity 混进这张卡。
- 不扩展新的公共 API 或 frame schema。

## Files In Scope

- `native/core/tests/session_test.rs`
- `example/test/terminal/render_terminal_viewport_test.dart`
- 必要时对应的 core / viewport 实现文件
- `docs/tasks/T-067-vt220-wrap-around-fidelity-regression.md`

## Functional Acceptance

- 严格 VT220 profile 下，连续满宽输出不会产出中间短行。
- native/core 层有专门针对该 wrap-around 失效场景的回归测试。
- Flutter/render 层有专门针对同一 frame 连续满宽行渲染的回归测试。
- 修复后 `vttest` wrap-around 页面中的 3 条连续满宽 `*` 行长度一致。
- 现有 wrapped-row、resize reflow、selection contiguous 相关回归不被破坏。

## Verification Commands

```bash
cd native/core
cargo fmt --check
cargo test
```

```bash
cd example
flutter test test/terminal/render_terminal_viewport_test.dart
```

## Manual QA

1. 在 VT220 profile 下运行 `vttest`。
2. 进入 screen features 的 wrap-around 页面。
3. 确认顶部 3 条 `*` 行连续、等宽、无空行。
4. 再复验 VT220 terminal reports，确认 DA 响应没有顺手回归。

## Done When

- VT220 wrap-around 失败已有最小自动化回归。
- native/core 和 Flutter/render 两层都有明确护栏。
- `vttest` wrap-around 页面人工复验通过。
- 没把本任务扩成完整 VT220 兼容性重构。

## Risks / Follow-ups

- 如果 root cause 最终只在一层，另一层的测试仍要保留，用来防止以后再把问题重新引入。
- 若后续 `vttest` 暴露新的 VT220 screen-features 问题，应再单开 focused task，不继续堆进这张卡。
