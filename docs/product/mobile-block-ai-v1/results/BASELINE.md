# 实施基线

核对日期：2026-10-08；PRD v1.1。原文与设计资料从用户给出的 zip 完整导入，文件完整性校验通过。设计 PNG/HTML 仅用于理解目标，不是产品验收图。

本轮从 `composer` 的 `763dc166bb1e56d6d50ed3379b57f366c9ca06b7` 开始。工作树中已有此前评审及移动会话恢复修复，先全部保留为 `29134363aecc20713f9f53e1c9a6c395ebf9ef2e`，没有重置用户改动。以下是这一生产版本的静态映射，不是最终 C 的验收声明。

## 当前机制与缺口

`existing` 表示代码已有核心机制；`partial` 表示有明确缺口；`missing` 表示入口/能力缺失；`needs-verification` 表示必须取得新的运行证据。所有条目均需对应最终验收用例，静态映射本身不产生 passed。

| 要求 | 基线 | 现状与实施方向 |
|---|---|---|
| S1-R01 | partial | 失败 Block 能从菜单诊断；补直接可见入口与两行命令标题 |
| S1-R02 | partial | 已有受限来源快照、详情、删除；删除最后来源会让同一草稿重新判成命令 |
| S1-R03 | partial | 发送前异步 readContext 后才读取附件并清草稿，存在错版本和覆盖新稿 |
| S1-R04 | existing | 手机紧凑提案已能进入完整 Review；复用，不另做审批流程 |
| S1-R05 | existing | 有 revision、目标/租约/人工输入代际校验及一次提交保护；仍需连点运行证据 |
| S1-R06 | existing | accepted 映射原生 Block，引用经过范围/身份校验；仍需真实 SSH 取证 |
| S1-R07 | missing | 关闭 AI 直接 takeOver 并聚焦终端；需无写权限的只读观察和独立接管 |
| S1-R08 | existing | task 阅读锚点和新内容提示已有；需连续录屏验证一行以内返回 |
| S1-R09 | existing | unknown 保留原 operation/receipt，恢复不自动重发；需断网注入 |
| S1-R10 | partial | 目标变化及旧来源保留已有；原目标检查入口目前仍会接管 |
| S1-R11 | existing | 保守 TUI 回退及底层稳定 viewport 已有；观察布局不能引入伪 resize |
| S1-R12 | partial | 错误分类、保存设置不发送已有；手机设置仍显示不可用 ACP |
| S2-R01 | partial | 会话/任务草稿分开，覆盖层隔离主输入；Raw 输入去向缺持续说明 |
| S2-R02 | partial | Auto/Command/AI 分流已有；手机隐去 Auto 和主动作文字 |
| S2-R03 | partial | Composer 已支持多行；手机 AI 仍 maxLines=1，未统一 1–4 行 |
| S2-R04 | missing | 无本地草稿全屏编辑的 Done/Cancel 事务；现有提案编辑不能替代 |
| S2-R05 | partial | composing 守卫已有；AI soft Return 是 send，应为 newline |
| S2-R06 | needs-verification | SafeArea/短高度处理和 Reader 已有；需真实键盘、旋转、焦点组合 |
| S2-R07 | partial | 目标详情和代码字体已有；窄屏标题/命令行数需统一 |
| S2-R08 | existing | 原生分页 Reader、保留范围和复制已有；需多页真实输出验收 |
| S2-R09 | partial | 来源详情/删除已存在；横向单行摘要和操作命中区需收口 |
| S2-R10 | needs-verification | 现有主题含触控尺寸；需逐控件检查实际 44×44 命中区 |
| S2-R11 | missing | 多会话分屏不是同任务双栏；需约束驱动的 AI + 只读终端 |
| S2-R12 | existing | 桌面 Dock/历史/灰字/Tab/原生 PTY 链保留，需回归 |
| S3-R01 | existing | 复用 AppThemeTokens、ColorScheme、ComposerTheme，不复制设计 HTML 色值 |
| S3-R02 | partial | 手机 unknown exitCode 会显示成功勾；原生六行预览继续保留 |
| S3-R03 | partial | 手机主动作图标缺文字，部分禁用理由与术语不统一 |
| S3-R04 | existing | 用户/助手/提案/原生事实/引用已有独立呈现 |
| S3-R05 | partial | unknown 优先级已有；目标变化和暂停文案需按真实状态统一 |
| S3-R06 | partial | 中英文和错误映射已有；只读/接管/发送文案需要明确 |
| S3-R07 | partial | 预览强制 1x，生产 phone 尚未固定系统字号；保留终端 pinch |
| S3-R08 | needs-verification | 已有对比度和减少动画测试；需新控件实际 token 测量/平台证据 |
| S3-R09 | partial | 已有真实组件预览；缺指定九组件及所有交互状态的完整状态册 |
| S3-R10 | partial | 跨端主题及 canonical 镜像已有；同任务 iPad 双栏和术语需统一 |
| S4-R01 | needs-verification | 最终 C 尚未冻结；需源码、工具、二进制和证据 E 的一致身份 |
| S4-R02 | needs-verification | 需真实 iPhone + SSH + 模型 API 全闭环，mock 单列 |
| S4-R03 | needs-verification | 测试输入客户端不是系统 IME；需真实候选、中文/emoji/undo |
| S4-R04 | needs-verification | 需设备旋转、触摸和选区/阅读位置记录 |
| S4-R05 | needs-verification | 需真实 VoiceOver 完成任务及连续证据，语义树不能替代 |
| S4-R06 | needs-verification | 需一次性 SSH fixture 分阶段断网及原回执检查 |
| S4-R07 | needs-verification | 需实际锁屏/后台时长、杀进程恢复事实；不承诺内存任务持久化 |
| S4-R08 | needs-verification | 需临时 vim/top/密码流程；截图不含秘密 |
| S4-R09 | needs-verification | 需 bounded 大输出、多页、Unicode、ANSI、复制保留内容 |
| S4-R10 | needs-verification | 既有单元回归可复用；仍需指定失败注入和实际效果计数 |
| S4-R11 | needs-verification | 需真实设备 profile 模式采样；模拟器 debug 不能替代性能 |
| S4-R12 | needs-verification | 当前未发现真实 iPad；已向用户询问设备可用性 |
| S4-R13 | needs-verification | 需真实 macOS API/ACP 与 make verify 全量记录 |
| S4-R14 | partial | 原安装脚本只换 Bundle ID，Keychain 仍用生产组；需独立身份和数据 |
| S4-R15 | needs-verification | 尚未产生最终实现/证据提交及完整可访问映射 |

