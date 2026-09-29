# Composer 全面设计优化

日期：2026-09-29。工作分支：`composer`。实现前基线：`5f164bea`。

## 用户目标与范围

启用 subagent，使用 imagegen 对 Composer 每个 UI 细节进行优化设计。图标可以重新设计；
每个功能的用途、状态表达和交互逻辑也需要梳理并落实优化。

本轮面向 Trail 桌面终端用户。保留 Warp Universal Input 式底部独立命令编辑体验，
让环境、输入归属、候选采用和命令执行更容易分辨。实现仍使用当前 Flutter 项目，
覆盖 canonical 与生成的 standalone 包；不把设计图作为运行时 UI 图片。

范围包括环境与目录、输入和灰字、工具栏、历史、补全与详情、自动候选、复制、撤销/
重做、终端输入切换、主操作、发送/运行/草稿/暂停/未知结果、恢复、加载/空/错误状态、
焦点与选区、快捷键、触摸板、窄窗、放大文字、深浅色、高对比和语义标签。

不新增未授权的 AI 模式或云历史。已有 shell 租约与提交边界、采用不执行、IME、
目录补全和触摸板滚动修复是必须保留的行为。

## 设计证据

- [交互审计](COMPOSER_REDESIGN_INTERACTIONS.md)：功能、状态、缺口和验收矩阵。
- [视觉系统审计](COMPOSER_REDESIGN_VISUAL_SYSTEM.md)：tokens、字体、图标、布局与状态。
- [设计前真实 Flutter 基线](redesign-evidence/before/README.md)：16 状态 × 3 配置，共 48 张。
- 可复用捕获入口：`example/test/design/composer_redesign_capture_test.dart`。

审计由三个 subagent 分别承担交互、视觉系统与基线捕获；主代理负责整合、imagegen、
后续实现分工及最终验证。实际基线使用 macOS 27.0；尚不代表其他支持 OS 的验证。

## Imagegen 视觉方向

使用内置 `image_gen`，没有使用 CLI 或 API key fallback。以下编号严格对应本轮聊天
中生成图像的显示顺序，每个方案为独立生成结果。源截图均为已经查看的本项目真实
Flutter 渲染；生成的文字与 glyph 只作为视觉参考，不直接进入产品。

| 显示顺序 | 设计图 | 完整生成 prompt | 输入参考 |
| --- | --- | --- | --- |
| 1 | [option-1.png](redesign-evidence/concepts/option-1.png) | [prompt](redesign-evidence/concepts/option-1-prompt.txt) | `example/test/design/goldens/macos-27/composer/light.png` |
| 2 | [option-2.png](redesign-evidence/concepts/option-2.png) | [prompt](redesign-evidence/concepts/option-2-prompt.txt) | `example/test/design/goldens/macos-27/composer/dark-history.png` |
| 3 | [option-3.png](redesign-evidence/concepts/option-3.png) | [prompt](redesign-evidence/concepts/option-3-prompt.txt) | `example/test/design/goldens/macos-27/composer/light.png` |

当前状态：**用户选择的显示顺序方案 1 已实现，独立视觉 QA 通过。**
视觉目标固定为 `option-1.png`：三层 dock、安静的环境信息、文本所有权状态、明确主操作，
上方独立候选与详情面板。按 1712×920 图像的 2× 密度对照 856×460 逻辑视口。
模式标签保持静态，不复制生成图中无对应功能的下拉箭头。窄窗保持全部操作可达。

生成图中示例 shell 输出、提交散列和分支名是 mock 内容，不是仓库状态证据。
方案 1 的模式下拉箭头不得照搬成无功能控件；当前只有命令模式。
方案 3 的历史弹层仍需在实现时跟随真实输入位置并约束可用空间。

## 实现与验收计划

