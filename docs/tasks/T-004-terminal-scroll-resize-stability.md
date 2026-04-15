# T-004 Terminal 滚动与 resize 稳定化

## Goal

让终端滚动与窗口尺寸变化在连续操作时更稳定：
- 鼠标滚轮按位移转换为行数；
- 重复发起的相同尺寸 resize 不再重复下发。

## Scope

- `app/lib/features/terminal/render_terminal_viewport.dart`
  - 优化 `PointerScrollEvent` 的行数计算，按 viewport 单元高度聚合滚动位移。
- `app/lib/features/sessions/session_controller.dart`
  - 缓存上一次的 resize 参数，跳过重复请求。
- `app/test/terminal/render_terminal_viewport_test.dart`（按需新增/更新）：
  - 覆盖滚轮位移聚合逻辑。
- `app/test/sessions/session_controller_test.dart`
  - 覆盖 resize 去重行为。
- `app/test/support/fake_core_bindings.dart`
  - 记录 resize 调用次数与参数。

## Non-goals

- 不引入新的滚动加速/惯性模型（例如平滑动画）。
- 不改动 native 的滚动语义协议。
- 不改变 selection/输入按键主流程。

## Files In Scope

- `app/lib/features/terminal/render_terminal_viewport.dart`
- `app/lib/features/sessions/session_controller.dart`
- `app/test/terminal/render_terminal_viewport_test.dart`
- `app/test/sessions/session_controller_test.dart`
- `app/test/support/fake_core_bindings.dart`

## Functional Acceptance

- 长度较大的滚轮位移会触发多行滚动，而非每次仅按 `sign` 单步。
- 同一会话在未发生尺寸变化时，多次 `resizeActiveSession` 不应重复调用 core resize。
- 会话尺寸变化时应带入正确的 cols/rows/pixel 尺寸。

## Verification Commands

```bash
cd /Users/robinfai/personal/flutterm/app
flutter analyze
flutter test
```

## Manual QA

1. 启动应用并打开一个 shell。
2. 发大量输出（如 `yes | head -n 200`，再 Ctrl+C 停止）。
3. 拖拽窗口边缘放大/缩小。
4. 滚轮快速向上/向下滚动，观察不再出现卡顿式抖动。
5. 快速切换窗口大小，确认光标与内容无明显错位。

## Done When

- 滚动和 resize 的行为通过新增测试覆盖。
- `flutter analyze` 与 `flutter test` 通过。
- 无新增 lint 问题。

## Risks / Follow-ups

- 本次不覆盖高频 resize 的性能基线，后续可加节流/防抖测试。
