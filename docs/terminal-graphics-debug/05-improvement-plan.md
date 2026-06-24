# 改进计划和落地记录

## 当前目标

让 terminal pets 在 ianvs terminal 中达到 iTerm2 对照里的基本视觉稳定性：

- pet 不周期性消失。
- replacement 时不闪空。
- 位置稳定。
- Codex input 背景仍走文本样式，不硬编码。
- 真实删除和清屏语义不被永久吞掉。

当前目标的核心边界：

```text
Rust 负责协议解析、delete/replacement 事务归并和 frame diff 状态。
Dart/Flutter 只按 frame diff 绘制，不用延时保留旧图来猜测协议意图。
```

## 已落地：补上当前失败场景测试

### 测试 A：clear 后不能输出空 graphics

复现场景：

```text
graphics=[old]
clear_screen
conflicting_scroll_regions 或其他 snapshot fallback
replacement
```

期望：

```text
不能向 Dart 输出 graphics=[]
```

这个测试对应最新 replay 中的：

```text
emptyAfterGraphic=2
fallback=clear_screen
fallback=conflicting_scroll_regions
```

落地测试：

```text
session_frame_diff_defers_single_clear_screen_graphics_gap
```

### 测试 B：clear 后 replacement 位置变化

复现场景：

```text
old placement: render_id=1, kitty_placement_id=0, row=37
clear
new placement: same kitty_placement_id=0, row=20
```

期望：

```text
render_id 仍稳定，或 Flutter 不因 identity 变化出现空窗
```

当前 `matching_cleared_kitty_graphic_id` 要求 position 一致，这个测试应能覆盖它的不足。

落地测试：

```text
parser_terminal_reuses_pet_render_id_across_clear_quiet_delete_and_moved_redraw
```

## 已落地：clear 后 pending placement 的状态模型

最终采用“pending clear 期间继续输出旧 placement”的模型。

具体做法：

- ED 2/3 clear 时，把当前 Kitty placement 移入 pending cleared 列表。
- frame diff 构建 placement 时，把 pending cleared placement 也纳入输出。
- asset snapshot 同样纳入 pending cleared placement，避免 Flutter cache 在中间空窗被清掉。
- replacement 到来后，复用旧 `render_id` 并移除 pending cleared 记录。
- 显式 Kitty delete、删除 image、按 cell 删除会清理 pending cleared 记录。

保留的取舍：

- 真正的 clear 仍会让 active graphics 为空。
- 对视觉 frame diff 来说，clear/replacement 的中间态会继续显示旧图，避免把未完成的视觉事务暴露给 Flutter。

## 已落地：稳定 render identity

Flutter overlay 是否保留旧图，依赖 `render_id` 是否稳定。

落地规则：

- 对同一 Kitty placement id 的 replacement，如果 clear 前只有一个候选，即使 position 变了也复用旧 render id。
- 如果 image id 相同且只有一个候选，也复用旧 render id。
- 显式不同 image/placement 且不是 replacement 的情况仍生成新 id。

需要覆盖：

- 同 position replacement。
- 不同 position replacement。
- 多候选时不误配。
- 显式 delete 后不复活旧 render id。

## 已落地：防止空 frame 触发缓存误清理

Rust 修复后，Dart 正常不应看到中间空 `graphics`。本轮没有引入 Dart 固定延时或硬保留逻辑，而是在 Rust frame diff 里保证：

- clear/replacement 期间仍输出旧 placement。
- `graphic_asset_snapshots` 包含 pending cleared placement。

因此 `_syncGraphicsCache` 仍按 frame 的 live asset key 工作，不需要特殊猜测。

## 已落地：final Kitty delete 清理

用户最新反馈是：

```text
退出 Codex 之后，pet 应该被清理掉，但现在没有。
```

这次没有采用应用退出兜底，也没有借 `?2004l`、进程退出、Dart 延迟隐藏去绕开问题。处理方式是回到 Kitty 协议事件：

- `q=2` 只表示响应抑制，不表示 delete 可以被无限延后。
- `a=d,d=I,i=...` 到来后，active placement 立即从协议状态中移除。
- Rust 暂存 deleted tombstone，只用于后续 replacement 复用 `render_id`。
- 如果后面没有 replacement，下一次 visual output 或 frame diff 会提交 delete，Dart 收到 `graphics=[]`。

新增覆盖：

```text
parser_terminal_clears_codex_pet_after_split_replacement_final_delete
session_frame_diff_clears_codex_pet_after_split_replacement_final_delete
```

真实 replay 的退出段：

```text
5630: Kitty delete i=49374
5631-5632: Shutting down...
5635+: frame diff graphics=[]
```

这是期望行为，说明退出后不会残留 pet。

## 后续建议：把 replay 工具入库

当前有效 replay 脚本仍在 `/private/tmp`。建议迁入：

```text
tools/terminal_graphics_replay.dart
```

或测试目录下专用 helper。

最低要求：

- 可指定 cast 路径。
- 可指定 dylib 路径。
- 输出关键指标。
- 遇到 `emptyAfterGraphic > 0` 返回非零。
- 打印空 frame 前后摘要。

## 当前完成情况

本轮代码侧已满足：

- 新增测试覆盖 clear 后空窗。
- 新增测试覆盖 clear 后 moved replacement 的 stable render id。
- 新增测试覆盖 split replacement 后 final delete 必须清空。
- `demo.cast` replay 当前构建中，退出段 final delete 后输出 `graphics=[]`。
- 普通 replacement 的中间空窗不再交给 Dart。

剩余人工验收：

- 用户重复启动 Codex 手动观察：普通动画不明显闪烁，退出后 pet 被清理。
