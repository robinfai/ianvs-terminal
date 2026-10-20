# 15 · 来源与设计决策

检索日期：2026-10-08。仓库链接冻结到编写commit；官方规范是工程参考，不能代替本项目实际测试。

|来源|用途|
|---|---|
|[repo-head](https://github.com/robinfai/ianvs-terminal/commit/763dc166bb1e56d6d50ed3379b57f366c9ca06b7)|冻结编写基线；实施需重新fetch|
|[agents](https://github.com/robinfai/ianvs-terminal/blob/763dc166bb1e56d6d50ed3379b57f366c9ca06b7/AGENTS.md)|项目内平台、字体与主题约束|
|[scope](https://github.com/robinfai/ianvs-terminal/blob/763dc166bb1e56d6d50ed3379b57f366c9ca06b7/docs/TERMINAL_PRODUCT_SCOPE.md)|产品与持久化边界|
|[lane](https://github.com/robinfai/ianvs-terminal/blob/763dc166bb1e56d6d50ed3379b57f366c9ca06b7/docs/CURRENT_EXECUTION_TARGET.md)|原生合同、多pane与桌面平台声明|
|[composer](https://github.com/robinfai/ianvs-terminal/blob/763dc166bb1e56d6d50ed3379b57f366c9ca06b7/docs/composer/COMPOSER_REDESIGN.md)|已选方案1和三层Dock；历史验收不是本轮验收|
|[blocks](https://github.com/robinfai/ianvs-terminal/blob/763dc166bb1e56d6d50ed3379b57f366c9ca06b7/docs/command-blocks/WARP_COMMAND_BLOCKS_RESEARCH.md)|桌面H/3、真实输出、搜索/过滤及回退边界|
|[acp](https://github.com/robinfai/ianvs-terminal/blob/763dc166bb1e56d6d50ed3379b57f366c9ca06b7/docs/ai/ACP_BACKEND.md)|桌面API/本地ACP及工具/权限/恢复边界|
|[make](https://github.com/robinfai/ianvs-terminal/blob/763dc166bb1e56d6d50ed3379b57f366c9ca06b7/Makefile)|当前测试/构建入口|
|[apple-keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards)|系统快捷键与Full Keyboard Access参考；不据此覆盖终端控制键|
|[apple-windows](https://developer.apple.com/design/human-interface-guidelines/windows)|原生窗口控制、尺寸与key window语义参考|
|[flutter-focus](https://docs.flutter.dev/ui/interactivity/focus)|FocusNode生命周期、事件作用域；落地仍须实际输入验证|
|[flutter-performance](https://docs.flutter.dev/perf/ui-performance)|profile/原生性能测量方法；本包目标值是提案而非官方承诺|

## 本轮决策

保留既有桌面外壳与方案1，不新选品牌方向；默认任务在当前pane呈现，证据检查器是按需附件视图，不是新增永久侧栏。维持桌面Block H/3规则；维护手机固定字号与六行规则的独立性。macOS为强制主验收，Linux/Windows不能沿用macOS结果。

后续发来的最新GitHub分支若变更这些前提，先建立基线差异；保留有效最新代码，不因本包日期较早而reset。需求冲突明确写DECISIONS，不静默采用任何一份旧文档。

## 事实与建议的边界

源码/文档描述是本轮读到的状态，并非现场缺陷复现；所有几何尺寸、性能阈值、按需检查器和新情境入口均为本轮PRD方案要求。例图是静态规格图，输出由可公开fixture构造。没有将任何图称为真实App截图。
