# Replay Player Design QA

## Target and implementation

- Design reference: `/Users/luobinghui/.codex/generated_images/019f8f89-028e-7c81-804c-40d62b3d1dd4/call_H8pYqc6GqRxB0cUzmISDc3f6.png`
- Implementation capture: `design-qa-assets/replay-command-review.png`
- Full comparison: `design-qa-assets/replay-command-review-comparison.png`
- Timeline comparison: `design-qa-assets/replay-command-review-timeline-comparison.png`
- Viewport: 1622 × 970 logical pixels at DPR 1
- State: light theme, saved replay, local command segments plus an SSH parent segment with a nested remote command

The implementation capture is produced by a deterministic Flutter widget test. Its
Ahem test font intentionally renders text as blocks, so typography was also checked
in the running macOS application. The comparison focuses on the replay player's
layout, density, hierarchy, controls, and semantic timeline.

## Fidelity review

| Surface | Result | Evidence |
| --- | --- | --- |
| Layout and spacing | Pass | The terminal remains the dominant surface. The semantic timeline, legend, session metadata, transport controls, and utility actions keep the same vertical order and grouping as the reference. Both instant and saved replay use the same shared dock. |
| Typography | Pass | Production uses the app's themed UI and terminal typefaces with the same label hierarchy. The implementation screenshot's block glyphs are a deterministic-test artifact rather than production styling. |
| Colors and tokens | Pass | Light-theme surfaces, borders, primary blue, directory blue, activity gray, and remote amber are derived from `ColorScheme` or shared replay tokens. |
| Shape and surfaces | Pass | Command cards, active outlines, track markers, dividers, and compact toolbar controls match the reference's restrained rounded treatment without adding decorative surfaces. |
| Icons | Pass | Material icons are consistently sized and aligned for playback, search, fit, copy, close, directory, and remote states. No handcrafted SVG or placeholder icon substitutes are used. |
| Image quality | N/A | The target contains no raster product imagery. The implementation uses Flutter text, dividers, and library icons at device resolution. |
| Copy and content | Pass | Command labels, path metadata, remote host context, playback time, speed, frame count, and privacy disclosure are coherent in the standalone replay state. |
| Responsiveness | Pass | The dock switches to a compact control layout below 960 logical pixels; timeline labels truncate instead of colliding, and controls retain usable targets. |
| Accessibility | Pass | Buttons have tooltips/semantic labels, keyboard Escape closes replay, contrast follows the active theme, and controls remain keyboard reachable. |

## Interaction and semantic-state review

- Clicking a command card seeks to that segment.
- Scrubbing, play/pause, previous/next step, speed selection, search, fit, copy,
  and close are covered by widget tests.
- Local shell-hook events produce named command cards and directory changes.
- Prompt-only metadata produces anonymous command ranges without inventing labels.
- With no hook or prompt semantics, the same timeline shows `Activity` fallback
  ranges rather than guessing command boundaries.
- `ssh` or `mosh` is shown as a remote parent segment. Remote commands are nested
  only when remote OSC semantic events exist; otherwise the parent contains one
  `Remote activity` range.
- Overlapping native-hook and OSC events are deduplicated.
- Input privacy is explicit: keystrokes can be redacted while command metadata is
  still included.

## Comparison passes

### Iteration 1

- P1 · Layout: the first implementation compressed commands into thin markers,
  which weakened the command-review hierarchy visible in the target.
- P2 · Content and behavior: the first pass lacked the target's command legend,
  larger command cards, visible remote nesting, and card-to-seek interaction.
- Fix: enlarged the semantic lane, added major/minor/directory/remote states,
  nested SSH children, added the legend, made cards seekable, and moved both
  replay modes onto the same timeline and control dock.

### Iteration 2

- Full-view comparison: `design-qa-assets/replay-command-review-comparison.png`
- Focused timeline comparison:
  `design-qa-assets/replay-command-review-timeline-comparison.png`
