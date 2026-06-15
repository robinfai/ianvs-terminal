# T-318 Command Center Context Chips

## Goal

展示 terminal-safe context chips。

## Scope

- 从现有 session/productivity state 派生 cwd、profile、shell hook status、last exit、selected block 和 read-only chip。
- 为 chip click 行为提供安全 action intent。
- 显示 shell integration unavailable reason。

## Non-goals

- 不触发命令执行。
- 不做 Agent / AI context。
- 不做 remote / SSH context。
- 不进行高频 filesystem probe。
- 不把 chip UI 下沉到 package。

## Files In Scope

- `example/lib/features/command_center/context_chip_models.dart`
- `example/lib/features/command_center/context_chips.dart`
- `example/test/command_center/context_chips_test.dart`

## Functional Acceptance

- cwd chip 反映当前 cwd 或 unavailable state。
- profile chip 反映当前 local profile。
- shell hook chip 可显示 enabled / disabled / limited。
- last exit chip 可指向最近失败 block。
- selected block chip 可打开 block actions。
- read-only chip 可见且不靠颜色单独表达。
- chip click 不会直接执行命令。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/command_center/context_chips_test.dart
```

## Manual QA

- 运行命令并切换 cwd，确认 cwd chip 更新。
- 运行失败命令，确认 last exit chip 状态。
- 切换 read-only，确认 read-only chip 更新。
- 点击 chip，确认只打开安全 action 或诊断，不直接执行命令。

## Done When

- Command Bar 和 mode router 可消费 context chips。
- chip states 和 click intents 有测试。
- chips 不造成 terminal input 失焦或误执行。

## Risks / Follow-ups

- git branch chip 如果需要 filesystem probe，必须另开任务定义 debounce、错误处理和性能限制。
- chips 过多会挤压输入区域，后续 UI 任务需要控制密度。
