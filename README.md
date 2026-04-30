# Ianvs Terminal

Ianvs Terminal 是 Ianvs 产品族下的现代终端客户端。当前推进 macOS Flutter app 和本地 shell 基础能力，不生成 Windows、Linux、iOS、Android 平台目录。

## 当前边界

- 客户端框架：Flutter。
- 首要平台：macOS。
- terminal 实现：依赖 `/Users/robinfai/personal/flutterm`。
- `flutterm_pty` 只用于 `NativePtyBackend.load()`；terminal runtime、viewport 和输入能力走 `flutterm_terminal`。
- macOS App Sandbox 必须关闭，否则 flutterm native core 无法创建本地 PTY shell。
- M1A 聚焦单个本地 shell session：运行状态、退出状态、重启、复制和粘贴。
- M1B 补齐单会话输出查找：Search / Cmd+F、结果跳转、选中当前匹配和复制。
- M1C 增加单窗口多 tab：每个 tab 是独立真实本地 shell，支持新建、切换、关闭和后台退出态保留。
- M1D 增加最小设置：字体、字号、主题预设和默认 shell，本地保存并即时应用到现有 tab。
- M1E 收口 macOS 桌面入口和本地使用验收：菜单、启动 prompt smoke、手工验证说明。
- M2A 增加 block 能力打底：产品侧 block 模型、header 操作、复制、跳转和重新输入接缝。真实 shell 尚不会自动生成 blocks。
- M2B 接入真实 zsh 命令 block：flutterm 提供通用 `shell_hook` 事件，Ianvs Terminal 通过 zsh integration 生成 block；非 zsh shell 暂不自动生成 block。
- M2C 增加 block 历史面板：当前 tab 的 blocks 可见、可选择、可跳转、可复制和可重新输入；暂不做 terminal 内 inline block card 或分隔线。
- M3A 增加默认现代输入栏：普通命令先进入底部输入栏，`Enter` 提交，`Shift+Enter` 换行；`Cmd+Shift+I` 切到 Raw 输入，`Cmd+K` 回到现代输入。
- M3B 增加当前 tab 命令历史搜索：历史来自已完成 blocks，`Cmd+R` 打开，选择后只回填现代输入栏，不自动执行。
- M3C 增加本地保存命令库：保存命令和当前 tab 历史统一进入命令搜索面板，保存命令全局可见。
- M3D 增加现代输入括号与引号补全：只作用于底部现代输入栏，支持 `()`、`[]`、`{}`、`'`、`"`，不补反引号。
- M3E 增加 Fig specs 转换框架和现代输入补全：Node 只用于构建期转换，运行时用 Dart 解析 JSON、路径模板和可转换 generator。
- M4A 增加单窗口 split panes：一个 tab 内可拆分多个真实本地 shell pane，Header、菜单和输入区始终作用于 active pane。
- M4B 增加基础 session restore：自动保存和恢复单窗口内的 tab、pane tree、cwd、active tab 和 active pane；恢复时重新创建真实 shell，不恢复旧进程或输出。
- 不在本项目实现零信任接入客户端、虚拟网络、流量网关、SSH 网关、AI 网关或管理后台。

## 设置

设置文件位置固定为：

```text
~/Library/Application Support/Ianvs/ianvs-terminal/settings.json
```

保存命令文件位置固定为：

```text
~/Library/Application Support/Ianvs/ianvs-terminal/saved_commands.json
```

Session restore 文件位置固定为：

```text
~/Library/Application Support/Ianvs/ianvs-terminal/session_restore.json
```

Fig completion specs 默认资产位置：

```text
assets/fig_specs/index.json
assets/fig_specs/specs/*.json
assets/fig_specs/diagnostics.json
```

当前设置项：

- 字体名称：为空时使用 flutterm 默认字体。
- 字号：默认 `14`。
- 主题：`Dark`、`Graphite`、`Light`。
- 默认 shell：默认使用当前用户 `$SHELL`，没有时使用 `/bin/zsh`。

字体、字号和主题修改后会立即影响所有已有 tab 的显示。默认 shell 只影响后续新建 tab 和当前 tab 的 Restart；不会替换已经运行中的 shell 进程。

## 常用验证

```bash
flutter pub get
flutter analyze
flutter test
flutter build macos
```

真实 shell smoke 需要显式指定本地 flutterm native core：

```bash
FLUTTERM_CORE_LIB=/Users/robinfai/personal/flutterm/native/core/target/debug/libflutterm_core.dylib flutter test test/real_shell_smoke_test.dart
```

