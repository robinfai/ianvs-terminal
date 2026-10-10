# 桌面 Block × AI 实施状态

核对日期：2026-10-10。整体状态：`implemented_unverified`。v1.1 交互修订见 [16_REVISION_1_1](16_REVISION_1_1.md)。本轮在 `composer` 分支从干净的 `79db5115d1e6c69ac62116f19fdfb2b102724df5` 开始迭代；当前实现候选 C3 为 `7e9f0dd8e7bd825c655ceb80d817d5fe214337bd`。

C3 的完整 `make verify` 已通过：`build/desktop-prd-v1/iteration-1/verify-7-metadata.json` 记录 exit 0、首尾源码干净，完整日志为同目录 `verify-7.log`。应用测试 2,965 项通过、1 项跳过；macOS 原生冒烟 4 项、真实 PTY 45 项、Composer 1 项、Keychain 1 项通过；Debug／Release 构建、签名检查和 Xcode 测试通过。上述计数描述不同测试集合，不等于 64 个完整产品场景通过。

| 阶段 | 状态 | 完整场景通过 | 当前工作 |
|---|---|---|---|
| D1 | in_progress | 0/16 | 输入权限、补充要求、编辑版本、未知出口、当前 pane 审阅及关闭保护已修复并通过自动回归；真实 API／ACP 全流程继续验收 |
| D2 | in_progress | 0/16 | 焦点、滚动、Reader、待审导航及单层顶栏回归已通过；实际拖窗、多 pane 组合、真实 IME／键鼠仍待验收 |
| D3 | in_progress | 0/16 | 主题色对、活动目标底栏和指定 macOS 27 视觉基线已验证；完整主题／状态／本地化和原生辅助技术矩阵未齐 |
| D4 | in_progress | 0/16 | C3 完整 gate 和回环 OpenSSH 六组原生 API 场景通过；ACP真实模型／取消恢复协议已通过；正常UI完整链路、窗口录像、物理输入、性能与升级回滚证据仍需补齐 |

64 个完整场景当前全部 `not_run`；本表阶段进度不替代 manifest 用例结果。正式 manifest 未因局部回归或构建成功改为通过。源包 PACK_QA、reader 和 qa 目录只说明交付包自身检查，不说明产品通过。

C3 的额外原生验收运行 `native-c3-workspace-1` 未完成：录屏工具初始化失败，随后 CUA 明确报告 Mac 锁屏，UI 驱动停在打开 Reader。仅终止了该次自有验收 App，运行 exit 79、`capture_artifacts_complete=false`；这是环境／采集阻断，不登记为产品失败，也不登记完整场景通过。Mac 解锁已向用户询问，等待恢复后重跑。回环 OpenSSH 的 `ssh-c3-native-1` 在 C3 首尾源码干净时 exit 0；它使用 production native session API，无 GUI，不能替代 D4-T02 完整场景。

iPhone 的 C3 独立 Trail PRD Profile 构建已成功，签名、描述文件和独立 Keychain 已校验；`build/mobile-prd-v1.1/ios/physical-profile.MIDSac/build-metadata.json` 仍记录 `installed=false`、`device_validated=false`、`acceptance_passed=false`。USB 重连已询问，尚未安装或完成新候选真机验收。实体 iPad 与外接显示器按用户已确认的条件保留未验收，不再重复询问。

- [当前交付结论与待验收边界](results/FINAL_REVIEW.md)
- [基线与证据身份](results/BASELINE.md)
- [跨端需求／实现／证据对照](results/CROSS_PLATFORM_REVIEW.md)
- [桌面 64 条逐项对照](results/DESKTOP_COMPARISON.md)
- [移动 49 条逐项对照](results/MOBILE_COMPARISON.md)
- [第一轮修复与验证](results/ITERATION_1.md)
- [平台与环境台账](results/PLATFORM_MATRIX.md)
- [主题映射与对比度](results/TOKEN_MAP.md)
- [本轮决策](results/DECISIONS.md)
- [验收清单](plan.json) 与 [证据 manifest](evidence/manifest.json)

macOS 是主交付平台；Linux／Windows 依既有宿主分别记录能力与缺口。本轮没有增加 Android、远程 ACP 或跨进程聊天恢复。已约定范围没有新的必需产品决策，未完成项是实现的完整验收与证据收集工作。