## 源码入口

- [AI 控制器](../../../../example/lib/features/ai/terminal_ai_controller.dart)：发送、附件、任务、审批、未知提交与目标变化。
- [AI Workspace](../../../../example/lib/features/ai/terminal_ai_workspace.dart)：Review、输入、动作、状态与阅读锚点。
- [Shell AI 连接](../../../../example/lib/features/shell/shell_screen_ai.dart)、[布局](../../../../example/lib/features/shell/shell_screen_state_terminal_layout.dart)：输入归属、底层 viewport 与覆盖层。
- [Composer](../../../../packages/ianvs_terminal/lib/src/composer/terminal_composer_view.dart)、[手机 Block](../../../../packages/ianvs_terminal/lib/src/terminal/command_blocks_compact.dart)、[Reader](../../../../packages/ianvs_terminal/lib/src/terminal/command_block_reader.dart)：canonical 实现。
- [App](../../../../example/lib/app.dart)、[主题](../../../../example/lib/ui/foundation/app_theme.dart)、[Composer 主题](../../../../packages/ianvs_terminal/lib/src/composer/composer_theme.dart)：字号、主题和触控策略。

这些相对链接指向当前工作副本；上述静态结论的不可变来源是 Git 提交 `29134363aecc20713f9f53e1c9a6c395ebf9ef2e`。

## 已实跑的基线检查

新增 `mobile_prd_submission_snapshot_test.dart` 共 8 项：2 通过、6 失败。失败覆盖异步读取期间的新稿、编辑后回到相同文本、删除/增加/替换来源，以及删除最后来源后错误变回 Command。使用 Completer 确定性屏障，不依赖计时猜测。

新增隔离 App harness 定向 Dart analyze 通过。它不读已有 Profile、AI key 或布局；采用内存配置和临时 known_hosts，驱动真实 App 编辑器、SSH 与审批入口。该静态检查不等于 harness 运行通过。

后续保留生产行为不变、仅修正验收 harness，取得 B4 的 42 张可读字体组件原图，以及 B6 的真实 SSH 模拟器闭环：原生命令退出 2 → 仅附加诊断来源 → 模型提案 → 完整 Review → 明确批准 → 修复命令原生退出 0 → 摘要。模型为 deterministic fixture，实际 model request 计数 2，受控命令执行计数 1。B6 保存 7 张 simctl 原始截图及 95.462 秒连续录屏；它们属于 before 证据，不代表本轮最终实现 C 的通过结论。

原始产物与 SHA-256 清单保存在附加的 `mobile-prd-baseline` worktree 的 `build/mobile-prd-v1.1/before/EVIDENCE_MANIFEST.json` 和 `EVIDENCE_INDEX.md`。早期磁盘不足、harness 失败记录保留；原有不可读字体图不计入这 42 张有效图。

## 文档和环境冲突

1. `docs/README.md` 与 docs contract 禁止所有运行证据，但本 PRD 明确要求在指定产品目录版本化证据；同时基线已跟踪大量 `docs/ai` 与 `docs/design` 内容，导致原 gate 本身失败。需要记录狭窄例外及既有清单，不能删除历史或全面跳过检查。
2. docs contract 当前把 fenced Markdown 示例中的三个 `<run-id>` 路径当作真实链接，须按 Markdown 内容边界检查；真正正文链接仍必须存在。
3. iOS entitlements 的 Keychain 组固定为生产组，仅更换 Bundle ID 不足以隔离。新的验收构建使用 `work.ianvs.trail.mobileprd` 及同身份 Keychain 组，不覆盖生产 App。
4. 本机工具实际为 macOS 27.0.1、Xcode 27.0、Flutter 3.44.8、Dart 3.12.2、Rust 1.90.0。模拟器有 iOS 18.4/26.3/27.0，没有 iOS 17；检查时 iPhone 17 未处于可连接状态，没有真实 iPad。
5. 当前 SDK 仅支持 simulator debug。真实设备 profile/release 需独立签名构建；不能把模拟器 debug 性能换名为 profile。
6. 可用 Docker 测试环境为 `colima-trail-tbench`，默认 colima 未运行；不修改其他容器，建立一个独立 SSH fixture。

## 验收分类

组件 PNG 标 `widget_golden`，原生模拟器截图标 `app_simulator`；输入客户端脚本标明不证明真实 IME。测试模型为 deterministic fixture，不算真实模型 API。未采集的原图、视频、真机性能及 VoiceOver 维持 not_run，不能以代码或旧证据补成 passed。
