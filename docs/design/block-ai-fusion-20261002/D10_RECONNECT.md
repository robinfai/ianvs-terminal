# D10：重连与旧任务衔接

2026-10-03，当前 composer 工作区。验证系统为 macOS 27.0.1 (26A434)；手机使用固定字号的 iOS 生产组件渲染，没有进行 iPhone 真机测试。本文补充 [断线保留](D10_DISCONNECT.md)，不代表 D10 所有边界或全部 20 场景完成。

## 已实现

- 失败 SSH 会话提供「重新连接并检查」。读取原提交回执后，用原会话的 profile snapshot 创建新 native session，旧会话继续保留供检查；重复点击不重复建连。
- 同一个 AI controller、taskId、原始目标、记录、附件和两份输入草稿转入新连接。旧批准撤销，重连不发模型请求或重放命令。
- 每条提交绑定原连接。即使不同连接出现相同 submission/block ID，也查询原 endpoint。未知回执仍阻止继续；确认原结果后，要显式选择当前目标，模型提出的新命令仍须单独批准。
- 同一时间线继续读取旧连接的真实 native block。展示层按连接区分 ID，原生请求仍使用原始 ID。手机 reader 的滚动位置、四个选区坐标和附件来源在重连后保持。
- 迁移最后成功的过滤条件，同时保留当前过滤草稿和错误，避免非法正则草稿覆盖原阅读范围。

## 本轮发现并修复

1. 手机关闭最后一个重连会话时，淡出动画中的 CommandBlocksPane 会重新挂载已释放的原始 viewport。现在在定时刷新和 build 时检查当前 runtime viewport 身份，结束生命周期的视图不再复用缓存子控件。保留 [修复前异常](evidence/ssh-reconnect/reconnect-mobile-before-lifecycle-fix.log)。
2. 已退出但保留的 SSH 会话仍响应布局 resize，向失效连接发窗口请求，导致重连成功后出现全局操作错误。保留会话现在拒绝 viewport/cell resize，历史网格维持原尺寸。真实应用断言重连后 lastError 和各 pane runtimeError 均为空，没有通过清空无关错误隐藏故障。
3. 两轮 SSH 验收在返回本地 zsh 后的 17KB 命令准备阶段失败：[第一轮](evidence/ssh-reconnect/reconnect-ui.log)、[第二轮](evidence/ssh-reconnect/reconnect-ui-second.log)。逐字节切片/拼接的解码成本随长度迅速增长，本机测量 17KB 约 1.15 秒、64KB 约 15.5 秒，超过 1.5 秒准备期限。改为每 1024 个十六进制字符一次的有界替换，期限、lease 检查、单次唤醒和未知回执规则不变。真实 zsh 验证 17KB/64KB、跨片 UTF-8、字面反斜线和命令替换文本、完整块标题及重复请求只执行一次。
4. Dart 块解码仍有旧 16KB 字符限制，现与 native 的 64KiB UTF-8 字节限制一致，测试包含 ASCII/emoji 边界和超一字节拒绝。
5. 原生 ProxyCommand 测试等待 PID 文件存在后立即解析，偶尔读到尚未写入的空文件。测试脚本现完整写入临时文件后同目录 rename，原进程回收断言保持。第二次并行全量运行另遇 ZMODEM ResourceLimit；未修改其生产资源上限，完整顺序运行通过。两个并行失败日志均保留。

## 实际重连链路

隔离临时 HOME、密钥与 loopback OpenSSH，实际生产 SSH/PTY；模型传输使用确定性 HTTP fixture。

1. 原命令向临时 proof 文件写一个 x；生成另一条尚未批准提案，输入跟进草稿并附加原始输出。
2. 中继切断实际传输，原会话保留，未批准提案撤销。原 receipt 和 block 仍可读取。
3. 点击重连，创建新 session；任务和草稿保持、原 proof 仍为 x、HTTP 数不增加。
4. [新连接目标选择](evidence/ssh-reconnect/D10-reconnected-target-choice.png)：同名同目录也明确说明这是新连接，旧输出继续作证据。
5. 明确选择当前目标后只获取新提案；新 proof 尚不存在。单独批准后写一个 y，原文件仍只有 x；两条 accepted 各自指向不同 session。
6. [新命令完成](evidence/ssh-reconnect/D10-reconnected-new-command-approved.png)：原失败/撤销记录保持，新执行形成自己的真实块。

[逐项结果](evidence/ssh-reconnect/disconnect-result.json)、[六组 SSH 总结果](evidence/ssh-reconnect/results.json)、[实际应用日志](evidence/ssh-reconnect/app.test.log)。

手机生产组件另验证：双击重连只建一个新会话；关闭旧会话后当前 AI 保持，关闭新会话无已释放控制器异常；触控阅读、选择后重连，再次打开旧输出保持位置与选区，再附加仍标原会话来源。截图：[手机重连](evidence/ssh-reconnect/D10-ssh-reconnected-iOS.png)、[恢复原选区](evidence/ssh-reconnect/D10-reconnected-reader-selection.png)。

