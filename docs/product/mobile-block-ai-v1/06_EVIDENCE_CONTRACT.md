# 06 · 截图、录屏、测试与 GitHub 证据合同

本合同是交付要求，不是建议。**源码、截图、运行行为和真实设备证明是不同证据，不能互相冒充。**

## 1. 三类材料彻底分开

| 材料 | 允许来源 | 能证明什么 | 不能证明什么 |
|---|---|---|---|
| design/ | HTML、线框、图像生成 | 设计意图与例子 | 已实现、真实执行、实机效果 |
| widget_golden | Flutter Widget/Golden fixture | 组件在受控数据下的布局 | 真实 Shell、IME、系统键盘、网络 |
| app_simulator / app_physical / app_desktop | 实际运行的完整 App | 对应环境下的 UI 与流程观察 | 单张图无法证明“只执行一次”或无泄漏 |

原生 UI、系统键盘/权限界面不是纯 Widget fixture 的组成部分。Flutter 官方说明 `integration_test` 不直接操作原生系统 UI；这类用例使用已有原生 XCTest/XCUITest、合适工具或人工操作，记录实际方法，不强制新增特定第三方测试框架。[Flutter 测试说明](https://docs.flutter.dev/testing/overview)

## 2. 仓库目录（统一）

```text
docs/product/mobile-block-ai-v1/
├── README.md / 00…12 文档 / plan.json
├── design/                         # 本包例稿；绝不充当验收
├── STATUS.md
├── results/
│   ├── BASELINE.md
│   ├── S1.md … S4.md
│   ├── FINAL_REVIEW.md
│   └── issues.md
├── evidence/
│   ├── manifest.json
│   ├── S1/S1-T01/<run-id>/
│   │   ├── before-01.png
│   │   ├── after-01.png
│   │   ├── flow.mp4
│   │   ├── assertions.log
│   │   └── events.jsonl
│   ├── S2/…
│   ├── S3/…
│   ├── S4/…
│   └── shared/<run-id>/
│       ├── build.log
│       ├── verify.log
│       ├── environment.json
│       ├── source-hashes.json
│       └── performance.json
└── scripts/validate_evidence.py
```

`run-id` 建议 `20261008T120000Z-<C前8位>`，必须是真实采集时间。不得把设计样稿复制成 after 文件；不得把旧截图改文件名装成最新构建。

## 3. 每项用例必须有的证据

07 的 48 项是场景覆盖，不是“总共交48张图就过”。一个场景包含多个状态时需要多张原图。每个通过用例至少：完整 App/组件原始 PNG、测试或人工断言日志、实际环境、实现 commit、动作步骤和观察结果；标明 video_required 的还需连续视频。

阶段一至少失败入口、上下文、完整审批、编辑失效、执行结果、只读接管、旧内容阅读、未知回执、目标变化、TUI 回退、配置错误、普通终端回归。阶段二重点键盘、多行、横屏、Reader、iPad/桌面。阶段三是深浅色与状态组合。阶段四必须是真实环境与最终构建的证据。

**before/after：** S1–S3 每个有界面变化的场景至少有一组同 fixture、同设备/OS、同主题、同字号、同视口的 before/after；before 可绑定变更前 commit B，after 必须绑定最终 C。before 放独立 baseline 清单或标 role=before，不计通过场景的 after 证据。S4 若只验收无 UI 变化无需伪造 before；修复缺陷则补失败前/修复后证据。

## 4. 原图规则

PNG 无损，保持真实像素尺寸与纵横比，保留足以判断完整布局和安全区的画面。不要裁掉顶部目标、底部按钮、系统键盘后宣称它们无遮挡；不要在原图里画圈、拼接、修改文案、消除错误或重绘 UI。

如需标注，另存 `annotated-*.png`，正文并排引用原图和标注图，**只有 raw 原图计入截图门槛**。拼图和缩略图只是报告附件；必须链接每张完整原图。

使用一次性 fixture 和假主机名称避免泄密。真实密码、API key、私钥、token、登录二维码、个人文件内容不得进入仓库。若原图意外含秘密，不提交它，先撤销暴露凭据并重新用脱敏测试环境采图；不能靠修图把它当未改原图。允许报告中的辅助图脱敏，但标为 redacted，并且不作为必要原始状态证据。

## 5. 每张截图的元数据

至少记录：用例 ID、环境 ID、captured_at（有时区）、implementation_commit、capture_class、实际平台/机型/OS、App build id、构建模式、逻辑 viewport、DPR、PNG width/height、orientation、locale、theme、font_policy、keyboard、SHA-256、步骤与预期。

逻辑单位与物理像素分开；例如 390×844 设计画布不能冒充某机型截图。系统字号固定只在手机 font_policy 标 `phone_fixed`；iPad/桌面标实际策略。Widget 图必须标 `widget_golden`，不能因平台参数设为 iOS 就写 `app_simulator`。

每个运行 App 的环境额外记录 `binary_sha256`（实际测试二进制或打包产物）、`build_commit` 与是否 physical。公开文档不存设备完整 UDID、序列号或个人主机名；使用稳定匿名 device id。

## 6. 行为日志与录屏

以下断言单张图无法证明，必须补测试/运行日志：零自动发送、零重复提交、旧 revision 不执行、只读 surface 零写入、来源身份未变化、晚到结果未覆盖新草稿、重连不重发、人工接管后无排队写入。

日志优先只记录匿名 ID、序号、状态、时间和计数，不存真实命令/提示词/密码；需要核验命令内容时使用可公开 fixture 与摘要 hash。AI/PTY 事件时间戳关联截图 run-id。

动态流程的视频为连续原始 mp4/mov/webm，至少展示起点、手势/操作、状态变化、终点；关键帧截图附视频时间戳。IME、旋转、回看不跳、只读接管、TUI、断连、VoiceOver 等不能仅交开始和结束两张图片。录屏中无“用脚本直接改状态却宣称点击 UI”。

视频体积优先可读且短小。仓库内放必需 PNG、关键日志及精简录屏；大 trace 可放用户授权的持久附件并记录 URL/hash/保留期。不要只依赖即将过期的 CI artifact。校验器的必要视频默认要求 repo 本地文件；使用外部附件须在评审中明确批准偏离，不能让脚本默默忽略缺失。

## 7. 文档必须真正嵌图

`results/S1.md…S4.md` 不得只有文件名列表。每个需求/场景段落包括：现象、操作、预期、实测、原图（Markdown `![]()`）、录屏链接+时间戳、断言日志链接、源码链接（固定 commit）和结论。

模板示意（路径在实际文件存在后才填写）：

```markdown
### S1-T05 · 连点批准只产生一次提交
需求：S1-R05、S1-R06
构建：完整实现 commit C；环境：ios-sim-01
步骤：打开审阅 → 连续点批准两次 → 等待回执 → 查看原生 Block
预期：submission_count = 1；Block 来源与 operation_id 一致
实测：填写真实观察，不预填“通过”

![执行后原始画面](../evidence/S1/S1-T05/<run-id>/after-01.png)
[连续录屏](../evidence/S1/S1-T05/<run-id>/flow.mp4) · 00:08–00:19
[断言日志](../evidence/S1/S1-T05/<run-id>/assertions.log)
```

提交时不得残留 `<run-id>`、TBD、待补图片链接等占位符；未完成场景直接写 blocked / not_run，不插不存在的图。

## 8. 避免 commit 自引用的正确顺序

1. 在实现代码稳定且工作树 clean 后提交 **C（implementation commit）**。
2. 从 C 构建并运行验证，输出写临时测试目录；记录源文件与测试二进制 hash。
3. 把证据及结果文档整理进仓库，生成 manifest，填 `implementation_commit=C`。
4. 提交 **E（evidence-only commit）**。manifest 不填自己的 evidence commit，以免自引用循环；E 从 PR/分支实际记录获取。
5. 复核 `C..E` 只有文档和证据。若含产品、测试 harness、依赖或配置代码变更，重新冻结新的 C 并验证受影响场景。

不同阶段可有各自实现 commit，最终 S4 候选需回归前三阶段，最终 manifest 统一绑定最后 C。历史阶段 manifest 可保留在各 run 目录，但不能混成“最新全过”。

## 9. 状态与门槛

用例状态：not_run / blocked / failed / passed。阶段状态：planned / in_progress / implemented_unverified / blocked / failed / verified。未经运行的模板保持 not_run。

`passed` 要求截图 + 日志 + 必要视频 + 来源等级 + 人工观察一致；`verified` 要求该阶段全部用例通过、无 P0/核心 P1、证据有效。缺设备可以交付代码和剩余工作，状态 `implemented_unverified` 或 `blocked`，不能变成 passed。

`python3 scripts/validate_evidence.py evidence/manifest.json --gate S4 --repo-root <仓库根目录>` 检查文件结构、SHA、环境类型、构建身份、需求/用例覆盖与源 hash。它**不理解画面、不验证截图真实性、不证明代码安全**；GitHub 后续人工评审不可省略。

## 10. 来源与方法

触控至少 44×44 点参考 [Apple UI Design Tips](https://developer.apple.com/design/tips/)。实机 profile 性能方法参考 [Flutter performance profiling](https://docs.flutter.dev/perf/ui-performance)。本包的分位数、内存与截图数量是项目拟定门槛，不是这些官方文档给出的产品实测结果。

## 11. 校验器使用补充

路径均相对本 PRD 根目录，`manifest` 文件本身可在 evidence/。`source_hashes` 的键则相对仓库根目录；`--repo-root` 用于比对实现 commit 中的源文件及当前工作树。只列少数文件不能证明全仓一致，最终人工审查还要检查完整 diff。

```sh
# 初始模板结构检查：应通过，但不表示任何产品用例通过。
python3 scripts/validate_evidence.py templates/manifest.template.json --structure-only
# 校验器自身单元测试（不是终端产品测试）。
(cd scripts && python3 -m unittest -v test_validate_evidence.py)
# 阶段门槛：S2 同时要求 S1、S2 完成；S4 要求四阶段完成。
python3 scripts/validate_evidence.py evidence/manifest.json --gate S2 --repo-root /实际仓库路径
python3 scripts/validate_evidence.py evidence/manifest.json --gate S4 --repo-root /实际仓库路径
```

JSON 字段样例在 `templates/`。视频与原图共用 captured_at / implementation_commit / environment_id / role=after / modified=false；日志与 metrics 也记录真实时间、hash 和实现 commit。完整 build.log 用 role=build；完整验证日志用 role=repo_verify。before 图的元数据保存在独立 baseline 清单，不放进计入通过门槛的 after artifacts。

额外测试可以放 additional_cases，当前校验器仅将固定 48 项作为必需门槛；附加场景仍由人工复核。校验器不能判断视频是否连续、图像是否真实或日志是否造假。

## 12. v1.1 逐帧和控制边界补充

每项用例的具体可见状态见 [10](10_SCREENSHOT_SHOTLIST.md)，共 110 个检查点；截图元数据补 shot_ids，结果段落使用三级用例标题并逐项嵌图。执行次数与只读写入的精确定义见 [11](11_INTERACTION_CONTRACT.md)。文件完整性校验通过之后，还须运行逐帧覆盖校验，二者都不替代人工视觉检查。
