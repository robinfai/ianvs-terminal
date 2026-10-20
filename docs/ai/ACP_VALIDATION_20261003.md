# ACP / gpt-5.6-sol 验证记录

当前 `composer` 分支已接入本地 Codex ACP。Agent 管理推理和会话，Trail
继续管理当前终端、审批、上下文校验、提交回执和 Command Block 引用。
原有模型 API 连接仍可使用。配置方法与边界见 [ACP_BACKEND.md](ACP_BACKEND.md)。

## 最终完整评测：9/12 通过，3/12 失败

修正首轮的收尾缺陷后，对同一固定 12 题重新执行完整一轮，每题一次。
模型为 `gpt-5.6-sol`（high），适配器为 `codex-acp@2.1.1`，数据集与
原始时限、容器资源限制均保持不变。开始于 2026-10-03 06:51:08 UTC，
结束于 08:29:32 UTC。**全部 12 题取得有效官方评分，通过率 75%。**
这是既有 12 题子集，不是全数据集排行榜成绩，也不是实际 UI 点击评测。

逐题结果见 [第二轮报告](evidence/acp-sol56-20261003/round2/report.md)，
官方奖励及异常见 [第二轮原始结果](evidence/acp-sol56-20261003/round2/results.json)。
首轮记录完整保留，没有只补跑失败题或用后续结果覆盖原始成绩。

| 未通过任务 | 本轮证据与处理 |
|---|---|
| `compile-compcert` | 达到官方 2400 秒 Agent 时限，官方奖励 0。期间编译持续占用约 2 核；AMD64 镜像在 ARM64 Colima 中运行。跨架构环境可能影响耗时，但没有证据将失败完全归因于环境。 |
| `sqlite-with-gcov` | 官方奖励 0。编译完成后，已获批命令的 cwd 通知延迟到达；同一 Session、节点、已接受 Block 的目录从 `/app` 变为 `/app/sqlite`，却被 `target_changed` 拦截，后续命令未提交。已修复并通过独立回归，但没有重跑此题或改写得分。 |
| `configure-git-webserver` | 官方奖励 0。Agent 的本地 user 推送、部署 Hook 与 HTTP 自测显示成功，最终输出退出码为 0；这不足以证明满足官方全部验收，具体失败原因未确认，没有以模型自述替代评分。 |

12 题均有真实 Block 协商及 `gpt-5.6-sol` 配置确认，轨迹共记录 78 次
审批、65 条最终摘要中的 Block 引用。CompCert 被超时终止，没有最终
动作摘要，因此其 Block 引用计数记为未知，而不是 0。工具轨迹中另有
一次内部对话压缩（think）；未观察到 Trail 之外的宿主执行或文件修改
调用，见 [工具范围记录](evidence/acp-sol56-20261003/round2/tool-scope-audit.json)。

整个评测期间，生产 AI、终端 harness 和原生库哈希未变，见
[第二轮 manifest](evidence/acp-sol56-20261003/round2/manifest.json)。目录修正
在独立副本通过测试，待整轮结束后才合入。在 manifest 覆盖的执行文件中，
当前版本仅改变两份 AI 控制器文件，哈希见
[当前源码记录](evidence/acp-sol56-20261003/post-validation-source-hashes.json)。
因此本节的 9/12 属于修正目录问题前的冻结版本，不能当作修正后的新成绩。

目录修正只接受当前任务已接受 Block 所关联、同一 Session 与节点的
目录通知。手动输入、其他 Block 或 SSH 节点变化仍阻止继续执行。
五项新增回归及相关既有测试共 68 项通过。独立的真实 `gpt-5.6-sol`
检查也通过：两次审批、两个不同 Block、最终目录 `/tmp/trail-acp-cwd`、
退出码 0，见 [目录检查记录](evidence/acp-sol56-20261003/directory-smoke.json)。
该检查不使用 Benchmark 题目或评分器。

## 首轮记录：8 题通过，4 题未评分

- 模型：`gpt-5.6-sol`，reasoning effort `high`。
- 适配器：`@agentclientprotocol/codex-acp@2.1.1`。
- 数据集：官方 `terminal-bench-2-1`，提交
  `7131e4375048a0e408a8fb404b5f499d726b695b`。
- 选题沿用此前冻结的 12 题；每题一次，没有补跑或替换失败题。
- 开始：2026-10-03 05:57:04 UTC；结束：06:41:00 UTC。
- **8 题通过，4 题执行/收尾异常而未取得有效评分。**
  因此只能确认 12 题中的 8 题通过，不能把有评分的 8/8 宣称为整体成功率。

