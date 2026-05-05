# Warp 源码与交互对比复审

日期：`2026-05-04`

## 基线

- Warp 仓库：`https://github.com/warpdotdev/Warp.git`
- 本机浅克隆：`../../warp`
- 当前 ref：`master@23eedf4`
- commit 时间：`2026-05-03T23:50:56-07:00`
- clone 形态：`--depth 1 --single-branch --filter=blob:none --sparse`
- sparse 目录：
  - `../../warp/app/src/terminal/`
  - `../../warp/app/src/terminal/model/`
  - `../../warp/app/src/terminal/input/`
  - `../../warp/app/src/search/command_search/`
  - `../../warp/app/src/search/command_palette/`
  - `../../warp/app/src/pane_group/`
  - `../../warp/app/src/launch_configs/`
  - `../../warp/app/src/integration_testing/`

本轮 Computer Use 对 `dev.warp.Warp-Stable` 被插件安全策略拒绝，后续交互截图由用户手动完成；这些截图只作为本机交互观察证据，不复制 Warp 素材到产品 UI。

## 交互截图观察

截图目录：`docs/design_snapshots/warp_alignment/warp_interaction/`

- `01_terminal_blocks.png`：Warp 在 terminal 内容区内直接按 command/output 形成 block，顶部保留 prompt/cwd/git 状态，底部 input editor 和上下文 chip 与当前 session 强绑定。
- `02_block_not_hover_click_actions.png`：block 被选中或 hover 后，右侧出现 inline actions；动作靠近 block 本体，而不是远离 terminal 的全局工具栏。
- `03_command_search.png`：command/search palette 是统一入口，零状态直接暴露 workflows、prompts、notebooks、environment variables、files、sessions、launch configurations、conversations 等类别。
- `04_completion_input.png`：输入 `git pull` 时，Warp 能识别 shell command，并允许用快捷键覆盖自动检测；补全/输入状态与 active block 区域之间有清晰分隔。
- `05_split_pane.png`：split pane 后，每个 pane 都保留独立 header、关闭/更多菜单、底部 cwd/git/context chips 和 agent/terminal prompt 区；active pane 视觉边界明确。
- `06_tab_or_launch_config_entry.png`：顶部 `+` 菜单把 new terminal tab、agent tab、cloud agent tab、shell selector 和 launch configs 入口集中在一起。

## 源码级对比

### Launch Config

Warp：

- `../../warp/app/src/launch_configs/launch_config.rs:15` 顶层 `LaunchConfig` 是 `name + active_window_index + windows[]`。
- `../../warp/app/src/launch_configs/launch_config.rs:23` 的 `from_snapshot` 从 app state 生成窗口级 snapshot，并跳过 quake window。
- `../../warp/app/src/launch_configs/launch_config.rs:92` 的 pane template 保留 `cwd`、`commands`、focus、pane mode 和 shell override。
- `../../warp/app/src/launch_configs/save_modal.rs:96` 的保存 modal 有 `NotSaved -> Success/Failure` 生命周期，`save_modal.rs:261` 直接把当前 app state 保存成 launch config。

Ianvs：

- `lib/src/terminal_windows.dart:28` 已有 `TerminalWindowsController`，包含 window collection、active window、new/close/select window。
- `lib/src/terminal_windows.dart:185` 已能导出 app-level `TerminalLaunchConfiguration`，`terminal_windows.dart:223` 已能 apply `windows[]`。
- `lib/src/launch_config.dart:21` 已升级为 `version = 2`、`scope`、`activeWindowIndex`、`windows[]`，并在单窗口时保留 legacy `tabs` 字段。

结论：Ianvs 的 app-level launch config 语义已经跟上 Warp 主要结构；后续优化集中在 `+` 菜单里的发现入口、tab config 日常保存路径、以及保存后验证体验的稳定 golden。

### Blocks

Warp：