- P0: none.
- P1: none.
- P2: none.
- P3: the implementation dock is about 55 pixels more compact vertically than the
  mock. This preserves the intended hierarchy and gives the terminal slightly more
  working space, so no further change is required.
- Intentional content difference: the QA fixture uses fewer local commands and an
  SSH example to verify the remote-session behavior requested after the mock was
  selected.

### Iteration 3 — Actual runtime evidence

- User-supplied runtime capture:
  `design-qa-assets/actual-replay-audit/01-actual-replay.png`
- Source/runtime comparison:
  `design-qa-assets/actual-replay-audit/02-source-actual-comparison.png`
- P1 · Duplicate semantic sources produced overlapping cards for `top` and the
  SSH session.
- P1 · Remote title, status, and time collided inside the SSH card.
- P2 · Anonymous labels exposed raw event numbering and tiny semantic noise.
- Fix: reconcile hook and OSC events into one open command per lane, enrich
  anonymous segments with later named metadata, promote anonymous wrappers into
  SSH parents, discard sub-100 ms anonymous cards, renumber visible anonymous
  commands, and split remote status from the SSH title.
- Fixed deterministic capture:
  `design-qa-assets/actual-replay-audit/03-fixed-replay.png`
- Before/after comparison:
  `design-qa-assets/actual-replay-audit/04-before-after-comparison.png`
- Regression fixture covers overlapping anonymous/named starts, duplicate
  finishes, and anonymous-to-SSH promotion. No remaining P0, P1, or P2 issue was
  found in the corrected reproduction.

final result: passed

---

# 默认设置 Tabs 与快捷键面板：设计验收记录

## 验收对象

- 用户参考图：`/var/folders/k2/8qbf3nrs7t1749d198rw0df40000gn/T/codex-clipboard-98804558-f3a7-4a0b-a289-c7a8d193f7f3.png`
- 原生实现截图：`design-qa-assets/defaults-tabs/native-light-shortcuts.png`
- 并排对照：`design-qa-assets/defaults-tabs/source-implementation-comparison.png`（左：参考图；右：实现）
- 状态：浅色主题、简体中文、左侧“键盘快捷键”已选中
- 平台：macOS 原生 Flutter debug 构建；截图 1128 × 746 px

## 设计决策

- 左侧五个入口改为真正的互斥 Tab：桌面端只挂载当前 Tab 的内容，不再滚动定位长表单中的锚点。
- “键盘快捷键”Tab 直接承载完整管理器，包括搜索、类别筛选、录入、停用、冲突提示和恢复默认。
- 标题栏、侧栏与底部保存栏跨 Tab 保持稳定，切换分区不会进入二级页面或丢失未保存状态。
- 800 px 及以上的常规桌面窗口使用左侧 Tabs；390 px 紧凑布局继续使用顺序表单和全屏快捷键编辑器。

## 对照结论

| 优先级 | 结果 | 说明 |
| --- | --- | --- |
| P0 | 无 | Tab 可切换、列表可滚动、保存/取消可达；无崩溃、溢出或不可达内容。 |
| P1 | 无 | 参考图中的左侧导航、蓝色选中态、固定页脚和内容层级均保留；快捷键管理器按用户要求成为当前 Tab 的唯一内容。 |
| P2 | 无 | 侧栏比例、页头分隔、内容边距、列表行密度、图标和边框与参考图及现有设计系统一致。 |
| P3 | 无 | 原生截图未发现需要继续调整的轻微视觉偏差。 |

参考图的“键盘快捷键”选中态下仍混合显示快捷键入口、安全权限与数据服务；实现根据本轮明确请求，将其修正为独立 TabPanel，并直接展示可操作的快捷键管理器。这是有意的交互差异。

## 交互与可访问性验证

