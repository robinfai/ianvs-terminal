# Terminal Graphics Debug 记录

本目录记录 terminal graphics / terminal pets 闪烁问题这一轮 goal 的背景、时间线、实现变化、当前根因判断和后续改进点。

## 证据边界

本目录只使用以下可见资料：

- 当前会话中用户提供的需求、截图描述和录制路径。
- 当前工作区已有的相关复盘文档。
- 当前工作区代码和测试改动的只读检查结果。
- 主代理上下文摘要中记录的最新 replay 观察。

当前主代理仍在继续修代码，所以这里不是最终验收报告。本文档把“已经验证过的阶段性事实”和“当前仍待修复的问题”分开记录。

## 阅读顺序

1. [summary.md](summary.md)：一页摘要，适合快速接手。
2. [01-timeline.md](01-timeline.md)：从最初不支持 pets 到当前闪烁问题的完整时间线。
3. [02-implementation-record.md](02-implementation-record.md)：本轮实现和已改动设计的记录。
4. [03-current-flicker-analysis.md](03-current-flicker-analysis.md)：当前 3-5 秒间隔消失近 1 秒的主要原因分析。
5. [04-evidence-and-verification.md](04-evidence-and-verification.md)：录制、回放、测试和当前证据状态。
6. [05-improvement-plan.md](05-improvement-plan.md)：建议主代理继续推进的改进点和验证门槛。
7. [06-workflow-retro.md](06-workflow-retro.md)：这轮协作流程的复盘和下次可复用规则。

## 当前一句话结论

闪烁大概率不是 Flutter 帧率本身造成的，而是 native 侧在 pet 周期性更新时仍会短暂输出空 `graphics`，同时某些 clear-screen replacement 会改变 `render_id`。Flutter 看到空列表或新 key 后会移除旧 overlay，并在新图片加载完成前短暂不画 pet。
