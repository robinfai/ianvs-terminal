# Warp 视频交互与 Composer 实现

分支：`composer`。实现基线：`541ddc0a`。日期：2026-09-29。
根据用户要求，把已观看的四段官方演示落实到交互和 UI；来源、时间点和限制见
[视频观察](WARP_VIDEO_REVIEW_20260929.md)。本轮没有重新访问本机 Warp。

## 落实的行为

| 观察 | 实现与验证 |
|---|---|
| 独立灰字后缀，右箭头采用后仍留在输入区 | 独立绘制层，不改 TextEditingValue；复制、选区和提交不含预测。→ / Ctrl+F / Ctrl+E 接受，Ctrl+→ 分段；中间光标、选区、IME、菜单、运行态隐藏 |
| 历史列表、按输入过滤、匹配强调 | ↑ / Ctrl+R / 底栏历史按钮打开；最近命令靠近输入框，按词过滤、匹配加粗、键盘/悬停选择、自动滚动、空状态。Esc 恢复原草稿及选区，接受可撤销，不执行 |
| 紧凑候选与右侧详情 | 宽窗单行名称、类型图标和标签，独立详情卡随选择更新；窄窗把说明放回行内。菜单横向贴近当前 token，并限制在所属输入区宽度内 |
| 自动展开独立于 Tab | 默认输入时保留灰字，手动 Tab 仍可查询目录。开启自动候选后显示菜单；保留唯一结果插入、多结果选择及连续目录补全 |
| alias 的名称和定义说明 | 从当前 zsh 的 aliases 参数获取有界快照；command 位置显示别名图标、类型和定义，只插入 alias 名称 |
| 多行、鼠标原位编辑、选区和按词移动 | 保留原生 TextField 编辑；新增 Ctrl/Option+Enter 换行；↑ 在非首条视觉行先移动光标，避免软换行时误开历史 |

历史由现有会话私有通道读取 zsh 的真实 history 参数，包含原终端执行的命令。
每次 prompt 原子更新，按会话保存在内存，不另开历史文件，不从 PTY 输出猜测命令。
数量、字节预算、alias 来源和提交合同见 [Composer V1](../protocols/COMPOSER_V1.md)。

## UI

继续使用 Universal Input 的底部圆角卡片、顶部会话/cwd 标签、等宽输入和底栏。
候选使用 ColorScheme 的 surface / outline / selection 语义色，复用宿主主题；
列表行高随文字缩放，详情面板随可用宽度切换，加载指示留在状态图标位置。
灰字共享真实 RenderEditable 的字体、行距、缩放和滚动偏移，不参与点击选区。

可交互预览在 [composer_preview.dart](../../example/lib/ui/previews/composer_preview.dart)。
以下是本机 macOS 27 的应用主题渲染，不能作为 macOS 26 的图片基线：

- [深色候选与详情](../../example/test/design/goldens/macos-27/composer/dark.png)
- [浅色灰字](../../example/test/design/goldens/macos-27/composer/light-suggestion.png)
- [窄窗 2x 历史](../../example/test/design/goldens/macos-27/composer/compact-history.png)

## 验证

- canonical 与 standalone 组件各 35 项通过，包含原有 Tab、IME、增量取消、提交和窄窗回归。
- 纯补全核心 10 项、私有通道 5 项、本地 provider 2 项、真实 zsh 集成 2 项通过。
- 真实 zsh PTY 矩阵通过：export、cwd、Unicode、多行、租约过期、非空 shell buffer、
  续行、密码/raw 隔离、close-on-exec 和断线恢复。
- 真实 macOS 应用测试通过：启动历史读取、灰字接受不执行、历史过滤/取消/采用、
  alias 说明、静态候选、连续目录补全、当前 shell 提交和焦点恢复。
- 深色/浅色/360px 2x，分别覆盖候选、历史、灰字，共 9 个视觉状态；截图已检查。
- 修改范围静态分析无问题；镜像通过统一同步入口生成。
- macOS Release 构建通过；使用仓库 `build_signed_apple_release.sh` 的本地 ad-hoc
  签名流程刷新嵌入产物，`codesign --verify --deep --strict` 验证通过。产物在
  `example/build/macos/Build/Products/Release/Trail.app`；没有安装或发布。

主机为 macOS 27.0 (26A428)、arm64、系统 zsh 5.9。应用测试的 Flutter 启动器提示
无法把窗口置前，但应用成功启动并完成所有输入、布局和 shell 断言；不把这次测试
描述为手动置前观察。真实输入法、完整 VoiceOver、其他支持 OS 和插件组合仍需人工矩阵。

## 范围边界

视频没有证明的行为仍保留 Composer 的明确提交合同，例如 Enter 采用候选后要再按
一次才执行、唯一候选的 Tab 插入、历史取消后恢复原草稿。它们已有回归，但不能
据此宣称是 Warp 的逐键实测结果。

本轮完成视频已确认的上述交互与可见 UI 调整。完整 Warp 功能对等仍不在证据范围内：
路径模糊匹配、动态 Git 分支、alias 参数展开，以及目录标签中的
文件浏览器尚未实现；当前 cwd 标签继续展示位置。AI 模式和会话云历史没有加入。
本机 Warp 的完整 18 项矩阵仍见[体验记录](WARP_EXPERIENCE_20260929.md)。

## 后续路径补全修复

用户提供 `cd ../../../` 无补全的截图后，修复了 provider 只允许 cwd 子目录的限制。
父级、绝对、当前 shell HOME 路径和目录链接现在都能补全；`~/'My files/中文目录/'`
保留正确的 tilde 展开。非空选区按 Tab 会给出提示，按 → 折叠选区后可继续补全。
新增真实 zsh 与应用用例覆盖截图路径、带空格/中文的连续补全和接受后实际进入目标目录。

本次在同一台 macOS 27.0 主机验证：canonical/standalone Composer 各 37 项、纯补全
核心 11 项、本地 provider 3 项、真实 zsh 集成 3 项和 macOS 应用回归通过；静态分析、
镜像一致性与本地 Release 构建及深度签名校验通过。选区组件用例覆盖 macOS/Linux
按键映射；应用回归显式送入 macOS 的 `moveRight:` 文本编辑指令，因为集成测试的
模拟按键不会自动经过 NSTextInputContext。未在其他 OS 上执行真实应用测试。

PTY 矩阵首轮在非空 buffer 被拒绝后，发送 Ctrl+C 等待 ready 超时；独立重跑全项通过。
本次没有修改提交协议或据此宣称已消除该时序问题。
