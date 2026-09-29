# Warp 常见本地命令体验与 Composer 对齐记录

状态：**已补充官方视频观察；本机 Warp 对照与对齐验收仍未完成**。记录日期：2026-09-29。

用户随后把当前目标改为按已观察的视频实现交互与 UI；该轮实现和 Composer 验证
见[视频对齐实现](WARP_VIDEO_ALIGNMENT_20260929.md)。本文件保留此前本机 Warp 对照的
完整矩阵与访问限制，不把旧目标的访问阻塞当成新实现工作的阻塞。

目标是通过真实 Warp 操作记录来改进 Composer。当前准备的用例、官方文档和
Composer 测试不能代替 Warp 实测，也不能据此宣称两者交互一致。

用户随后指定查看官方视频。现已播放四段官网内嵌演示，记录了补全、文本编辑、
历史和行内建议的可见行为，详见[官方视频观察](WARP_VIDEO_REVIEW_20260929.md)。
视频来源、时间点、截图及没有确认的行为分别列出；下面的本机 18 项矩阵仍保持待验收。

## 访问与证据

本轮通过电脑工具选择 Warp 时，工具返回：

> Computer Use is not allowed to use the app 'dev.warp.Warp-Stable' for safety reasons.

因此没有获取 Warp 窗口、版本、输入模式、快捷键设置或截图，也没有向 Warp
发送命令。此限制来自电脑工具，不是应用没有安装，也不是用户尚未同意操作。
官方公开视频可继续提供交互参考。本机对照仍需访问条件改变，或用户提供按下述
步骤录制的画面。

随后在自动续跑中复核访问时，自动审批再次拒绝，明确指出重复获取该应用属于绕过
已有访问限制。不要再以其他应用名称、间接执行、备用自动化方式或重复调用尝试访问
Warp。在访问限制没有明确改变前，仅有“继续目标”不解除本机访问阻塞；用户新指定
的官方视频研究可独立推进。

Composer 基线：`composer` 分支 `3eabbab7`。检查源代码与现有回归入口：

- [编辑器、候选与按键](../../packages/ianvs_terminal/lib/src/composer/terminal_composer_view.dart)
- [请求生命周期、Tab 与提交](../../packages/ianvs_terminal/lib/src/composer/terminal_composer_controller.dart)
- [本地目录与 scripts provider](../../native/core/src/completion_host.rs)
- [本地补全上下文](../../native/completion_core/src/lib.rs)
- [组件回归](../../packages/ianvs_terminal/test/composer/composer_test.dart)
- [真实应用回归](../../example/integration_test/composer_acceptance_test.dart)
- [真实 zsh 合同回归](../../native/core/tests/composer_integration_test.rs)

当前代码存在不代表新一轮实测通过；下面明确区分已覆盖行为与待补证据。

## 文档参考，不是实测

