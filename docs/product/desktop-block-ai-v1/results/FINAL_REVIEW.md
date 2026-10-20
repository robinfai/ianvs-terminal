# C10 当前交付结论与验收边界

当前实现为 **C10 `2d18e608c2a1149a093451b5246cb370de0167c3`**。C9补齐草稿关闭保护、右键输入归属、DPR变化和旧菜单目标；其完整verify11发现两项鼠标／焦点协议回归，原失败保留。C10在实际pointer处理前激活目标，并仅为精确失焦系统报告保留独立权限；原103项界面测试、相关297项和canonical165项通过，集合有重叠不累加。独立复评未见阻断，完整 [verify12](../evidence/shared/C10-gates/verify-12.log) 已 exit0（792秒、源码首尾clean；[metadata](../evidence/shared/C10-gates/verify-12-metadata.json)），应用3090通过／1跳过，原生smoke4／真实PTY45／Composer1／Keychain1及Debug／Release／签名检查／Xcode通过，首次正常UI复验因AX陈旧和提前结束录屏仅留局部观察；第二次有界复验补做遮罩取消及idleAI取消／明确关闭，保留A，未复现AXTree错误，但首轮原因仍未定且没有新增正式场景通过。详见 [C9–C10本轮记录](C9_FOLLOWUP.md)。以下C8完整gate／3个正式场景保持历史身份，不直接改记为C10通过。

核对日期：2026-10-10。整体状态为 **`implemented_unverified`**。上一正式归档候选 C8 为 `19001573d9974c510e1e4cbcfeb01c94368ea157`；本轮起点 `79db5115d1e6c69ac62116f19fdfb2b102724df5`。C4 的生产修复已收拢，C5–C8 仅测试／驱动变化。C8原生workspace已实际通过功能与测试结束检查，连续窗口录像完整；这不代表 D1–D4、真实模型或所有平台通过。

**C8正式登记3/64 passed（D1-T01、D3-T05和D4-T01）、61/64 not_run。** C8归档metadata／文件合同校验通过；四阶段仍in_progress，未宣称完整阶段验收通过。 C8完整`make verify`第十轮已exit0、886秒、源码首尾干净；verify-9的SDK缓存沙箱权限exit2保留历史。C8组件复采48/48、63PNG及macOS Debug预览入口构建均成功，源码首尾clean／unchanged；完整gate通过不等于全部产品场景或全主题矩阵通过。

## 已修复并纳入 C3 自动验证

| 范围 | 当前行为与回归 |
|---|---|
| 审阅、补充要求与执行身份 | 未知时保留未发送要求，检查回执不发送；人工编辑保留旧版本，保存不执行；API重复操作ID返回原回执，冲突拒绝；旧目标／版本／授权不得写入 |
| 观察与输入归属 | 收起／Esc进入只读观察；Reader／AI打开同步撤销人工Composer权限；旧Run／异步粘贴失效；关闭后依据当前owner恢复；ready、运行Block、路由、窗口和晚到回调不抢其他任务焦点 |
| Block与检查器 | H/3短摘要保留真实状态与退出码；搜索显示单块200／总1000限制；Reader按当前pane打开，可显式并排；边界新手势、长手势及DPR替换维持单一滚动归属 |
| 桌面壳与关闭 | 单层顶栏与原生拖动区域；顶部／溢出／侧栏／折叠组显示待审入口，仅定位原pane；关闭风险确认、取消保留、录制等待后的身份重核对；部分关闭只清理实际关闭pane |
| 状态、主题与移动共享路径 | 底栏同时保留未知回执和当前核对／断连事实；主题目标色对与指定macOS27基线通过；移动隐藏controller生命周期由Shell owner统一分发，手机固定字号合同保留 |

逐项源码和回归入口见 [DESKTOP_COMPARISON](DESKTOP_COMPARISON.md)、[CROSS_PLATFORM_REVIEW](CROSS_PLATFORM_REVIEW.md)。历史红测、修复与定向验证过程见 [ITERATION_1](ITERATION_1.md)，历史局部结果不能冒充新候选的完整验收。

