# Warp 官方视频交互观察

观察日期：2026-09-29。分支：`composer`。

已在浏览器播放、回放并暂停观察官方文档内嵌的四段演示，保存了五张关键画面。
这份记录用于补充交互设计依据；没有操作本机 Warp，也没有把视频中的旧界面当成
当前版本的完整行为合同。时间为播放器显示的约数，不是录制画面左侧的计时器。
只记录可见画面、可读按键提示和官方文档明文；未从音轨转录或推测不可见按键。

## 来源和覆盖范围

| 视频 | 官方入口 | 本次观察 |
|---|---|---|
| [Completions Documentation Demo，53 秒](https://www.loom.com/embed/92594c821ae341f69d5d1c1af56f2c69) | [Tab completions](https://docs.warp.dev/terminal/command-completions/completions/) | 候选位置、选中态、说明卡、自动弹出设置、alias 和目录类型显示 |
| [Input Text Editor Demo，54 秒](https://www.loom.com/embed/1517049fefc34227bf1abaf19cc7e6ea) | [Modern text editing](https://docs.warp.dev/terminal/editor) | 鼠标定位、多行增长、全选、按词移动、复制粘贴 |
| [Command History，30 秒](https://www.loom.com/embed/8119beca8d794b06859c5dea1b1377bb) | [Command history](https://docs.warp.dev/terminal/entry/command-history/) | 历史列表展开、选择变化、输入 `git` 后过滤 |
| [Autosuggestions Demo，约 17 秒](https://www.loom.com/embed/5e87c52ae855486ab88ffb2f89aeaf73) | [Autosuggestions](https://docs.warp.dev/terminal/command-completions/autosuggestions/) | 灰字建议、右箭头接受、接受后仍留在编辑器 |

[Universal Input 官方页面](https://docs.warp.dev/terminal/input/universal-input/) 内嵌的
[Master Warp's Input](https://www.youtube.com/watch?v=4c05OEqzQIA) 未播放成功：
独立嵌入页报错误 153，正常 YouTube 页面要求登录以验证非机器人。没有把标题、
缩略图或文字介绍记作视频观察结果。继续使用可播放的官方 Loom 演示获取基础交互证据。

四段可播放演示展示的是较早的输入界面，未显示可确认的 Warp 版本。
Universal Input 页面现已标为 Legacy；保持用户指定的 Universal Input 视觉目标，
不据此改成新版 Agent 界面，也不直接照搬旧演示的提示符、背景或布局尺寸。

## 视频中实际看见的细节

| 位置 | 可见行为 | 对 Composer 的含义 |
|---|---|---|
| 补全 00:07 | 当前 token 上方出现紧凑列表；选中 `add` 时，右侧显示独立说明卡 | 长说明可随选中项展示，避免每个候选都占两行 |
| 补全 00:12–00:17 | `git checkout` 下列出 `-`、`-2`、`-b`、`-f` 等不同候选，选中项说明同步变化 | 命令、选项、参数位置应决定候选内容；列表选择与说明必须一致 |
| 补全 00:22 | 设置中独立列出输入时打开候选菜单的开关 | 自动展开是独立偏好；不能以它作为显式 Tab 能否使用的条件 |
| 补全 00:37、00:47 | 先显示 shell alias 定义，后在候选中出现 `gc` 及其 `git checkout` 别名说明 | alias 是一种有来源、可说明的候选；本视频不足以证明任意 alias 的参数展开规则 |
| 补全 00:52 | `Movies/`、`Music/`、`Public/` 以目录图标和 Directory 类型显示，名称带 `/` | 候选类型需要直观区分；仅从这帧不能断定接受后插入的转义或尾随字符 |
| 编辑 00:05–00:10 | 鼠标把光标移到同一行中间，并在原位修改文字 | 编辑必须保留插入点右侧文本，无需把整条命令移回行尾 |
| 编辑 00:15、00:20、00:25 | 同一草稿增长为多行；之后所有草稿行一起高亮选中 | 多行是一个编辑缓冲区；换行不产生新的输出块，全选作用于草稿 |
| 编辑 00:30 | 按键显示含 `Option+←`，光标按词向左移动 | 保留平台文本编辑习惯，避免候选按键处理吞掉正常编辑组合键 |
| 编辑 00:35–00:45 | 在前面的行中插入内容，选取文字，并出现复制后的重复文本行 | 中间编辑、选区和粘贴需要共用一个草稿与撤销历史 |
| 历史 00:05–00:20 | 输入区上方出现可滚动历史列表，选中行变化；另有 History Search 提示 | 历史是独立的数据源与选择状态，不能用终端输出搜索代替 |
| 历史 00:25 | 输入 `git` 后，列表保留 Git 历史命令并强调匹配文字 | 召回应支持按当前输入过滤，而不是只遍历无关历史 |
| 灰字 00:01 → 00:02 | `git` 是实色，后面的预测为灰字；按键提示出现右箭头后，整条命令变为实色，仍停留在输入区 | 接受建议只更新草稿，不执行命令；灰字不能提前成为真实文本 |

## 三种建议不能混成一个状态

1. **候选菜单**：当前 token 的命令、参数、目录等可选项；有当前选中项和说明。
2. **行内建议**：光标后的预测后缀；接受前不属于真实草稿，不应被复制或提交。
3. **历史召回**：过去的完整命令；有独立过滤与浏览状态。

这一区分来自以上视频画面。建议 Composer 分别维护这三类状态，但共用同一个
草稿编辑器；接受任何建议的动作与提交命令的动作分开。具体状态优先级仍需用
Composer 回归和后续 Warp 对照验证，不能声称视频已覆盖所有冲突情况。

## 文档补足的键位规则

下面来自 2026-09-29 查阅的官方文档，不等同于视频逐键证明：

- [Tab completions](https://docs.warp.dev/terminal/command-completions/completions/)：Tab 唤起补全，方向键浏览；提供路径模糊匹配、本地 Git 分支等能力。
- [Autosuggestions](https://docs.warp.dev/terminal/command-completions/autosuggestions/)：`→` 或 `Ctrl+F` 接受完整建议；macOS 下 `Ctrl+→` 可分段接受。若把 Tab 改为接受行内建议，唤起菜单的键位改为 `Ctrl+Space`。自动弹出菜单是另一项设置。
- [Modern text editing](https://docs.warp.dev/terminal/editor)：`Esc` 关闭候选或历史菜单；macOS 的 `Shift+Enter`、`Ctrl+Enter`、`Option+Enter` 可插入换行；`Ctrl+R` 打开 Command Search。

**尚未由这些视频确认**：候选菜单内 Enter 是否仅接受、唯一候选是否一步插入、
多次 Tab 的目录续补、空格/中文/隐藏文件的插入形式、Esc 后草稿恢复、历史边界上的
方向键优先级、运行中 Ctrl+C、真实输入法和窄窗布局。保留原体验矩阵对应项目，
不把已有 Composer 行为反写成 Warp 的事实。

## 与当前 Composer 的差距和后续顺序

以 `3eabbab7` 的实现为比较基线，核对了 controller、view 和本地 provider。
本轮只补充证据与设计判断，没有修改运行时代码。

| 顺序 | 当前状态 | 下一步可执行的对齐项 |
|---|---|---|
| 1 | 有 Tab 菜单；没有 Composer 历史召回和独立灰字模型 | 先补历史浏览、按草稿过滤、取消后恢复原草稿；再补灰字预览与接受，避免把预测混入实际命令 |
| 2 | 每条候选占名称和说明两行，普通项统一使用 code 图标 | 宽窗采用紧凑候选与选中项详情，按目录/文件/命令/选项区分图标；窄窗保留可读的内联说明 |
| 3 | 顶部会话/cwd 标签和底栏已具备；目录标签当前主要用于展示 | 依据 Universal Input 文档补足标签的实际动作；不能从旧 Loom 视频推定新版标签交互已验证 |
| 4 | 本地路径只支持 cwd 及其子目录，主要为前缀匹配；缺少动态分支和 alias provider | 另行明确目录范围、匹配与来源合同，再扩展常用路径、模糊匹配、分支和 alias |
| 5 | 已有草稿、多行、IME guard 和按键回归 | 增加多行编辑与候选/历史状态冲突的回归，随后做 Composer 真实窗口检查 |

其中“取消恢复草稿”“响应式详情”“状态优先级”是针对 Composer 的实现要求，
不是这几段视频已经完整证明的 Warp 细节。现有 Tab 按需补全修正继续保留：
关闭自动候选时，显式 Tab 仍可查询当前目录。

## 保存的画面

截图是浏览器播放器中的公开演示帧，保留来源标题和进度条；不是本机 Warp 截图。
播放器控件可能遮挡部分画面，因此只用它们证明可见内容，不据截图推测完整按键序列。

| 文件 | 来源与时间 | 用途 |
|---|---|---|
| [候选详情](warp-video-evidence/completion-details-07s.jpg) | 补全，约 00:07 | 选中项和右侧说明卡 |
| [多行全选](warp-video-evidence/editor-selection-25s.jpg) | 编辑，约 00:25 | 多行仍属于同一草稿 |
| [历史过滤](warp-video-evidence/history-filter-25s.jpg) | 历史，约 00:25 | `git` 过滤与匹配强调 |
| [灰字接受前](warp-video-evidence/autosuggestion-before-01s.jpg) | 行内建议，约 00:01 | 实际输入和预测的颜色差异 |
| [灰字接受后](warp-video-evidence/autosuggestion-accepted-02s.jpg) | 行内建议，约 00:02 | 右箭头接受后仍停在编辑区 |

原本机对照流程、18 项用例及未完成验收保留在
[Warp 体验记录](WARP_EXPERIENCE_20260929.md)。这批视频已足以明确上述交互层次和
可见差距，但不能据此宣称 Composer 已与 Warp 完成对齐。
