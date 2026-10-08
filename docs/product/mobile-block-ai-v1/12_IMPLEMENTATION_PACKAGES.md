# 12 · Codex 工作包、依赖与交付顺序

这里的 `WP` 是建议提交单元，不是追加产品功能或硬性天数估算。先按最新分支做差距表，已满足的需求只补证据，禁止重复实现一遍。每个工作包完成都要同时更新测试、截图与结果文档。

## 1. 开始前的 WP-00

读取 `AGENTS.md`、当前 execution target、产品边界、本包 00/06/10/11。记录 `git rev-parse HEAD`、当前分支与工作树状态；fetch 远端时不覆盖未提交工作，不 reset --hard，不强推。若指定分支无法读取或仓库状态冲突，明确阻塞，不悄悄改 main。

产出 `results/BASELINE.md`：

| 字段 | 必填内容 |
|---|---|
| 版本 | 文档基线、实际开始 HEAD、差异说明 |
| 当前能力 | 每个 Sx-Rnn 的 existing / partial / missing / needs-verification |
| 生产入口 | 当前真实路径、调用关系、canonical 与生成镜像 |
| 工具/设备 | Flutter/Xcode/Rust 版本，可用 simulator、iPhone、iPad、macOS、输入法 |
| 依赖 | 隔离 SSH fixture、模型 mock、实际模型 API / 桌面 ACP 的可用性 |
| 变更前证据 | 相应场景原图、环境和 baseline commit |
| 风险 | 已有失败、未跑 gate、需产品确认的重大差异 |

只有真实能力变化或明确未实现的需求进入实现清单。文档旧日期下的缺口，不经当前代码验证不能当作本轮 bug。

## 2. 阶段一：行为闭环先行

| 工作包 | 内容与边界 | 主要现有入口（需核对最新 tree） | 验收/输出 |
|---|---|---|---|
| WP-11 | 失败 Block 直接诊断、上下文 Chips、保留原草稿；不自动推理/执行 | compact blocks、controls、shell_screen_ai | S1-T01/T02/T11；D1-01 对照原图 |
| WP-12 | 提案→全屏审阅→编辑新 revision→一次批准→原生 Block | workspace proposal/review、controller、approval | S1-T03/T04/T05；D1-02/03，连续录屏 |
| WP-13 | 只读查看与接管/暂停/中断分离；先堵所有写入口 | shell AI、runtime/input/focus routes | S1-T06/T10；只读键盘/粘贴/鼠标报告反向测试 |
| WP-14 | 锚点、新提案提示、unknown 与 target_changed 恢复 | timeline/reader、connections、controller | S1-T07/T08/T09/T12；原提交检查与场景结果 |

顺序：WP-12/13 的边界测试先于 UI 按钮改名。WP-11 可独立推进；WP-14 依赖稳定的来源/任务身份。完成后冻结 S1 实现 commit 并提交完整 S1 证据；没有实机可暂标 implemented_unverified，但不能宣称最终通过。

## 3. 阶段二：统一输入和响应式

| 工作包 | 内容与边界 | 主要现有入口 | 验收/输出 |
|---|---|---|---|
| WP-21 | 一个可见主输入、Auto/Command/AI 可见路由、共享主动作决策；保留 controller 边界 | composer view、AI prompt/composer | S2-T01；输入决策表与静态/原生测试 |
| WP-22 | 1–4 行输入、展开编辑、软件/硬件键盘、IME、长命令选区 | editor、iOS input bar、focus/shortcuts | S2-T02/T03/T06/T10；系统键盘连续录屏 |
| WP-23 | 键盘/旋转/短窗、Reader、Chips、手势冲突 | compact blocks、reader、mobile navigation | S2-T04/T05/T07/T08/T09；竖横屏 before/after |
| WP-24 | iPad 双栏/窄窗、macOS Dock 和分屏回归 | shell layout、workspace adapter | S2-T11/T12；真实窗口，不用窄桌面冒充手机 |

