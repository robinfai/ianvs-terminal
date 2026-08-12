# Ghostty 配置能力对比审计

这份文档记录 `ianvs terminal` 当前仓库基线与 Ghostty 官方配置能力之间的差异，用于后续产品和配置系统演进时做长期参考。

## 审计基线

- 审计时间：2026-05-15 09:30:31 CST
- 仓库分支：`codex/hyper-first-shell`
- 仓库基线提交：`90c294ce95e090ac9aa1bf44a8e4f5b7bf4ca6e6`
- 基线提交时间：`2026-05-14 20:27:02 +0800`
- 基线提交标题：`Clarify terminal and PTY ownership at the app boundary`

## 参考资料

本次只引用 Ghostty 官方文档，抓取时间均为 2026-05-15：

- [Ghostty Configuration](https://ghostty.org/docs/config)
- [Ghostty Configuration Option Reference](https://ghostty.org/docs/config/reference)
- [Ghostty Keybindings](https://ghostty.org/docs/config/keybind)
- [Ghostty Keybinding Action Reference](https://ghostty.org/docs/config/keybind/reference)
- [Ghostty Shell Integration](https://ghostty.org/docs/features/shell-integration)
- [Ghostty Themes](https://ghostty.org/docs/features/theme)
- [Ghostty Features Overview](https://ghostty.org/docs/features)

## 范围与口径

- 只比较“用户可配置能力”和其直接依赖的运行时行为。
- 不把纯 VT 兼容性逐项展开；只有当某个 VT 能力被配置显式控制时才纳入。
- `ianvs terminal` 按仓库边界拆两层看：
  - `packages/ianvs_terminal` / `native/core` 是否已经具备底层能力。
  - `example/` 是否已经把该能力建模成稳定配置或对用户暴露。
- 对比目标不是“把 Ghostty 原样照抄”，而是识别哪些能力适合吸收到 `ianvs terminal` 当前产品方向中。

## 当前 ianvs terminal 配置面

### 配置载体

- Profile 持久化在应用支持目录下的 `ianvs_profiles.json`，由 `ProfileRepository` 负责读写。
- App 级配置持久化在 exact-current `ianvs_config.json`，由
  `LocalTerminalConfigRepository` 负责读写。
- predecessor 配置不发现、不迁移、不删除。

对应代码：

- `example/lib/features/profiles/profile_repository.dart`
- `example/lib/features/config/local_terminal_config_repository.dart`

### 已建模的终端 profile 配置

`TerminalSessionConfig` 当前主要包含：

- 启动程序、参数、环境变量、工作目录
- emulation
- scrollback lines
- shell integration 总开关
- font family / fallback / size / lineHeight
- 颜色盘
- cursor shape / blink
- copy-on-select
- option-drag-mode

对应代码：

- `packages/ianvs_terminal/lib/src/config/terminal_config.dart`
- `example/lib/features/profiles/profile_models.dart`
- `example/lib/features/profiles/profile_editor.dart`

### 已建模的 app 级偏好

当前 app 级偏好很少，主要只有：

- 默认 profile
- 主题模式 `system / light / dark`

对应代码：

- `example/lib/features/preferences/app_preferences_models.dart`
- `example/lib/features/shell/defaults_appearance_dialog.dart`

### 已存在但还不是完整配置系统的能力

下面这些能力已经存在于运行时或 `example/` 产品层，但多数还没有被抽象成统一配置语义：

- shell hook：`preexec`、`command_finished`、`precmd`、`precmd.pwd`
- shell integration snapshot：recent commands、recent directories、prompt marks
- 自动 profile 切换：按 `hostname`、`username`、`directory`
- triggers：输出匹配后通知或回发文本
- 搜索 scrollback、prompt mark 导航、命令输出选择
- advanced paste、paste history、instant replay
- autocomplete、coprocess、password manager、tmux integration
- hotkey window
- inline image overlay 渲染

对应代码：

- `native/core/src/pty.rs`
- `example/lib/features/sessions/session_state.dart`
- `example/lib/features/sessions/session_controller.dart`
- `example/lib/features/shell/shell_screen.dart`
- `packages/ianvs_terminal/lib/src/terminal/terminal_viewport.dart`

### 关键仓库证据索引

| Topic | 仓库证据 |
| --- | --- |
| Profile 文件持久化 | `example/lib/features/profiles/profile_repository.dart` |
| App 偏好文件持久化 | `example/lib/features/preferences/app_preferences_repository.dart` |
| 终端配置模型 | `packages/ianvs_terminal/lib/src/config/terminal_config.dart` |
| Profile 编辑器当前暴露字段 | `example/lib/features/profiles/profile_editor.dart` |
| Theme preset 系统 | `example/lib/ui/foundation/terminal_theme_presets.dart` |
| shell hook 注入实现 | `native/core/src/pty.rs` |
| shell integration snapshot 数据结构 | `example/lib/features/sessions/session_state.dart` |
| 自动 profile 切换逻辑 | `example/lib/features/sessions/session_controller.dart` |
| 快捷键硬编码入口 | `example/lib/features/shell/shell_screen.dart` |
| hotkey window 平台桥接 | `example/lib/features/shell/window_bridge.dart` |
| copy-on-select 实际触发点 | `packages/ianvs_terminal/lib/src/terminal/terminal_viewport.dart` |
| inline image overlay 渲染 | `packages/ianvs_terminal/lib/src/terminal/terminal_viewport.dart` |
| terminal 标题同步 | `example/lib/features/sessions/session_controller.dart` |
| command finished / bell / activity 通知 | `example/lib/features/shell/shell_screen.dart` |

## 差异矩阵

| Area | Ghostty 官方能力 | ianvs terminal 当前状态 | 差异类型 | 吸收价值 |
| --- | --- | --- | --- | --- |
| 配置文件形态 | 文本 `config.ghostty`，支持多位置加载、`config-file` 拆分、可选 include、命令行同名 flag 覆盖 | 两份 JSON 持久化文件，按 repo 当前实现分成 profile 与 app preferences，缺少统一入口 | 基础设施缺口 | 很高。先补统一配置层，再谈单项功能 |
| 配置热重载 | 官方支持 reload config，且文档区分哪些选项可热更新、哪些只影响新 surface | 未看到通用文件监听或 reload 协议；现有编辑器更多是“保存后影响新会话” | 基础设施缺口 | 很高。对后续任意配置扩展都有复用价值 |
| 启动命令模型 | `command`、`initial-command`、`working-directory`、CLI `-e`、shell/direct 模式区分 | 只有 `program + args + env + cwd`，语义偏直接启动配置 | 模型较薄 | 中高。适合吸收 `working-directory` 继承语义和初始命令语义 |
| 新 tab/window cwd 继承 | 依赖 shell integration，可让新 surface 继承上一个 terminal 的 cwd | 已能记录 cwd 和 prompt mark，但默认 profile/新 tab 体系里没有同等级、显式的 cwd 继承配置 | 能力已部分存在，缺产品语义 | 很高。与现有 shell hook 非常契合 |
| shell integration 模式选择 | `detect / none / bash / elvish / fish / nushell / zsh` | 当前只有 `enabled` 布尔开关，实际注入支持 `zsh` / `bash` / `fish` | 配置语义不足 | 高。底层能力已在，扩展成本相对低 |
| shell integration feature flags | `shell-integration-features` 可单独开关 `ssh-env`、`ssh-terminfo`、`sudo` 等 | 当前只有总开关，没有 feature 级控制，也没有 remote terminfo/sudo/ssh 配置语义 | 明显缺口 | 高。比继续堆 shell 工具 UI 更基础 |
| command finished 通知策略 | `notify-on-command-finish = never / unfocused / always` | 运行时已经会在 `command_finished` 时发通知，但没看到用户配置策略面 | 已有行为，缺配置面 | 中高。很适合快速补齐 |
| 关闭确认策略 | `confirm-close-surface` 能结合 shell integration 判断是否提示 | 当前有平台 `requestQuitConfirmation` 与 shell integration，但没看到统一配置策略模型 | 产品行为零散 | 中高。适合纳入窗口/会话配置 |
| 字体 family 与 style | 支持 regular / bold / italic / bold-italic 独立 family 与 style | 当前只支持单一 `family + fallback + size + lineHeight` | 明显缺口 | 高。对终端观感影响大 |
| synthetic style / variable font / font feature | 支持 `font-style*`、`font-synthetic-style`、`font-feature`、variable font axis、codepoint map | 当前没有对应模型 | 明显缺口 | 中。重要但排在统一配置层和 keybind DSL 后面 |
| 主题系统 | 支持内建数百主题、theme 文件、light/dark 配对主题 | 当前有 5 个内建 preset，可手工改 20 个颜色槽；app 自身只支持 light/dark/system 模式 | 主题生态和导入能力不足 | 很高。可直接改善用户可用性 |
| 颜色配置边界 | theme 文件可覆盖背景、前景、cursor、selection、palette，且可作为单独文件加载 | 当前颜色结构合理，但只能走 profile JSON / 编辑器保存 | 能力结构不错，载体不够强 | 高。比重做颜色模型更应该先补“导入/切换/组合” |
| cursor 配置 | `cursor-style`、blink、prompt 时光标行为与 shell integration 联动 | 当前支持 shape / blink；shell integration 已追踪 prompt，但没看到“prompt 态光标样式策略” | 部分缺口 | 中。可作为 shell integration 细化项 |
| copy-on-select | 官方支持 `false / true / clipboard`，并区分 selection clipboard 与 system clipboard | 当前只有布尔 `copyOnSelect`，PointerUp 时直接 copy selection | 配置粒度不足 | 中高。实现简单，收益直接 |
| 右键与中键语义 | 官方有 `right-click-action`、selection clipboard 约定、中键 paste | 当前没看到同等级统一配置；有粘贴、复制动作，但更多在 app 层菜单里 | 交互配置不足 | 中。适合在交互配置扩展时一起做 |
| 粘贴安全策略 | 官方区分 bracketed paste 安全、title-report 等安全开关 | 当前支持 bracketed paste 模式识别，但没看到用户级安全策略开关 | 安全配置缺口 | 中。价值高，但实现需先厘清策略 |
| 快捷键 DSL | 官方 `keybind` 支持序列、global 绑定、发送 `text` / `esc` / `csi`，绑定 tab/split/search/prompt/quick terminal 动作 | 当前快捷键主要硬编码在 `ShellScreen`，没有声明式 registry、没有配置化覆盖 | 最大产品缺口之一 | 很高。推荐列为第一优先级 |
| command palette / action registry | Ghostty keybind/action 系统和 command palette 是统一动作面 | 当前 `ShellScreen` 已经有 action menu，但动作和快捷键表述散落 | 结构未收口 | 很高。与快捷键 DSL 应一起做 |
| tabs / splits / window 行为配置 | 官方支持 new tab 位置、show tab bar、split jump、split zoom、divider color、unfocused split opacity | 当前已有 tabs / splits / focus，但相关行为和视觉几乎不是可配置模型 | 窗口层配置薄 | 高。尤其适合吸收 tab/split policy |
| window state restore | 官方支持保存/恢复窗口位置、尺寸、tabs、splits、cwd | 当前有 profile 与 app 偏好持久化，但未看到完整窗口布局恢复系统 | 明显缺口 | 高。对桌面 terminal 产品形态很重要 |
| quick terminal / hotkey window | 官方支持 quick terminal 的位置、尺寸、屏幕、动画、autohide、space behavior | 当前已有 `toggleHotkeyWindow()` 能力，但几乎没看到同等级配置模型 | 已有入口，缺产品语义 | 很高。属于“已有雏形，适合做实” |
| 背景视觉配置 | 官方支持 `background-opacity`、blur、background image、background image opacity | 当前没有终端背景级配置；现有 blur 多是 app chrome 视觉 token | 明显缺口 | 中。好看，但不该排在配置基础设施前 |
| window decoration / 原生窗口偏好 | 官方支持 `window-decoration`、titlebar theme、step resize 等 | 当前没看到对平台窗口装饰偏好的稳定配置 | 明显缺口 | 中。与桌面壳成熟度相关 |
| 标题报告与窗口标题 | 官方单独讨论 title-report 风险；terminal 标题与 tab 标题都有动作和配置约束 | 当前 frame 已带 `windowTitle`，session controller 也会更新窗口标题，但没有 title-report 安全配置面 | 部分具备，缺安全边界 | 中高。适合随安全配置一起补 |
| 搜索与 prompt 跳转 | 官方有 `search`、`jump_to_prompt`、scrollback export 等 action | 当前已具备搜索 scrollback、prompt 导航、命令输出选择，且是 app 层真实工作流 | 当前不弱 | 不是优先补差项；更多是整理成统一 action/config 体系 |
| inline image / graphics | 官方支持 Kitty graphics protocol，且可配 image storage limit | 当前 frame model 和 viewport 已支持 inline image overlay，但没看到用户配置 limit 或 graphics policy | 能力已部分存在，缺配置面 | 中。属于后续增强项 |
| 安全键盘输入等平台特性 | Ghostty 暴露 secure input、mouse reporting toggle、readonly 等动作/策略 | 当前存在部分相关 app 行为，但未形成统一配置与动作协议 | 产品壳层差距 | 中。需要和快捷键/action registry 一起看 |

## ianvs terminal 已有且不应被 Ghostty 对比掩盖的能力

下面这些能力不是 Ghostty 本轮配置对比里的主要强项，但 `ianvs terminal` 已经具备或正在显式建模，后续不该因为追 Ghostty 而被误判为“还没做”：

| Area | ianvs terminal 当前状态 | 备注 |
| --- | --- | --- |
| 输出触发器 | profile 可按 regex 触发 notify 或 send text | 更偏工作流自动化，不是 Ghostty 那类终端基础配置 |
| 自动 profile 切换 | 可按 host/user/dir 切换 profile | 很有产品辨识度，适合保留并继续增强 |
| advanced paste | 支持粘贴前转换文本 | 更偏 shell workflow |
| paste history | 支持最近复制/粘贴历史，且可落盘 | 不属于 Ghostty 配置强项 |
| instant replay | 可从最近 terminal frame 恢复文本 | 偏工作流增强 |
| autocomplete | 可基于可见输出和 recent commands 做建议 | 偏 shell product，而不是纯 terminal emulator |
| coprocess / password manager / tmux integration | 已作为 shell action surface 存在 | 说明项目方向并不只是“做一个 Ghostty 克隆” |

## 建议吸收顺序

### P0：先做配置基础设施，不要先堆选项

建议优先新增一个统一配置子系统，至少覆盖：

- 单一用户配置入口
- include / machine override / profile override
- 运行时 reload
- 配置默认值、来源和优先级定义
- 配置变更后哪些项热更新、哪些只影响新会话的协议

没有这层基础设施，后续无论是主题导入、快捷键、自定义 quick terminal 还是 shell integration feature flags，都会继续散落在 profile JSON、app preferences 和硬编码逻辑里。

### P1：吸收 Ghostty 最值钱的“可组合交互能力”

这一批推荐最先落地：

1. 声明式 keybinding registry + 用户覆盖
2. shell integration 模式选择与 feature flags
3. command finished / close confirm / cwd inheritance 等基于 shell integration 的配置语义
4. quick terminal / hotkey window 的位置、尺寸、autohide、动画配置
5. 主题导入、主题文件、light/dark paired themes

这批能力会直接把当前项目从“功能不少，但配置分散”推进到“可以持续扩展的桌面 terminal 产品”。

### P2：补产品质感与平台细节

这一批有价值，但应排在 P0/P1 之后：

- window restore / tab bar policy / new tab position
- right-click / middle-click / clipboard policy
- prompt 态 cursor 策略
- title-report / paste safety / readonly / secure input 策略
- background opacity / blur / background image
- split divider / unfocused split dimming

### P3：高阶字体与图形配置

放在更后面更合理：

- `font-feature`
- variable font axis
- per-style font family
- codepoint map
- graphics/image storage limit

这些能力有明显价值，但不应该先于统一配置系统和 keybinding/action 体系。

## 结论

如果只挑最值得吸收的 Ghostty 经验，结论不是“先补透明度、背景图或某个窗口选项”，而是下面三条：

1. 把配置层做成一个统一、可组合、可重载的系统。
2. 把快捷键和动作从硬编码提升为声明式 registry。
3. 把现有 shell integration、hotkey window、主题和通知这些已有能力补成完整配置语义。

这三条做完之后，再继续吸收 Ghostty 的视觉配置、字体高阶能力和窗口策略，ROI 会明显更高，也更符合 `ianvs terminal` 当前“terminal runtime + shell product”双层定位。