## 验证

| 范围 | 结果 | 日志 |
| --- | --- | --- |
| AI、Shell、SessionController（含 19 项手机流程） | 718 项通过 | [应用](evidence/ssh-reconnect/reconnect-app-verified.log) |
| 共享 runtime、块解码、时间线 | 258 项通过 | [共享](evidence/ssh-reconnect/reconnect-core-verified.log) |
| 本地真实 zsh | 4 项通过，含 17KB/64KB 字面命令 | [本地](evidence/ssh-reconnect/reconnect-long-local.log) |
| 原生全部单元测试 | 顺序运行 416 通过、1 忽略 | [顺序](evidence/ssh-reconnect/reconnect-native-unit-serial.log) |
| 原生并行运行诊断 | 两轮各有一个失败，不能写成并行全量通过 | [PID 发布竞态](evidence/ssh-reconnect/reconnect-native-unit.log)、[ZMODEM 资源上限](evidence/ssh-reconnect/reconnect-native-unit-fixed.log) |
| 真实 SSH / macOS | 六组协议测试及一项完整应用集成通过 | [总日志](evidence/ssh-reconnect/reconnect-ui-fixed.log) |
| 应用最新源码与相关测试分析 | 无问题 | [静态分析](evidence/ssh-reconnect/reconnect-analyze-verified.log) |
| 共享运行时、块解码及相关测试分析 | 无问题 | [共享静态分析](evidence/ssh-reconnect/reconnect-core-analyze.log) |

复现 SSH：仓库根目录执行 PATH=/Users/robinfai/development/flutter/bin:$PATH python3 tools/ssh_boundary_lab/composer.py --bash /tmp/bash --disconnect-ui --output build/block-ai-fusion-20261003/reconnect-ui-fixed。

原生全量命令：cargo test --offline --manifest-path native/core/Cargo.toml --lib -- --test-threads=1。

## 追加：多次重连、大量历史与 SSH 配置入口

- 原聚合列表把多个连接各自的 128 块窗口再次裁成总共 128 个，旧连接的卡片、书签和 reader 状态会提前丢失。新增回归先复现 [只剩 128 个块](evidence/ssh-reconnect-extended/reconnect-history-before.log)，再调整为每个来源单独限制 128 个；组合 controller 接收完整合并列表，普通单连接 controller 的默认上限不变。
- 三个连接使用相同原生 block ID，各自返回 129 项超额 fixture，合并后保留 384 个唯一展示引用。最早来源的阅读锚点、过滤条件、书签不丢；逐一复制各来源的 block-0 得到不同的原始文本；显式关闭中间连接后只移除其 128 项。此项为协议/控制器证据，未声称真实网络生成了 384 个命令。
- 再次继续任务发给模型的 original_submissions 现在附带 source_session_id 和 source_context_id，避免模型把历史提交误认成当前连接的提交；回执检查仍固定到原 endpoint。
- 实际 macOS 流程扩展为四个 native session：首次连接 → 断线后重连 → 再次断线且公钥认证拒绝 → 恢复认证后的重连。拒绝认证仅通过临时测试服务的 authorized-key 文件实现，并在 finally 中恢复；没有修改个人密钥。两次已经批准的命令始终分别只写一个 x/y，原回执分别指回原连接，认证失败与重连不产生额外模型请求或命令重放。
- 认证失败页增加「SSH 连接设置」，使用现有生产连接编辑器，原会话配置填入表单。取消保留原任务/草稿，不修改旧连接。明确点击「连接」才用编辑后的同一 profile ID 创建新连接；用户若选择保存则沿用现有保存与失败反馈。SessionController 回归验证修改后的连接用于新 session，旧 profile snapshot 不变，拒绝另一个 profile ID 的替换。
- 手机与桌面生产 Shell 验证连续点击设置只开一个页面，编辑后取消不建连、不丢附件；真实 macOS 验证认证失败 → 打开设置 → 取消 → 再次打开并明确连接 → 恢复。手机固定字号；没有真机测试。
- 不可用连接不再展示空的目标比较卡片；读取新连接成功后才要求显式选择执行目标。「重新连接并检查」使用主题主按钮，检查状态、返回终端和设置保留次级操作。

证据：[四连接与认证恢复逐项结果](evidence/ssh-reconnect-extended/disconnect-result.json)、[认证失败界面](evidence/ssh-reconnect-extended/D10-reconnect-authentication-failed.png)、[SSH 设置](evidence/ssh-reconnect-extended/D10-reconnect-ssh-settings.png)、[恢复后目标选择](evidence/ssh-reconnect-extended/D10-reconnect-after-authentication-recovery.png)、[手机设置页面](evidence/ssh-reconnect-extended/D10-ssh-settings-iOS.png)。

