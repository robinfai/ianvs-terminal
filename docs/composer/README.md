# Composer

`composer` 分支实现独立、可选的命令编辑器，UI 参考
[Warp Universal Input](https://docs.warp.dev/terminal/input/universal-input/) 的
Terminal 模式：底部停靠圆角输入区、顶部会话/目录标签、多行等宽编辑区、紧凑底栏、
向上浮动的候选列表。颜色来自宿主 ColorScheme，支持深浅色、窄窗口和放大文字。

每个桌面 Session 底部的 **Composer · 命令编辑器** 开启编辑器。Tab 选择/接受候选；
选中候选时 Enter 只接受候选，无选择时 Enter 提交；Shift+Enter 换行。
Esc 依次关闭候选、折叠选区、回到传统终端。Cmd+Z / Cmd+Shift+Z 撤销/重做，
Ctrl+C 清空本地草稿。复制保留原始草稿内容。关闭 Session 会丢弃其内存草稿；
切换输入模式、标签或窗格不会将草稿写入 PTY。

文件夹按钮可按会话开启本地文件/目录及 package scripts 候选，默认关闭。
它只读取受当前 shell 租约约束的 cwd 和输入的子目录，不执行脚本、不查询集群。
长命令运行、续行和密码输入使用原终端；shell 回到空顶层提示符后可恢复 Composer。
SSH、Bash、fish 或未提供可信适配器的宿主仅有草稿和静态候选，Run 不可用。
iOS 不展示此桌面编辑器。Replay 继续只读。

## 范围与来源

来源是用户提供的 `ianvs-composer-v2-20260929.zip`（SHA-256
`3f3c801e00a351202233b99723ffdd3e708da5746679b576d3b65d83429767bc`）。
文档用作设计提案和验收参考，不视为额外操作授权。从 main `0c71b522` 建立分支。
仅迁移旧 `codex/wasm-completion` 中的纯 matcher/catalog，来源与许可证边界见
[PROVENANCE.md](../../native/completion_core/PROVENANCE.md)。不恢复旧 ABI、toolbelt、
历史采集或 Project Workspace。当前唯一 active lane 仍为 runtime-contract-stability。

| 方案阶段 | 实现状态 | 证据状态 |
|---|---|---|
| F0/F1：纯 matcher、当前合同、独立草稿、静态候选、异步 identity 校验 | 已实现 | Rust / Dart / widget 回归；真实窗口检查 |
| F2：本地 zsh 提交、raw 回退、本地文件/scripts provider | 已实现限定范围 | macOS 27.0 / arm64 / 系统 zsh 5.9 的真实 PTY 与应用验收入口 |
| UC-06/21：真实拼音输入法、VoiceOver 完整操作、全部支持 OS 与插件/keymap 组合 | 保留原生输入与语义入口 | 尚未完成完整人工矩阵，不宣称发布验收全部通过 |
| F3：Bash/fish、远程桥接、历史选择器、Kubernetes provider | 延期 | 无增强提交支持声明 |
| F4：WASM parity、高亮/snippet、AI 路由 | 延期 | 未实现 |

ZLE fd 回调无法直接结束当前 read loop，实测后采用“私有通道准备 + 单次 NUL 唤醒 +
commit widget 再校验”。这是方案中纯通道交接的具体适配；不使用清行/盲打 Enter。
自定义 NUL 键位会拒绝提交，builtin accept-line 不经过用户包装 widget。完整合同、
超时、取消和文件系统预算见 [Composer V1](../protocols/COMPOSER_V1.md)。

## 代码与验证

- 纯核心：`native/completion_core`，仓库自有 14 条 Fig-style command specs。
- 原生宿主：`native/core/src/composer_bridge.{rs,zsh}`、`completion_host.rs`。
- 可复用组件：`packages/ianvs_terminal/lib/src/composer`，同步到 `ianvs_terminal_core`。
- 产品组装：`example/lib/features/terminal_composer/composer_pane.dart`。
- Widget previews：`example/lib/ui/previews/composer_preview.dart`，深色、浅色、2x 窄窗。

```sh
make test-composer
make test-composer-ui
make terminal-core-check
```

聚焦测试覆盖范围替换/右侧保留、Unicode 边界、IME composition 阻止提交、乱序/取消、
增量候选、按会话隔离、深浅色 2x、重复提交、拒绝/未知保留草稿、cwd/export、
多行、非空 shell buffer、续行、密码 raw 隔离、文件名转义、权限默认关闭、预算与脚本不执行。
自动化 IME composition 测试不能代替真实输入法；AX 标签检查不能代替完整 VoiceOver 验收。

2026-09-29 本机 `make verify` 通过，包含 1,968 项示例应用测试、45 项真实 PTY 用例、
Composer 应用验收、Debug/Release 构建、签名和原生 Xcode 测试。
最后的候选取消/滚动修正另通过 canonical 与 standalone 各 18 项回归、3 张快照比较、
真实 Composer 应用测试及重新构建的 Release 签名检查。

本次主机：macOS 27.0 (26A428)、arm64、`/bin/zsh` 5.9。其他 Apple 支持版本保持
[现有兼容窗口](../APPLE_PLATFORM_COMPATIBILITY.md)，尚未在本次运行中验证。
新增/受影响的 Composer 界面快照只在该主机生成。按仓库的逐 OS 基线规则，
macOS 26 CI 的六张旧快照仍需在 macOS 26 更新，并生成三张 Composer 快照；
这部分 CI 验收尚未完成，不跨系统复制图片充当基线。
本地 provider 不承诺中断内核中阻塞的文件系统调用；固定并发上限避免累积工作线程。
