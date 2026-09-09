# Imagegen prompts

## SSH editor

Use case: ui-mockup. Asset: Trail macOS SSH configuration dialog implementation target.
Image1 is the current SSH form with real fields; Image2 is the design system target for Profile Startup. Redesign SSH in that same neutral restrained native style. Single complete 1100x900 screenshot, center an800x760 dialog,12px radius,white surface,subtle shadow,light-gray surrounding background. NO sidebar for this short task. 14px body22px title38px input6px radius,#007AFF only primary action/focus.
Purpose: enter connection details, choose authentication, save locally and connect. Preserve current logic and fields, do not invent connection tests, server status, synchronization requirements, avatars or icons-as-decoration.
Header72px title "SSH 连接", subtitle "生产环境", close at right.
Main32px padding. Simple open sections with fine dividers, not boxed cards. Left136px label column,20px gap,right controls.
"连接": row "会话名称" input "生产环境"; row "主机" input "prod.example.com"; row with "用户" input "deploy" and "端口" narrow input "22".
"身份验证": row "方式" dropdown "自动（先密钥，后密码）"; row "密码回退" masked blank/password input and reveal icon; row "私钥" field "~/.ssh/id_ed25519" with secondary text action "选择". Compact helper "私钥内容加密保存在本机。" Keep existing clear-secret actions as small accessible trailing icon buttons with trash icon, not extra full-width rows.
Collapsed disclosure "高级选项" with small description "跳板机、转发与连接设置".
Fixed bottom area separated by one divider: a checked checkbox left followed "保存此 SSH 会话", one quiet sentence "机密信息会加密，密钥保留在平台安全存储中。"; final action row bottom right "取消" outline and "连接" blue. All visible without clipping and without nested scroll boxes. The scrollbar if needed belongs only to body; footer never occludes content.
Keep exact Chinese labels, plain useful controls, no gradient hero, no cards inside cards. Date anchor2026-09-09 no date display.

Mode: built-in image_gen. Current source screenshots are reference images; generated targets are design artifacts.

## Profile startup

Use case: ui-mockup
Asset type: high fidelity implementation target for Trail, a Flutter macOS terminal configuration dialog.
Primary request: redesign the existing Profile STARTUP form. The supplied screenshot is the real current application, a content reference, not an edit target. Keep the existing capabilities and navigation categories, while decisively improving hierarchy, field alignment and density.
Create realistic production-quality UI with clear hierarchy, strong typography and purposeful spacing. Focus this primary screen on editing startup configuration, one primary Save action; no invented features, cards inside cards, marketing, metrics or illustrations.
Target dimensions: 1440 x 1024 screenshot canvas. Center an exact 1040 x 760 native desktop dialog at x200,y132 on a neutral light-gray background. Straight-on flat UI, no perspective. The dialog is the actual product modal. Border radius12, very subtle single shadow. White main surface; neutral sidebar #F4F5F7; restrained existing macOS blue #007AFF. Body text14px SF Pro/PingFang style, section titles14 semibold, page title22; crisp dark text.
Layout: header72px with title "编辑 Profile" and subordinate "Local Shell" left, close icon right. Full-height sidebar200px below header, search "查找设置", 36px navigation rows with neutral line icons. Exact nav labels "常规" "启动" "终端" "外观" "按键" "自动化" "高级". "启动" selected with pale blue row and blue text, no saturated blue bar, no repeated mini cards.
Main content padding32px. Title "启动" and one short quiet subtitle "配置命令、工作目录和进程环境。". Sections are separated by space and one fine divider; NO rectangular group cards.
Section "启动命令": aligned form rows with a fixed 136px left label column, 20px gap, right controls fill ~580px. Inputs38px high, white fill, crisp 1px #D5D7DC border, radius6. Row1 label "Shell / 程序" value "/bin/zsh". Row2 label "工作目录" input placeholder "使用默认工作目录". The helper text is small below the input, never above as another heading.
Section "参数": left label "启动参数"; right one compact inline row value "-l" with small up/down/remove icons, followed by low-emphasis "+ 添加参数" text action.
Section "环境变量": aligned empty key/value row with column headers "名称" "值", quiet empty-state "未设置环境变量", one "+ 添加变量" action. Keep all three sections and controls fully visible, no main page vertical overflow at this size.
Sticky footer60px across entire dialog: left muted "更改仅应用于新会话"; right "取消" outline secondary and solid blue "保存" primary. Preserve realistic disabled, helper and focus affordances; no diagnostic copy. Content is Simplified Chinese, exact quoted text only.
Constraints: preserve useful function and existing seven categories; code-ready layout, modest generous space, well-aligned baseline, no oversized controls, no deep grey filled input rectangles. Date anchor 2026-09-09; do not show dates.