这个 smoke 会验证普通输出、`echo ianvs && exit 7` 的退出码事件、产品侧查找和复制真实终端输出、多 tab 独立输出，以及默认 shell 设置可用于新建本地 shell。
M1E 还会重复启动带可控 `PS1` 的真实本地 shell，验证初始 prompt 文本进入 frame，而不是只显示光标。
M2B 还会用 `/bin/zsh` 验证真实命令 block：`echo ianvs-block` 应生成 succeeded block，`false` 应生成 failed block。
M2C 会验证 block 历史面板和 Header 始终同步当前 active tab，退出态仍可选择、跳转和复制已有 block。
M3A 会验证现代输入提交真实 shell 命令，以及 zsh block 仍能从现代输入提交的命令生成。
M3B 会验证真实 zsh block 可以进入当前 tab 命令历史搜索，选择后回填现代输入栏 draft。
M3C 会验证真实 zsh block 可以保存为本地命令，并在重新加载保存命令库后搜索和回填。
M3D 会验证现代输入栏内括号和常用引号的成对插入、选区包裹、右符号跳过和空成对符号删除；Raw 输入不启用这套补全。
M3E 会验证 Fig 风格 specs、路径模板、可转换 generator、zsh cwd 和 PATH root command 补全。
M4A 会验证一个 tab 内两个真实 shell pane 的独立输出、关闭 pane 后剩余 pane 可用，以及 zsh cwd 继承后的路径补全。
M4B 会验证两 tab / 两 pane 布局恢复、active pane 恢复，以及恢复后的新 shell 使用保存的 cwd。

M1C 多 tab 验证点：

- `Cmd+T` 新建 tab，`Cmd+W` 关闭当前 tab。
- `Cmd+Shift+[` 和 `Cmd+Shift+]` 在 tab 间切换。
- 在两个 tab 分别执行不同命令，切换后输出仍保留。
- 关闭一个 tab 后，另一个 tab 仍保持可输入和可查找。

M1D 设置验证点：

- 点击 Settings 或按 `Cmd+,` 打开设置面板。
- 修改字号后 terminal 字体尺寸立即变化。
- 切换 `Dark / Graphite / Light` 后 terminal 背景和前景立即变化。
- 修改默认 shell 后，新建 tab 和 Restart 使用新的 shell 路径。
- 默认 shell 留空时显示错误，并保留原设置。

M1E macOS 收口验证点：

- macOS 菜单包含 Settings、New Tab、Close Tab、Restart、Copy、Paste、Find。
- 菜单操作和 header 按钮作用一致，都只影响当前 active tab。
- 退出态允许 Copy / Find / Restart，禁用 Paste。
- 只有一个 tab 时禁用 Close Tab；两个及以上 tab 时可关闭当前 tab。
- 启动后 prompt 文本应可见；如果只看到光标而没有 prompt，继续记录到 `FLUTTERM_FEEDBACK.md`。

M2A block 能力打底验证点：

- Header 中的 block 操作在没有 block 时禁用，显示 `Block 0/0`。
- 测试注入 block 后，Header 显示当前 block 序号、状态和命令预览。
- 上一个 / 下一个 block 会跳转到对应 scrollback offset。
- Copy command、Copy output、Copy all 只复制当前 active tab 的 block。
- Reinput 只把命令文本写回当前 active shell，不追加换行。
- 非 zsh 真实本地 shell 当前不会自动生成 block；M2B 只打开 zsh shell integration。

M2B zsh block 验证点：

