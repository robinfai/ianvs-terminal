# Terminal Graphics / Pets 闪烁问题总结

## 当前状态

代码侧已经针对用户录制的 `demo.cast` 完成修复和回放验证。当前结论不是“所有 `graphics=[]` 都不能出现”，而是按协议区分三类情况：

```text
1. delete + replacement 同一视觉事务：不能向 Dart 暴露中间空图层。
2. 用户打开 /pets 菜单、Loading Pet、hide/reselect 等独立 delete：可以清空。
3. Codex 退出时 final Kitty delete：必须清空，不能靠应用退出兜底。
```

最新 replay 使用当前 `native/core/target/debug/libianvs_core.dylib`，结果为：

```text
frames=174
graphicFrames=138
emptyAfterGraphic=34
uniqueRenderIds=[1,113,118,132]
```

这些空图层不再集中出现在普通动画 replacement 中。样本分布是：cast line 4699-4712 对应 `/pets` 菜单输入期间的独立 delete，cast line 5635 之后对应退出后的 final delete 清理。退出清理现在已经通过 Kitty delete 事件落地为 `graphics=[]`。

## 已修复的根因

本轮最终确认过两个不同问题：

```text
问题 A：pet replacement 周期中暴露了中间空状态
graphics=[old]
graphics=[]
graphics=[new]
```

这个会造成用户看到周期性闪烁。修复方向是 Rust 侧延后发布中间态：replacement 到达前不把这个空窗交给 Dart。

```text
问题 B：final Kitty delete 被延后逻辑吞掉
graphics=[old]
delete without replacement
graphics=[old]
```

这个会造成退出 Codex 后图片残留。修复方向不是监听应用退出，而是让没有后续 replacement 的 Kitty delete 在 Rust 状态机里真正提交为空图层。

修复后，Rust 在 ED 2/3 clear 后保留 pending cleared Kitty placement；Kitty delete 后保留 deleted tombstone 只用于后续 replacement 复用 render id。`q=2` 只作为响应抑制处理，不再改变 delete 语义。

## 已经完成或阶段性完成的工作

- 将目标从 terminal pets 专用修复升级为通用 terminal graphics 能力。
- 引入 `TerminalFrameDiff.graphics`，frame 只传 placement 和 asset 引用。
- Rust 侧解析和管理 Kitty/Sixel/iTerm2 图片能力。
- FFI 提供 asset meta 和 RGBA copy。
- Dart/Flutter 增加 graphics model、cache 和 viewport overlay 绘制。
- 处理过 Kitty payload 泄漏、多 pet 叠加、透明通道乱码、input 背景被误修等问题。
- 已有专项测试覆盖 quiet delete、split replacement、clear-screen 单帧 deferral 等场景。

## 关键证据

修复前最新 replay 线索显示：

```text
frames=167
graphicFrames=163
emptyAfterGraphic=2
uniqueRenderIds=[1,100]
```

空窗位置包括：

```text
index 102: graphics=0, fallback=clear_screen
index 103: graphics=0, fallback=conflicting_scroll_regions
index 104: graphics=1, render=100
```

当前 replay：

```text
frames=174
graphicFrames=138
emptyAfterGraphic=34
uniqueRenderIds=[1,113,118,132]
```

这次不能再用 `emptyAfterGraphic=0` 作为完成标准，因为退出清理必须产生空图层。完成标准改为：

```text
普通动画 delete+T 不产生中间 empty frame。
final delete 后必须产生 empty frame。
菜单 / loading 的独立 delete 允许产生 empty frame。
```

## 已落地的改进

1. 补强 `session_frame_diff_defers_single_clear_screen_graphics_gap`，覆盖 clear 后等待 replacement 期间不能输出空 `graphics`。
2. 新增 `parser_terminal_reuses_pet_render_id_across_clear_quiet_delete_and_moved_redraw`，覆盖 clear、quiet delete、分片 PNG、位置变化后仍复用 `render_id`。
3. 新增 `parser_terminal_clears_codex_pet_after_split_replacement_final_delete`，覆盖 split replacement 后的 final delete。
4. 新增 `session_frame_diff_clears_codex_pet_after_split_replacement_final_delete`，覆盖 session frame diff 的退出清理。
5. 新增 `parser_terminal_reuses_pet_render_id_across_adjacent_sync_replacement`，覆盖相邻 synchronized update 边界。
6. `GraphicsStore` 新增 pending cleared Kitty placement 和 deleted tombstone。
7. frame diff 将 pending cleared placement 纳入 placement 和 asset snapshot 输出。
8. `matching_cleared_kitty_graphic_id` 支持同 placement 的单候选匹配，避免位置变化导致换 id。
9. 显式 Kitty delete、删除 image、按 cell 删除会清理 pending cleared placement，避免真实删除被复活。

## 不建议的方向

- 不要靠 Dart 固定延时保留旧图来掩盖问题。
- 不要硬改光标所在行或 Codex input 行背景。
- 不要通过降低 frame diff 频率来减少看到闪烁的概率。
- 不要把阶段性 replay 成功当作最终完成，必须用当前构建和用户复现场景再验证。

## 完成定义

本轮代码侧已达到：

- 当前 `demo.cast` replay 中 final delete 后输出 `graphics=[]`，退出后不残留 pet。
- replacement 过程中不会把 split transfer 的中间空窗暴露给 Dart。
- Rust 专项测试覆盖 clear 后空窗和 moved replacement。
- Flutter 不需要 app-specific 背景或时间猜测补丁。

剩余验收项：

- 用户用当前 app bundle 重复启动 Codex，确认退出后 pet 被清理，普通动画不再明显闪烁。
