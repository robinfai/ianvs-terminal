# Terminal Graphics and Pets Retrospective

本目录记录一次完整的终端图片能力迭代：从 terminal pets 报错、平台化方案、Kitty 图像协议接入，到 Codex pet 渲染、背景色、透明通道、位置和闪烁问题的排查与修复。

## 阅读顺序

1. [SUMMARY.md](SUMMARY.md)：一页总结，适合新 agent 快速接手。
2. [01-timeline-and-evidence.md](01-timeline-and-evidence.md)：按对话和证据整理完整时间线。
3. [02-architecture-record.md](02-architecture-record.md)：记录本轮 terminal graphics 的分层设计。
4. [03-debugging-log.md](03-debugging-log.md)：记录从协议泄漏、背景色、透明乱码到闪烁的排查过程。
5. [04-frame-diff-flicker-analysis.md](04-frame-diff-flicker-analysis.md)：解释 20-30fps frame diff 与闪烁的关系，以及为什么修复应在 Rust 侧。
6. [05-verification-evidence.md](05-verification-evidence.md)：命令、replay 指标和构建结果。
7. [06-workflow-retro-and-followups.md](06-workflow-retro-and-followups.md)：流程复盘、成熟度评分、后续改进和 next-session instructions。

## 证据边界

本复盘只使用当前会话可见内容、goal 摘要、subagent 只读分析、当前工作区 diff、测试输出和用户提供的截图/录制路径。不可见的助手中间操作只按已有摘要记录，不补编细节。

用户提供的主要录制：

- `/Users/robinfai/tmp/demo.cast`

最终 replay 统计显示：

```text
frames=175
graphicFrames=173
emptyAfterGraphic=0
```

这说明在该录制场景中，“有图之后突然发出无 graphics frame”的闪烁源已经被消除。
