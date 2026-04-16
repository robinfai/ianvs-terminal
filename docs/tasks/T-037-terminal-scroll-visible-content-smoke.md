# T-037 Terminal scroll 后可见内容变化 Smoke

## Goal

补一条最小自动化覆盖，证明 shell screen 在触发滚动后，只要 core 返回新的 frame diff，terminal viewport 的**实际可见内容**会重新绘制成新的行文本，而不仅仅是 scroll 调用链路被触发。

## Scope

- `app/lib/features/terminal/render_terminal_viewport.dart`
  - 增加最小 debug-only 测试可观测面，记录最近一次 paint 的可见行文本。
- `app/test/widget_test.dart`
  - 新增一条 shell screen 级别的 scroll + frame update + repaint 测试。
- `docs/tasks/T-037-terminal-scroll-visible-content-smoke.md`
  - 记录本次任务边界、验收、验证与风险。
- `docs/TESTING.md`
  - 同步新增覆盖范围并收窄剩余可见内容变化缺口。

## Non-goals

- 不改动 Rust core、FFI 协议、滚动算法、scrollback 数据结构或 viewport 布局策略。
- 不扩展到 golden 截图、真实 GUI 手测、resize 后可见内容变化或复杂滚动手势。
- 不覆盖跨平台滚轮差异、高输出性能、selection 与 scroll 的组合场景。

## Files In Scope

- `app/lib/features/terminal/render_terminal_viewport.dart`
- `app/test/widget_test.dart`
- `docs/tasks/T-037-terminal-scroll-visible-content-smoke.md`
- `docs/TESTING.md`

## Functional Acceptance

- 测试能在 shell screen 中先渲染一组可见行文本。
- 触发滚轮事件后，fake core 返回新的 frame diff。
- terminal viewport 的最近一次 paint 记录出的可见行文本变为新的 frame 内容。
- 证明 scroll 之后 frame diff 驱动的可见内容更新已经被自动化覆盖。

## Verification Commands

```bash
cd /Users/robinfai/personal/flutterm/app
flutter analyze
flutter test test/widget_test.dart
flutter test test/terminal/render_terminal_viewport_test.dart
```

## Manual QA

1. 如环境允许，运行 `flutter run -d macos`。
2. 在 terminal 中产生多行输出。
3. 向上/向下滚动后确认 viewport 中可见文本确实变化。

## Done When

- shell screen 的 scroll 后可见内容 repaint 路径有自动化覆盖。
- 相关验证命令通过。
- `docs/TESTING.md` 已同步到新覆盖现状。

## Risks / Follow-ups

- 当前覆盖验证的是“scroll 后新 frame 被绘制出来”，不覆盖 resize 后可见内容变化。
- 若后续需要更强保证，可继续补 golden / 像素级可视验证，但应另拆任务。
