# T-041 Terminal 非对称列范围选择语义

## Goal

补一条最小自动化覆盖，锁定 terminal 文本选择在**首尾列范围不对称**时的当前线性多行语义，避免后续改动无意破坏现有复制结果。

## Scope

- `app/test/terminal/selection_controller_test.dart`
  - 新增一条非对称多行列范围选择的单元测试。
- `docs/tasks/T-041-terminal-selection-asymmetric-columns.md`
  - 记录本次任务范围、验收、验证与风险。
- `docs/TESTING.md`
  - 同步当前新增覆盖项，并把未覆盖项收窄到真正的矩形/block 选区语义。

## Non-goals

- 不改动 selection 算法、widget 交互、clipboard bridge 或 renderer。
- 不实现真正的矩形/block 选区。
- 不扩展到 widget/integration 层或外部应用粘贴验证。

## Files In Scope

- `app/test/terminal/selection_controller_test.dart`
- `docs/tasks/T-041-terminal-selection-asymmetric-columns.md`
- `docs/TESTING.md`

## Functional Acceptance

- 测试能构造一个跨三行、首尾列范围不对称的选择区间。
- `textForFrame(...)` 会按照当前线性多行语义返回首行尾段 + 中间整行 + 末行前段。
- 该语义被自动化锁定，避免后续修改时意外漂移。

## Verification Commands

```bash
cd /Users/robinfai/personal/flutterm/app
flutter analyze
flutter test test/terminal/selection_controller_test.dart
```

## Manual QA

本次主要补 selection 语义单元覆盖，不直接要求 GUI 手测。

## Done When

- 新增非对称列范围选择语义测试通过。
- 相关验证命令通过。
- `docs/TESTING.md` 已同步覆盖现状。

## Risks / Follow-ups

- 当前测试锁定的是既有线性多行语义，不代表已经支持真正的矩形/block 选区。
- 若后续要实现矩形选区，应拆独立任务明确新的交互和复制语义。