- `../../warp/app/src/terminal/model/block.rs:286` 的 `Block` 是 terminal model 内部对象，持有 prompt/output grid、cwd、session、timestamps、prompt snapshot、filter query 等。
- `../../warp/app/src/terminal/model/block.rs:617` 的 `BlockState` 区分 before/executing/done/background/static。
- `../../warp/app/src/terminal/model/block.rs:644` 的 `BlockMetadata` 把 session 和 cwd 绑定进 block。
- `../../warp/app/src/terminal/model/blocks.rs:135` 的 `BlockHeightItem` 支持 restored separator、inline banner、subshell separator 和 rich content。
- `../../warp/app/src/terminal/model/blocks.rs:239` 的 `BlockList` 是 terminal scroll/render 模型的一部分。

Ianvs：

- `lib/src/terminal_blocks.dart:22` 的 `TerminalBlock` 仍是产品层记录，字段主要是 command/output/status/scrollback offset。
- 当前 UI 已有 inline rail、active block card、status rail、sticky command header、右侧历史 panel 和默认布局截图 gate，但 block 还不是 flutterm scrollback 原生 row-range。

优化点：

- 下一步应把 block divider、status gutter、sticky command header 的底层扩展继续沉到 flutterm，Ianvs 侧只消费 row range 和 metadata。
- 保留现有 side panel 作为导航/历史入口，但主体验应向 terminal-native block 分组迁移。

### Input / Completion

Warp：

- 本机截图显示底部 input editor 与 cwd/git/context chips 绑定，输入时有 shell command autodetect 和覆盖提示。
- `../../warp/app/src/terminal/input/common.rs:263` 和 `common.rs:289` 说明 workflow enum / dynamic workflow menus 可以直接附着在输入区。

Ianvs：

- 现有 `_ModernInputBar` 已从普通表单收口为 editor 容器，并通过 inline shell 承载 completion / history / palette。
- 默认布局在 editor 上方新增 `_InputContextStrip`，把 target、cwd、status、last command 放在 input-adjacent 区域，避免默认画面只在顶部 chrome 表达 session context。
- `lib/src/saved_commands.dart:9` 已有 `SavedCommandEntry` schema，可以继续扩展成 workflow-like saved command。

优化点：

- completion 要补更明确的候选列表、来源标签和选择态，避免只停留在 inline hint。
- 输入区可以增加 command type/autodetect 状态，但不要引入 Warp 的 AI/agent 文案作为产品默认路径。

### Command Search / Session Navigation

Warp：

- `../../warp/app/src/search/command_palette/data_sources.rs:27` 的 `DataSourceStore` 聚合 actions、sessions、Warp Drive、launch configs、new sessions、conversations、repos 和 files。
- `../../warp/app/src/search/command_palette/data_sources.rs:89` 开始按 query filter 注册 launch configs / sessions / workflows / env vars / files 等来源。
- `../../warp/app/src/search/command_palette/navigation/search.rs:89` 会用 session prompt、last/running command 和 hint text 做 fuzzy search。
- `../../warp/app/src/search/command_search/view.rs:66` 的默认占位就是搜索 history、workflows 等更宽来源。

Ianvs：

- `lib/src/command_palette.dart:21` 已有 workflow/history/session/ssh/launch filter 与 source count。
- `_CommandPalettePanel` 已在 input-adjacent inline shell 中显示 source rail，让 Workflow、History、Sessions、SSH、Launch 的可用数量和点击筛选成为截图可见入口。
- session detail 已包含 prompt-ish context、cwd、target、last command、recency。

优化点：

- session search 的 prompt fidelity 还受 shell metadata 限制，后续应消费更完整的 prompt snapshot 或 flutterm shell hook metadata。
- Files、prompts、notebooks、conversations 等 Warp 类别不属于当前 Ianvs Terminal 本地能力，本轮不伪装为已支持 source。

### Pane / Session

Warp：

- `05_split_pane.png` 显示每个 pane 都有独立 header、close/overflow、pane-local context chips 和 input。
- `../../warp/app/src/pane_group/mod.rs:2372` 附近已把 pane 内 terminal sessions 作为 pane group 可遍历对象。

