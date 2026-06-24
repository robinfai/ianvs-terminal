# 证据和验证

## 用户提供的主要证据

用户提供过多张截图和一个录制文件：

```text
/Users/robinfai/tmp/demo.cast
```

截图证据覆盖：

- Codex 仍提示 pets 不可用。
- Kitty payload 泄漏成文本。
- pet 多实例叠加。
- Codex input 灰底缺失。
- iTerm2 正确渲染对照。
- pet 背景乱码。
- pet 位置不稳定。
- pet 闪烁。

## 已有复盘中的阶段性验证

当前工作区已有一组复盘文档记录过一次阶段性结果：

```text
docs/retros/2026-06-terminal-graphics-pets/
```

其中记录过 replay 指标：

```text
frames=175
graphicFrames=173
emptyAfterGraphic=0
```

这些记录说明某个构建和某次 replay 下，已经消除了“有图之后输出空 graphics frame”的问题。

但用户最新反馈说明这个状态不能当作最终关闭。可能原因包括：

- 之后又发现新的录制片段或新启动路径。
- replay 使用的 dylib 和正在手动验证的 app bundle 不是同一个构建。
- 单帧 deferral 修复了窄场景，但没有覆盖多 fallback frame。
- render identity 变化导致 Flutter 仍有 decode 空窗。

## 当前最新 replay 线索

修复前，主代理上下文摘要中记录了一次 replay 观察：

```text
frames=167
graphicFrames=163
emptyAfterGraphic=2
uniqueRenderIds=[1,100]
```

两个空图层 frame 出现在：

```text
index 102: kind=snapshot, graphics=0, fallback=clear_screen
index 103: kind=snapshot, graphics=0, fallback=conflicting_scroll_regions
index 104: graphics=1, render=100, asset=49374, row=20, col=217
```

这说明当前问题还没有关闭。关键不是“有没有 pet”，而是曾经有 pet 之后又发出了空图层 frame。

## 当前已跑过的专项测试

主代理上下文摘要记录过这些测试结果：

```text
cargo test session_frame_diff_defers_single_clear_screen_graphics_gap --test session_test -- --nocapture
```

这个测试先红后绿，证明它能捕捉“clear 后 replacement render id 不稳定”的简单场景。

还记录过这些专项测试通过：

```text
cargo test quiet_kitty_delete --test session_test -- --nocapture
cargo test kitty_replacement --test session_test -- --nocapture
cargo test codex_pet --test session_test -- --nocapture
cargo build
```

这些通过结果有价值，但还不足以覆盖当前最新问题，因为 replay 仍显示：

- 连续两个空 graphics frame。
- replacement 后 render id 变化。

## 修复后的 replay 结果和判读方式

修复并重新执行 `cargo build` 后，使用当前 dylib 回放同一个 `/Users/robinfai/tmp/demo.cast`：

```text
IANVS_CORE_LIB='/Users/robinfai/personal/ianvs/ianvs-terminal/native/core/target/debug/libianvs_core.dylib' \
dart --packages=.dart_tool/package_config.json /private/tmp/replay_pet_cast.dart
```

最新输出：

```text
frames=174
graphicFrames=138
emptyAfterGraphic=34
uniqueRenderIds=[1,113,118,132]
assetIds=[49374,49375]
timedOut=false
seenExit=true
```

这次结果说明：

- `emptyAfterGraphic` 不能再机械要求为 0，因为 final Kitty delete 必须清掉图片。
- cast line 4699-4712 的空图层来自 `/pets` 菜单输入期间的独立 delete。
- cast line 5635 之后的空图层来自退出后的 final delete 清理，这是期望行为。
- 普通动画的 split replacement 现在不再通过空图层来更新图片。

本轮关键修正是：退出清理不通过 `?2004l`、应用退出、Dart 延时保留等兜底实现，而是由 Rust 按 Kitty `a=d` delete 事件提交。

## 已补上的验证

本轮新增或更新了这些验证：

```text
cargo test session_frame_diff_defers_single_clear_screen_graphics_gap --test session_test -- --nocapture
cargo test parser_terminal_reuses_pet_render_id_across_clear_quiet_delete_and_moved_redraw --test session_test -- --nocapture
cargo test parser_terminal_clears_codex_pet_after_split_replacement_final_delete --test session_test -- --nocapture
cargo test parser_terminal_reuses_pet_render_id_across_adjacent_sync_replacement --test session_test -- --nocapture
cargo test session_frame_diff_clears_codex_pet_after_split_replacement_final_delete --test session_test -- --nocapture
cargo test quiet_kitty_delete --test session_test -- --nocapture
cargo test kitty_replacement --test session_test -- --nocapture
cargo test codex_pet --test session_test -- --nocapture
cargo build
```

当前重新跑过的聚合验证：

```text
cargo test --test session_test parser_terminal_ -- --nocapture
# 26 passed

cargo test --test session_test session_frame_diff_ -- --nocapture
# 11 passed

cargo test --no-default-features --features rust-only graphics::tests -- --nocapture
# 47 passed

cargo build
# passed
```

## 剩余验证

还建议补充：

1. 用户手动重复启动 Codex，不再看到 3-5 秒间隔消失近 1 秒。
2. 将 replay 工具正式入库，并输出 native dylib 路径、mtime 或 build identity，避免旧构建误判。

当前全量 `cargo test --test session_test -- --nocapture` 结果：

```text
104 passed
0 failed
```

## 建议的 replay 指标

后续 replay 工具建议至少输出：

- `frames`
- `graphicFrames`
- `emptyAfterGraphic`
- `uniqueRenderIds`
- `assetIds`
- 每次 `graphics=[]` 前后的 frame index。
- `snapshot_fallback_reason`
- `render_id`
- `asset_id`
- `asset_version`
- `row`
- `col`
- `width_cells`
- `height_cells`
- loaded dylib path。
- loaded dylib mtime 或 build id。
