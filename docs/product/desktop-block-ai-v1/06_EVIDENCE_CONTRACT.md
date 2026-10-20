# 06 · 桌面截图、录屏、测试与提交证据合同

## 1. 证据分类

设计稿（design_reference）、HTML文档渲染（document_render）、Widget/golden（widget_golden）、真实原生桌面App（app_desktop）、真实模型/适配器验证、物理设备操作分别记录。**本包64个主场景的必交原图最低为实际macOS原生App；前三类不可以替代。** 原生App可由integration test驱动，但必须保留真实生产装配、PTY/SSH与相关controller，不能只截图独立预览页。

PNG证明某个时刻的可见状态；单张图不证明没有误执行、没有抢焦点或滚动连续性。动态case须连续录屏，行为安全须测试/日志/受控副作用断言。性能须profile数据和统计，不能用视频目测。平台目录存在、编译成功、UI预览分别都不等于该平台原生终端通过。

## 2. 目录与结果文档

```text
docs/product/desktop-block-ai-v1/
├── STATUS.md
├── results/
│   ├── BASELINE.md
│   ├── DECISIONS.md
│   ├── D1.md … D4.md
│   ├── PLATFORM_MATRIX.md
│   ├── PERFORMANCE.md
│   ├── issues.md
│   └── FINAL_REVIEW.md
└── evidence/
    ├── manifest.json
    ├── D1/D1-T01/{before,after,video,logs}/...
    ├── D2/... D3/... D4/...
    └── shared/{build,environment,full-gate,metrics}/...
```

所有路径相对PRD根目录；原图应置于`evidence/`，不得指向`/tmp`、本机绝对路径、sandbox或会过期的CI下载链接。大型trace/video可使用稳定GitHub Release/LFS等已授权渠道，但必须有可取回路径、SHA-256及文档说明；包内自动gate只检查已物化的本地证据，因此下载后重新跑校验。不能只贴Actions临时URL。

每个阶段结果必须有三级标题 `### D1-T01 · ...` 等，里面写：相关需求、实际操作、预期/实际、当前状态、源码文件+行/commit、日志/视频、原始截图Markdown嵌图、允许差异/限制。不能仅写“截图在目录里”。长命令顶部和尾部的图要在同case并列，完整窗口图至少一张。

## 3. 每张图必须附带的数据

manifest中每张图记录：`shot_ids`、`path`、`sha256`、`environment_id`、`implementation_commit`、`captured_at`（含时区）、`role`（before/after）、`modified:false`、`pixel_size`、`viewport_logical`、`pixel_ratio`、`theme`、`locale`、`window_state`、`active_pane`、`font_scale`、`description`。

环境记录真实OS版本/构建、设备/CPU架构、Flutter/Dart版本、profile/debug/release、App bundle id/构建标识、源码commit、二进制哈希、捕获方法、是否原生App、是否VM。额外区分系统缩放、文字缩放、实际显示器/DPR；VM中的原生App可验证部分功能，但不替代要求物理键鼠、屏幕或硬件性能的项目。

源构建需包含锁文件、native库、生成镜像、主题/字体配置的校验记录；若修改过未提交工作树，记录dirty patch与hash，但不能标“干净commit的最终验收”。最终候选必须可从干净commit重建。

## 4. 原图与标注图

原图原样保存；需要标注时新增`annotated/`，记录对应原图。不能裁掉错误/目标/执行按钮后说通过；局部图必须有全窗口锚定图。不能用ImageGen、美化工具或重新绘制画面冒充运行图。设计稿和Widget图只存design或独立preview目录。

用一次性fixture和虚构host避免秘密进入原图。必须脱敏才能分享的历史截图只能作为经过修改的辅助图，不能作为本包要求`modified:false`的正式原图；重新用无秘密fixture捕获。不得提交真实密钥、密码、用户Shell历史、私人仓库路径或真实token。

159个检查点代表应证明的状态，不强制159个独立文件。一个截图覆盖多个相容状态时填`reuse_reason`并人工确认；不能同图证明light/dark、提交前/后、different pane等互斥状态。状态名称相同不代表来源相同。

## 5. 录屏规范

固定流程从清楚的起始状态录到结果，展示触发动作、目标、审批/输入状态、结果和返回；禁止剪掉失败后假称一次连续通过。可另提供剪辑摘要，但原始连续视频仍保留。录屏不需要拍整个私人桌面，原生App+必要系统输入法/读屏状态足够。

动态证据需要视频与可对应的行为日志。键盘测试日志记录实际modifier和resolved action，不能只写“按了Ctrl+C”。VoiceOver可用音轨或逐步人工操作记录；无法录音写限制。性能测试另跑不录屏的样本，避免采集开销污染。

## 6. 行为日志与一次性口径

记录匿名run/session/task/pane/window/operation/submission/block id、proposal revision、source、owner generation、event、时间与结果；公开fixture可记录命令摘要。必要事件：draft_prepared、intent_resolved、proposal_reviewed、submission_requested/accepted、receipt_unknown、observer_input_rejected、takeover_revoked、focus_restored、reader_anchor_restored。

`accepted_operations[id] <= 1`与副作用计数<=1，**不是write syscall数量=1**。只读断言是observer UI来源的键位/鼠标/粘贴/焦点报告写入=0，**不是整个PTY零字节**；原有协议应答和其他有效已授权操作可能存在。声明source标签必须与真实调用路径核对，不能给越权改标签。

## 7. 实现C、证据E与最终C4

每阶段先提交实现C，再从C构建采证，最后提交仅文档/证据E。记录C和E；E不可作为自己文件中的自引用“本次commit”。可在最终回复或后续记录填E。

阶段验收可以使用其阶段C。最终集成候选冻结C4后重新跑受影响场景。自动`--gate final`严格要求所有通过case的after证据来自manifest的最终implementation_commit。未变场景要沿用旧C，需另提交依赖闭包文件/hash、锁文件/资源/驱动环境对照和人工批准，标`manually_reviewed_reuse`，**不能靠自动脚本称最终全过**。缺任何证明直接重跑。

比较C..E应只含允许的文档与证据。产品源、测试驱动、构建配置、native依赖、字体/主题变化都可能改变证据；“只改UI”不是免测理由。

## 8. 状态与阶段退出

case：`not_run / blocked / failed / passed`。阶段：`planned / in_progress / implemented_unverified / blocked / failed / verified`。未跑不能写passed；代码做完但缺原生环境写implemented_unverified。

所有P0/核心P1修复且有证据后才能verified。非阻断P2须明确issue与接受人；不删除用例或下调阈值来凑过。模型失败、产品失败、测试驱动失败和环境阻塞分别记录。Linux/Windows的not_supported是平台事实，不是macOS可免测理由。

## 9. 校验命令

```sh
# 从PRD根目录运行：模板只校验结构，不会认证产品
python3 scripts/validate_evidence.py templates/manifest.template.json
# 某阶段实际证据与逐case嵌图
python3 scripts/validate_evidence.py evidence/manifest.json --gate D1
# 最终严格gate
python3 scripts/validate_evidence.py evidence/manifest.json --gate final
# 校验器自身测试，不是产品测试
python3 -m unittest discover -s scripts -p 'test_*.py' -v
```

自动校验检查覆盖、状态、平台/原生声明、文件、PNG尺寸、哈希、commit、录屏/日志、行为断言及逐case嵌图。它不理解画面是否真属于产品，也不判断测试是否造假；09人工审查不可省略。
