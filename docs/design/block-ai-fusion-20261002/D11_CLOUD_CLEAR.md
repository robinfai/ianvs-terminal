# D11 cloud 实测与 D12 主屏清屏修复

2026-10-03，当前 `composer` 工作区，macOS 27.0.1（26A434）。这次使用用户指定的本机 `ssh cloud` 配置解析连接参数，通过生产 Trail 原生 SSH 连接实际 Linux Bash 节点。它补充此前 loopback 证据，不把模拟节点称为 cloud。

## cloud 暴露的真实缺陷

首次真实验收中，两次 `ls` 均生成独立且退出 0 的块，手动切换 Normal 保留输出，top/vim 也占据完整终端。但退出 TUI 后，两条 `ls` 块消失。[等待刷新后的失败日志](evidence/cloud-clear/cloud-read-only-native-verified.log)确认原生快照只剩 Vim，排除了 Flutter 轮询尚未更新的解释。

原因是 Linux procps top 使用主屏重绘，第一次发送 ED 2（清可见屏幕）时，`Grid.clear()` 同时清空了语义命令边界。其行为比清可见屏幕更强，连之前已经完成的块也一起丢失。新的[原生复现](evidence/cloud-clear/cloud-clear-reproduction.log)在两条完成命令后模拟主屏清屏，同样失败。

修复在原生网格完成：主屏清屏前，如果当前可见区域仍含已完成的命令输出，将这屏真实字符单元送入现有、有上限的滚动历史；清空可见屏幕后保留仍有效的历史边界和当前命令边界。没有建立 Flutter 输出副本。后续 TUI 重绘没有新的已完成输出，不重复追加整屏历史。alternate screen 的清屏逻辑保持原样，显式清历史（ED 3）和终端重置仍可释放历史；禁用 scrollback 时也不额外缓存输出。

## 实际节点结果

最终流程先在独立会话取消历史文件路径并进入 `/`，再执行受控中文 `printf`、两次 `ls`、Linux `top -d 1` 和无配置／无交换文件的 Vim。没有编辑远端启动配置；云端没有运行故障注入。连接沿用已有密钥文件引用和严格主机密钥校验，临时配置与密钥内容不进入归档。

- 两次 `ls` 对应两个不同的原生块，退出码均为 0。Normal→Blocks、top→手动 Blocks、vim→手动 Blocks 后，逐值核对两块的 ID、命令、原输出、退出码、总行数和来源行基准，全部保持。
- top/vim 的可见终端均为 **1728×1002px、44 行×203 列**。行列期望由真实字体单元与可用空间计算，等待远端 resize 回传后核对；没有用默认 PTY 的启动尺寸充当期望。
- TUI 退出后仍为 Normal，由 tab 右键手动恢复 Blocks。同一 session 和节点 context 保持，不新建第二个 PTY。
- 直接查看[恢复后的块](evidence/cloud-clear/cloud/ssh-cloud-restored-blocks.png)、[Vim 全屏](evidence/cloud-clear/cloud/ssh-fullscreen-vim.png)和[手动恢复菜单](evidence/cloud-clear/cloud/ssh-mode-menu.png)，并对照 [D11 设计](screens/D11-v2.png)：模式入口位于原 tab 菜单，普通终端和命令块各自保持原有布局。这里展示的是能力已恢复状态，不冒充设计中的嵌套节点未协商状态。

完整结果见 [cloud-result.json](evidence/cloud-clear/cloud/cloud-result.json)和[最终日志](evidence/cloud-clear/cloud-read-only-native-final-verified.log)。实际 cloud 覆盖直接原生 SSH；多级跳转和认证／断线故障由下述隔离环境验证，没有对真实 cloud 断网或更改凭据。

## 回归与边界

- 原生库 [418 项通过、1 项忽略](evidence/cloud-clear/cloud-clear-native-regression.log)。忽略项是另一套需要 `product.py` 专用 fixture 的 bootstrap 验收，本页不声称执行了它。11 项命令块专项属于这 418 项，包括同一输出快照、五次重绘不增长历史、alternate screen 往返、历史容量、ED 3 和零 scrollback。
- 底层 VT [49 项清屏相关测试](evidence/cloud-clear/cloud-clear-vendor-tests-direct.log)通过。
- 新原生库的[完整 AI／PTY 场景和四组手机组件](evidence/cloud-clear/cloud-clear-workspace-native.log)共 5 项通过，包括 reader 选区／引用、HTTP 恢复、静默与持续输出、Vim 输入交接及配置保存。
- [六组真实 loopback OpenSSH](evidence/cloud-clear/cloud-clear-ssh-lab-final.log)通过：zsh/bash、emacs/vi、原生 SSH／本地 ssh。另有完整 macOS 多级跳转、top/vim、断线重连、认证失败与恢复通过。[断线结果](evidence/cloud-clear/loopback/disconnect-result.json)确认实际执行后丢失回执，重连检查仍 unknown，执行证明只有一个 `z`，模型请求保持 6 次，没有重发。
- 新增网格断言曾在 resize 尚未回传时失败（32／38 行旧快照），日志保留。现在按已有 native 测试方式等待精确的 44×203，不移除或放宽行列要求。这与前述实际历史丢失是两类问题。
- 最终静态分析、镜像检查及 diff 检查通过。[27 项证据、8 个源码哈希](evidence/cloud-clear/manifest.json)已验证。没有实体 iPhone 测试、外部模型请求、提交或推送。

## 复现

从根目录执行 `cargo test --offline --manifest-path native/core/Cargo.toml --lib` 和 `cargo test --offline --manifest-path native/vendor/par-term-emu-core-rust/Cargo.toml --lib clear`。隔离 SSH 使用 `python3 tools/ssh_boundary_lab/composer.py --bash /path/to/bash --ui --disconnect-ui --output /absolute/evidence/path`。

真实节点用 `example/integration_test/ssh_composer_acceptance_test.dart`，通过 `COMPOSER_SSH_FIXTURE` 指定本地私有配置文件，设置 `cloudReadOnly: true`、`lsOutput: "usr"` 和实际 SSH connection；通过 `BLOCKS_NATIVE_EVIDENCE_DIR` 指定证据目录。该路径只适用于具有 Linux top、Vim 的已授权 Bash 节点，不自动探测或修改用户其他主机。

这轮补齐实际 cloud 节点和清屏后历史保留，整体目标仍需最终 20 场景审计，以及设计合同中高对比、减少动态效果和实际辅助技术的独立核验。
