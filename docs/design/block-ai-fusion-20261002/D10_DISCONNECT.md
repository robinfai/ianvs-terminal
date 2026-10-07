# D10：真实 SSH 断线保留验收

2026-10-03，`composer` 工作区，macOS 27.0.1 (26A434)。本页记录实际传输中断后的保留与只读检查。后续已补齐重连主流程，见 [重连与旧任务衔接](D10_RECONNECT.md)；不能视为 D10 所有边界或全部 20 场景完成。

## 已修复的实际问题

1. 原生 SSH 把未收到远端退出状态的关闭默认为退出 0，导致真实断线被当作正常结束。现在仅采用收到的退出码；状态缺失作为传输失败报告 255。EOF 只结束数据流，继续等待退出状态/通道关闭。依据 [RFC 4254 §5.3、§6.10](https://www.rfc-editor.org/rfc/rfc4254.html#section-6.10)。真实 OpenSSH 的 `exit 7` 也已验证，确保未把正常非零退出误判为断线。
2. 失败 SSH 退出原先删除 native session 和 UI pane，连带销毁 Composer/AI。应用现在对 SSH 255 选择保留；运行时禁止原始输入、Composer 提交与补全，保留缓冲区、原提交回执和只读请求，用户显式关闭才释放。普通退出继续原有关闭行为。
3. 保留 pane 后，原界面仍会丢弃块视图并把 AI 切回文字记录。现在保留同一块 controller 和混合时间线，Normal 提供只读原终端，AI 的草稿、附件及任务保持。
4. 断线撤销旧提案和推理，不自动恢复。即使活跃终端已不可读，也可检查保留的 native receipt journal；确认输入接受不等于命令成功，终端不可用状态仍阻止恢复批准。
5. 只读终端仍需要应用快捷键，但不应连接手机输入法。共享视图增加显式 autofocus 选择，应用保留导航焦点；普通只读 reader 默认不抢焦点。回归同时验证 Cmd+数字切换和 iOS 主题下无 IME 连接。

## 实际流程与截图

1. 独立临时目录和密钥的 loopback OpenSSH，真实生产 native SSH/PTY；执行两次 `ls`，多级跳转、top/vim 后手动恢复 Blocks。
2. 通过生产 HTTP 客户端获得固定测试提案，人工测试操作批准一次。临时文件只写入一个 `x`，原 submission 对应唯一 block。
3. 再产生一条未批准提案，输入跟进草稿并附加原始证据。[断线前](evidence/ssh-disconnect/D10-before-transport-loss.png)。
4. 临时 TCP 中继关闭自己的连接，保持服务监听。真实 SSH 报告退出 255；旧提案变为已撤销，任务、原始块、附件、草稿都在。[断线后](evidence/ssh-disconnect/D10-retained-task-after-disconnect.png)。
5. 检查原提交回执仍为 accepted 且 block ID 不变；所有原生 block ID 保持，文件仍只有一个 `x`，HTTP 请求数不增加。调用批准/恢复也不会写入或请求模型。
6. 返回 Normal 可看完整终端历史，再打开 AI 恢复同一任务和草稿。[只读终端](evidence/ssh-disconnect/D10-readonly-terminal-after-disconnect.png)。

[原生断线逐项结果](evidence/ssh-disconnect/disconnect-result.json)、[完整 SSH 运行结果](evidence/ssh-disconnect/results.json)、[macOS 测试日志](evidence/ssh-disconnect/app.test.log)。

另有生产 Shell 的 macOS 1280×800 与 iOS 390×844 固定字号组件回归：[桌面](evidence/ssh-retention/D10-ssh-disconnected-macOS.png)、[手机](evidence/ssh-retention/D10-ssh-disconnected-iOS.png)。手机输出保持最多六行，附件范围和草稿可见，没有进行 iPhone 真机测试。

## 验证范围

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| 完整 AI、Shell、模式 | 616 项通过 | [日志](evidence/ssh-retention-regression.log) |
| SessionController、手机/桌面 Shell、AI 恢复 | 131 项通过；部分与上行重叠 | [日志](evidence/ssh-retention-app.log) |
| 共享运行时生命周期与事件 | 231 项通过 | [日志](evidence/ssh-retention-core.log) |
| 共享键盘与触控 | 21 项通过 | [日志](evidence/ssh-readonly-viewport.log) |
| 原生 SSH 单元测试 | 35 项通过 | [日志](evidence/ssh-native-unit.log) |
| 真实 SSH | 六组原生协议 + 一项完整 macOS UI 通过 | [结果](evidence/ssh-disconnect/results.json) |
| 应用及共享代码静态分析 | 无问题 | [应用](evidence/ssh-retention-analyze.log)、[共享包](evidence/ssh-retention-core-analyze.log) |

模型回复为隔离的确定性 fixture，不能证明模型质量。真实故障由中继切断连接造成，不是注入假的 Dart 退出事件。没有对用户 `cloud` 节点做断线、终止进程或写入；临时服务和密钥随测试退出清理。

复现：`PATH=/Users/robinfai/development/flutter/bin:$PATH python3 tools/ssh_boundary_lab/composer.py --bash /tmp/bash --disconnect-ui --output build/block-ai-fusion-20261003/ssh-disconnect`。

## 仍待整改

- 本页记录时尚缺的「重新连接并检查」入口与显式目标衔接，已在 [后续重连轮次](D10_RECONNECT.md) 实现；剩余边界与失败记录见该页。新连接不继承旧批准，不自动重发未知提交。
- 截图暴露的复合命令标题缺失已在后续轮次修复，并增加原生完整文本、取消后归属、长命令及真实 macOS UI 断言；见 [完整命令验收](COMPOUND_COMMANDS.md)。本页旧截图保留作为发现问题时的证据。
- 断线横幅沿用现有错误 UI；重连入口、重复状态提示和中英文文案需要随恢复流程一起完成最终设计复核。不能根据这些截图宣称 D10 视觉完成或 imagegen 未发现问题。