- 五个左侧入口保持可聚焦、可点击，并通过语义树暴露为带选中状态的按钮。
- 快捷键筛选、类别选择、录入、停用、恢复默认和冲突阻止保存均有回归覆盖。
- 切换到外观 Tab 时只显示外观与终端画布间距；切换到安全 Tab 时只显示权限控制。
- 普通 800 × 700 桌面窗口和 1200 × 900 大窗口均验证 Tabs；390 × 844 验证紧凑布局。
- 浅色中文原生画面已与参考图置于同一比较输入中复核，未发现剩余 P0、P1 或 P2 问题。

final result: passed

---

# 默认设置与外观：设计验收记录

## 验收对象

- 视觉源：`/Users/robinfai/.codex/generated_images/01a02578-c512-7530-aacc-a44037835a76/exec-03b2496d-7675-4172-a6a7-813bd2e2fbda.png`
- 实现截图：`design-qa-assets/defaults-appearance-redesign/native-light-security.png`
- 深色验证：`design-qa-assets/defaults-appearance-redesign/native-dark-security.png`
- 完整对照：`design-qa-assets/defaults-appearance-redesign/comparison-full.png`（左：视觉源；右：实现）
- 聚焦对照：`design-qa-assets/defaults-appearance-redesign/comparison-security-focus.png`（左：视觉源；右：实现）

## 环境与状态

- 平台：macOS 原生 Flutter 应用，debug 构建
- 应用截图：1128 × 740 px，设备像素比由宿主显示器决定
- 对话框可视区域：约 960 × 700 px
- 视觉源：1409 × 1117 px
- 语言：简体中文
- 主题：浅色（同时复验深色；验收后已恢复用户原来的深色设置）
- 分区：安全与权限
- 策略状态：OSC 52「按 Profile」、OpenURL「每次询问」、RequestAttention「拒绝」
- ReportVariable：0 项已记住的决定

视觉源与当前显示器尺寸不同，因此完整对照按同一显示高度等比缩放，没有拉伸；聚焦对照单独裁出主权限区域，避免背景和窗口尺寸干扰判断。

## 对照结论

| 优先级 | 结果 | 说明 |
| --- | --- | --- |
| P0 | 无 | 页面可打开、可滚动、可关闭；没有崩溃、溢出或内容不可达。 |
| P1 | 无 | 桌面侧栏、选中态、权限策略下拉、OpenURL 风险说明、ReportVariable 管理入口和固定操作栏均已实现。 |
| P2 | 无 | 标题层级、卡片边界、图标、分隔线、选中蓝色和整体信息密度与视觉源保持一致；中文长文案没有遮挡主要操作。 |
| P3 | 有 | 当前宿主显示器高度较小，实际截图比视觉源更紧凑，并在首屏露出下一节“数据服务”；这是约束下的自适应表现，不影响核心任务。 |

## 交互与可访问性验证

- 五个侧栏入口均可用，并通过滚动定位到对应分区。
- 三个权限策略均使用键盘可操作的下拉控件；OpenURL 菜单实机打开验证通过。
- 当前分区和策略控件具有语义标签，选中态不仅依赖颜色。
- 固定底栏保留“重置默认值”“重置主题”“取消”“保存更改”，修改后保存按钮启用。
- 390 × 844 紧凑布局继续使用触控友好的原单选卡片，不强塞桌面侧栏。
- 浅色、深色渲染均通过；临时验收设置已恢复。

## 迭代记录

1. 将长表单重组为桌面侧栏 + 单一滚动内容，保留所有原有表单项和保存语义。
2. 将三组终端协议单选卡片压缩为可扫描的权限行，并给当前策略增加上下文说明。
3. 将 ReportVariable 合并为摘要行和按需展开管理，减少常态页面高度。
4. 补齐中文/英文文案、响应式分支和键盘交互测试。
5. 在原生 macOS 应用中复验浅色、深色、侧栏跳转和下拉菜单，并生成完整与聚焦对照图。

final result: passed
