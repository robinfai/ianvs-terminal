# T-068 Trackpad Momentum and Return-to-Bottom Scrollback Behavior

## Goal

补齐真实 trackpad 的惯性滚动和回到底部行为，让 scrollback 在
`PointerPanZoom` 路径上具备自然的减速续滚和稳定回底。

## Scope

- 只修 terminal viewport 的 trackpad pan/scrollback 行为。
- 保持 wheel path、thumb drag path、mouse-reporting path 不回归。
- 为 momentum continuation 和 return-to-bottom 补自动化与手工护栏。

## Non-goals

- 不改 selection、copy、search、alternate screen 语义。
- 不把这张卡扩成通用滚动动画系统或用户可配动量参数。
- 不扩展新的公共 API。
- 不补做 `T-059` 之外的 VT220 / DPI / prompt 人工矩阵。

## Files In Scope

- `packages/ianvs_terminal/lib/src/terminal/terminal_viewport.dart`
- `example/test/terminal/render_terminal_viewport_test.dart`
- 必要时 `packages/ianvs_terminal/test/terminal_api_test.dart`
- `docs/tasks/terminal-interaction/T-068-trackpad-momentum-and-return-to-bottom-scrollback-behavior.md`

## Functional Acceptance

- `PointerPanZoom` 路径继续保留高精度 delta 累积，不在 `panZoomEnd` 时直接丢掉剩余滚动意图。
- 手指松开后，viewport 会按最近 pan 更新估算速度，继续做减速续滚，直到耗尽或撞边界。
- 快速向下滚动后，scrollback 能自然回到 offset `0`，不会停在半路。
- wheel path、thumb drag path、mouse-reporting path 的现有行为不回归。
- 现有 trackpad pan -> positive scrollback delta 测试保持为绿，并新增 momentum / return-to-bottom 专项回归。

## Verification Commands

```bash
cd example
flutter test test/terminal/render_terminal_viewport_test.dart
```

## Manual QA

1. 在真实 trackpad 上制造足够长的 scrollback。
2. 验证普通上下滚动仍正常。
3. 验证松手后会继续惯性滚动，而不是立即停住。
4. 验证 scrollbar thumb drag 仍正常。
5. 从中段快速向下滚动，确认 viewport 能自然回到底部 prompt。

## Result

- Status: complete
- Completed on: 2026-05-07
- Automated verification:
  - `flutter test test/terminal/render_terminal_viewport_test.dart`
- Manual QA:
  - 普通上下滚动：pass
  - 惯性滚动：pass
  - scrollbar thumb drag：pass
  - return-to-bottom：pass
  - 该人工项在另一台真实 trackpad 机器上完成

## Done When

- `PointerPanZoom` 的 momentum continuation 已落地且有自动化护栏。
- return-to-bottom 失效已修复且有自动化护栏。
- 真实 trackpad 人工复验通过。
- wheel / thumb drag / mouse-reporting 路径不回归。

## Risks / Follow-ups

- Flutter test 只能覆盖 widget 级 pan/scroll 合成，不替代真实 trackpad 手感验证。
- 如果后续发现 momentum continuation 和 selection auto-scroll 互相干扰，应再开 focused task，不在本卡顺手扩范围。
