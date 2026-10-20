# D05：无输出、字符截断与原始证据引用

2026-10-03，`composer` 工作区，macOS 原生应用。依据 [D05 合同](DESIGN.md#d05-结果证据与继续追问)补验，沿用固定字号手机要求，不进行 iPhone 真机测试。此记录不代表 20 个场景全部完成。

## 发现和修复

原来输出超过 16,000 UTF-16 字符时只截断正文，行号却仍指向截断前的范围；不连续选段用尽预算后还会保留未发送片段的完整行号。这会让模型把缺失内容当作可引用证据。

现在原生快照携带物理终端行的字符起点，保留软换行对应关系；序列化优先保留预算内的完整末尾行，同步更新行号。单行本身超过预算时明确标记 `first_line_truncated`，不切断 Unicode 代理对。没有可靠行映射的旧上下文不猜测行号；未发送片段不再计入已包含行数。用户冻结的原始附件不被序列化过程修改。

真实模型还暴露了两类协议问题：无输出时编造文字形式的内部引用，以及把截断后的末尾重新编号为第 1 行。应用现在提供准确的 `citation` 字段，无可引用行时为 null；系统提示说明空输出、部分单行和截断范围。仅靠提示不足以保证格式，因此每条回复会保存本次请求实际提供的引用范围，包括只读 `read_block` 的结果。界面只为这些范围创建入口，拒绝未知来源、越界及跨缺口引用；后续命令不会覆盖旧回复的证据范围。内部标记不作为正文展示，原始模型回复仍保留以便审计。

后续补拍暴露 D06 的另一次模型差异：附加失败证据后，模型只返回新的诊断命令工具调用，正文为空。控制器现要求本轮先有说明，才允许展示写入提案；缺失时通过已有修正循环最多补答两次，仍缺失则报错，无 PTY 输入也无可批准卡片。只读观察不受阻，已有说明后不要求重复诊断。这个检查只保证说明不为空，不假装自动验证诊断是否正确；成功补答和持续缺失都新增了回归测试。

## 真实模型与原生流程

入口为 `example/integration_test/terminal_ai_model_scenarios_test.dart`。测试使用新建的 `/private/tmp/trail-model-scenes-*`，覆盖 HOME、ZDOTDIR、工作目录与配置目录；只访问合成文件，没有访问用户项目、SSH 或数据库。转发器检查请求所属 session/cwd，拒绝用户目录路径和密钥进入 JSON，不修改模型响应。

完整流程保留此前 D02 澄清、D03 只读审批、D05 有限成功和 D06 失败诊断，再增加两个新任务：

1. 实际 PTY 执行 `true`，退出 0、输出 0 行。模型解释成功返回不能证明服务健康；没有虚假证据按钮，提问本身不执行命令。
2. 实际 PTY 执行合成脚本，产生 600 行。最早一行含失败信息，但该行没有出现在请求中。默认读取末尾 160 行，再按字符预算缩到第 **467–600 行**。模型引用这一真实范围，说明输出截断和“状态未核实”，不把退出 0 当作所有任务成功，也没有追加读取或执行。
3. 点击引用打开原输出阅读器。阅读器用分页展示 ID，验收逐行比较原始 native block 的 index、sourceRow 和文本，并确认命令块计数不变。页面动画和字体测量稳定后，另核对引用起点的滚动位置；不能拿仍挂载的后台块或分页 ID 当作原生命令 ID。

最终结果为 **7 次模型请求、4 条实际 PTY 命令、返回模型均为 gpt-6-luna**，见 [原生结果](evidence/output-boundaries/real/result.json)和[原始请求与回复](evidence/output-boundaries/real/model-traffic.json)。这是一组有界模型样本，不保证任意模型、任意日志或多次随机运行都能正确总结。

## 视觉和验证范围

对照既有 imagegen [D05 设计图](screens/D05-v2.png)，人工检查真实应用截图：无输出回复保留退出码与有限结论；截断回复的正文、强调和等宽内容清楚，单一蓝色证据入口标出实际行号；阅读器保留原命令、目录、退出状态和输出。没有生成替代运行截图，也没有把 imagegen 当作自动正确性判定器。

最终截图：[无输出](evidence/output-boundaries/real/D05-real-model-empty-output.png)、[截断总结](evidence/output-boundaries/real/D05-real-model-truncated-output.png)、[原始输出定位](evidence/output-boundaries/real/D05-truncated-evidence-original-reader.png)。

- [839 项应用回归](evidence/output-boundaries/evidence-diagnosis-app.log)通过：AI、Shell、session 和 terminal mode。
- 75 项最终专项回归通过，覆盖上下文序列化、来源按钮、历史引用和焦点；它们与应用回归部分重叠，不能相加为独立用例总数。
- 真实模型完整原生流程通过；请求数量、模型 ID、命令数量和引用定位以归档 `real/result.json` 为准。
- 独立原生字体测试通过：请求零基第 466 行，稳定后的视口位置为 465.65 行，目标行可见。阅读器顶部 8px 内边距产生不足半行的差异；早期截屏出现在字体测量完成前，不能据此认定最终定位错误。
- [静态分析](evidence/output-boundaries/evidence-diagnosis-analyze.log)无问题，[发布镜像](evidence/output-boundaries/evidence-verified-mirror.log)一致，`git diff --check` 通过；Shell 主文件仍为 1698 行。

中间失败记录保留：字符预算测试首先复现旧行号；真实模型的空输出标记和尾部重新编号推动协议及界面校验修复。随后两个阅读器断言失败分别误选后台块、把分页 ID 当作原生命令 ID，属于验收脚本问题，未据此修改生产阅读器。缺少诊断正文的一次实际回复保留于 `missing-diagnosis-before/`，没有从报告中删去。[归档清单](evidence/output-boundaries/manifest.json)记录 34 个证据文件及源码哈希，不包含代理密钥或 OAuth 凭据；本轮代理已关闭。

## D12 的独立预检

本机 k9s 0.50.16 已通过独立 PTY 预检：在临时 kubeconfig 和仅监听回环地址的合成 Kubernetes API 上显示 `trail-fixture-pod`，进入 alternate screen，并以 `:q` 退出 0。使用只读模式并关闭版本检查，未读取现有 kubeconfig 或连接真实集群。配置依据为官方 [命令说明](https://k9scli.io/topics/commands/)和[配置说明](https://k9scli.io/topics/config/)。

这仅证明后续测试夹具可用。**Trail 内 k9s 的完整网格、AI 覆盖页、Esc/Ctrl+C 输入交接及退出后手动 Blocks 仍需验收**；不能用预检替代 D12 完成。探测脚本和请求记录保留在本证据目录的 `k9s-preflight/`。

整体目标保持开放。继续按 [实现矩阵](IMPLEMENTATION.md)检查其他场景及输出淘汰后的引用边界，不提交或推送未经要求的改动。
