# 协作复盘

## Review window

本复盘覆盖当前可见会话中 terminal graphics / terminal pets 相关内容，以及当前工作区已有复盘文档和代码状态。不可见的命令输出只按主代理摘要记录，不补编细节。

## 做得好的地方

- 用户提供了高质量对照：当前应用截图、iTerm2 截图和 `demo.cast`。
- 用户及时指出不能硬改 input 行背景，避免走向 app-specific 补丁。
- 用户提出 frame diff 20-30fps 的怀疑，推动分析从 Flutter 现象回到 native frame 边界。
- 主代理已经把一部分现象固化成 Rust/Dart/Flutter 测试。
- 现在启用文档子代理，把过程从聊天记录沉淀为项目资料。

## 摩擦点

| 现象 | 影响 | 改进 |
|---|---|---|
| 早期主要靠截图推进 | 协议、像素、位置、背景和闪烁混在一起 | 遇到 terminal graphics 问题先建立 replay 指标 |
| 阶段性文档写过“已完成”，但用户又复现 | 后续接手者可能误判状态 | 文档中明确区分阶段性验证和当前开放问题 |
| replay 脚本在 `/private/tmp` | 诊断过程不可复用 | 把 replay 工具入库 |
| dylib 路径可能不一致 | 可能用旧构建验证新代码 | replay 输出 dylib path 和 build identity |
| 单帧测试覆盖不足 | 当前多 fallback 空窗漏掉 | 按 replay 真实序列补测试 |

## Agent-first 成熟度评分

| 维度 | 分数 | 依据 | 升级动作 |
|---|---:|---|---|
| Context packaging | 3 | 用户给了方案、截图、录制、iTerm2 对照 | 把 cast、截图和目标指标写成任务包 |
| Task decomposition | 2 | 实现、调试、验证、文档在一个长 goal 中交织 | 下次拆成实现、replay、渲染、文档四个子任务 |
| Verification | 2 | 已有测试和 replay，但当前仍有漏网场景 | replay 工具入库并成为固定门槛 |
| Delegation/tooling | 3 | 已使用文档子代理，主代理继续修代码 | 后续可再分协议、Flutter、验证三个子代理 |
| Communication cadence | 3 | 用户持续给出反馈，主代理持续更新 | 中途更早输出假设树和证据矩阵 |
| Decision policy | 3 | 明确不靠时间猜测和不硬改背景 | 把这些写进 debugging checklist |
| Artifact hygiene | 2 | 有复盘，但目录和状态有分叉 | 统一 docs 入口和“当前状态”字段 |
| Memory/preferences | 2 | 用户偏好被遵守，但还没完全长期化 | 写入 runbook 或未来 `TERMINAL_GRAPHICS_DEBUGGING.md` |

## 下次处理类似问题的规则

```text
本任务是终端协议/渲染问题。不要先猜 UI 补丁。
先收集 cast、当前应用截图和对照终端截图。
用 replay 输出 frames、graphicFrames、emptyAfterGraphic、render_id、asset_id、asset_version、row、col 和 fallback reason。
按 PTY bytes -> Rust parser/store -> TerminalFrameDiff -> Dart cache/merge -> Flutter render 分层定位。
如果用户看到闪烁，优先查 native 是否输出过 graphics=[]，以及 render_id 是否稳定。
不要用固定时间窗口遮挡协议中间态。
不要硬编码某个应用的 input 行背景色。
验证前确认加载的是当前构建的 native dylib。
最终回复必须说明：根因层级、修复点、验证命令、剩余风险、文档同步位置。
```

## 建议沉淀为长期文档

这次目录是调试记录。等主代理最终修完后，建议再从这里提炼两个长期文档：

- `docs/TERMINAL_GRAPHICS.md`：稳定架构和协议边界。
- `docs/TERMINAL_GRAPHICS_DEBUGGING.md`：录制、回放、指标和排查步骤。
