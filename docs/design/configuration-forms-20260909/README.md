# 配置表单布局与视觉调整（2026-09-09）

覆盖全局设置、Profile 编辑器和 SSH 配置。设计稿由内置 imagegen 生成；实现沿用 Flutter 控件与项目主题 token。目标稿和差异标注只用于设计复核，真实界面以 `final/` 中的 Flutter 渲染截图为准。

最新一轮根据用户截图完成了[间距与下拉菜单交互复核](interaction-review/README.md)：快捷键筛选区响应式同排、弹出菜单匹配原控件、统一其他表单标签，并修正暗色阴影。190 个测试文件、1783 项回归全部通过；详细证据与排除范围见该记录。

## 设计取舍

- 依据 [macOS HIG 复核](macos-hig-review.md) 修订第一版目标稿：正文 13/16，标题 17/22，说明 12/15，沿用系统字体。截图使用 SF 与中文后备字体。
- 全局设置与 Profile 最大 940×700，侧栏 190；SSH 最大 720×700。
- macOS 表单采用 20 内容边距、120 标签列 + 12 列间隔，常规控件基准 28；触控平台基准 48。控件允许随文字放大，窄宽或文字放大时改为上下排列。边距、列宽和窗口大小属于项目选择，并非 Apple 的强制尺寸。
- 统一中性输入底色、6px 控件圆角、细分隔线和浅蓝选中状态，移除 Profile 内层分组卡片。
- Profile 外观按字体 → 光标 → 配色排列。备用字体与自定义颜色默认折叠；非法内容保存时自动展开、切换分区并定位错误。
- 常规设置的默认 Profile 和语言改为紧凑下拉框。菜单保留 SSH 地址信息，失效默认 Profile 回退到自动选择并可保存修复。
- SSH 主机独占一行；用户与端口同行；密码显隐、清除与私钥选择集中在字段尾部。底栏保存选项和按钮保持可操作。

## 差异闭环

| Imagegen 标注 | 实现调整 |
| --- | --- |
| Profile 容器偏窄 | 修正宽度计算；HIG 复核后根据字号和内容密度收为 940 |
| 输入框灰底且过高 | 删除局部主题覆盖，继承统一配置主题 |
| 字号与行高不在同一网格 | 并排紧凑输入，显示 px / × 单位 |
| 分组留白导致配色被挤出首屏 | 收紧分组、折叠项和底栏，首屏可见常用配色及自定义入口 |
| 光标开关偏右 | 移到控件列起点 |
| 页脚提示过长 | 精简为“更改仅应用于新会话” |
| SSH 用户与端口脱离网格 | 统一输入列并内联端口 |
| SSH 底栏不清晰 | 复选框靠左、增加分隔线，按钮在大字号时换行 |
| 第一版整体偏松、字体偏大 | 依照 macOS 字体样式下调字号，收紧控件、边距、侧栏和页眉 |
| SSH 单行输入高度不一致 | 统一带图标、密码显隐和私钥选择的实际高度，并验证错误和放大文字状态 |

有意保留的差异：字体继续使用自由输入，未虚构系统字体目录；SSH 继续显示私钥口令；参数与环境变量继续使用现有的增删、排序交互。配色条展示真实解析后的 ANSI 0–7 色，不是整个终端的实时预览。

## 产物

- `before/`：调整前实截图。
- `targets/`：4 张 imagegen 目标稿。
- `iteration-1/`、`iteration-2/`：实现过程截图；`iteration-3/` 为 HIG 复核前版本。
- `hig-review/`：第一轮 HIG 调整后的实截图，保留为历史记录。
- `annotations/appearance-iteration-1.png`：Profile 外观差异标注。
- `annotations/ssh-iteration-1.png`：SSH 差异标注。
- `annotations/macos-hig-alignment.png`：macOS 字号、控件和间距的前后标注。
- `final/`：最终实截图（全局设置 7、Profile 9、SSH 3）。
- `interaction-review/`：用户反馈截图、8 张交互补充实截图、最新 Imagegen 差异标注与复核记录。
- [prompts.md](prompts.md)：完整提示词，全部使用内置 imagegen，没有 CLI/API 回退。
- [字段预览](../../../example/lib/ui/previews/configuration_fields_preview.dart)：浅色、深色与 390 宽 / 1.5 倍文字的独立 widget preview。

标注图由图像模型生成，可能重绘局部文字或控件，不能代替原始截图的像素比较。历史迭代使用 Flutter widget 测试默认的硬阴影；当前 `final/` 与 `interaction-review/after/` 通过共享截图 binding 开启真实模糊阴影，并据此修正了暗色模式的白色光晕。

## 第一轮 HIG 验证记录

以下保留第一轮执行结果；最新交互修正的验证结果见[交互复核记录](interaction-review/README.md#验证与边界)。

- 静态分析：`dart analyze lib test`，无问题。
- 最终截图生成与 SSH 表单测试：46 项通过，其中 19 张截图、27 项 SSH 表单行为测试。随后使用正式截图测试验证已更新的基线。
- 应用广泛回归：189 个测试文件，共 1770 项；1769 项通过。唯一失败在既有 `session_recording_lifecycle_test.dart` 的临时目录删除阶段，抛出 `PathNotFoundException`；该文件单独复跑 33 项全部通过。本轮没有修改录制业务或测试代码，不能把首次运行记录为全绿。
- 终端事件架构检查单独运行，2 项通过。首次默认 30 秒超时；以 `--timeout 2m` 重跑原断言，耗时 51 秒通过。
- 广泛回归未包含 `cat_log_benchmark_test.dart` 性能基准，也未更新 `app_surface_visual_capture_test.dart` 中既有的桌面 Shell、命令面板和 Profile 列表三张失配基线；这些不属于配置表单。架构检查按上一条独立执行。
- 界面检查覆盖浅色 / 深色、窄宽、文字放大、软键盘、滚动、错误展开与定位、未保存退出提醒、密码显隐与凭据清除、参数增删排序、默认 Profile 回退及保存。独立 widget preview 已添加并通过静态分析，未另行进行交互式 preview 验收。
- `git diff --check` 通过。

在 `example/` 下复核截图时，先令 `FLUTTER_ROOT` 指向本机 Flutter SDK 根目录，再运行：

```sh
flutter test --no-pub test/design/profile_tab_visual_capture_test.dart test/design/settings_tab_visual_capture_test.dart test/design/ssh_editor_visual_capture_test.dart
flutter test --no-pub test/profiles/profile_editor_test.dart test/shell/defaults_appearance_redesign_test.dart test/ssh/new_session_launcher_test.dart
flutter test --no-pub --timeout 2m test/sessions/terminal_event_subscription_architecture_test.dart
```

截图依赖 macOS 系统字体；更新基线前应先检查实截图，再使用 `--update-goldens`。