2026-09-29 查阅的官方 [Tab completions](https://docs.warp.dev/terminal/command-completions/completions/)
说明 Tab 可唤起命令、选项、路径候选，并支持模糊匹配；也提供输入时自动展开的设置。
文档包含本地 Git 分支和别名补全示例。它没有证明本机 Warp 的设置或具体按键行为。

原视觉参考为 [Universal Input](https://docs.warp.dev/terminal/input/universal-input/)。
该页面当前标记为 Legacy，站内另有 Classic Input。实测开始时必须记录实际输入模式；
保留用户要求的 Universal Input 对齐目标，不因文档命名变化改换设计目标。

## 可重复的本地样本

在仓库根目录执行：

```sh
python3 tools/composer/create_experience_fixture.py --parent /private/tmp
```

脚本创建唯一临时目录并输出进入命令。两个应用都使用该目录和本地 zsh。
样本包含两个 `do` 开头的目录、同前缀普通文件、带空格的嵌套目录、中文文件、
隐藏目录、三个 package scripts，以及有三个分支的独立 Git 仓库。
不安装依赖，不修改用户 shell 配置，也不使用业务项目的数据作为演示样本。

## 实测步骤

每项开始前回到样本根目录和空输入框。记录 Warp 版本、shell、输入模式、窗口宽高、
主题、Tab 设置、自动候选设置。每项至少保留“操作前、候选/编辑中、接受或提交后”
三个关键状态；按键序列要包括 Tab/Enter/Esc 的次数，避免把接受候选误记为执行命令。
截图命名为 `01-warp-before.png`、`01-warp-menu.png` 等；Composer 使用同编号对应图。

以下 **18 项 Warp 观察均待完成**，没有用推测填入结果。

| 编号 | 操作 | 要记录的交互 | Composer 当前证据 / 差距 |
|---|---|---|---|
| 01 | 打开空输入区，键入 `pwd`，Enter | 输入位置、上下文、提示、执行后焦点、输出与草稿边界 | 有停靠编辑器和提交后焦点测试；需同状态画面对比 |
| 02 | `ls ./` → Tab → ↓ → Tab / Enter | 菜单位置、默认选中项、排序、按键是否仅接受 | 已有真实应用用例；Warp 的接受/执行键序列待观察 |
| 03 | `ls ./docu` → Tab → Tab | 唯一候选、尾随 `/`、连续进入子目录 | 已有唯一/连续目录及空格转义测试 |
| 04 | `cd do` → Tab | 目录与普通文件的筛选、多个候选 | provider 只接受 folders；需 UI 实测 |
| 05 | `cat he` → Tab；`cat 中` → Tab | 空格和 Unicode 的显示、插入、光标位置 | 空格文件已有应用用例；中文路径需实测 |
| 06 | `ls ./` 与 `ls ./.` 分别 Tab | 隐藏目录何时出现 | provider 根据输入前缀决定隐藏项；需 UI 实测 |
| 07 | `ls ../`、`ls /private/tmp/`、`ls ~/` 分别 Tab | 父级、绝对、home 路径的范围和反馈 | 当前 provider 明确不支持这三种范围，尚未对齐 |
| 08 | `ls ./dcm` → Tab | 非连续字符匹配、匹配高亮、排序 | 本地 provider 仅前缀匹配，尚无路径模糊匹配 |
| 09 | `git st`、`git --v` 分别 Tab | 子命令/选项说明、可用宽度、接受后空格 | 静态 catalog 已有；显示与插入细节待实测 |
| 10 | `git checkout feat` → Tab | 分支名称、分支类型、是否需要网络 | 当前仅迁移静态 catalog，没有动态 Git 分支 provider |
| 11 | 执行 `alias ll='ls -l'`，再输入 `ll ./` → Tab | alias 展开后是否仍有相同候选 | 已有会话 alias 名称和定义说明；仍不展开 alias 参数上下文 |
| 12 | `npm run te` → Tab | script 名称、说明、候选接受 | 已有有界 package.json 读取；需与 Warp 同状态对比 |
| 13 | 输入 `git sta --short`，将光标放在 `sta` 后 Tab | 中间替换、右侧参数保留、撤销后光标 | 已有组件/应用回归；需 Warp 对照 |
| 14 | 依次执行 `printf 'first\n'`、`printf 'second\n'`，↑/↓/Ctrl+R | 历史顺序、按前缀过滤、退出后恢复原草稿 | 已有会话历史、过滤、选择、取消恢复及真实应用回归；Warp 同条件对照仍待完成 |
| 15 | `printf 'one\n'`，Shift+Enter，再输入 `printf 'two\n'` | 多行高度、换行键、粘贴换行、一次提交、撤销 | 有多行/IME/提交回归；真实输入与视觉仍待对照 |
| 16 | 编辑中 Ctrl+C；执行 `sleep 10` 后 Ctrl+C | 清空草稿与中断运行如何区分、焦点落点 | Composer Ctrl+C 仅清草稿；运行输入需回原终端，需对齐体验 |
| 17 | 执行不存在的 `composer_fixture_missing`；执行 `printf 'line %s\n' {1..40}` | 错误、输出滚动、输入区是否遮挡、恢复编辑 | 保留原终端输出；尚无同状态 Warp 比较 |
| 18 | 两个窗格保留不同草稿，切换后恢复；缩窄窗口 | 会话隔离、候选归属、焦点、菜单裁切与键盘可达性 | 有隔离、窄窗和 2x 字号组件回归；需真实窗格画面对照 |

## 对齐工作队列

按上述证据，先前 Tab 开关问题已修正，但不能把它视为这次 Warp 对齐已经完成。
以下工作保留在本目标内，实测后补充行为细节与实现验收：

1. 记录上述实际交互，尤其 Tab / Enter / Esc、默认选中、尾随空格和路径续补。
2. 对齐历史召回、常见路径、模糊匹配、Git 分支和 alias 的本地工作流。
3. 对齐运行中中断、输出滚动、光标与焦点恢复；保留命令只在明确提交时执行。
4. 用同窗口尺寸和输入状态检查 Universal Input 的布局、提示与候选菜单。
5. 每个差异都关联代码修改、回归用例和 Composer 实际运行证据。

当前访问限制不授权绕过电脑工具，也不构成将本目标缩减为“查文档”的理由。

## 完成判据

- [ ] Warp 版本、输入模式、相关键位设置与所有步骤的真实结果已记录。
- [ ] 每项有有效画面或用户提供的同一步骤记录，并能与 Composer 的实际行为对照。
- [ ] 确认的差异已落实到 `composer` 分支；每项有实现或用户明确接受的取舍。
- [ ] 行为回归、适用的构建检查和真实应用操作通过。
- [ ] 体验记录中的截图、键序列和结论一致，不用代码测试代替 Warp 实测。

目前这些完成判据尚未满足。此前本机访问阻塞已持续三个目标回合，目标因此标记
为阻塞。用户随后指定的官方视频研究已取得独立进展；体验清单、样本及视频证据
均已准备，保留全部对齐范围，不宣称本机体验或实现验收完成。