## Settings general

Use case: ui-mockup. Asset type: production-quality Flutter macOS dialog target for Trail, coordinated with the supplied design target.
Image1 is the approved design language reference (Profile startup target). Image2 is the existing Settings General page content reference. Generate ONE SETTINGS GENERAL screen in the SAME design system as Image1, not a comparison and not multiple ideas.
Target1440x1024 canvas with1040x760 dialog centered at x200,y132. Existing native desktop app modal, flat white main surface, neutral light-gray background/sidebar, 12px shell radius, modest single shadow, #007AFF accent. Clean readable14px Chinese SF Pro/PingFang style,22px page title. Purposeful spacing, label/control alignment, fine dividers instead of outlined group cards. Do not add features.
Header72px: "默认设置与外观", subtitle "Trail", close icon. Sidebar200px below header: five items "常规" "外观" "键盘快捷键" "安全与权限" "数据同步"; selected "常规" has pale-blue background and blue text exactly matching Image1.
Main padding32px: title "常规", short subtitle "选择新标签页的默认 Profile 和应用界面语言。". Separate sections with whitespace and fine divider, no boxed sections.
Section heading "新会话". Aligned form row left label136px "默认 Profile", right dropdown38px "Local Shell". Below its control: small gray helper "/bin/zsh". Full width unobtrusive support row below: "字体、颜色和启动参数在 Profile 中配置。" plus text action "编辑 Profile".
Second section heading "语言". One aligned row left label "界面语言", right dropdown "跟随系统". Below control small helper "使用当前设备的首选语言。". Native downward chevrons. Do NOT show long radio lists. All existing choices remain in dropdown menus but closed here. Do not add app search, preview pane, metrics, fake new options or onboarding.
There should be comfortable remaining white space; do not artificially fill it with content. footer60px fixed: left two quiet text buttons "重置默认值" and "重置主题"; right "取消" secondary and "保存更改" muted disabled primary because no edits. Controls38px,6px radii,white fill,1px neutral borders. Alignment more important than decoration.
Preserve real product capabilities and Chinese text. Date2026-09-09, no dates shown.

## Profile appearance

Use case: ui-mockup. Production-quality implementation target for the Appearance tab of Trail macOS Profile configuration.
Reference Image1 is the shared visual language target, Image2 is actual existing Appearance content. Generate one screen in same exact modal style as Image1: 1440x1024 overall canvas, centered1040x760 dialog,72px header,200px sidebar,60px footer,32px main padding, crisp white surface, light neutral sidebar, blue #007AFF,14px readable SF Pro/PingFang-style Chinese body,22px title,38px input height,6px field radius. Understated native professional terminal app. No card-in-card containers, no marketing.
Header "编辑 Profile" subordinate "Local Shell", close. Sidebar search "查找设置", exact categories "常规" "启动" "终端" "外观" "按键" "自动化" "高级". Pale-blue selected "外观".
Main title "外观" subtitle "调整字体、光标和终端配色。". Organize frequently used fields first in three simple open sections separated by fine dividers, all visible.
"字体": aligned136px left labels with right controls, first row "字体" value "JetBrainsMono Nerd Font Mono". Next row one shared label "字号与行高" and compact adjacent inputs "13" and "1.2" with small unit labels "px" and "倍"; no giant input widths. Under it a collapsed disclosure row chevron-right "备用字体" and quiet summary "5 种字体". Fallback font list must be collapsed, do not show its rows.
"光标": row "形状" with dropdown "方块", row "闪烁" with native blue toggle on.
"配色": understated preset dropdown labelled "主题预设", value "当前配色"; horizontal small color swatches that convey current palette; disclosure row "自定义颜色" collapsed, existing ANSI details live behind it. Do not invent terminal live preview or new controls.
Footer left quiet "更改仅应用于新会话"; right outline "取消" and blue "保存". Consistent alignments and modest whitespace, focused usable form, no high-gray input slabs or oversized list. Date2026-09-09, no dates in UI. Exact Chinese text as quoted.
# 第一轮 Profile 外观差异标注

