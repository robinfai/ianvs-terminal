# 移动／桌面 PRD 与实现对照

当前实现为 **C10 `2d18e608c2a1149a093451b5246cb370de0167c3`**。C9补齐草稿关闭保护、右键输入归属、DPR变化和旧菜单目标；其完整verify11发现两项鼠标／焦点协议回归，原失败保留。C10在实际pointer处理前激活目标，并仅为精确失焦系统报告保留独立权限；原103项界面测试、相关297项和canonical165项通过，集合有重叠不累加。独立复评未见阻断，完整 [verify12](../evidence/shared/C10-gates/verify-12.log) 已 exit0（792秒、源码首尾clean；[metadata](../evidence/shared/C10-gates/verify-12-metadata.json)），应用3090通过／1跳过，原生smoke4／真实PTY45／Composer1／Keychain1及Debug／Release／签名检查／Xcode通过，首次正常UI复验因AX陈旧和提前结束录屏仅留局部观察；第二次有界复验补做遮罩取消及idleAI取消／明确关闭，保留A，未复现AXTree错误，但首轮原因仍未定且没有新增正式场景通过。详见 [C9–C10本轮记录](C9_FOLLOWUP.md)。以下C8完整gate／3个正式场景保持历史身份，不直接改记为C10通过。

2026-10-10，起点 `79db5115`，上一正式归档候选 C8 为 `19001573d9974c510e1e4cbcfeb01c94368ea157`。C4生产修复保留，C5–C8仅测试／验收驱动变化；C8真实macOS workspace功能和原框架收尾通过、原生录像完整。当前整体仍为 `implemented_unverified`；C8完整gate verify-10已exit0／886秒、源码首尾clean，应用3,065通过／1跳过，原生smoke4／PTY45／Composer1／Keychain1、Debug／Release、签名与Xcode测试通过；verify-9权限中止仍保留。C8组件复采48/48、63PNG及Debug预览入口构建成功，首尾clean／unchanged、未launch，独立4/63代表图复核无新增阻断。历史C3完整gate不改写为C8。正式登记3passed（D1-T01／D3-T05／D4-T01）与61not_run；C8归档metadata／文件合同PASS而非全阶段gate，源码、组件／自动回归、完整产品场景分别记账。

| 主题 | 移动要求 | 桌面要求 | 实现与尚待确认 |
|---|---|---|---|
| 草稿到模型 | S1-R01–03 | D1-R01–04 | 已有准备／发送分离；提交未知时补充意图遗漏由本轮修复 |
| 审批与编辑 | S1-R04–05 | D1-R05–07 | 三档已具备；本轮保留旧文本和新 revision，API 操作 ID 去重；编辑保存零执行 |
| 输出与证据 | S1-R06、S2-R08–09 | D1-R08–09、D2-R07–09/R15 | 共享原生时间线／Reader保留；桌面检查器、手势归属、DPR替换及截断已实现。C8真实原生Reader引用／重开／过滤范围保留通过；跨pane、宽窄并排、淘汰与物理惯性完整矩阵仍待 |
| 收起与人工接管 | S1-R07 | D1-R10、D2-R12 | 收起／Esc进入只读观察，显式接管才恢复人工写；C8原生子集通过。C4预览onClose也遵循该合同，预览不替生产原生证据；后台窗口／生命周期组合仍待 |
| 未知与重连 | S1-R09–10 | D1-R11–13 | 本轮补结束跟进出口与未发送要求；原 receipt、未知事实保留，新任务不能复用旧授权 |
| TUI与密码 | S1-R11、S4-R08 | D1-R16、D2-R16、D4-R09 | C3 Composer原生gate为历史；C8真实vim 45×203、获批退出→只读→明确接管／手动恢复通过。vim由runtime准备；read／密码／top、先接管再退出与目标变化完整矩阵未验 |
| 布局与键盘 | S2-R01–07/R10–12 | D2-R01–06/R10–14/R16 | 手机固定字号；桌面1/1.5/2缩放范围不变。C4 divider加入Tab／裸轴向键／真实比例增减语义／边界原因，2×2回归零PTY写；物理键鼠和系统辅助技术仍另验 |
| 视觉与可访问性 | S3-R01–10 | D3-R01–16 | C4修真实高对比预览接线、tab／Block／主按钮focus和主按钮禁用说明，六组件册48项／63PNG已完成；C8同候选48项／63PNG及预览构建已复采，4/63代表图独立复核；非完整笛卡尔矩阵。组件图不代替原生字体／DPI／VoiceOver／全主题状态矩阵 |
| 生命周期 | S4后台／锁屏 | D4窗口／sleep/wake | 手机上隐藏controller丢失生命周期已通过红测确认；由Shell owner统一分发修复 |
| 关闭与待审定位 | S1任务／草稿和断连记录 | D1-R13、D2-R11 | 本轮补风险关闭确认及取消保留、录制等待后的版本／附件复查；桌面顶部／溢出／侧栏待审标记只定位来源。C10普通UI仅核对A关闭确认／Cancel／Esc保留局部，见[C10原生局部复验摘要](../evidence/shared/C10-native-partial/review-summary.json)；首轮因AX异常与录屏提前结束停止；[第二次C10有界复验摘要](../evidence/shared/C10-native-fixed-window/review-summary.json)补做遮罩取消及idleAI取消／明确关闭，只移除B并保留A。首轮原因仍未定，split／12tab／运行中关闭与完整矩阵仍未验 |
| 原生与性能 | S4-R01–15（14场景） | D4-R01–16 | C8本地App／PTY自动主链与连续录像通过；fixture模型不是真实API。C3SSH六组及ACP实际模型／恢复协议保留历史；物理IME、VoiceOver、断网、性能、iPad、升级回滚未齐 |