## C4 新增修复与组件支撑

| 范围 | 最终行为与验证边界 |
|---|---|
| 预览合同与字体 | Composer／Block真实highContrast传到生产主题；AI预览收起改为只读观察并保留task／提案／草稿；Block／Reader字体继承真实结果字体并完整注册捕获字体。仅预览接线与捕获质量，不是系统字体验收 |
| 分割条可达性 | Tab可达，裸轴向键按实际10px增减；Semantics increase/decrease共用ratio／cell约束，播报当前与预告的一位小数比例，边界／无空间有原因；反轴／组合键不吞，不改变终端目标。实际VoiceOver/FKA仍待 |
| 标签、Block和主按钮焦点 | hover下仍有可辨焦点；Block近端Material修复被遮ink，pointer down不选中、release／标题Enter选当前块；主按钮局部前景双色焦点边保留尺寸与权限。真实像素定向测试保留3:1焦点要求 |
| 禁用说明与状态册 | 主按钮禁用原因进入自身Semantics节点；Block、来源Chip、候选、主按钮、tab和分割条六组件提供真实交互状态册。C4冻结后48项通过、63PNG及macOS预览入口构建成功 |

C4 `1c95adcaab32fac64fb08142da7a0eb3b8620b5a` 的组件证据位于 `build/desktop-prd-v1/iteration-1/component-states-c4-1/`，首尾同一干净源码。Widget测试DPR=1、PNG导出2×，字体来自仓库和固定SDK资产，无PTY／模型；63图不是组件×主题×状态的完整笛卡尔矩阵，也不是物理DPI、IME或VoiceOver证据。C8已在同候选重新采集48/48与63PNG，预览入口构建成功，两次首尾clean／unchanged，未launch；原始材料见 [C8组件归档](../evidence/shared/C8-component-states/archive-index.json)。独立视觉复核只打开4/63张代表图（button-focused、block-selected、block-focused、高对比深色2×窄fixture），未见新增阻断，不声称全部63张逐图检查。C4保持历史身份。

## 当前证据及其适用范围

