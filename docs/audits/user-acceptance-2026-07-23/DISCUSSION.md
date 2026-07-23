# Ianvs Terminal 收口调整：直接处置与待讨论清单

日期：2026-07-23
来源：[用户视角功能验收](REPORT.md)

## 本轮已直接处置

以下问题有明确的平台规范、可访问性或安全反馈依据，不涉及产品定位选择，已直接调整：

1. **回放可访问性与退出路径**
   - Instant Replay 和 Recording Replay 增加可识别的工作区、控制区语义与焦点遍历边界。
   - `Esc` 在搜索框持有焦点时仍可退出回放，退出后恢复主工作区语义。
   - Clear Instant Replay 增加不可撤销确认。
2. **弹窗可访问性**
   - 统一弹窗脚手架增加对话框语义容器和有序焦点遍历；Defaults & appearance 不再从辅助功能树消失。
3. **macOS 基础集成**
   - 启用标准 `Settings…` 菜单与 `⌘,`，桥接到 Defaults & appearance。
   - 使用稳定名称记忆主窗口尺寸和位置。
4. **状态与反馈**
   - 默认 Profile 的“未配置”改为“自动回退”，同时展示实际生效 Profile。
   - 录屏、滚屏与诊断导出改用短提示，并提供 Reveal 操作，避免暴露完整内部路径和 Snackbar 排队。
5. **命令面板可读性**
   - 加宽面板并允许说明显示两行，降低说明截断。
6. **仓库卫生**
   - 忽略 `.DS_Store`。

## 需要讨论后再决定

下列调整会改变产品定位、默认行为或信息架构，不宜在本轮单方面落地。

| 议题 | 需要决定什么 | 可选方向 | 当前建议 | 影响 |
|---|---|---|---|---|
| 原生菜单与多窗口 | 是否把 macOS 标准菜单和 New Window 作为发布门槛 | 仅补高频命令；完整映射动作注册表；保持应用内入口为主 | 先补 App/File/Edit/View/Window/Help 高频动作，再单独设计多窗口生命周期 | 平台学习成本、状态模型、测试面明显增加 |
| 统一动作入口 | 命令面板是否展示全部已实现动作 | 精选短列表；完整注册表；分“常用/高级” | 注册表生成完整列表，用分类、搜索权重和高级分组控制密度 | 决定隐藏功能的可发现性和长期维护成本 |
| Auto Composer 定位 | 作为正式能力发布，还是暂时隐藏 | 正式入口；实验功能；移除发布口径 | 在用途与目标用户明确前标为实验功能，不计入已交付特性 | 影响产品叙事、快捷键和维护成本 |
| Dynamic Profiles 入口 | iTerm2 Profile 导入放在哪里 | Profiles > Import；命令面板；首次迁移向导 | 放入 Profiles > Import，并先展示字段与安全预览 | 涉及外部配置兼容、命令安全与错误恢复 |
| Hotkey Window | 是否作为一级能力开放配置 | 默认启用；设置中 opt-in；继续隐藏 | 在 Settings 中 opt-in，提供冲突检测、权限状态和测试热键 | 涉及全局快捷键冲突、窗口生命周期和多显示器行为 |
| Toolbelt 信息架构 | 历史工具与专业工具如何分层 | 维持平铺；按任务分组；拆成 History/Advanced | Commands/Dirs/Output/Paste 归 History，tmux/Coprocess/Annotations/Secrets 归 Advanced | 影响高频路径、面板复杂度和高级能力发现性 |
| Secrets 命名与持久化 | 内存 Secret 是否继续称 Password Manager | Session Secrets；接入 Keychain；保留现名 | 先改名 Session Secrets 并明确重启丢失；需要持久化时再设计 Keychain | 涉及安全预期、信任与迁移 |
| Relaunch 默认范围 | 是否默认恢复 Pane/Session 布局 | 只记窗口；默认恢复布局；设置中 opt-in | 窗口尺寸位置始终恢复，Pane 布局先 opt-in | 涉及意外重启、失效 cwd/进程与隐私 |
| 只读与粘贴状态文案 | 状态需要多强的视觉占比 | 仅状态栏；Pane 标题/边框；首次教育提示 | Read-only 在 Pane 标题显示锁标；`PASTE` 改为 `Bracketed paste` 并提供说明 | 影响终端可用面积与新用户理解 |
| 通知设置 | Bell、命令完成和 Activity 是否统一 | 保持分散；统一设置区；按 Profile 配置 | 统一到 Settings > Notifications，显示权限状态并提供测试通知 | 涉及系统权限、全局与 Profile 作用域 |
| Profile 渐进披露 | 编辑器默认展开哪些区块 | 全部展开；记忆用户状态；基础展开高级折叠 | General/Startup 默认展开，高级区折叠并记忆用户选择 | 影响新手负担与高级用户效率 |
| 可访问性验收线 | 发布采用哪个标准和平台范围 | WCAG A；WCAG 2.1 AA；加入多平台矩阵 | 以 WCAG 2.1 AA + macOS 键盘/VoiceOver 为发布验收线 | 决定后续组件改造、测试成本与发布定义 |

## 建议讨论顺序

1. 先确定发布对象与可访问性验收线。
2. 再确定原生菜单、统一动作入口和多窗口范围。
3. 然后收敛 Toolbelt、Profile、通知与 Hotkey Window 的信息架构。
4. 最后决定 Auto Composer、Dynamic Profiles、Secrets 等差异化能力的发布身份。