## 需要产品澄清与需要执行的区别

五个交互歧义已由 [v1.1 修订](../16_REVISION_1_1.md) 收敛，相关修复已纳入 C3 自动验证，完整原生／模型流程继续验收。手机固定字号、API 基础模式、不做 Android／跨进程会话恢复已经明确，无需重复询问。

真 iPad、直接软键盘操作、支持系统矩阵、外接显示器和真实 API／ACP 完整流程属于尚未完成的验证工作。不能因环境暂缺减少范围。无法完成时记录具体条件、最后可验证状态和下一步，而不是笼统“待手工”或假定通过。

用户本轮已确认暂时没有实体 iPad 和外接显示器，要求记录为未验收项；详见[平台台账](PLATFORM_MATRIX.md)。这两项不再需要重复产品澄清。

C3 workspace的录屏初始化错误和后来明确锁屏是历史事实；后续还修正了验收驱动陈旧Reader定位，不能把停住全部归因锁屏。C6缺当时owner诊断，原因未确定；C7功能链完成但语义结束校验失败；C8保持生产权限和原语义检查后通过。Mac已解锁，当前不是等待解锁。详见[当前交付结论](FINAL_REVIEW.md)。

手机后续恢复结果仍属于 **C4**：独立 `work.ianvs.trail.mobileprd` 已完成用户授权的 cloud 配置与私钥导入，手机保活设为30秒／3次。第一次目录清理报错后出现配置重建，已如实告知并恢复；第二次仅覆盖指定临时单文件，独立核对2459→0字节、两份配置元数据未变，清理前后两次重启均可使用保存的cloud连接，后续只读命令成功。三张原图与设备日志保留私有，公开[脱敏审阅摘要](../evidence/shared/C4-cloud-restoration/independent-review-summary.json)。镜像随后因iPhone被使用而结束，长时保活与完整真实模型／Smart／移动PRD仍未验；不把镜像结束当SSH断连。DeepSeek设置继续保留，原连接测试和Manual/Smart查看历史见原摘要。实体iPad、外接显示器按用户确认保持未验收。

逐项锚点见[桌面64条](DESKTOP_COMPARISON.md)和[移动49条](MOBILE_COMPARISON.md)，已确认的缺陷与回归过程见[第一轮记录](ITERATION_1.md)。旧 mobile STATUS／manifest 保持原始身份；C4安装／设置smoke不覆盖其历史验收结果，也不自动提升本轮正式场景状态。
