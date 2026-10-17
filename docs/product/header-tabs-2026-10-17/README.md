# Header tabs refinement

按用户选定的第 1 张设计细化桌面标签栏。保留既有布局、切换、拖动、徽标、菜单和关闭保护。

- 轻浮起选中态、圆角轨道、统一内缩和对齐；深色下保持选中层级。
- `⌘数字` 与关闭按钮共用右侧固定槽位。只按 Cmd 显示提示，松开恢复：当前标签常显关闭，其余标签悬停／键盘焦点时显示关闭。
- 宽度不足仍使用原溢出菜单；520 px 和双倍文字下提示不溢出。

[设计对比与完整验收](design-qa.md) · [浅色](screenshots/light-871.0-default.png) · [深色](screenshots/dark-871.0-default.png) · [窄窗口 Cmd](screenshots/dark-640.0-cmd.png) · [关联回归](evidence/regressions.log)

本轮不安装手机、不合并；CI 状态以最新 PR Checks 为准。