- flutterm 使用通用 DCS hook：`ESC P hook;<hex-json> ESC \`，不是 Ianvs 专用协议。
- 默认 shell 为 `/bin/zsh` 时，新 session 会生成 `~/Library/Application Support/Ianvs/ianvs-terminal/shell-integration/zsh` 并通过 `ZDOTDIR` 注入 hooks。
- 默认 shell 不是 zsh 时，不注入 `ZDOTDIR`，Header block 区仍按 M2A 行为显示。
- 在 zsh tab 里执行 `echo ianvs-block` 后，Header 应显示 `Succeeded` block，复制输出能拿到 `ianvs-block`。
- 执行 `false` 后，Header 应显示 `Failed` block。

M2C block 历史面板验证点：

- 没有 block 时右侧历史面板不显示，Header 显示 `Block 0/0`。
- 有 block 后右侧面板显示序号、状态、命令预览和输出首行预览。
- 点击面板中的 block 行，Header 的 `Block N/M` 同步变化，并滚动到该 block 的输出位置。
- 面板里的 Copy command、Copy output、Copy all 和 Reinput 操作只作用于当前 active tab。
- 切换 tab 后，面板内容立即切换到该 tab 的 blocks。
- shell 退出后仍可选择、跳转和复制 block，但 Reinput 禁用。

M3A 现代输入验证点：

- 启动后底部输入栏默认聚焦，普通输入不会立刻写入 PTY。
- `Enter` 提交当前 draft 并清空；`Shift+Enter` 在 draft 中插入换行。
- Paste 在现代输入模式下插入 draft；Raw 模式下写入 terminal。
- `Cmd+Shift+I` 切换 Raw 输入，`Cmd+K` 回到现代输入。
- 出现 terminal app 模式时会显示 Auto raw；flutterm 当前未公开 alternate screen，不能覆盖所有场景。
- block 的 Reinput 只填入当前 tab 的现代输入 draft，不直接执行命令。

M3B 命令历史搜索验证点：

- `Cmd+R` 或底部 History 按钮打开当前 tab 的命令历史搜索面板。
- 搜索匹配保存命令和当前 tab 已完成 blocks 的命令文本，大小写不敏感。
- 保存命令优先显示；历史命令最新排在前面。
- 相同命令已保存时，不再重复显示对应历史项；running block、空命令和其他 tab 的命令不会进入当前历史结果。
- `Up / Down` 切换结果，`Enter` 把当前命令填入现代输入栏，不自动提交。
- Raw 输入模式下不打开历史搜索；先用 `Cmd+K` 回到现代输入。
- shell 退出后仍可查看历史结果，但不能重新输入。

M3C 本地保存命令验证点：

- 底部 Save command 按钮保存当前非空 draft，保存前会 trim，空 draft 禁用。
- 命令搜索面板显示 `Saved` / `History` 来源标记。
- History 行可以保存；Saved 行可以删除。
- 保存命令是全局本地资产，切换 tab 后仍可搜索；当前 tab 历史仍只来自 active tab。
- 重新启动 app 后，保存命令从 `saved_commands.json` 恢复。
- M3C 不做标题、标签、云同步、跨设备共享、参数化模板、补全、pane、session restore 或 flutterm 修改。

M3D 输入补全验证点：

- 在现代输入栏输入 `(`、`[`、`{`、`'`、`"` 时插入成对符号，光标停在中间。
- 选中文本后输入上述左符号，会用成对符号包裹选区。
- 光标后方已经是对应右符号时，输入右符号只移动光标，不重复插入。
- 光标夹在空成对符号中间时，`Backspace` 删除整对符号。
- 反引号不自动补全；普通字符、路径补全、命令补全和 shell 语法判断不属于 M3D。
- Raw 输入模式继续把键盘输入交给 flutterm terminal，不走现代输入补全。

M3E Fig specs 补全验证点：

- 构建期转换固定参考 `withfig/autocomplete@aef52acff84c45edde61ae610cc2c964802b9a38`。
- 本地转换命令：

```bash
FIG_AUTOCOMPLETE_DIR=/path/to/autocomplete/src \
FIG_AUTOCOMPLETE_REVISION=aef52acff84c45edde61ae610cc2c964802b9a38 \
node tool/fig_spec_converter/src/cli.mjs
```

- 现代输入栏按 `Tab` 打开或接受补全；补全面板打开时 `Up / Down` 切换，`Enter / Tab` 接受，`Escape` 关闭。
- root command 补全来自 Fig `index.json` 和当前环境 `PATH` 里的可执行文件。
- `filepaths` / `folders` template 由 Dart 读取当前 tab cwd；zsh tab 通过 `precmd.pwd` 更新 cwd。
- 可序列化 generator 由 Dart `Process.run` 执行；JS `postProcess`、`custom` 和函数型 `script` 写入 `diagnostics.json`，运行时不执行。
- Raw 输入模式和 shell 退出态不触发现代补全。

M4A split panes 验证点：

- Header 和 macOS 菜单包含 Split Right、Split Down、Close Pane、Next Pane、Previous Pane。
- `Cmd+D` 向右拆分 active pane，`Cmd+Shift+D` 向下拆分 active pane。
- `Cmd+Option+[` 和 `Cmd+Option+]` 在当前 tab 的 pane 之间切换。
- `Cmd+Option+W` 关闭 active pane；最后一个 pane 时禁用关闭。
- 点击 pane 会切换 active pane；Copy、Paste、Restart、Find、History、Completion 只作用于 active pane。
- 拖动 pane divider 会调整比例，并触发对应 shell resize。
- 新 pane 继承 active pane 当前 cwd；如果 cwd 不存在，回退到默认启动 cwd。
- M4A 不做 session restore、launch configuration、pane 持久化、SSH 或 flutterm 修改。

M4B session restore 验证点：

- 默认自动保存、自动恢复，不新增设置开关。
- 保存内容只包含 `activeTabIndex`、tab fallback title、active pane id、pane tree、split direction / ratio 和 leaf cwd。
- 新建 tab、split pane、关闭 tab / pane、切换 active tab / pane、拖动 divider、zsh `precmd.pwd` 更新 cwd 后会触发保存。
- 重新启动 app 后恢复上次的 tab / pane 布局和 active 状态；每个 pane 都是新建真实 shell。
- restore 文件缺失、坏 JSON、空 tabs 或非法 split ratio 时，直接回退为一个默认 tab / 一个默认 pane。
- 恢复 cwd 不存在时，回退到设置默认 cwd、`$HOME` 或当前目录，并保存回退后的 cwd。
- M4B 不恢复旧进程、scrollback、blocks、modern draft、selection、find query、history query、completion panel、窗口尺寸或窗口位置。

本地启动 macOS app：

```bash
flutter run -d macos
```

如果 `flutter run -d macos` 输出 `Failed to foreground app; open returned 1`，但 app 已构建、进程已启动并显示 Dart VM Service，这不作为 M1E 阻塞项。若手工打开 app 不可见，再单独检查 macOS window activation。
