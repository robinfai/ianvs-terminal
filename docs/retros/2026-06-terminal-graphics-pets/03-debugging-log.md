# Debugging Log

## 问题 1: Codex 仍提示 pets 不可用

用户截图显示终端仍输出：

```text
Pets aren't available in this terminal. Terminal pets need image support...
```

判断：

- 这不是单纯“画不出来”，而是上层 Codex 认为当前终端不支持图片协议。
- 需要能力宣告和 query 响应，而不只是 Flutter 画图。

处理方向：

- 增加 graphics config。
- 对 xterm256 profile 开启。
- 增加 Kitty advertise 兼容模式。
- 响应 Kitty query。

## 问题 2: Kitty payload 泄漏成文本

用户截图显示屏幕上大量 `OKGi=49374` 和长串 base64，pet 还大量叠加。

判断：

- APC/OSC/DCS 序列没有完全从文本流中剥离。
- Kitty chunk 续传和响应序列处理不完整。
- delete/placement 没有稳定替换旧图。

处理方向：

- 完整处理 Kitty APC parser。
- 识别 tmux/screen passthrough 包装。
- split/multipart 序列必须在 Rust 侧完整消费。
- 图像输出不应污染 terminal text grid。

## 问题 3: Codex input 背景被吞

用户指出 Codex input 本应有灰色背景，并给 iTerm2 对照图。

判断：

- 背景色是文本渲染语义，不应该通过图像层修复。
- 不能硬改光标所在行背景色。

过程教训：

- 当一个 visual bug 和图像同时出现时，必须先判断它属于文本 style、cursor、selection、row background 还是 graphics overlay。
- 不要为了匹配某个截图写 app-specific 背景补丁。

## 问题 4: 透明背景乱码

用户截图显示 pet 四周出现横向条纹或背景污染。

判断：

- RGBA 透明通道未按 Flutter 解码期望预乘。

处理方向：

- 在 Dart asset cache decode 前执行 premultiply。
- 将图像像素问题和 terminal placement 问题分离。

## 问题 5: 位置漂移和重复启动不一致

用户反馈重复启动时 pet 展示位置不对。

判断：

- Kitty placement 坐标、默认 placement、scrollback row、DPR 和 viewport row mapping 需要统一。
- 不能让 Dart 用上一帧状态推断新位置。

阶段性审查提出过这些风险：

- 无 `p=` 的 Kitty 默认 placement 需要稳定 identity。
- 显式 `p=` 不应只用 placement id，避免不同 image id 冲突。
- `asset_version` 应代表内容版本，不应跟随内部 placement 对象 id。
- scrollback 图像还需要更完整的裁剪和位置记录。

## 问题 6: 明显闪烁

用户反馈：

- iTerm2 中 pet 顺滑变化。
- 当前应用在 Codex 启动阶段闪烁特别明显。
- 稳定后仍轻微闪烁。

关键转折：

- 用户提供 `/Users/robinfai/tmp/demo.cast`。
- replay 统计比截图更明确，能看到 frame diff 输出中的 `graphics=0`。

定位到两个窗口：

1. Quiet delete 与文本刷新交错。
   - terminal pets 先发 quiet delete。
   - Codex 菜单或启动文本刷新。
   - replacement 图像还没有完成。
   - Rust 如果此时提交 delete，就发出 `graphics=[]`。

2. Clear screen 后立刻重传 pet。
   - clear screen 触发 snapshot fallback。
   - pet replacement 紧随其后。
   - 20-30fps frame extraction 可能采到清屏后的空图层 frame。

最终处理：

- `commit_deferred_kitty_deletes_for_visual_output` 不再因为普通文本输出提交 quiet delete。
- `delete_kitty_graphics` 会清掉匹配的 deferred quiet delete，显式非 quiet delete 仍能正确删除。
- `take_frame_diff` 对 `clear_screen + previous graphics + current graphics=0` 做一次 damage-generation 级 deferral。

## 被证伪或收敛的路径

### 仅靠 Dart retention 不合适

曾考虑在 Dart/Flutter 层保留旧 graphics 一小段时间以遮挡闪烁。这能改善肉眼现象，但会破坏语义：

- Rust 如果真的删除图片，Dart 仍可能错误显示。
- 时间窗口大小不可证明。
- 不同机器、不同输出速率、不同 frame cadence 下结果不稳定。

最终原则：

- Rust 输出稳定事实。
- Dart 不猜 protocol 中间态。

### frame diff cadence 是放大器，不是根因

20-30fps 会让中间空 frame 被用户看到，但如果 Rust 不产出错误空 frame，cadence 本身不会导致 flicker。

### 背景色不应由 graphics 修复

Codex input 灰底和 pet 图片是两个层级的问题。硬改 cursor row 背景会制造新回归。

## 调试工具教训

有效工具：

- iTerm2 对照截图。
- asciinema cast。
- replay 脚本统计 `frames`、`graphicFrames`、`emptyAfterGraphic`。
- frame diagnostics：active graphics、scrollback graphics、placement count、fallback reason。

需要产品化的工具：

- 把 `/private/tmp/replay_pet_cast.dart` 迁入仓库工具目录。
- replay 输出应包括 render id、asset id/version、row/col、fallback reason 和 build identity。
- 每次跑 replay 前确认加载的是最新 dylib。

## 问题 7: 退出或显式 delete 后图像残留

用户后续反馈：`67` 一类消失问题解决后，退出 Codex 时 pet 应该被清理，但仍可能残留。这个问题不能通过 Dart 保留或随机超时兜底处理，因为退出清理本身是 Kitty delete 协议语义。

复核判断：

- `a=d` delete 是协议边界；Rust 输出应立刻反映删除事实。
- clear/replacement 的防闪烁延后只适用于“旧图被替换但新图还在传输”的中间态，不能吞掉显式 delete。
- 旧实现中部分 Kitty delete target 直接操作 `store.placements` 或 `store.clear()`，会绕开 `GraphicsStore` 中的 pending clear、deleted tombstone、virtual placement 和 deferred delete 状态。
- `d=a` / `d=c` / 默认 delete / `d=x` / `d=y` / `d=z` 需要统一经过 Kitty-only 删除逻辑，不能误删 iTerm2 或 Sixel 图像。

处理方向：

- 在 `GraphicsStore` 内新增统一 Kitty delete helper。
- 删除匹配项时同时清理 active placements、pending cleared Kitty placements、deleted tombstones、virtual placements 和无 tombstone 的 deferred delete。
- `kitty.rs` 只负责把 delete target 映射到 store 方法，不再直接改内部集合。
- 不新增 Dart fallback，不新增运行时延迟。

新增确定性测试：

- `parser_terminal_kitty_delete_all_preserves_non_kitty_graphics`：Kitty `d=a` 只删除 Kitty 图，不删除 iTerm2 inline image。
- `parser_terminal_kitty_delete_by_z_index_clears_pending_clear_hold`：ED2/ED3 清屏后处于 pending clear 的 Kitty 图，收到 `d=z` 后必须被清理。

验证口径同步调整：

- 早期用 `emptyAfterGraphic=0` 证明“无闪烁空帧”。
- 当前更严格的口径是：空图像 frame 必须能在 cast 中对应显式 Kitty delete 或退出清理；replacement、animation frame、普通文本刷新不能产生无协议依据的空图像 frame。
