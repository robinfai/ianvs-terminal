# 当前 UI 验证入口

产品 UI 的检查要求见 [人工验收清单](docs/compatibility/MANUAL_VERIFICATION.md)，
运行方法见 [TESTING](docs/TESTING.md)。本页不保存历次设计方案或截图验收记录。

- 组件与交互测试：`example/test/ui/`、`example/test/shell/`。
- 视觉回归测试：`example/test/design/`；当前黄金图保存在
  [goldens](example/test/design/goldens/)，不保存在 `docs/`。
- 平台约束及未解决的视觉差异见 [KNOWN_ISSUES](docs/KNOWN_ISSUES.md)。
- 新截图、对比图和运行日志写入 `build/`；基线更新必须先确认预期视觉变化。
