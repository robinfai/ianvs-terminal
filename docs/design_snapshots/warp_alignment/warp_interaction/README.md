# Warp Interaction Notes

日期：`2026-05-04`

这些截图由用户在本机 Warp 中手动完成，用于 Ianvs Terminal 的交互对齐观察。Computer Use 对 `dev.warp.Warp-Stable` 被安全策略拒绝，所以本目录不是自动化截图基线；Ianvs 自身的 golden 仍保存在上级目录。

## 有效截图

- `01_terminal_blocks.png`：terminal block、prompt/cwd/git 状态、底部 input editor。
- `02_block_not_hover_click_actions.png`：block inline actions 贴近 terminal 内容出现。
- `03_command_search.png`：统一搜索入口包含 workflows、prompts、notebooks、environment variables、files、sessions、launch configurations、conversations 等类别。
- `04_completion_input.png`：输入区识别 shell command，并提示可覆盖自动检测。
- `05_split_pane.png`：split pane 后每个 pane 都有独立 header、context chips 和输入区。
- `06_tab_or_launch_config_entry.png`：顶部 `+` 菜单集中 tab、agent、shell selector 和 launch config 入口。

## 对 Ianvs 的直接启发

- Blocks：inline actions 应靠近 active block，本体分组要继续向 flutterm row-range / divider / sticky header 推进。
- Palette：Ianvs 已有 saved/history/session/ssh，下一步应补 launch config 和 workflow-like saved command source。
- Input：completion 需要更明确的候选列表、来源标签和选择态；可增加 command type/autodetect 状态。
- Pane：split 后每个 pane 的 header、context chips、输入区都应保持独立，后续补 drag/drop 到 tab bar。
- Launch config：`+` 菜单是高价值主入口，应继续承载 tab config / app config / saved config discovery。

`01_initial_window.png` 是自动化探测阶段的失败截图，不作为有效对比样本。
