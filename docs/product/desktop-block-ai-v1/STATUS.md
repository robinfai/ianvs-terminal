# 桌面 Block × AI 实施状态

核对日期：2026-10-10。v1.1 交互修订见 [16_REVISION_1_1](16_REVISION_1_1.md)。当前在 `composer` 分支迭代，开始时 HEAD 为 `79db5115d1e6c69ac62116f19fdfb2b102724df5`，开始工作树干净。本轮尚未冻结候选实现 C，不能把旧构建、静态参考或局部测试登记为新 C 的完整验收。

| 阶段 | 状态 | 完整场景通过 | 当前工作 |
|---|---|---|---|
| D1 | in_progress | 0/16 | 收起、补充要求、编辑版本、未知出口及当前 pane 审阅 |
| D2 | in_progress | 0/16 | 焦点归属与迟到粘贴回归；多 pane、Reader 与原生输入仍需核验 |
| D3 | in_progress | 0/16 | 主题／可访问性与完整状态矩阵；不能以原静态图作验收 |
| D4 | planned | 0/16 | 新候选 C 的完整 gate、API/ACP、原生输入、窗口与性能证据 |

64 个场景当前全部 `not_run`；本表阶段进度不替代 manifest 用例结果。源包 PACK_QA、reader 和 qa 目录只说明交付包自身检查，不说明产品通过。

- [基线与证据身份](results/BASELINE.md)
- [跨端需求／实现／证据对照](results/CROSS_PLATFORM_REVIEW.md)
- [桌面 64 条逐项对照](results/DESKTOP_COMPARISON.md)
- [移动 49 条逐项对照](results/MOBILE_COMPARISON.md)
- [第一轮修复与验证](results/ITERATION_1.md)
- [平台与环境台账](results/PLATFORM_MATRIX.md)
- [主题映射与对比度](results/TOKEN_MAP.md)
- [本轮决策](results/DECISIONS.md)
- [验收清单](plan.json) 与 [证据 manifest](evidence/manifest.json)

macOS 是主交付平台；Linux／Windows 依既有宿主分别记录能力与缺口。本轮没有增加 Android、远程 ACP 或跨进程聊天恢复。
