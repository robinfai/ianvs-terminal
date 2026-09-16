# 标注图生成记录

模式：内置 imagegen。用途：代码审查后的建议标注，不是原始现场证据，也不是已实现界面。

最终图：/Users/robinfai/personal/ianvs/ianvs-terminal/docs/design/terminal-layout-review-20260916/annotated-review.png

## 首次提示词

Use case: precise-object-edit
Asset type: 中文桌面终端 UI 审查标注图，仅供讨论，不是新界面设计或实现截图。
Input images: Image 1 是用户提供的 Trail 当前四分屏截图，作为唯一需要保留的画面主体/edit target；Image 2 是本轮实际打开应用捕获的同一四分屏现场参考，帮助确认真实性。
Primary request: 扩展画布，在现有截图外围添加六条清晰中文标注。必须保留原截图的 UI 结构、两个平分栏宽的标签、四个窗格、Local Shell 标题、当前粘贴标记、深浅背景差异、现有拆分/放大/关闭图标与 shell prompt；这些现状正是被讨论的对象。不要把优化建议直接画成已经实现的新界面。不要沿用前一轮生成稿。
Presentation: 制作横向高分辨率审查图，目标约 2400×1600。左侧完整原截图按比例缩放，占宽约 68%，四个窗格都保留；右侧外部注释列占约 32%。背景简洁浅灰白；使用六枚蓝色编号圆点和不交叉的细引线精确指向组件；中文用易读黑色无衬线，大号标题。不给软件内部加卡片，不覆盖终端命令。顶部标题“Trail · 代码核对后的优化建议”，副标题“当前界面 + 修改建议 · 尚未实现”。这是审查标注，不是多个设计选项。
Annotation text must be verbatim; short title bold, body regular:
01 指向非活动窗格标题栏里的“粘贴”标记
“模式不是粘贴按钮”
“这是括号粘贴状态，点击仅聚焦窗格”
“普通协议收进「模式」；只读、远端等关键状态保留”

02 指向第一行两个巨宽标签
“标签等宽，但设上限”
“少量标签靠左；新建与溢出同时保留”
“继续支持拖拽、快捷编号和新输出提示”

03 指向左上 Local Shell 窗格标题
“保留动态标题”
“缩短重复编号，目录仅用可靠元数据补充”
“不能把程序标题一律替换成目录”

04 指向非活动窗格的深暗终端正文
“减弱后台正文遮罩”
“当前暗色蒙层约 54%，影响同时阅读”
“保留焦点边框与各 Profile 的终端主题”

05 指向活动窗格标题右侧的拆分/放大/关闭工具图标
“窗格操作就近归组”
“分屏、放大与更多；菜单绑定当前目标窗格”
“明确区分关闭窗格和关闭整个标签”

06 指向中间分屏分隔线
“保留已有布局机制”
“1px 分隔线 + 8px 拖拽区已经实现”
“栏高与终端内边距先保持，不强行对齐 shell 首行”

Footer outside screenshot:
“优先顺序：状态语义 → 正文可读性 → 操作归属 → 标签宽度”
“依据：现有代码与现场窗口；完整证据见配套分析文档”
Constraints: Exactly one annotated audit image. Keep existing screenshot content and all four panes. Do not redesign interface, invent feature states, fabricate a new directory name, delete the paste-state badge, recolor the terminal panes or replace existing title text. Annotation wording must be accurate readable Chinese. No extra charts, no product marketing, no image watermark. Avoid treating this generated marked-up illustration as raw test evidence.

## 最终修订提示词

Use case: precise-object-edit.
Input image is the edit target: the annotated Trail audit board.
Make ONE targeted correction: replace and clean up only the right-side annotation column. Keep the entire left app screenshot, six blue marker positions and leader lines, main heading, subtitle, and bottom footer unchanged. This remains an annotated current-state screenshot, NOT a redesigned application.
Right column must display EXACTLY six entries vertically in order 01,02,03,04,05,06. Use consistent blue number badges, bold Chinese headings, black short description lines. All text must fit with generous right padding; no cropped Chinese words or lines, no overlap. Do not include any instruction such as “指向” in the image. Each entry's heading and two description lines must be exactly the following:

01  模式不是粘贴按钮
括号粘贴状态，点击仅聚焦
普通协议收进「模式」详情

02  标签等宽，但设上限
少量标签靠左，新建入口保留
支持拖拽、快捷编号与输出提示

03  保留动态标题
目录仅用可靠元数据补充
缩短重复编号，不覆盖程序标题

04  减弱后台正文遮罩
当前暗色蒙层约 54%
保留焦点边框和各自终端主题

05  窗格操作就近归组
分屏、放大、更多绑定目标窗格
区分关闭窗格与关闭整个标签

06  保留已有布局机制
已有 1px 线和 8px 拖拽区
不强行对齐 shell 首行

Preserve every other part of the image. Do not add any new interface control or artifact. Produce the final corrected board as a single high-resolution image.
