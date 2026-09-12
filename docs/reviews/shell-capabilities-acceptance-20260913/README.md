# Shell 能力自动化验收

2026-09-13 验收通过。本次使用当前工作区代码运行原生与应用测试、真实 OpenSSH 夹具，并直接操作正在运行的 Trail Development 完成本地 Zsh → Bash → Zsh 的界面验证。未发现需要修改产品代码的问题；本次仅补充验收用例、逐项证据与报告。

## 结果

| 验收层 | 结果 | 证据 |
| --- | --- | --- |
| 原生完整回归 | 390 项通过；默认忽略的 SSH 产品测试另行运行通过 | [日志](native-test.log) |
| Flutter 状态、界面、配置、SFTP、诊断导出 | 219 项通过 | [日志](app-test.log) |
| 真实 OpenSSH | 26 个场景通过，其中 24 个场景验证全部 7 项能力，另 2 个确认降级 | [逐项证据](product/capability-evidence.json)、[验收日志](product/product-test.log) |
| 正在运行的开发版 | 初始化、命令执行、切 Bash、子层执行、父层恢复、清理均通过；无运行时错误 | [界面操作结果](live-ui-results.json) |

## 逐项能力

以下 7 项在 24 个真实 SSH / 子 Shell 场景中均通过初始化检查与运行事件核验。每个场景执行 `false` 和 `true`，分别确认退出码 1 和 0；运行数据来自产品原生传输，不是测试伪造的协议事件。

| 能力 | 运行验证 |
| --- | --- |
| 当前目录 | 返回提示符后收到当前 context 的有效绝对路径 |
| 提示符生命周期 | 命令结束后收到 precmd |
| 命令开始执行 | 收到对应命令的 preexec，位于完成事件之前 |
| 命令文本 | 开始、完成事件均匹配实际输入的命令 |
| 命令执行结束 | 收到相同 context 与命令的 command_finished |
| 退出码 | false 为 1，true 为 0 |
| Shell 类型 | 开始与结束事件的 Shell 类型与初始化结果一致 |

开始输入前没有 preexec / command_finished；全部内置能力的注册结果已确认。九种直连场景还核对了 Ready 检查结果出现在 Connected 提示之前。

主机名、用户名、集成版本、提示符跳转、命令输出区域、自定义变量这 6 项扩展在未收到相应数据时保持待确认。它们的事件判定、坐标约束与策略覆盖由 Flutter 自动化用例验证；不声称内置 Hook 已在真实 Shell 中提供了这 6 项扩展。

## 连接与边界

- Bash、Zsh、Fish 根 Shell 及连续 Bash → Zsh → Fish 均逐项通过。
- 本地 SSH 包装与协议 SSH 两条 A → B → C 路径均通过；A/B 不提供 SFTP，C 提供 SFTP。
- 在 C 切换 Zsh，文件请求仍固定到 C；上传覆盖、返回上层及拒绝访问已退出目标通过。
- 已有 ControlMaster 保留，文件传输没有改连其他端点。
- 预装 Hook 复用、陈旧标记修复、只读 HOME、严格历史配置通过。
- 第三方 DEBUG 冲突及不支持的 sh 正确降级；关闭注入不产生 Bootstrap 回执。
- 各层历史不包含注入正文，并有真实命令的正向对照；[产品检查结果](product/results.json)。

首次扩展验收误把只在夹具内部开放的 B 当作可直连节点，因没有宿主映射端口而失败。已按实际拓扑改为经 A 进入 B，完整重跑通过；这是测试配置修正。[首次日志](fixture-port-correction.log)

## 界面与可复现性

实时开发版创建独立标签页，未输入命令就显示 7 / 13 项已激活；命令相关 4 项的依据为初始化检查。输入 false 后升级为真实事件。进入 Bash 后重新检查，退出恢复 Zsh 的运行证据和本地主机链路。最后通过标签页菜单清理测试标签页，原用户标签页保留。没有启用 Driver 或重启应用。

以下图片来自自动化 Flutter widget 渲染，用于检查布局状态，不作为真实 SSH 运行数据的证据：[明色桌面](screenshots/desktop-light.png)、[暗色窄屏及 2 倍字体](screenshots/compact-dark.png)、[链路选定布局](screenshots/selected-design.png)。图片已实际检查，滚动和关闭行为由对应自动化用例验证。

[机器可读汇总](summary.json) · [本次源文件哈希](source-hashes.json)

本次提交的 Shell/SSH 验收日志统一了换行并清理行尾空白，保留原测试输出内容。

运行入口：`cargo test --manifest-path native/core/Cargo.toml --lib -- --test-threads=1`；真实 SSH 使用 `python3 tools/ssh_boundary_lab/product.py --context colima --output <证据目录>`。应用用例范围见 app-test.log，截图使用 IANVS_CAPABILITY_CAPTURE_DIR。