| 运行 | 已核对结果 | 证据边界 |
|---|---|---|
| C10 `native-c10-ax-2` | 同一cleanC10有界普通UI复验；A关闭Cancel／Esc／遮罩取消保留，B idleAI草稿取消保留，明确Close只移除B PID17469并保留A PID3929／ttys008／草稿；runner q退出0，见[第二次C10有界复验摘要](../evidence/shared/C10-native-fixed-window/review-summary.json) | 0 AXTree错误不抹除首轮异常；1 Window move警告首因未定。7检查点均非前台；256秒录像含检查点但非完整App时段，SCStream与停止请求关系未记录；12tab／split／物理键等未完，无formal pass |
| C10 `native-c10-windows-1` | 普通UI隔离App、源码首尾clean；非活动A的关闭确认仅列A原稿，Cancel／Esc后保留；A／S原稿与三个Shell PID／TTY有离散记录；runner正常q退出0，见[C10原生局部复验摘要](../evidence/shared/C10-native-partial/review-summary.json) | 10条AXTree错误后AX陈旧；首因未定，不归因CUA或移动。录像312秒、SCStream -3822提前结束，S保留／最后界面图在录像外；final close／AI／split／12tab／重排／物理快捷键未完成；本轮无formal pass |
| C10 `verify-12` | 完整make verify exit0、792秒、源码首尾clean；应用3090通过／1跳过；原生smoke4、真实PTY45、Composer1、Keychain1，Debug／Release构建、签名检查与Xcode测试通过；[原日志](../evidence/shared/C10-gates/verify-12.log)／[metadata](../evidence/shared/C10-gates/verify-12-metadata.json) | 四个driver均有foreground open returned1警告，随后实际断言通过；不证明前台物理输入或正常UI视觉验收。nightly resource benchmark未运行；签名检查不推公证／证书类别；C8正式3/61及C4手机身份不迁移 |
| C8 `native-c8-tabs-1` / D1-T01 | 正常产品 UI 两标签页、真实本地 Shell；14 张原图独立复评；A PID29364／ttys014，B PID32038／ttys016，进入与收起 AI、切页及显式接管后 marker／PID／PTY 与两类草稿保留；底栏 AX 操作者转录记录 Session1／2；正常 q 退出0 | 显式菜单选择 Blocks，非新安装默认模式；部分截图窗口非前台；离散 OS 采样不证明所有瞬态进程；只读 no-echo 探测仅辅助，不充当输入门禁强断言；无模型请求、非物理输入 |
| C8 `native-c8-workspace-1` | exit0、源码首尾clean；原功能与框架收尾断言通过；74周期原生图、6精确原生点、42widget支撑图；53.658333秒窗口录像与严格区间门禁true；133项产物SHA独立核对一致 | 真实macOS App／本地PTY，确定性本地HTTP模型、自动WidgetTester输入；不是物理输入、真实模型或其他尚未验收场景的通过证明 |
| C8 `verify-10`（保留verify-9历史） | 完整make verify exit0、886秒、源码首尾clean；应用3,065通过／1跳过；原生smoke4、PTY45、Composer1、Keychain1，Debug／Release构建、签名与Xcode测试通过 | 证明C8现有完整自动gate在该环境通过，不代表64完整场景通过；verify-9因SDK cache权限exit2仍保留，不当产品失败 |
| C8组件状态册（C4历史另存） | 同候选48/48测试、63PNG和macOS Debug预览入口构建exit0；首尾clean／source unchanged，4/63代表原图独立复核无新增阻断 | 未launch、无PTY／模型，固定字体／widget DPR1／PNG导出2×；不是全部主题状态矩阵或实际系统DPI／辅助技术验收 |
| C4 `verify-8`、C5测试修复 | C4完整gate exit2；Bash5.3首次覆盖到不存在的`/bin/false`／`/bin/true`测试路径；C5改外部`/bin/sh -c 'exit …'`，保留1／0／7和全部style断言，core suite 1,018通过／6忽略 | 只修测试夹具与镜像，不改生产返回码；不能将C4gate改写为通过 |
| 历史C3 `verify-7` | 完整make verify exit0、首尾clean；应用2,965通过／1跳过；原生冒烟4、真实PTY45、Composer1、Keychain1；Debug／Release、签名与Xcode测试通过 | 既有自动gate在记录环境的历史结果；不改作C8 gate或64完整产品场景通过 |
| 历史C3 `ssh-c3-native-1` | 真实回环OpenSSH六组zsh/bash × emacs/vi及各自local→SSH均PASS，含受控多跳／父Shell恢复；exit0、首尾clean | production native session API子集，无GUI，不能标D4-T02完整通过 |
| 历史C3 ACP协议／恢复探针 | 适配器2.1.1实际返回OK，完成回执确认模型gpt-5.6-sol；cancel后同session/load记忆短语核验通过，均exit0、首尾clean | 拒绝终端写入／只读fixture tool；不是Finder／原生UI审批或D4-T04通过 |
| 物理iPhone C4安装与连接 | DeepSeek连接smoke保留；后续已授权导入cloud，精确单文件清理前、后各一次重启可重连、只读命令成功；三张原图独立审阅，详情见[C9本轮记录](C9_FOLLOWUP.md) | 第一次目录清理报错后配置重建的影响已恢复但因果未定；手机仍C4，长时保活／Smart／完整模型闭环未验，不当C9真机结果 |

C8原始目录为 `build/desktop-prd-v1/iteration-1/native-c8-workspace-1/`。公开支撑归档目录由本轮证据收拢统一生成：