先让最短可用窗口有明确退路，再优化正常尺寸。不能先用缩小字号/缩小点击区掩盖 overflow。手机固定字号与主动终端缩放区分处理。

## 4. 阶段三：视觉和状态语言

| 工作包 | 内容与边界 | 主要现有入口 | 验收/输出 |
|---|---|---|---|
| WP-31 | tokens、Typography、状态文案清单与语义图标盘点 | AppThemeTokens / ComposerTheme / 现有图标 | S3-T01/T02/T05；token 映射表及对比结果 |
| WP-32 | Block/Proposal/Task/Composer/Context 分层；主动作与禁用原因 | 真实公共 Flutter 组件 | S3-T03/T04/T09；组件状态册，不使用整图 UI |
| WP-33 | 中英长文、固定手机字号、焦点、减少动效 | l10n、semantics、focus/motion tokens | S3-T06/T07/T08；真实 App 与语义检查 |
| WP-34 | 跨端回归、canonical 同步、同 OS golden 更新 | canonical 包与生成 standalone | S3-T10；镜像检查和实际 desktop 证据 |

不在大面积移动/重命名所有文件后才补回归。每次只拆一个可以独立测试的组件，再跑实际 App 的关键路径。

## 5. 阶段四：真实平台闭环

| 工作包 | 内容 | 验收/输出 |
|---|---|---|
| WP-41 | iPhone 实机、中文 IME、旋转、VoiceOver | S4-T01～T04；真实机型/OS、原始连续录屏 |
| WP-42 | 故障注入、锁屏后台、TUI/密码、长输出、重复批准 | S4-T05～T09；operation/Block/owner 匿名事件与副作用断言 |
| WP-43 | profile 性能、iPad 实机、macOS API/ACP、隔离升级回滚 | S4-T10～T13；样本数、原始统计、数据边界与真实设备 |
| WP-44 | 冻结最终 C，按影响面/最终矩阵回归，提交 E，生成最终报告 | S4-T14；48 用例和全部帧检查点、两个校验器与人工复核 |

实机/性能不是“最后一天补截图”。从 WP-00 就安排设备可用性，从 S1 就保留事件/采集入口。硬件不在环境中时记录具体需求并完成其余可验证项；不得通过删除实机场景来让所有状态变绿。

## 6. 每个工作包提交需要包含什么

提交说明至少写：需求/用例 ID、当前问题、实际改动、保留边界、测试命令/结果、证据路径、遗留风险。不把 PRD 计划内容写成已实现。实测与预期分栏，不复制粘贴一个“通过”填满所有格。

建议实现代码与测试 commit C → 从 C 构建采证 → evidence-only commit E。小工作包的中间图可保留，但阶段关闭与最终复核用对应冻结构建，不将旧图重新标为新 SHA。

## 7. 风险处理与变更权限

| 情况 | 正确处理 | 不接受 |
|---|---|---|
| 最新代码已经修复 PRD 中的旧缺口 | 记录 existing，补测试/原图 | 重写成熟逻辑以制造改动量 |
| 缺 iPhone/iPad 或输入法 | 写 blocked / implemented_unverified 和精确补测步骤 | 模拟器截图标实机 |
| 某性能目标基线不达标 | 提交原始数据、归因、待确认调整 | 偷改阈值/删样本 |
| 需要改公共协议/持久化/远程 ACP | 单独记录提案并等待明确授权 | 当作 UI 顺手重构 |
| source 与证据 commit 不一致 | 重建并重跑影响面 | 改 manifest 的 SHA 假装同一构建 |
| 模型与 UI 测试偶发失败 | 保留失败、重现条件、重跑记录 | 只保留成功一次并抹掉原因 |

## 8. 最终提交反馈

最终回复必须有分支、实现 C、证据 E、PR/compare 入口、四阶段真实状态、运行过的测试清单、截图/录屏/manifest 入口、未完成项、回滚方式。不要只说“已完成，可检查”。

本轮用户授权的是按 PRD 完善与提交项目；不自动授权发布商店、操作生产服务、安装到用户生产 bundle、读取真实机密、长期后台监控或新建远端服务。
