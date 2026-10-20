# Header tabs refinement

按用户选定的第 1 张设计细化桌面标签栏。保留既有布局、切换、拖动、徽标、菜单和关闭保护。

- 轻浮起选中态、圆角轨道、统一内缩和对齐；深色下保持选中层级。
- `⌘数字` 与关闭按钮共用右侧固定槽位。只按 Cmd 显示提示，松开恢复：当前标签常显关闭，其余标签悬停／键盘焦点时显示关闭。
- 宽度不足仍使用原溢出菜单；520 px 和双倍文字下提示不溢出。

[设计对比与完整验收](design-qa.md) · [浅色](screenshots/light-871.0-default.png) · [深色](screenshots/dark-871.0-default.png) · [窄窗口 Cmd](screenshots/dark-640.0-cmd.png) · [关联回归](https://github.com/robinfai/ianvs-terminal/blob/cbebe0244b554f99084100e9bda465d8f87ac83f/docs/product/header-tabs-2026-10-17/evidence/regressions.log)

本轮不安装手机、不合并；CI 状态以最新 PR Checks 为准。

验证：139 项关联回归、103 项主应用回归、4 组标签专项状态均通过；设计回归 839 通过、1 项原有跳过；macOS 原生融合验收、静态分析和 Release 构建通过。macOS 26 与 27 的六张变更基线分别取自各自系统渲染并审阅，详见验收记录。

历史验收原件保留在[固定提交目录](https://github.com/robinfai/ianvs-terminal/tree/cbebe0244b554f99084100e9bda465d8f87ac83f/docs/product/header-tabs-2026-10-17)。运行日志和临时产物已按文档归档规则移出当前 `docs/`；此处结果仅对应文中记录的构建与环境。