完整逐题结果见 [冻结报告](evidence/acp-sol56-20261003/report.md)，
原始奖励与异常见 [results.json](evidence/acp-sol56-20261003/results.json)。
全部 12 题均完成 Block 协商并确认 ACP 配置模型为 `gpt-5.6-sol`。
轨迹记录中没有发现 Trail 桥接之外的宿主执行或文件修改工具调用。

未评分的四题是 `large-scale-text-editing`、`build-pmars`、
`compile-compcert` 和 `sqlite-with-gcov`。第一题的 Agent 命令包含顶层
`exit`；另外三题的轨迹包含持久 shell 中的 `set -e`，随后会话不可用。
共同的评测缺陷是：收尾代码再次读取已关闭终端时抛出异常，导致 Harbor
没有运行 verifier。不能把这些缺失评分直接解释为模型能力得分。

本轮经过生产任务控制器、ACP、MCP 和原生 SSH/Block 通路。每次终端写入
均产生审批卡，由专用 harness 在对应的一次性容器内批准。它没有经过
真实 UI 点击，不属于 UI 验收，也不是全数据集排行榜成绩。历史 API/UI
评测的模型和执行边界不同，不能据此计算 ACP 相对于 API 的因果提升。

ACP session 的模型选择已验证；适配器返回的模型用量标签来自此配置，
并非独立的服务端模型回执。其 usage 只覆盖最后一次推理，未作为全任务
token 总量发布。

## 首轮发现后的修正

评测期间生产代码保持冻结，并逐题校验哈希。以下修正在独立副本验证，
整轮结束后才应用到当前分支；**没有用修正后重试成绩覆盖本轮结果**。

- 保留原始模型 API，并增加 ACP 设置及独立模型选择。重复保存相同配置
  保留会话；更换 ACP 连接时开启新任务，旧任务供查看，避免丢失上下文后
  静默继续。
- 修复统一下拉组件在设置对话框中的固有尺寸计算冲突。
- 将新的终端状态观察加入 Block 引用证据范围。
- 格式错误的 ACP 回包立即结束请求，不再遗留到超时；收紧子进程环境，
  显式使用文件凭据存储。
- 通用工具说明明确命令使用持久 shell，顶层 `exit` 和 shell 选项会影响
  后续会话。需要独立退出语义的脚本应使用显式子 shell。
- 修复评测收尾：即使 Agent 关闭 shell，也保留动作、阶段和断连信息，
  让官方 verifier 有机会继续评分。此修正不代表四个未评分任务已经解决。

冻结版本哈希见 [manifest.json](evidence/acp-sol56-20261003/manifest.json)，
修正后版本哈希见 [post-fix-source-hashes.json](evidence/acp-sol56-20261003/post-fix-source-hashes.json)。
完整原始轨迹和冻结源码副本保留在本机忽略目录
`tmp/terminal-bench/acp-2-1/sol56-round1/`。

## 修正后的验证

环境为 macOS 27.0.1（26A434），其他支持系统本轮未实测。
本地 Colima 为 Linux/aarch64、10 核、28 GiB 内存，启用了 Rosetta。
已核实 `compile-compcert` 的官方镜像为 Linux/amd64，存在跨架构运行；
其耗时不能直接与原生 Linux 主机比较。每道题仍使用官方容器资源限制。

- AI、配置、协议和架构契约回归均包含于下述全量测试，静态分析通过。
- 真实 `gpt-5.6-sol` 取消/恢复检查通过：重新连接相同 ACP session，
  保留取消前的上下文；最终分支显式文件凭据配置也完成实测。
- 独立容器交互检查通过：提交命令、读取交互提示、批准 `send_keys`、
  得到真实 Block 输出和退出码 0。
- 独立容器 shell 退出检查通过，收尾保留断连结果而不抛错。
- 当前分支 macOS Debug 构建成功，`Trail Development.app` 的
  `codesign --verify --deep --strict` 验证通过。
- 首次应用全量测试：2388 通过、24 失败、2 跳过。继续逐项核对并修正
  测试预期后为 2412 通过、0 失败、2 跳过；合入目录修正及五项回归后，
  最终全量测试为 **2417 通过、0 失败、2 跳过**，静态分析无问题。
  原始 [失败清单](evidence/acp-sol56-20261003/application-test-failures.txt)
  保留作为过程记录；修正依据见
  [UI 回归核对记录](evidence/acp-sol56-20261003/ui-regression-review.md)。

当前 ACP profile 面向本地桌面 Agent；手机运行 Agent、远程 ACP 网关和
应用重启后的会话恢复尚未实现。原有终端命令不会因 ACP 取消而自动中断。
