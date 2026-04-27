# T-038 Terminal resize 后可见内容变化 Smoke

## Goal

补一条最小自动化覆盖，证明 shell screen 在触发 layout resize 后，只要 core 返回新的 frame diff，terminal viewport 的**实际可见内容**会重新绘制成新的行文本，而不仅仅是 resize 调用链路被触发。

## Scope

- `example/test/widget_test.dart`
  - 新增一条 shell screen 级别的 resize + frame update + repaint 测试。
- `docs/tasks/T-038-terminal-resize-visible-content-smoke.md`
  - 记录本次任务边界、验收、验证与风险。
- `docs/TESTING.md`
  - 同步新增覆盖范围并移除 resize 可见内容缺口。

## Non-goals

- 不改动 Rust core、FFI 协议、viewport 布局算法、scrollback 数据结构或 terminal renderer 架构。
- 不扩展到 golden 截图、真实 GUI 手测、复杂窗口管理或 scroll + resize 组合压力场景。
- 不覆盖高 DPI 细节、字体测量误差或像素级视觉一致性。

## Files In Scope

- `example/test/widget_test.dart`
- `docs/tasks/T-038-terminal-resize-visible-content-smoke.md`
- `docs/TESTING.md`

## Functional Acceptance

- 测试能在 shell screen 中先渲染一组可见行文本。
- 触发 layout resize 后，fake core 记录到新的 resize 调用。
- resize 后 fake core 返回新的 frame diff。
- terminal viewport 的最近一次 paint 记录出的可见行文本变为新的 frame 内容。

## Verification Commands

```bash
cd example
flutter analyze
flutter test test/widget_test.dart
```

## Manual QA

1. 如环境允许，运行 `flutter run -d macos`。
2. 在 terminal 中产生多行输出。
3. 调整窗口大小，确认 viewport 中可见文本能跟随后续 frame 更新正确变化。

## Done When

- shell screen 的 resize 后可见内容 repaint 路径有自动化覆盖。
- 相关验证命令通过。
- `docs/TESTING.md` 已同步到新覆盖现状。

## Risks / Follow-ups

- 当前覆盖验证的是“resize 后新 frame 被绘制出来”，不覆盖像素级视觉 fidelity。
- 若后续要验证提示符差异、矩形选区或更复杂 clipboard 语义，应拆独立任务继续推进。
