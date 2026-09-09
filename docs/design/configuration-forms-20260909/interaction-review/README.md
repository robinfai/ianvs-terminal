# 配置表单交互复核（2026-09-09）

根据用户提供的两张截图，修正快捷键筛选区拥挤、下拉菜单与输入框风格脱节，并检查全局设置、Profile 和 SSH 配置中的同类问题。本轮沿用上一轮 macOS 字体规范；通过调整布局和组件解决问题，没有继续缩小字号。

## 1. 打开快捷键设置与筛选：已修正

原界面在约 800×600 的逻辑窗口中，把搜索、分类、恢复按钮分成三行；搜索与分类之间仅有很小的空隙，浮动标签贴近边框。恢复按钮独占一行，也挤占列表空间。

- 内容宽度至少 480、文字缩放不超过 1.3 倍时，搜索、分类、恢复按钮同排，控件底部对齐，间隔 12。
- 窄宽或大字号时，搜索独占首行，分类与恢复按钮共用第二行。
- 搜索改为框内提示，保留语义标签；分类使用外置标签。
- 筛选区与列表间隔增至 16，保留列表的独立滚动区域。

证据：[用户截图](before/01-shortcut-toolbar.png)、[浅色调整后](after/shortcuts-light.png)、[深色调整后](after/shortcuts-dark.png)。530 宽和 520 宽 / 2 倍文字的布局由 widget 测试验证。

## 2. 展开、选择与关闭菜单：已修正

原 Material 下拉路由使用与紧凑桌面表单不同的尺寸，整块弹出列表过宽、行距过大，选中底色与阴影也不一致。

- 共享下拉组件改为锚定菜单，弹层与输入框等宽，向可用窗口区域展开。
- 字号、背景、边框和圆角继承项目主题；选中项显示勾选标记。
- 桌面单行菜单以 32 为最小行高，触控以 48 为基准；多行描述和放大文字可以撑高菜单项。
- 保留空值选项、禁用选项、自定义选中内容、外部更新与表单重置。
- 验证 Tab 聚焦、方向键 / Enter 选择、Esc 关闭并返回输入框焦点；菜单最大高度受窗口约束。
- 排查并修正空值禁用字段提示重复的问题。

证据：[用户截图](before/02-category-menu.png)、[浅色菜单](after/category-menu-light.png)、[深色菜单](after/category-menu-dark.png)、[含说明的 Profile 菜单](after/profile-menu.png)。尺寸、长内容、缩放、窗口边界和键盘行为有独立测试。

32、48、12、16 等为本项目组件布局数值，单位为逻辑尺寸；不代表 Apple 对所有控件的强制要求。

## 3. 检查其他配置表单和状态：已修正发现的问题

| 问题类型 | 发现与调整 | 证据 |
| --- | --- | --- |
| 局部尺寸覆盖 | Profile 终端仿真和光标下拉仍固定 48 行高；移除覆盖，继承共享菜单规则 | 共享组件与 Profile 回归测试 |
| 标签与帮助文字混用 | SSH 高级字段、数据同步凭据、快捷键录入条件仍混用浮动标签；统一为外置标签，帮助文字放在对应字段下方 | [SSH 高级选项](after/ssh-advanced.png)、[远程服务](after/data-remote.png) |
| 相邻输入过密 | 数据同步 URL、用户名、密码之间的间距从 6 调整为 12 | [远程服务](after/data-remote.png) |
| 暗色阴影错误 | 配置弹层阴影使用了文字颜色，暗色下出现白色光晕；改用 ColorScheme.shadow | [深色菜单](after/category-menu-dark.png) |
| 大字号与滚动 | 外置标签在窄宽下上下排列；保留高级选项滚动、错误展开与定位、固定操作底栏 | [520×900、1.5 倍文字](after/ssh-advanced-compact.png)、SSH 行为测试 |

本轮发现的问题已修正。没有把这次配置界面复核扩展为整个应用的完整可访问性审核。

## 验证与边界

- `dart analyze lib test`：无问题。
- 截图生成和共享下拉交互测试：31 项通过；其中 25 个截图测试生成 27 张真实 Flutter 渲染截图，另有 6 项共享下拉行为测试。
- 广泛回归：190 个测试文件，1783 项全部通过，包含上述截图基线与配置交互测试。
- 回归排除性能基准 `cat_log_benchmark_test.dart`、既有非配置界面基线失配的 `app_surface_visual_capture_test.dart`，以及上一轮已独立通过的终端事件架构检查。本轮未改动这些实现，也未更新非配置界面基线。
- `git diff --check` 通过。

证据使用真实 Flutter widget 渲染与交互，不是根据设计稿绘制的实现示意图。截图加载 macOS SF 字体及中文后备字体；共享截图 binding 开启真实模糊阴影。用户原截图为 Retina 2 倍图，新快捷键截图为 800×600、1 倍像素密度，比较时应按逻辑尺寸对齐。其他截图尺寸由各自测试定义。

原生窗口自动化工具本次未能在合理时间内提供可用交互，因此未完成运行中 macOS 应用的人工式验收，也没有进行 VoiceOver 实测。测试中的示例地址与凭据不写入用户运行中的配置。

## 产物与复核

- [Imagegen 差异标注](annotations.png)、[完整提示词](prompts.md)。标注图可能重绘局部文字和比例；原始 `before/`、`after/` 截图是复核依据。
- `after/` 包含 8 张补充截图；父目录 `final/` 的 19 张配置截图已同步到当前实现。
- 原始 Imagegen 输出保留于 `/Users/robinfai/.codex/generated_images/01a07ba4-bb0e-75b1-9fde-b679193ddd16/exec-a9bb56bd-da0b-47ba-8a75-15bf165d3d0d.png`。

在 `example/` 下使用项目 Flutter SDK 运行：

```sh
flutter test --no-pub test/ui/app_dropdown_form_field_test.dart test/config/shortcut_editor_test.dart test/ssh/new_session_launcher_test.dart test/data/configuration/data_api_settings_test.dart
flutter test --no-pub test/design/settings_tab_visual_capture_test.dart test/design/profile_tab_visual_capture_test.dart test/design/ssh_editor_visual_capture_test.dart
```
