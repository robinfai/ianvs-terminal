# D03/D05/D10：执行后保留完整命令

2026-10-03，`composer` 工作区，macOS 27.0.1 (26A434)。本轮修复此前真实断线截图发现的复合命令标题缺失；不代表 D10 重连衔接或全部 20 场景完成。

## 问题与修复

批准的输入是 `printf x >> disconnect-proof.txt; printf 'SSH_ONCE\n'`，原先 Block 标题只剩第一段。Bash 的 DEBUG 钩子拿到第一条简单命令；原生块投影忠实显示了这个不完整值，Flutter 省略号不是根因。

- Readline/ZLE 接受输入时，将同一份原始文本与 pending submission 一起保存。真正进入 preexec 后发出完整命令，消费一次并清除。SSH bootstrap 的发射函数同样处理，因此复用已有 shell 钩子也能采用新适配器的原始输入。
- 分号、多行、管道、条件执行、开头空格、末尾换行、引号、中文和 emoji 保留原值，不从显示行或历史记录拼接。关闭内存历史的六组真实 SSH 也通过。
- 已接受但停留在续行提示的输入被 Ctrl+C 取消后，在新的主提示符清除遗留的命令与 submission。后续手工输入不会冒领旧回执。
- Composer 接受 64 KiB，但块标题解析原先只接受 16 KiB，DCS 帧上限还未考虑 JSON 与十六进制编码的叠加。现在标题上限对齐 64 KiB，帧仍有明确上限；超限丢弃后下一条正常命令可恢复。
- 应用的独立协议观察器原先在分包尚未收齐且超过 4 KiB 时丢弃帧前缀。仅为 Ianvs shell hook 保留相应的有界完整帧，通用协议原有缓冲上限保持。完整帧一次到达与多包到达都有超限恢复检查。

## 验证

| 验证 | 结果与范围 |
| --- | --- |
| 修复前 | 新增完整标题断言后，真实 Bash/emacs 失败；[原始日志](evidence/compound-command/bash-emacs-before.test.log) |
| 原生库 | 416 通过、1 项独立 SSH 产品环境测试按原声明忽略；包含长标题、协议分包、超限恢复与 bootstrap 复用。[日志](evidence/compound-command/compound-core-regression.log) |
| 本地真实 zsh | 3 项通过，标题与原提交回执逐值一致。[日志](evidence/compound-command/compound-local.log) |
| 真实 SSH | zsh/bash、emacs/vi、直接 SSH/本地 ssh 共六组；复合/重复/嵌套命令、取消归属、17 KiB 标题及 exit 7 通过。[结果](evidence/compound-command/compound-final/results.json) |
| 关闭历史 | 相同六组使用关闭内存历史的 shell，通过同样断言。[结果](evidence/compound-command/compound-no-history/results.json) |
| macOS 生产 UI | SSH 连续命令、嵌套节点、top/vim、手动恢复 Blocks、实际传输中断保留任务全部通过；新增原生块完整标题断言。[日志](evidence/compound-command/compound-final/app.test.log) |
| 静态与镜像 | 更新的两份集成代码分析无问题；发布镜像无漂移；`git diff --check` 通过。[分析](evidence/compound-command/compound-analyze.log)、[镜像](evidence/compound-command/compound-mirror.log) |

已查看最终源码的 [断线后实际截图](evidence/compound-command/compound-final/D10-retained-task-after-disconnect.png)：Block 显示整条复合命令及 `SSH_ONCE` 输出，退出 0；未批准提案被撤销，原草稿和附件仍在。临时文件只有一个 `x`，原 submission/block ID 保持；[断线逐项结果](evidence/compound-command/compound-final/disconnect-result.json) 确认没有重发或新增模型请求。

实际 SSH 覆盖 17 KiB 输入；64 KiB 最坏转义边界由原生解析/投影测试证明，并非声称在各个远端 shell 上运行了 64 KiB 输入。测试回复为固定 HTTP fixture，不证明模型质量。本轮未访问用户 cloud，未做 iPhone 真机测试，也没有重新声称先前全部 Flutter 测试均已重跑。

复现命令：

```sh
env PATH=/Users/robinfai/development/flutter/bin:$PATH python3 tools/ssh_boundary_lab/composer.py --bash /tmp/bash --disconnect-ui --output build/block-ai-fusion-20261003/compound-final
python3 tools/ssh_boundary_lab/composer.py --bash /tmp/bash --history-off --output build/block-ai-fusion-20261003/compound-no-history
cargo test --offline --manifest-path native/core/Cargo.toml --lib -- --test-threads=4
cargo test --offline --manifest-path native/core/Cargo.toml --test composer_integration_test
```

## 后续

D10 仍缺少重新连接入口与任务向新连接的显式衔接。现有 `TerminalAiRuntime`、时间线块控制器和输入订阅都绑定原 session；不能只换 tab 或把旧 block ID 当作新 session 的证据。实现需要同时保留原生历史/回执来源、读取新目标、重新确认执行目标，并阻止旧批准或未知提交被自动重发。最终场景视觉审计继续按 IMPLEMENTATION.md 的完整矩阵推进。
