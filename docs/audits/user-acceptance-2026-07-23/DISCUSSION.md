# Ianvs Terminal 收口调整：直接处置与待讨论清单

日期：2026-07-23
来源：[用户视角功能验收](REPORT.md)

相关交付：

- `a200a232`：收敛 Terminal 产品范围，移除 Project Workspace 等越界概念。
- `4f1a9796`：直接处置验收中不需要产品决策的缺口。
- `04d5ff5e`：落实 Command Composer 与 Password Manager 的隐藏决策。

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

## 讨论结论

讨论以“技术预览”为当前发布对象。以下结论已经确认；“后续实施”表示产品方向已定，但不代表当前代码已经交付。

| 议题 | 已确认结论 | 边界与理由 | 当前状态 |
|---|---|---|---|
| 发布对象与验收线 | 当前为技术预览；新增或修改流程以 WCAG 2.1 AA、Desktop/macOS 键盘与 VoiceOver 为目标 | 完整应用 AA 认证留到公开发布门槛，不把技术预览表述为已完成全量认证 | 决策已确认；本轮回放、弹窗与键盘退出阻断已修复，专项全量审计后续继续 |
| 原生菜单与多窗口 | 原生菜单只承载稳定、高频动作；不伪造 `⌘N`，真正多窗口单独设计生命周期 | 避免菜单堆满高级动作，也避免用新标签假装新窗口 | Settings、Open Terminal at Folder 已实现；其余精选 App/File/Edit/View/Window/Help 动作后续实施；多窗口明确延期 |
| 统一动作入口 | 原生菜单与命令面板都从统一动作注册表派生；命令面板覆盖全部产品可见且已接线动作，并区分产品动作、隐藏实验动作与内部动作 | 解决动作已经实现但入口不一致，同时避免把实验或内部能力意外暴露 | 发布可见性门禁已用于隐藏两项功能；完整注册表驱动的菜单与命令面板后续实施 |
| Settings 信息架构 | 将 Defaults & appearance 升级为真正 Settings；管理默认 Profile、应用外观、布局恢复、通知和 Hotkey Window，并链接 Manage Profiles | 全局设置留在 Settings，Profile 只管理新 Session 的启动和行为 | 后续实施；当前仍是 Defaults & appearance |
| 通知设置 | Command finished、Bell、Activity 统一到 Settings > Notifications；显示系统权限状态并提供测试通知 | 全局通知与 Profile Automation 的触发通知分开，避免作用域混淆 | 后续实施 |
| Hotkey Window | Settings 中 opt-in，默认关闭；展示注册/冲突状态并提供测试动作 | 全局快捷键可能冲突，技术预览不应无提示抢占 | 后续实施；当前原生端仍会启动时注册，实施时必须改为显式开启 |
| Relaunch 范围 | 窗口尺寸和位置始终恢复；Pane/Session 布局恢复默认关闭，由 Settings 显式开启 | 避免意外恢复失效 cwd、进程意图或敏感上下文 | 已符合：窗口 frame 使用稳定 autosave 名称，`restoreLayout` 默认 `false`；Settings 说明后续补齐 |
| Toolbelt 信息架构 | 分为 History（Commands、Directories、Prompt Marks、Captured Output、Paste History）、Review（Instant Replay、Annotations）和 Advanced（tmux、Coprocess） | 先按用户任务分层，再放专业工具；隐藏功能不占入口 | Password Manager 已移除；其余分组后续实施 |
| Profile 渐进披露 | General、Startup 默认展开；Terminal、Keys、Automation、Advanced 默认折叠，并记忆用户展开状态 | 降低首次编辑密度，同时保留高级用户效率 | 后续实施 |
| Profile 导入 | 将当前 Dynamic Profiles 定位为一次性导入：`Profiles > Import Profiles… > iTerm2 JSON`；预览支持/忽略字段、冲突、shell/command/cwd；默认仅新增，覆盖必须再次确认 | 当前实现不是后台同步，继续称 Dynamic Profiles 会产生错误预期 | 后续实施；“Dynamic Profiles”名称保留给未来真正同步能力 |
| Read-only 与粘贴状态 | Pane 标题显示只读文本和锁图标；`PASTE` 改为 `Bracketed paste`；`MIME PASTE` 改为 `MIME paste` 并解释含义；状态不能只依赖颜色 | 让协议状态转成用户语言，并提高防误输入状态的显著性 | 后续实施 |
| Command Composer | 作为隐藏实验功能保留代码，等待重新设计；不进入技术预览功能口径或验收范围 | 用途和目标用户尚未收敛 | 已实现并回归验证 |
| Password Manager | 作为待重新设计的隐藏功能保留代码；本轮不改名 Session Secrets | 后续设计必须先明确 Keychain、生命周期和授权模型 | 已实现并回归验证 |

## 原始讨论题与选项

下表保留讨论时的原始选项、建议和影响，用于追溯上述结论如何形成；执行状态以上一节为准。

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

## 已落地的功能隐藏决策

2026-07-23 已确认以下两项不进入技术预览的用户可见范围：

1. **Command Composer**
   - 标记为隐藏实验功能。
   - 保留实现代码，等待后续重新设计。
   - 不出现在原生菜单、命令面板、Toolbelt、Settings 或默认快捷键中，也不计入技术预览的功能口径和验收范围。
2. **Password Manager**
   - 标记为待重新设计的隐藏功能，不在本轮改名为 Session Secrets。
   - 保留实现代码，等待后续明确 Keychain、生命周期和授权模型。
   - 不出现在原生菜单、命令面板、Toolbelt、Settings 或默认快捷键中，也不计入技术预览的功能口径和验收范围。

动作注册表仍保留两项内部动作，并以发布可见性元数据阻止产品入口和用户快捷键重新暴露；回归测试覆盖默认入口隐藏。

## 后续执行顺序

1. 先完成统一动作可见性、注册表驱动命令面板和精选 macOS 原生菜单；真正多窗口继续延期。
2. 再将 Defaults & appearance 升级为 Settings，集中通知、Hotkey Window 和布局恢复说明。
3. 然后重组 Toolbelt、Profile 渐进披露和一次性 Profile 导入，并调整 Read-only/粘贴状态表达。
4. 每个新增或修改流程按 WCAG 2.1 AA + macOS 键盘/VoiceOver 回归；公开发布前再做完整应用认证。
