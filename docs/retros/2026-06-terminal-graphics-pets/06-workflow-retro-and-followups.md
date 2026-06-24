# Workflow Retro and Followups

## What Worked

### 用户提供了高质量对照证据

用户提供了当前应用截图、iTerm2 对照截图和 `demo.cast`。这些证据把问题从“看起来闪”变成了可以分层定位的工程问题。

特别有效的证据：

- iTerm2 对照：明确正确行为，包括 pet 顺滑、input 行灰底、位置稳定。
- `demo.cast`：让排查从人工观察转为 replay 统计。
- 多轮截图反馈：帮助区分协议解析、背景色、透明通道、位置和闪烁问题。

### 最终修复回到了正确层级

最终修复不靠 Dart 延时保留，而是回到 Rust/native：

- 不完整 Kitty transfer 期间不输出 frame。
- quiet delete 不被普通文本提交。
- clear screen 空图层 frame 做一次事件级合并。

这符合目标：

```text
Rust 计算，Dart 渲染，不中断不丢失
```

### 形成了可回归测试

相关问题被固化进 Rust 和 Dart/Flutter 测试，特别是：

- terminal pets 真实更新序列。
- quiet delete + Codex menu refresh。
- clear screen + immediate graphics replacement。
- RGBA premultiply。
- graphics cache 和 viewport render。

## Friction Patterns

| Pattern | Evidence | Root cause | Workflow fix |
|---|---|---|---|
| 早期依赖截图人工判断 | 背景色、位置、闪烁多轮靠用户截图推进 | 没有先建立 replay 统计工具 | 协议/渲染问题先收集 cast，并写 frame diff analyzer |
| 曾靠 Dart 层猜测遮挡闪烁 | 用户强调不要靠猜时间 | 根因层级判断太晚 | 每次 flicker 先判断 bytes/native/frame/Dart/render 哪层产出错误 |
| 临时工具未入库 | replay 脚本在 `/private/tmp` | 诊断脚本被当作一次性工具 | 有效诊断脚本迁入 `tools/` 并记录用法 |
| 旧 dylib 影响判断 | 摘要记录早期 rerun 加载旧 dylib | 验证前没有 build identity 检查 | replay 输出 native dylib 路径和 mtime/build id |
| UI 背景问题容易被硬编码修复 | 用户明确“不要硬改光标所在行背景色” | 图像问题和文本 style 问题混在一起 | debugging checklist 明确分层，不跨层补丁 |

## Agent-First Maturity Score

| Dimension | Score | Why | Upgrade |
|---|---:|---|---|
| Context packaging | 3 | 用户提供方案、截图、录制和 iTerm2 对照 | 把这些固化成任务包模板 |
| Task decomposition | 2 | 实现、调试、验证混在一个长 goal | 下次拆成实现、replay、渲染、验证四阶段 |
| Verification | 3 | 最终有 replay 指标、多层测试和 build | 更早引入 replay gate |
| Delegation/tooling | 2 | subagent 和 replay 都有效，但出现较晚 | 开始阶段就分派协议/渲染/验证探索 |
| Communication cadence | 3 | 多轮反馈推动快速收敛 | 中途更早输出假设树和排除项 |
| Decision policy | 3 | 最终坚持不靠时间猜测 | 对“可逆 UI 缓解”和“协议语义修复”先做决策 |
| Artifact hygiene | 2 | 最终有测试和构建记录，但临时脚本未入库 | 诊断工具、录制、验证 ledger 统一落文档 |
| Memory/preferences | 2 | 用户偏好在对话中明确，但尚未长期化 | 写入 debugging runbook 和 next-session instructions |

## Followup Backlog

| Priority | Change | Impact | Effort | Owner | Trigger |
|---:|---|---|---|---|---|
| 1 | 将 replay cast 统计工具入库 | High | M | agent | 下一次 terminal graphics regression |
| 2 | 为 graphics frame diagnostics 增加文档 | High | S | agent | 新增或修改 frame debug 字段 |
| 3 | 建立 iTerm2/Kitty 对照验收模板 | Medium | S | shared | 任何图片、背景、DPR、位置问题 |
| 4 | replay 输出 dylib 路径和 build identity | Medium | S | agent | native dylib 修改后验证 |
| 5 | 补 `docs/TERMINAL_GRAPHICS.md` 长期架构入口 | Medium | M | agent | graphics 平台从迭代进入稳定维护 |
| 6 | 补 `docs/TERMINAL_GRAPHICS_DEBUGGING.md` runbook | Medium | M | agent | 下一次协议/渲染问题前 |
| 7 | 建立 graphics scrollback/cropping 专项任务 | Medium | M | shared | 需要回看历史图片或多行图像裁剪 |

## Next Debugging Checklist

1. 先收集最小 `cast`、当前应用截图和对照终端截图。
2. 写 replay 统计，不先猜 UI 修复。
3. 统计至少包含：`frames`、`graphicFrames`、`emptyAfterGraphic`、`render_id`、`asset_id`、`asset_version`、row/col、fallback reason。
4. 分层定位：PTY bytes -> Rust parser/store -> `TerminalFrameDiff` -> Dart merge/cache -> Flutter render。
5. 先写失败测试，再改实现。
6. 不使用固定时间窗口掩盖协议中间态。
7. 验证前确认 native dylib 已 rebuild 且 app bundle 使用的是新产物。
8. 完成后更新复盘、验证 ledger 或相关任务文档。

## Next-session Agent Instructions

```text
本任务是终端协议/渲染问题。先不要直接猜 UI 修复。
先读取 docs/FRAME_DIFF.md 和 docs/retros/2026-06-terminal-graphics-pets/SUMMARY.md。
必须先建立 replay/统计证据：frames、graphicFrames、emptyAfterGraphic、render_id、asset_id、asset_version、placement。
按 PTY bytes -> Rust parser/store -> TerminalFrameDiff -> Dart merge/cache -> Flutter render 分层定位。
对闪烁、位置、背景问题，优先写最小复现测试和 replay 指标，不用 Dart 延时或硬编码背景掩盖。
验证前确认 native dylib 已重新 build 且 app 使用的是新产物。
最终回复必须包含：根因层级、修复点、验证命令、剩余风险、文档同步位置。
```