- [x] 核对当前源码、分支与已有产品视觉参考。
- [x] 启用三个 subagent 分别审计交互、视觉系统和实际渲染。
- [x] 使用 imagegen 生成三个独立方向，保存图片与完整 prompts。
- [x] 捕获设计前浅/深/窄窗 2× 的完整状态基线。
- [x] 用户选定视觉方向：方案 1。
- [x] 完善所有状态的具体结构与文案。
- [x] 建立统一主题 tokens 与语义图标映射，复用宿主的向量图标字体。
- [x] 实现全部界面细节、响应式布局、明确的状态/主操作与完整辅助操作入口。
- [x] 修复审计确认的状态生命周期问题，补充行为回归。
- [x] 更新交互预览，生成 after 证据，与 before/视觉目标对照。
- [x] 验证深浅色、窄窗/短窗、2× 字体、高对比、焦点和语义；IME/键盘/触摸板的自动与手工边界见下表。
- [x] 运行 canonical/standalone、真实 macOS 应用回归及静态分析，检查镜像一致性。
- [x] 构建并校验本地 Release；实现与验收记录一同提交 `composer`。

## 最终实现

环境、命令编辑、操作区形成三层 dock；就绪状态位于环境行右侧。候选列表与详情独立
位于输入区上方，按实际可用空间布局，短窗优先保留结果，窄窗可打开完整可选择的详情。
“历史”“自动建议”“更多”保持可见，复制/撤销/重做/清空/终端输入/快捷键统一位于更多菜单。
采用与执行使用同一决策逻辑，按钮和 Enter 不再分歧，灰字不会隐式加入命令。

执行反馈与补全反馈分离；仅结果未知保留 pending transaction，确认接收或拒绝后立即清理。
晚到的响应保留新草稿，恢复草稿不重试执行。触摸板滚动不因悬停或普通模型更新重定位；
鼠标跨帧点击采用和拖选详情保留正确焦点。延迟焦点回调会复核当前活动窗格及输入归属。

新增 `ComposerTheme` 与 `ComposerIcons`，复用宿主 ColorScheme、字体和真实图标资产。
全部视觉实现为 Flutter 控件。默认细边框、高对比状态、禁用态、文字放大与长路径截断
集中使用主题角色；图标操作带可访问名称，自动建议名称包含开/关，候选保留选中与采用语义。

- [同密度最终浅色图](redesign-evidence/after/final/reference-light-completion.png)
- [深色补全](redesign-evidence/after/final/reference-dark-completion.png)
- [窄窗 2× 未知结果](redesign-evidence/after/final/narrow-2x-unknown.png)
- [渲染矩阵、命令与限制](redesign-evidence/after/README.md)
- [独立视觉复核、修复迭代与允许差异](../../design-qa.md)

## 最终验收

主机为 macOS 27.0 (26A428)、arm64、系统 zsh 5.9。以下逐项对应交互审计 A01–A17；
自动测试、实际应用观察与尚未执行的人工矩阵分开记录，不将实现完成等同于全部平台发布验收。

