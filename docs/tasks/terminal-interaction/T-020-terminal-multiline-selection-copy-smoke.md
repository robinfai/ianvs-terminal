# T-020 Terminal 多行选区复制回归

## Goal

补一组最小自动化测试，验证 terminal 多行选区在复制前的文本提取语义稳定，尤其是跨行换行和反向拖选归一化行为。

## Scope

- `example/test/terminal/selection_controller_test.dart`
  - 新增 `SelectionController.textForFrame` 的多行选区回归测试。
- `docs/tasks/terminal-interaction/T-020-terminal-multiline-selection-copy-smoke.md`
  - 记录本次任务范围、验收、验证与风险。

## Non-goals

- 不改动 `Copy` 按钮 UI、键盘快捷键复制或系统剪贴板写入路径。
- 不修改 terminal renderer、Rust core、FFI 协议或 session 生命周期架构。
- 不覆盖矩形选区、复杂 ANSI 样式、富文本复制或跨平台差异。
- 不引入新的测试框架、桌面自动化依赖或额外 harness。

## Files In Scope

- `example/test/terminal/selection_controller_test.dart`
- `docs/tasks/terminal-interaction/T-020-terminal-multiline-selection-copy-smoke.md`

## Functional Acceptance

- 多行选区复制文本会按行插入换行符。
- 反向拖选（从后往前选）会被正确归一化，提取结果与正向拖选一致。
- 选区结束列超过行文本长度时会安全裁剪，不抛异常。
- 无选区时返回空字符串。

## Verification Commands

```bash
cd example
flutter analyze
flutter test test/terminal/selection_controller_test.dart
```

## Manual QA

1. 如环境允许，启动应用并打开一个 terminal tab。
2. 输出多行文本。
3. 从后往前拖选跨行内容并执行复制。
4. 在外部文本框粘贴，确认文本顺序、换行与预期一致。

## Done When

- 多行选区文本提取的关键边界由自动化测试覆盖。
- `flutter analyze` 与目标测试命令通过。
- 未超出 Scope / Non-goals。

## Risks / Follow-ups

- 本任务只验证文本提取语义，不验证系统剪贴板写入本身；按钮/快捷键路径已由其他任务覆盖。
- 若后续要支持矩形选区或更复杂 selection 语义，应拆独立任务继续扩展。