本轮验证：[719 项应用回归](evidence/ssh-reconnect-extended/reconnect-repeated-regression.log)、[140 项定向回归](evidence/ssh-reconnect-extended/reconnect-settings-tests.log)（属于前者子集）、[28 项共享块/时间线回归](evidence/ssh-reconnect-extended/reconnect-history-core.log)、[应用分析](evidence/ssh-reconnect-extended/reconnect-settings-analyze-final.log)、[共享分析](evidence/ssh-reconnect-extended/reconnect-history-core-analyze.log)。六组真实 SSH 和完整 macOS 流程结果位于 [results.json](evidence/ssh-reconnect-extended/results.json)。

## 追加：实际执行后丢失回执

在同一隔离 SSH 验收中增加第五个 native session，使用生产提交协议和真实 shell。中继收到原子发布的控制请求后暂停读取服务端返回数据，但继续转发客户端输入；不修改或解析加密 SSH 数据。独立 loopback 测试验证暂停期间输入可达、恢复可取回暂缓数据、断线丢弃未送达数据、新连接不继承暂停。

1. 在第四个连接上单独批准 `printf z >> unknown-proof.txt; printf 'UNKNOWN_ONCE\n'`。中继已经确认暂停返回数据，测试独立读取临时 HOME 中的 proof 文件，确认远端确实写入一个 z。
2. 此时应用原生 receipt 仍为 pending，blockId 和 exitCode 为空。切断实际 SSH 连接后，界面保留 unknown，未伪造失败、成功或一个真实输出块。
3. 明确点击重连，创建第五个连接；仍查询第四个连接上的原 submission。点击「检查原提交」后原 receipt 为 unknown，继续/批准不可用。测试再调用控制器的继续与批准也不发命令。
4. proof 始终只有一个 z；模型请求数从故障前到重连检查后均为 6。原 x/y 文件不变，原任务、待发送草稿和附件保持。

[原始 pending/unknown 回执和执行次数](evidence/ssh-unknown-receipt/disconnect-result.json) 保留原 submissionId 与来源 sessionId；[六组 SSH 结果](evidence/ssh-unknown-receipt/results.json) 和 [macOS 应用日志](evidence/ssh-unknown-receipt/app.test.log) 均通过。

截图发现了真实文案缺陷：[修正前](evidence/ssh-unknown-receipt/before-copy-fix-D10-executed-without-receipt-disconnected.png) 把输入已经可能发出的未知结果描述为「提案已失效」。现在卡片明确说明可能已经执行，不能再次发送；新目标提示同样先要求核对原回执。未知期间发送按钮禁用，Enter 保留原始草稿且不发模型请求；原回执确认后恢复发送。原审批/重发阻断逻辑保持，修正的是界面的准确性和操作状态。

实际最终截图：[断线后未知结果](evidence/ssh-unknown-receipt/D10-executed-without-receipt-disconnected.png)、[重连检查后仍未知](evidence/ssh-unknown-receipt/D10-unknown-original-receipt-after-reconnect.png)。手机固定字号生产组件：[中文完整卡片](evidence/ssh-unknown-receipt/D10-unknown-card-zh-phone-true.png)、[英文恢复操作](evidence/ssh-unknown-receipt/D10-unknown-recovery-en-phone-true.png)。四组中英文/桌面/手机回归核验状态文案、禁用操作、Enter 不清理草稿、不重发；现有用例验证 receipt 转 accepted 后恢复入口。手机截图还发现短命令固定预留三行，现改为一至三行自然高度，完整审阅入口不变。不是 iPhone 真机证据。

验证：[723 项应用回归](evidence/ssh-unknown-receipt/unknown-receipt-app-final.log)、[49 项 workspace 最终组件回归](evidence/ssh-unknown-receipt/unknown-receipt-components-final.log)（前者子集，均在手机预览高度调整后复验）、[中继单向故障测试](evidence/ssh-unknown-receipt/unknown-relay-test.log)、[静态分析](evidence/ssh-unknown-receipt/unknown-receipt-final-analyze.log)、[六组真实 SSH 与完整 macOS](evidence/ssh-unknown-receipt/unknown-receipt-final-ui.log)。系统仍为 macOS 27.0.1 (26A434)。测试只使用临时 HOME、密钥和本机 loopback 服务，模型回复为确定性 fixture。

## 尚待完成

- 多次重连、认证失败/恢复、已经执行但回执丢失的真实链路均已补验；其他系统/网络条件仍不能由本机 loopback 结果推断。
- 大量历史的聚合截断已修复，384 块来源隔离、状态保留与中间连接关闭已有控制器回归。真正因 native 历史预算淘汰的输出仍不可恢复，界面继续如实提示不可读取。
- 与 imagegen 场景稿逐项的最终视觉复核，包括中英文、深色及桌面文字缩放。本轮截图证明当前渲染和已检查流程，不是 imagegen 无问题的结论。
- 没有在个人 cloud 节点做断线测试，没有测试真实模型的推理质量。

主按钮样式调整后补验：[19 项手机与桌面生产组件](evidence/ssh-reconnect-extended/reconnect-settings-mobile-final.log)、[六组 SSH 与 macOS 最终流程](evidence/ssh-reconnect-extended/reconnect-settings-final-ui.log) 均通过；上述追加截图已更新到此轮。
