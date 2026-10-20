# Trail / ianvs-terminal · 桌面端 Block × AI PRD

> 2026-10-10 修订：与本文有关的敏感性、补充要求、收起/Esc、人工编辑保存和未知结果出口，统一以 [v1.1 交互修订](16_REVISION_1_1.md) 为准。原有 64 项需求及全部原生验收门槛保留。


**版本 1.1 · 2026-10-10 · macOS 主验收 / Linux、Windows 独立能力与证据矩阵**
**编写基线：`composer@763dc166bb1e56d6d50ed3379b57f366c9ca06b7`**

本包专门面向桌面端，不是将手机界面放大。核心为单层窗口栏、底部状态栏、pane-local 三层 Composer、真实 Command Block、键鼠效率、多会话/分屏与 API / 本地 ACP 工作流。保留已有终端架构，优化产品行为与视觉，不开发第二套 PTY、项目容器或 Agent 引擎。

> 本包是需求、静态设计与未来验收计划。全部产品用例初始 `not_run`。HTML / PNG 示例不是实际 Flutter App 截图，不是产品验收证据；来源包没有构建或运行产品。`PACK_QA.md`、离线 reader.html 和 design/ 保留来源 v1.0 的历史说明；当前实施与验证以 STATUS.md 和 results/ 为准。

## 内容与阅读顺序

|文件|用途|
|---|---|
|[00 范围与基线](00_SCOPE_AND_BASELINE.md)|已核验事实、桌面/移动差异、保留合同与平台范围|
|[D1 桌面工作流](01_STAGE_1_DESKTOP_WORKFLOW.md)|失败块→AI→完整审阅→真实结果；API/ACP、只读与接管|
|[D2 输入与多窗格](02_STAGE_2_INPUT_AND_PANES.md)|键位优先级、IME、补全、滚动、分屏、窗口焦点/DPI|
|[D3 视觉系统](03_STAGE_3_VISUAL_SYSTEM.md)|tokens、三层Dock、状态、字体、深浅色、无障碍|
|[D4 原生验收](04_STAGE_4_NATIVE_ACCEPTANCE.md)|真实PTY/SSH/API/ACP、物理输入、性能、构建/回滚|
|[05 示例设计稿](05_DESIGN_REFERENCE.md)|16 张 16:9 桌面状态例稿及逐屏说明|
|[06 证据合同](06_EVIDENCE_CONTRACT.md)|原图/录屏/日志、commit、哈希与结果文档|
|[07 验收矩阵](07_ACCEPTANCE_MATRIX.md)|64 个 Given/When/Then 场景|
|[08 Codex 交接](08_CODEX_HANDOFF.md)|完整执行约束及启动提示词|
|[09 复核手册](09_REVIEWER_PLAYBOOK.md)|完成后依据最新 GitHub HEAD 独立复核|
|[10 截图检查点](10_SCREENSHOT_SHOTLIST.md)|159 个需要证明的可见状态|
|[11 交互合同](11_INTERACTION_CONTRACT.md)|焦点、只读、回执、版本与异步状态规则|
|[12 实施工作包](12_IMPLEMENTATION_PACKAGES.md)|16 个可独立提交的实施切片|
|[13 桌面平台矩阵](13_DESKTOP_PLATFORM_MATRIX.md)|macOS 主门槛、Linux/Windows 原生宿主门槛|
|[14 键盘与布局规范](14_KEYBOARD_AND_LAYOUT.md)|作用域键位表、几何公式、滚动手势合同|
|[15 来源](15_SOURCES_AND_DECISIONS.md)|不可变源码链接、官方规范、已知限制|

共 **64 条需求 / 64 个验收场景 / 159 个截图检查点 / 16 张桌面示例稿 / 16 个工作包**。场景数不是测试断言上限；每项中包含的负向与边界子场景不能省略。

## 放入仓库

将目录内容放入 `docs/product/desktop-block-ai-v1/`。桌面采用 `D1…D4` 编号，与移动包 `S1…S4` 独立，避免证据冲突。不要覆盖移动 PRD、旧 Composer 审计或历史评测记录；共享组件要求冲突记录在 `results/DECISIONS.md`。

## 四阶段门槛

D1 是桌面核心流程；D2 是键鼠和多窗格；D3 是视觉和无障碍；D4 是真实桌面发布候选验证。每阶段 16 个场景，均需实际原生桌面 App 截图；组件图补充而不能替代。D4 另要求物理键盘/触摸板、真实模型/API/ACP和真实显示环境。缺失设备或后端时继续可做工作，但状态为 `implemented_unverified` / `blocked`。

[打开离线阅读版](reader.html) · [打开静态设计册](design/index.html)

## 执行说明

先看最新 HEAD 和 `AGENTS.md`，创建 `results/BASELINE.md`，再实施。最新代码若已满足某项，则保留实现并补测试/证据，不重复重构。完成后以 `STATUS.md`、`results/FINAL_REVIEW.md`、`evidence/manifest.json`、源码与证据 commits 为评审入口。