- `evidence/shared/C8-native-workspace-1/`：`run-metadata.json`、`native-test.log`、`result.json`、`source-input-hashes.json`及补充、`binary-input-hashes.json`、`environment.json`、`visual-review.log`、`native-window.mp4`和`archive-index.json`。
- `evidence/shared/C8-native-tabs-1/`：正常 UI 双标签页的运行身份、操作者 AX 转录、逐点进程树、构建哈希和独立 14 图审阅；正式截图及闭环见 [D1-T01](D1.md)。
- [第二次C10有界复验摘要](../evidence/shared/C10-native-fixed-window/review-summary.json)：A三种取消与B idleAI取消／明确关闭的局部观察，零AX错误仅限这次序列；不改写第一轮或完整case状态。
- [C10原生局部复验摘要](../evidence/shared/C10-native-partial/review-summary.json)：本轮关闭确认／取消局部事实与原始输入哈希；录屏中止、AX与键盘未定因，不能作为完整D2场景通过。
- [C10 gate归档](../evidence/shared/C10-gates/archive-index.json)：verify-12原日志／metadata逐字节归档，冻结C10完整运行exit0；提交前103／297／165定向记录另见 `evidence/shared/C10-input-regression/`，不混算为本次运行。
- `evidence/shared/C8-gates/`：verify-9环境中止与verify-10完整通过的原日志／metadata；第十轮实际时间为2026-10-10 07:23:24–07:38:10 UTC。
- [C8组件证据](../evidence/shared/C8-component-states/archive-index.json)：48项／63PNG、capture／native-build日志与metadata、preview构建身份及4/63代表图 [视觉复核](../evidence/shared/C8-component-states/visual-review.log)；未启动原生预览，不占用正式App截图检查点。
- `evidence/shared/C4-gates/`：verify-8、iPhone build／install摘要与`ui-followup-summary.json`。早先设置检查保持原身份；后续三张cloud恢复原图保留私有，脱敏审阅另归档至 `evidence/shared/C4-cloud-restoration/`，不补成formal case截图。
- 历史C3原始gate、SSH／ACP记录见 [C3支撑证据](C3_GATE_EVIDENCE.md)；C3 iPhone `physical-profile.MIDSac`仍保持当时未安装的构建身份，后续C4安装另列。分支为 [composer](https://github.com/robinfai/ianvs-terminal/tree/composer)。

原生窗口PID91804／window28413、1728×1084 points／3456×2168 pixels，arm64 macOS27.0.1 build26A434；D01检查点确认同PID active/frontmost后才继续。D12前置为resumed、AI task持焦点／active／route current、原target处于alternate screen；result记录45×203网格和批准后只读观察／显式接管／手动恢复均通过。原生输入是自动驱动，`font_scale=1.0`来自该固定SDK macOS embedder与无override源码推导，**不是运行时测量**，与原生pixel_ratio=2分开。

语义观测为platform disabled、outstanding handles1→1；测试框架随后正常释放其自有句柄并通过原结束检查。host在result后继续录像约1.4秒，正常stop后回执PID／recorded／exit0，driver才返回；严格时段仍包含保守media_end门禁。`native_command_count=1`仅统计首次编辑命令的匹配Block，不表示整段运行只执行一条命令或一次write syscall。图像解码／hash成功不替代逐图／录像独立视觉审阅。

### 历史中止与失败边界

C3额外workspace运行有录屏工具初始化失败，后来CUA确认锁屏并在Reader阶段停止，exit79／capture false；后续又修正了验收驱动陈旧Reader定位，因此不把该停顿全部归因锁屏。C6在批准vim退出后未回只读，但没有D12当时lifecycle／focus证据，不能确定是后台或生产竞态；root在该次运行中没有主动CUA操作。C7前台与D12所有权已证、全部功能断言到result，但最终报SemanticsHandle未释放，整体仍失败；CUA AX触发engine额外句柄仅为有源码路径支持的假设，C7未记录语义起终值，不能写成已实证因果。

C8仅调整driver诊断／录制首尾握手，在运行中不调用CUA AX；原生产owner和语义检查保留，最终通过。C6／C7失败和C3中止均不回写为通过，也不据当前成功宣称曾定位并修复了产品TUI竞态。

正式 [manifest](../evidence/manifest.json) 已登记D1-T01、D3-T05与D4-T01为`passed`，其余61项`not_run`；各自的原生步骤、截图、必要录像和断言见 [D1-T01](D1.md)、[D3-T05](D3.md#d3-t05--ai-内容与执行事实分层) 与 [D4-T01](D4.md#d4-t01--真实本地-shell-端到端)。本次合并后的 [metadata 校验](../evidence/shared/C8-documentation-check/metadata.log)通过，[文档合同测试](../evidence/shared/C8-documentation-check/docs-contract.log)20/20 通过。[最终门禁](../evidence/shared/C8-documentation-check/final-gate.log)实际 exit 1，共 65 项未满足（4 个阶段、61 个未验场景）；产品整体仍 `implemented_unverified`。历史 exit 1 的 68 项属于旧状态，不挪用为本次计数。

## 尚未验证及恢复条件

| 未完成范围 | 当前条件与后续动作 |
|---|---|
| 单层栏真实拖窗、窗控命中、标签拖放／溢出、侧栏待审导航、关闭告警、后台焦点和四pane组合 | Mac已解锁且本次前台原生链完成；继续隔离手验。位移需前后Bounds，NSAlert需同PID告警窗口，不能仅用主窗口录像 |
| 真实API／本地ACP、Finder PATH、恢复／权限、Manual／Smart三档矩阵 | C8模型为fixture；C3ACP协议和C4手机连接仅局部历史事实。当前候选正常UI配置／审批／执行／错误恢复完整矩阵仍缺 |
| 中文IME物理候选、触摸板惯性、VoiceOver／FKA、系统减少动画 | 需要实际系统操作与可核对视频／日志；自动composing／pan／Semantics不替代 |
| 完整TUI／密码／特殊输出、睡眠恢复、unknown／partial竞争、长输出性能、升级回滚 | C8vim和慢命令为真实原生子集；继续正式步骤、故障注入、profile原始采样和持久数据保留证据 |
| 全主题／状态／长路径中英、四尺寸、1／1.5／2倍文字、字体／DPI | C8六组件48项／63PNG已复采、4代表图复核，完整矩阵仍缺；逻辑缩放／PNG导出比不是系统DPI。macOS26旧基线未复采 |
| iPhone完整模型→SSH与审核行为 | C4已保存cloud及私钥，清理前后两次重启和只读SSH验证成功；30秒／3次已设置。镜像因手机被使用而结束，后续状态不可见；长时保活、连续模型→SSH和Smart完整矩阵仍待。无需重新导入或重复授权 |
| 实体iPad、外接显示器 | 用户明确暂无，保留未验收，不再次询问，不用模拟器／窗口缩放替代 |
| 支持系统／架构与其他桌面平台 | macOS14／15／26／27、iOS17／18／26／27支持要求不变；本轮只有arm64 macOS27.0.1／iPhone iOS27.0.1部分事实，旧系统与Intel仍缺。Linux／Windows未有当前App host，不从零移植或宣称可交付 |

手工入口 [tools/desktop_prd/README.md](../../../../tools/desktop_prd/README.md) 已提供独立AI配置、Profile／布局存储及本地Shell HOME／ZDOTDIR／XDG。它不复制生产私钥或API配置，不预设模型、不注入任务、不自动审批；SSH使用人工配置的远端环境。此入口是数据隔离，不是系统沙箱；Development窗口位置／尺寸偏好仍与普通Development应用共享，ACP既有认证路径可能使用宿主登录。入口接线测试不代表已经使用该入口完成全部原生手验。

## 无需再次作产品决策的事项

[v1.1修订](../16_REVISION_1_1.md)和[DECISIONS](DECISIONS.md)已明确三档审核、未知时补充要求、收起／Esc只读观察、编辑版本和结束未知跟进。手机固定字号、API基础模式、不做Android／远程ACP／跨进程聊天恢复，以及Linux／Windows不从零移植的范围均已明确。

本轮没有新的必需产品决策。当前缺口是完整场景的真实执行和证据收集；环境暂缺不自动删减已承诺要求。实体iPad和外接显示器的缺口按已确认条件记录，其余可执行工作继续推进。