Ianvs：

- Ianvs 已有 pane local header、active marker、split/close/focus、drag handle 承载点、pane-local context chips 和 pane menu。
- pane menu 已支持把当前 split pane 移到新 tab，复用原 session，不重启 PTY。
- 缺口主要是完整 drag gesture 到 tab bar，以及更完整的 prompt/git 状态密度。

优化点：

- 后续若继续追 Warp split pane 操作，应补完整 drag/drop gesture，而不是把 pane 操作回流到全局 header。
- 每个 pane 底部的 cwd/git/session context 应保持独立，split 后不能只显示 active pane 的上下文。

### Settings / Verification

Warp：

- `../../warp/app/src/terminal/session_settings/new_session_shell.rs:23` 定义 new session shell。
- `../../warp/app/src/terminal/session_settings/startup_shell.rs:13` 定义 startup shell。
- `../../warp/app/src/terminal/session_settings/working_directory_config.rs:112` 支持 split/tab/window 分 source 的 cwd policy。
- `../../warp/app/src/integration_testing/mod.rs:5` 拆出 terminal、pane_group、launch_configs、navigation_palette、window、workspace 等 app-level harness。

Ianvs：

- Settings 已预留 session defaults，但行为接入仍浅。
- `test/demo_terminal_session_test.dart` 已开始作为桌面端 E2E harness，配合 launch config / warp alignment golden 和 `5%` 归一化像素 contract 形成基础验收。

优化点：

- 把 Settings 预留项接入实际 new tab / split / new window 行为，尤其是 cwd policy。
- 继续维护 manual Warp screenshot checklist，因为当前 Computer Use 不能直接控制 Warp；Ianvs 自身 UI 则继续用 Flutter golden 和 demo harness 验证。

## 改进优化点汇总

| 分组 | 当前结论 | 下一步 |
| --- | --- | --- |
| blocks | Ianvs 已有可见 block rail / card / panel，但不是 terminal-native block list。 | 推动 flutterm row-range divider / gutter / sticky header 扩展，产品侧只消费结构化 block metadata。 |
| 输入 / 补全 | 输入区已 editor 化，并在默认布局显示 input-adjacent context chips；`04_completion_input.png` 已改为 terminal pane-local contract，覆盖 block band、command/output body、actions、detection strip 和 input editor。 | 更深 prompt/git fidelity 依赖 shell metadata；completion candidate 下拉若有新的 Warp 基准图再补 dedicated rect contract。 |
| 命令搜索 | 已覆盖 workflow/history/session/ssh/launch，并在 palette 里显示 source rail 计数筛选；source rail 和 results top 已加入 5% rect contract。 | 后续补 session prompt snapshot fidelity；不伪装 Files / prompts / notebooks 等非当前产品能力。 |
| pane / session | split pane 视觉承载、pane-local menu、context chips、每 pane 底部输入区和 move-to-tab 行为已到位。 | 后续补完整 drag gesture 到 tab bar 和更高密度 prompt/git context。 |
| launch config | app-level schema 已对齐，UI 已有 name-first/save-success；compose / success 的 panel 与内部关键控件已有 5% rect contract。 | 把 `+` 菜单和 saved config discovery 继续固化为主入口，补 tab config 日常保存流。 |
| 桌面验证 | Ianvs 有 widget/real shell/golden/demo harness；default / completion / split 等 dedicated golden 已补齐；default block/input、completion input pane-local、command palette、session palette、add menu、split pane、saved config sidecar 已有 `5%` pixel contract；Computer Use 不能控制 Warp。 | 保留手动 Warp 截图清单；Ianvs 自身继续用 demo harness + golden + pixel contract 防退化。 |

## 复核命令

```bash
git -C ../../warp rev-parse --short HEAD
git -C ../../warp sparse-checkout list
rg "old Warp absolute path patterns" *.md docs AGENTS.md
```
