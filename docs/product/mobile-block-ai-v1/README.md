# Trail / ianvs-terminal 移动端 Block × AI 产品完善包

**版本：1.1 · 2026-10-08**  
**对象：Codex 实施、产品设计、代码评审与真实设备验收**  
**基线：`composer@763dc166bb1e56d6d50ed3379b57f366c9ca06b7`**

这是四个阶段的实施 PRD，不是“从零开发一个终端”。目标是在现有 Flutter / Rust / PTY、Command Block、Composer、AI Task 与审批回执之上，完成手机端核心体验，并保证 iPad / macOS 不退化。

> 本包所有设计例图、HTML 页面、状态数据均为**设计参考**，不是应用截图或验收结果。全部用例初始状态为 `not_run`。未运行项目、未生成产品真实截图、未修改或推送 GitHub 源码。

## 阅读顺序

| 文档 | 用途 |
|---|---|
| [00 范围与基线](00_SCOPE_AND_BASELINE.md) | 冻结边界、已有能力、不可破坏的合同 |
| [01 阶段一：核心闭环](01_STAGE_1_CORE_FLOW.md) | 失败 Block → AI → 审阅 → 执行 → 结果；只读观察与接管 |
| [02 阶段二：输入与响应式](02_STAGE_2_RESPONSIVE_INPUT.md) | 统一输入语义、软键盘、长命令、横竖屏、iPad 分栏 |
| [03 阶段三：视觉系统](03_STAGE_3_VISUAL_SYSTEM.md) | 语义 tokens、组件层级、深浅色、状态与跨端一致性 |
| [04 阶段四：实机与交付](04_STAGE_4_DEVICE_ACCEPTANCE.md) | 中文 IME、VoiceOver、断连、TUI、性能、最终发布门槛 |
| [05 示例设计与标注](05_DESIGN_REFERENCE.md) | 每阶段静态设计稿、布局与文案规格 |
| [06 截图与证据合同](06_EVIDENCE_CONTRACT.md) | 图片、视频、日志、SHA、提交顺序、证据分级 |
| [07 验收矩阵](07_ACCEPTANCE_MATRIX.md) | 48 个固定场景与需求、截图、行为证据的映射 |
| [08 Codex 交接指令](08_CODEX_HANDOFF.md) | 可直接复制给 Codex 的执行要求 |
| [09 GitHub 复核手册](09_REVIEWER_PLAYBOOK.md) | 完成后如何按最新分支复核、判定返工 |
| [设计册](design/index.html) | 离线打开：四阶段、12 个静态界面例稿，无需安装依赖 |
| [实施状态模板](templates/STATUS.template.md) | 不把开发完成、截图完成、实机通过混成一种状态 |
| [证据清单模板](templates/manifest.template.json) | 48 个场景已预置，默认未运行 |
| [证据校验器](scripts/validate_evidence.py) | 检查覆盖、文件、哈希、来源类型与阶段门槛，不替代人审 |

## 四个阶段与门槛

| 阶段 | 主目标 | 完成判定 |
|---|---|---|
| S1 | 核心流程可理解且执行安全 | 12 场景；真实运行 App + SSH 路径、行为日志与手机模拟器画面 |
| S2 | 输入、阅读、布局不中断 | 12 场景；响应式测试、真实系统键盘操作、iPad 适配 |
| S3 | 视觉与状态语言统一 | 10 场景；同环境基线对比、tokens、语义及桌面回归 |
| S4 | 在实机上证明产品体验 | 14 场景；真实 iPhone + iPad + macOS、原始截图/录屏、性能与完整验证 |

阶段编号 `S1…S4` 与问题严重度 `P0/P1/P2` 是不同概念。任一阶段发现执行安全类 P0，优先修复，不等到 S4。

## 放入仓库的位置

将本目录内容放入 `docs/product/mobile-block-ai-v1/`。文档之间均使用相对链接。
设计册留在 `design/`；**真实证据只能进入 `evidence/`**。不要覆盖既有 `docs/composer/` 或 `docs/ai/` 历史记录；需要纠正文档时保留日期与明确的替代关系。

阶段结果落入 `results/S1.md` 至 `results/S4.md`，总状态放入 `STATUS.md`，最终证据清单为 `evidence/manifest.json`。后续评审以这些文件和当次最新 commit 为入口。

## 交付原则

实现复用已有 runtime；可见主动作明确说明“执行命令 / 发送给 AI / 审阅命令”。采用候选、放入草稿、关闭页面、查看输出均不隐式执行。手机固定字号，不把动态文字放大列为手机验收；iPad 和 macOS 的文字缩放按现有项目约束继续验证。

## v1.1 执行补充

在原四阶段范围基础上，补充 [10 逐帧截图清单](10_SCREENSHOT_SHOTLIST.md)、[11 交互/控制合同](11_INTERACTION_CONTRACT.md) 和 [12 Codex 工作包](12_IMPLEMENTATION_PACKAGES.md)，并加入截图覆盖/文档嵌图校验器。保持 49 条需求与 48 个验收场景，不借版本更新增加产品领域。

设计参考沿用 V1.0 的 12 屏/4 张设计板，不修改它们为“新截图”，也不把它们当产品证据。所有实施状态仍为 not_run；本次仅交付文档、设计参考与文档工具。