| 项目 | 本轮实现与证据 | 限制 |
| --- | --- | --- |
| A01 功能入口/状态 | dock、完整 More、空/加载/失败/未知状态；127 场景渲染、9 项布局交互、独立 QA | 127 图自动覆盖，人工看代表场景 |
| A02 主操作一致 | controller 公共 primaryAction；采用不提交、再次执行；真实窗口点击采用与执行观察 | CUA 组合键不用于证明键盘矩阵 |
| A03 pending 生命周期 | 新控制器回归覆盖 accepted/rejected 清理、unknown 保留及晚到响应 | 无自动重试 |
| A04 未知结果持久性 | execution/completion 独立；loading、编辑、polling、复制后未知反馈仍可见 | 测试控制器与渲染 fixture |
| A05 自动建议/Tab | 新开关语义与可逆状态；原有每次 Tab 授权回归保留 | 偏好仅当前会话 |
| A06 路径 | 原生应用集成重跑 cwd、父级、绝对、HOME、空格/中文连续 Tab 并 cd | Rust/provider 未改；符号链接沿用既有回归，不冒充新手测 |
| A07 历史 | toggle、关闭、Esc/Down 恢复选区、无结果；真实 shell history 集成 | 完整原稿/选区有控制器断言 |
| A08 滚动 | wheel/pan-zoom、悬停与更新时位移断言；原生集成持续滚动 | 未做物理触摸板惯性手测 |
| A09 会话/取消 | 既有 cancellation/identity/独立会话回归通过 | 未扩大协议或 provider 范围 |
| A10 灰字/复制 | 灰字绘制与原稿分离；精确复制测试；实际 OS Copy→Edit/Paste 往返 | 原生样例为 `printf 'composer-native-reviewn'` |
| A11 编辑操作 | 多行/软换行、Unicode、选区、undo/redo、clear/recover 回归；窄窗 More | 模拟键盘与原生点击证据分开 |
| A12 IME | composition 阻止提交/补全的自动测试保留 | 真实拼音输入法人工矩阵未执行 |
| A13 焦点 | 原生应用采用→执行→ready；跨帧鼠标采用/详情选区；pane 回调复核 | 密码/raw 等既有原生集成路径，不声称全生命周期手测 |
| A14 视觉 | 127 渲染、同源同密度对比、浅深/320/360/2×/短窗/高对比；9 金图 | macOS 26 金图需在对应系统更新 |
| A15 可访问性 | More/关闭名称、auto On/Off；语义 tap/selected/disabled 回归；原生 AX 复核 | 未进行完整 VoiceOver 操作 |
| A16 工程一致性 | canonical 与生成镜像相同回归、静态分析、同步检查，结果见下方 | 仅修改 canonical，镜像使用同步脚本 |
| A17 运行产物 | 仓库签名脚本构建本地 Release，Mach-O/host dlopen/签名校验 | 本地 ad-hoc 签名；未安装、发布或推送 |

原生前台检查使用本轮单独启动的 `Trail Development.app`，未操作用户已安装的 Trail。
CUA 主线程输出包含候选、采用后草稿、完整 More、执行后清空与就绪，以及 OS 剪贴板
回填的真实截图；这些图片未另存到仓库，不提供虚构的磁盘链接。原生字体和
`TrailLightIcons.ttf` 已核对，固定字体 fixture 图与它们不是逐像素相同的证据。

随后对原生命令字宽复核，发现仅声明 `monospace` 在 macOS 会回退成比例字体：同长度的
`iiiiiiii` 与 `WWWWWWWW` 分别为 32.7679 和 119.0400 逻辑像素。现已将终端实际字体
与 Menlo 等加入回退链。相同原生字宽断言与完整应用流程由失败转为通过；不再仅依据
注册了固定字体的 golden 判断原生等宽性。最终 127 张 fixture 图 SHA-256 均与修复前一致。

CUA 的组合键注入曾只送出 C 而未送出 Control（临时事件日志 `ctrl=false meta=false`），
因此不把该工具的 Ctrl+C 结果视为产品快捷键验证；普通 Esc 返回终端已观察。临时
诊断代码已移除。真实键盘、物理触摸板、IME、VoiceOver 和其他支持 OS 仍属于发布前
人工覆盖项，不是本次伪造的通过项。

最终执行结果（2026-09-29）：

| 检查 | 结果 |
| --- | --- |
| canonical Composer 单元/组件回归 | 76/76 passed |
| 自动生成 standalone 同套回归 | 76/76 passed |
| 渲染 127 + macOS 27 金图 9 + 布局交互 9 | 145/145 passed |
| 真实 macOS 应用、zsh 及原生等宽字宽断言 | 1/1 passed |
| 修改的 Composer/宿主/预览/测试静态分析 | `--fatal-infos` 无问题 |
| `tools/sync_terminal_core.dart --check` | generated sources are current |
| 最低 Flutter 3.41 的浮层 API | 本地 SDK 的 3.41.0 tag 已确认包含 `OverlayPortal.overlayChildLayoutBuilder` |
| Release | 121.0 MB；Mach-O alignment、host dlopen 与 ad-hoc 签名校验通过 |

[保留的结果日志与 Release App.framework SHA-256](redesign-evidence/after/verification-results.txt)。
当前本地产物：`example/build/macos/Build/Products/Release/Trail.app`。
未更新 macOS 26 的基线，不将本机验证扩展为全部 Apple 支持版本。