模式：内置 imagegen，目标稿与 Flutter 实截图对比标注。

```text
Use case: compositing.
Asset type: annotated UI alignment review, in Chinese.
Input image 1 is the design target (reference only). Input image 2 is the actual Flutter implementation screenshot and is the edit target.
Create one professional comparison board. Preserve both screenshots and their UI contents without redesigning them; put target on left, current implementation on right. Add numbered orange/red callouts around the current screenshot, with leader lines to precise differences. Chinese title: "第一轮差异标注 · Profile 外观". Labels: "1 容器偏窄：统一至 1040 px"; "2 输入框偏高、灰底过重：统一 38 px 与中性底色"; "3 字号与行高：对齐到同一标签 / 控件网格"; "4 分组留白过大：收紧间距，让常用配色首屏可见"; "5 闪烁开关：移到控件列起点"; "6 底部提示过长：精简为一句话".
These are observed implementation deltas, not proposed new features. Do not invent fields, remove content, change values, or 'fix' the screenshots. Use callouts in surrounding margins so original UI stays legible. Preserve original Chinese text as closely as possible. Add small captions "设计目标" and "第一轮实截图". Clean white background, no decoration.
```
# macOS HIG 复核差异标注

模式：内置 imagegen，compositing。输入为 `iteration-3/profile/04-appearance.png` 与 `hig-review/profile/04-appearance.png`，输出为 `annotations/macos-hig-alignment.png`。

```text
Use case: compositing
Asset type: macOS configuration UI review board.
Primary request: Annotate the differences between these two REAL Flutter screenshots, preserving their screens and all original field values. Image 1 is the prior iteration, Image 2 is the implemented macOS HIG refinement. Put them side by side on a clean landscape 2400x1500 white review board with Chinese labels and restrained blue measurement lines. Crop only the empty outer background; keep each entire dialog and its aspect ratio. Do not redesign, invent, remove, or relocate any controls within either screenshot.
Text (verbatim): "macOS 配置表单 · 规范复核"; left label "调整前"; right label "调整后"; four callouts: "正文 14 → 13 pt · 标题 22 → 17 pt", "常规控件基准 38 → 28 pt", "内容边距 32 → 20 · 标签列 136 → 120", "对话框 1040×760 → 940×700"; footer "13 pt 正文与 28 pt 控件基准参考 Apple HIG；边距、列宽及窗口尺寸为项目选择。"
Callout lines should point to matching real features: heading and form label for type; text input and save button for control baseline; content left edge and font label column for spacing; dialog outer edge for window size.
Constraints: informational audit annotations only. Image 2 is the authoritative implementation. Do not claim all controls are exactly 28 pt, do not label pixel-perfect or HIG certified. Original terminal font-size field must stay 14.0: that is user terminal configuration, different from UI body typography. Keep swatches, cursor switch, original Chinese, entire footer, and disclosure rows unchanged. No new app chrome or traffic lights.
```
# 第一轮 SSH 差异标注

模式：内置 imagegen，目标稿与 Flutter 实截图对比标注。

```text
Use case: compositing. Create a Chinese annotated UI comparison board for SSH configuration. Image 1 is reference target; image 2 is actual Flutter screenshot to annotate. Place both unchanged side by side on a white board, titled "第一轮差异标注 · SSH 配置", captions "设计目标" and "第一轮实截图". Add orange numbered callouts with precise leader lines to actual screenshot: "1 输入底色：移除局部灰底覆盖"; "2 用户 / 端口：并入统一标签网格"; "3 分组间距：让高级选项入口首屏可见"; "4 底栏：勾选框靠左，补充分隔线"; "5 按钮文字：检查主题与截图字体继承". Preserve the private key passphrase field in actual image: it is a real existing feature even though target omitted it. Do not delete or redesign any fields, do not change actual data or fix current pixels. Callouts only, keep original content legible.
```
