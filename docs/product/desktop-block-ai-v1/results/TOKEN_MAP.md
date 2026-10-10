# D3-R01 / D3-R02 · 生产主题映射与色对计算

截至 2026-10-10，本表完成生产主题盘点、四种模式的计算，以及三项实测缺陷的局部修复。它是 `D3-T01/T02` 的源码和自动回归证据，**不是这两个场景已完成原生验收的声明**。完整 App 原图、实际 ANSI/OSC/选区与用户终端配色仍须补验。

计算起点是 `composer` 分支 HEAD `79db5115d1e6c69ac62116f19fdfb2b102724df5` 加本轮工作区变更；不是新的冻结候选。运行环境为 macOS 27.0.1（26A434）、Flutter 3.44.8、Dart 3.12.2（macos_arm64），`ThemeData.platform = macOS`。未把 Flutter 测试字体、历史 C1/C3 或手机图片作为本轮桌面设备证据。

## 1. 单一来源与沿用范围

应用入口 [app.dart](../../../../example/lib/app.dart#L42) 分别设置浅色、深色、高对比浅色与高对比深色。生产构建器 [buildIanvsTerminalTheme](../../../../example/lib/ui/foundation/app_theme.dart#L12) 沿用已安装的 `ianvs_design 0.4.0`；`AppThemeTokens` 是共享 `IanvsTokens` 的业务命名适配，不能把 `AppThemeTokens.light/dark` 中未参与覆盖的旧常量当成最终生产调色板。

|语义|实际来源及映射|沿用 / 本轮变化|消费组件|
|---|---|---|---|
|surface|`IanvsTokens.canvas/chrome/field/raised` → `AppThemeTokens.canvas/chrome/panel/panelElevated` 与对应 `ColorScheme.surface*`；`ComposerTheme.surface/popover/contextSurface` 从同一 `ColorScheme` 派生|沿用，无第二套主题管理|外壳、Block、Dock、审阅、Chip、底栏、Reader|
|text|共享 `text/muted/subtle` → `AppThemeTokens.text*` 与 `TextTheme`；Composer 在宿主 `onSurface/onSurfaceVariant` 上混入少量 `primary`，不是另定品牌蓝|沿用；高对比增强次级文字|正文、状态、路径、来源范围、命令与代码|
|border|共享 `separator/border` → `AppThemeTokens.border/borderStrong`；Composer 的 `border/divider` 派生自 `outlineVariant`；高对比使用 `outline`，必要时回退可读前景|沿用|轻分隔、Dock、提案边界、Reader、Chip|
|action|`ColorScheme.primary/onPrimary` 为填充动作色对；TextButton 沿用共享设计的可读 actionColor|默认填充/文字不变；新增 `ComposerTheme.primaryActionOverlay`，应用 FilledButton 与 Dock 共同消费|执行、采用、发送给 AI、执行一次、审阅|
|status|`danger/warning/success` 及对应容器；失败 Block 使用 `ComposerTheme.error` 图标/文字，普通状态用 `muted`；未知不由颜色自动判定|沿用；本轮没有新增状态品牌色|Block 退出状态、Dock unknown、AI 审核说明、底栏事实|
|focus / small mark|宿主 `design.focus`、应用 input/button 的 focus 样式；Composer focus 沿用宿主 primary 与高对比校验|修正应用 Composer 的 `accent` 映射到已有 `design.focus`，使选中 Block 上书签和输出光标有可读前景；无新色值|书签、终端光标、输入框、按钮、候选|
|selection|应用 `selected` / `ColorScheme.primaryContainer`；Composer 为 `primaryContainer` 在 surface 上 55% 合成；选中 Block 再将 Composer selection 以 28% 合成|沿用，区别候选选中与整个 Block 选中；不改终端用户选区覆盖|候选、Block、终端选区|
|typography|UI 为共享系统字体；代码用 `IanvsTypography.code`；Dock/Block/Reader 使用 `ComposerTheme.commandStyle/resultStyle` 与终端原有等宽回退链|沿用，未缩小字号解决布局；无新字体文件|所有受影响组件|
|icons / metrics / motion|`ComposerIcons` 沿用 Material vector glyph；共享 spacing、radius、control metrics；Composer 120ms 状态时长与已有减少动画路径|沿用；`readerTopInset = 44` 是现有 macOS chrome 几何值，不是视觉 padding 猜值|动作、状态、Reader、安全区|

关键实现：[共享适配](../../../../example/lib/ui/foundation/app_theme.dart#L32)、[高对比](../../../../example/lib/ui/foundation/app_high_contrast.dart#L5)、[Composer 派生](../../../../packages/ianvs_terminal/lib/src/composer/composer_theme.dart#L58)、[新增状态层角色](../../../../packages/ianvs_terminal/lib/src/composer/composer_theme.dart#L134)、[应用与 Dock 共用](../../../../example/lib/ui/foundation/app_theme.dart#L113)、[Dock 消费](../../../../packages/ianvs_terminal/lib/src/composer/terminal_composer_view.dart#L1137)、[图标族](../../../../packages/ianvs_terminal/lib/src/composer/composer_icons.dart#L10)。

`primaryActionOverlay` 是可选扩展字段，旧宿主自定义构造可继续省略；默认保留 Material 以前景色构造状态层的方式。只有 10% 状态层使按钮文字低于 4.5:1 时，才选择远离文字亮度的黑/白中性层；状态透明度仍交给 `FilledButton.styleFrom`。黑/白在中央 token 工厂里有这个明确用途，没有散落到生产 Widget 或新增固定品牌色。

## 2. 四种模式的实际值

以下为生产 factory 导出值，列顺序固定为浅色、浅色高对比、深色、深色高对比。无透明度时写 `#RRGGBB`；JSON 保留 `#AARRGGBB` 及参与计算的实际 `Color` 数值。下列颜色只描述当前默认应用主题，不覆盖任意用户 ANSI palette。

|AppThemeTokens 角色|浅色|浅色高对比|深色|深色高对比|
|---|---|---|---|---|
|canvas|#FAFAFB|#FAFAFB|#202123|#202123|
|chrome|#F3F3F5|#F3F3F5|#1E1F21|#1E1F21|
|panel|#FFFFFF|#FFFFFF|#292B2E|#292B2E|
|panelElevated / overlay|#FFFFFF|#FFFFFF|#303236|#303236|
|border|#DEDFE4|#60646C|#37393E|#B9BCC4|
|borderStrong|#B9BCC3|#60646C|#45474D|#B9BCC4|
|textPrimary|#24262A|#24262A|#F3F4F6|#F3F4F6|
|textMuted|#60646C|#24262A|#B9BCC4|#F3F4F6|
|textSubtle|#676D76|#24262A|#A8ADB7|#F3F4F6|
|accent|#0969DA|#0969DA|#0874DF|#0874DF|
|focus / focusRing|#0969DA|#0969DA|#39A6FF|#39A6FF|
|selected|#DEEBFA|#DEEBFA|#213D56|#213D56|
|danger|#B52C2A|#B52C2A|#FF8F8B|#FF8F8B|
|warning|#895700|#895700|#FFC250|#FFC250|
|success|#187047|#187047|#75D3A7|#75D3A7|

`ColorScheme.surfaceContainerLowest/panel`、`onSurface/textPrimary`、`onSurfaceVariant/textMuted`、`outline/borderStrong`、`outlineVariant/border` 是上述同源映射。高对比更改文本/边界与宽度，不更改字号或填充主色。终端 viewport 的 canvas/foreground 由 `ColorScheme` 桥接，并不直接使用遗留 `terminalSurface`。

|ComposerTheme 角色|浅色|浅色高对比|深色|深色高对比|
|---|---|---|---|---|
|surface / popover|#FFFFFF|#FFFFFF|#292B2E|#292B2E|
|foreground|#1E3551|#1E3551|#BFD8F1|#BFD8F1|
|muted|#52657E|#1E3551|#9DB0C8|#BFD8F1|
|border / divider|#D3D9E3|#60646C|#353C46|#B9BCC4|
|accent（本轮修正）|#0969DA|#0969DA|#39A6FF|#39A6FF|
|focus|#0969DA|#0969DA|#0874DF|#0874DF|
|selection|#EDF4FC|#EDF4FC|#253544|#253544|
|onSelection|#0753A5|#0753A5|#8DCEFF|#8DCEFF|
|hover|#F4F4F4|#E9E9EA|#333538|#3D3F42|
|primaryAction / onPrimaryAction|#0969DA / #FFFFFF|#0969DA / #FFFFFF|#0874DF / #FFFFFF|#0874DF / #FFFFFF|
|primaryActionOverlay（新增）|#000000|#000000|#000000|#000000|
|errorSurface / onError|#F2E1E2 / #B52C2A|#F2E1E2 / #B52C2A|#3B2E2F / #FF8F8B|#3B2E2F / #FF8F8B|
|disabledForeground|#97A2B1|#1E3551|#6E7B8B|#BFD8F1|
|disabledSurface|#F0F6FD|#F0F6FD|#272F39|#272F39|

Mac UI `bodyMedium = 13`、`bodySmall = 12`、`labelSmall = 11`；Composer command 16/1.5、result 14/1.4、context 12/1.35、metadata 11/1.4，command/result 为 monospace + 既有平台回退。高对比 control height 仍为 32，border 从 1 到 1.5，focus 从 1 到 2，shadow alpha 变为 0。这里只记录 factory 的字体与尺寸，未证明原生字形等宽或 2× 布局。

## 3. 消费者盘点

|组件|消费路径与视觉合同|高对比 / 本轮变化|
|---|---|---|
|Block|[容器与选中](../../../../packages/ianvs_terminal/lib/src/terminal/command_blocks_view.dart#L786) 用 surface、selection、border；标题/元数据/退出状态用 result/context/metadata 与 error/muted；[原生输出](../../../../packages/ianvs_terminal/lib/src/terminal/command_blocks_output.dart#L367) 为 TerminalViewport，未改成 Markdown|高对比加强边界；书签改用宿主可读 accent；失败保留局部图标和文字，没有整块红底|
|三层 Dock / 补全|[Dock](../../../../packages/ianvs_terminal/lib/src/composer/terminal_composer_view.dart#L546) surface/border；[编辑器](../../../../packages/ianvs_terminal/lib/src/composer/composer_editor.dart#L123) 独立文字/光标，取消内外双重边框；[候选](../../../../packages/ianvs_terminal/lib/src/composer/composer_suggestions.dart#L377) 分别用 hover 与 selection/onSelection|新增动作 state-layer token；不改变三层结构、占位高度或键位。高对比候选有额外选中标记|
|AI 正文 / 审阅|[正文](../../../../example/lib/features/ai/terminal_ai_message.dart#L97) 用 TextTheme、共享 code 与中性 chrome；[提案](../../../../example/lib/features/ai/terminal_ai_workspace.dart#L821) 用文字状态及局部边界；[审阅面板](../../../../example/lib/features/ai/terminal_ai_workspace.dart#L1219) 用 panel 和已有 Material 按钮|沿用；主动作状态层跟随同一个 token。提案与真实输出仍是不同控件/语义|
|来源 Chip|[InputChip](../../../../example/lib/features/ai/terminal_ai_workspace.dart#L546) 由 ChipTheme 管背景、标签、图标和边界；命令/行范围/截断标签独立|高对比 side 和小字增强；无新增颜色，删除区域与跳转不依赖色差|
|桌面底栏|[DesktopSessionStatus](../../../../example/lib/features/shell/widgets/desktop_session_status.dart#L117) 用 chrome、border、bodySmall、IconTheme；完整详情在语义/Tooltip 中|沿用。未知回执可与断连/ready 并存，不用绿色表示“可执行”|
|Reader|[宿主](../../../../packages/ianvs_terminal/lib/src/terminal/command_block_reader.dart#L237) 与 Reader 使用 surface、foreground/muted/error/divider；输出继续复用 TerminalViewport|沿用；几何安全区与状态颜色分开；不产生独立 Reader palette|
|原生终端 scrollbar|[颜色桥接](../../../../example/lib/ui/foundation/app_terminal_colors.dart#L17) 使用 outlineVariant track 与 onSurfaceVariant thumb；[实际绘制](../../../../packages/ianvs_terminal/lib/src/terminal/terminal_viewport.dart#L5062) 是两层透明合成|thumb alpha 从 .62 到 .75；cursor/selection 用户覆盖不变|

对以上受影响 Widget 搜索未发现新增 `Color(0x...)` 或固定品牌 `Colors.blue/red/...`。`Colors.transparent` 是去除编辑背景/占位绘制的技术用途。既有终端搜索 palette 的例外见第 6 节；不能把“受影响 Widget 无新硬编码”扩写成全仓库无硬编码色值。

## 4. 计算与回归结果

一次性导出器直接调用 `buildIanvsTerminalTheme`，在匹配的 `MediaQuery.highContrast` 下解析 `ComposerTheme.of` 和 `resolveTerminalColors`。对比算法导入已有 [composer_theme_test.dart:7](../../../../packages/ianvs_terminal/test/composer/composer_theme_test.dart#L7) 的 `contrast()`，透明色先用 Flutter `Color.alphaBlend` 按生产消费顺序合成。按钮状态额外读取真实 `TerminalComposerView` 生成的 `FilledButton.style`，没有重写主题工厂或从截图取色。

最终导出 4 模式 × 69 组合 = **276 色对**：其中 **242 个列为本次目标的文字/必要控件/焦点组合全部达到阈值**；另外 34 个为装饰边界、disabled 或 renderer 输入诊断，没有混入通过计数。普通文字目标 4.5:1，必要非文字控件/焦点 3:1；判断使用未四舍五入的 double。此表显示六位小数，JSON 保留完整精度。

|实际组合（修后）|浅色|浅色高对比|深色|深色高对比|
|---|---:|---:|---:|---:|
|主文字 / panel|15.154879|15.154879|12.899454|12.899454|
|底栏 bodySmall / chrome|5.357908|13.675250|8.681748|14.987890|
|AI 审阅说明 / panel|5.937621|15.154879|7.472019|12.899454|
|来源 Chip 行范围 / 背景|5.937621|15.154879|7.472019|12.899454|
|Dock command / surface|12.515828|12.515828|9.665799|9.665799|
|Dock context / surface|5.978802|12.515828|6.430172|9.665799|
|候选 metadata / selection|5.393689|11.290972|5.702395|8.571808|
|失败文字 / selected Block|6.077190|6.077190|6.258973|6.258973|
|错误提示文字 / errorSurface|4.961580|4.961580|5.896481|5.896481|
|主按钮 default|5.192061|5.192061|4.591144|4.591144|
|主按钮 hovered|5.908196|5.908196|5.256578|5.256578|
|主按钮 focused|6.145690|6.145690|5.478968|5.478968|
|主按钮 pressed|6.145690|6.145690|5.478968|5.478968|
|书签 / selected Block（3:1）|5.046185|5.046185|5.288503|5.288503|
|Composer focus / surface（3:1）|5.192061|5.192061|3.092049|3.092049|
|应用 inputFocus / panel（3:1）|4.000888|4.000888|4.353822|4.353822|
|终端 thumb / track（3:1）|3.245141|5.109366|4.665384|4.400374|

三项修复均先由新增真实组件回归复现。`desktop_action_contrast_test.dart` 修前 **7 fail / 5 pass**；修后其 **12 项通过**。测试从实际 Material / InkWell 状态控制器取按钮的最终前景、背景与状态层，覆盖普通 FilledButton、tonal FilledButton 及生产 Dock；从实际选中 Block 取容器背景和书签图标。滚动条检查生产 bridge 的 track→thumb 叠层，保留已有用户覆盖测试。

|缺陷与触发|修前实测|局部修复|修后实测|
|---|---|---|---|
|浅色主按钮 focus / pressed，白色 10% 状态层冲淡蓝底|白字对合成背景 4.355578015787879:1|新增共用 `primaryActionOverlay`，默认填充/文字不改|6.145689951683987:1|
|深色主按钮 hover / focus / pressed，同高对比|hover 4.061005604119453；focus/pressed 3.911632296111716|同上；Material 仍决定 .08/.10 状态透明度|hover 5.256577564830706；focus/pressed 5.478968429856439|
|深色已选 Block 书签，含高对比|#0874DF 对合成 #282E34 = 2.996576283309443:1，不能舍入为通过|App 的 Composer accent 复用 `design.focus` #39A6FF|5.2885028481061545:1|
|浅色终端出现可拖动 scrollbar，thumb 叠于 track|#9E60646C 叠于 #F4F5F6 = 2.5490696082833555:1|thumb alpha .75，未改 profile cursor/selection|#BF60646C 叠于同 track = 3.2451410664811036:1|

聚焦执行：新增 12 项 + 既有应用主题合同 4 项 + 既有 Composer 主题 8 项 + 一次导出 = **25 passed**。锚点：[按钮状态](../../../../example/test/ui/desktop_action_contrast_test.dart#L28)、[滚动条](../../../../example/test/ui/desktop_action_contrast_test.dart#L96)、[真实 Block](../../../../example/test/ui/desktop_action_contrast_test.dart#L120)、[已有应用合同](../../../../example/test/ui/app_theme_contract_test.dart#L20)、[已有 Composer 合同](../../../../packages/ianvs_terminal/test/composer/composer_theme_test.dart#L14)。全量 gate、镜像同步与冻结候选记录由主任务单独完成，本文件不代替。

4 个生产变更文件与新增回归的定向 analyze 为 **No issues found**，`git diff --check` 通过；文档中的本地链接、行号范围、报告 hash、276/242 计数及主题源码 hash 已核对。另一代理独立只读复评没有发现可执行回归，重点检查了可选扩展参数兼容、copyWith/lerp、tonal/state 继承和滚动条两层透明合成；该复评没有追加设备证据。

## 5. 可复核的本地报告

报告保存在 git 忽略的 `build/desktop-prd-v1/iteration-1/`，一次性导出器按仓库规范位于已排除分析的 `tmp/desktop-prd-v1/iteration-1/`；为本轮工作区计算记录；没有改写 mobile 的历史 manifest，也没有登记为公开设备截图。

|文件|用途 / SHA-256|
|---|---|
|[theme_export_test.dart](../../../../tmp/desktop-prd-v1/iteration-1/theme_export_test.dart)|生产导出工具；`a2122c477101755652e72f950eb1abaae103967017f97537f606ada992e3ab6f`|
|[theme-colors-before.json](../../../../build/desktop-prd-v1/iteration-1/theme-colors-before.json)|修前完整值；`f31bbd6f6f1fbc55e612ba59288d92105b5745a5a987e1ea76d01c9c3a229a20`|
|[theme-colors.json](../../../../build/desktop-prd-v1/iteration-1/theme-colors.json)|修后完整值（UTC 2026-10-10 02:47:54）；含生产/共享库源码 hash、色对、字体、状态层与终端策略；`13725ccedd94fcc740f9c0db15a0a49bebfb526c08f6f27828df1619748d340a`|
|[theme-contrast-before.log](../../../../build/desktop-prd-v1/iteration-1/theme-contrast-before.log)|7 项预期红测；`5753ea6d22b05cfabc0139e35dfacab9db874edcfd8da414b523eb4fadb658d6`|
|[theme-contrast-after.log](../../../../build/desktop-prd-v1/iteration-1/theme-contrast-after.log)|25 项绿测；`bbf1b5d970bba0732497dac1e1717094228feed106c95c4a1a35e00585e1bb6a`|
|[theme-analyze.log](../../../../build/desktop-prd-v1/iteration-1/theme-analyze.log)|4 个生产变更文件与新增回归的定向静态分析|

从仓库根目录使用既有 Flutter SDK 可重算：

```sh
flutter test --no-pub --reporter expanded example/test/ui/desktop_action_contrast_test.dart example/test/ui/app_theme_contract_test.dart packages/ianvs_terminal/test/composer/composer_theme_test.dart tmp/desktop-prd-v1/iteration-1/theme_export_test.dart
```

导出只针对当时源码；重跑会更新 `theme-colors.json`，必须重新记录 hash，不能冒用上表修后身份。

## 6. 不在本次通过计数内的边界

普通模式下 Dock / Block 的轻分隔约 1.23–1.42:1，提案/Chip 装饰边界约 1.53–1.90:1，disabled 文字约 2.37–3.13:1。这些是明确保留的诊断项，未把装饰分隔等同于唯一控件/焦点指示；也未用 disabled 豁免掩盖 enabled 主按钮。高对比对应 Dock 边界为 5.937621 / 7.472019:1。实际 focus、hover、selected 是否始终可区分仍须 `D3-T09` 状态册与键盘操作证据，单看 token 不能证明焦点可见。

ANSI/OSC 与 UI 颜色是不同证据层：

- [原生终端桥接](../../../../example/lib/ui/foundation/app_terminal_colors.dart#L17) 默认文本/背景来自应用主题，`minimumContrastRatio = 4.5`；普通模式保留程序显式前景，高对比关闭该保留；profile 的 cursor/selection 覆盖继续生效。本轮未更改 ANSI palette、profile 配置或用户指定颜色。
- [Block / Reader 输出](../../../../packages/ianvs_terminal/lib/src/terminal/command_blocks_output.dart#L367) 使用 Composer 的 surface、foreground、accent、selection，`minimumContrastRatio = 4.5`，仍交给真实 TerminalViewport。per-cell inverse、dim、显式背景以及 selection foreground 的处理在 [render_terminal_viewport.dart](../../../../packages/ianvs_terminal/lib/src/terminal/render_terminal_viewport.dart#L1389)，本表不复制该逻辑也不代替实际输出。
- 既有 [TerminalSearchHighlightStyle](../../../../packages/ianvs_terminal/lib/src/terminal/terminal_viewport_colors.dart#L3) 默认 active/inactive 为固定蓝/琥珀，未由本轮 token 新增。active border 对其 fill 的输入级计算是浅色 2.051658 / 深色 2.159520:1；描边跨内外背景、程序背景与搜索状态可见性尚未实际验证，保留为 renderer 诊断，不列为已经满足必要焦点指标。真实 ANSI、搜索、选区与 OSC 链接组合及配置仍须采集。
- 所有文字/色对结论仅对已列默认四模式成立；不声称任意用户主题、第三方宿主、自定义 ThemeExtension、系统 HDR/色彩配置或完整无障碍标准认证。需要在本轮候选 App 中采集浅深/高对比同场景原图、真实 ANSI/OSC/选区、键盘焦点，以及受影响的组件状态册。

## 7. 底栏只读复评

活动 `sessionId` 分别校验 pane / composer 的来源；缺少匹配数据时显示核对中，而不沿用上一 pane 的 ready。`hasUnresolvedSubmission` 与 shell 状态并列，因此断连或 shell 再次 ready 不会把旧未知提交写成成功。底栏不创建 session、不读取终端、不获取写入 owner。

复评发现替代式 Reader 已阻断人工输入时，旧底栏仍会写 Human input。主任务已补 `reader` 监听，并根据 `isOpen / blocksInput` 显示证据阅读器及只读：[底栏](../../../../example/lib/features/shell/widgets/desktop_session_status.dart#L39)、[Shell 注入](../../../../example/lib/features/shell/shell_screen.dart#L1690)。这条路径经源码复核；真实 Shell Reader 状态测试由主任务/负责代理记录，不把本次主题测试充作它的验证。

当前没有需要用户重新选择的主题范围问题。实际桌面原图、ANSI/用户配置、辅助技术和系统主题切换是后续执行验收工作；若要放弃高对比、降低阈值或覆盖用户终端 palette，才会构成新的产品范围决策。
