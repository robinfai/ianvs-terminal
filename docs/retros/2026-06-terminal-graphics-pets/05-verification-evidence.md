# Verification Evidence

## Replay

输入录制：

```text
/Users/robinfai/tmp/demo.cast
```

回放脚本：

```text
/private/tmp/replay_pet_cast.dart
```

最终使用 macOS debug app bundle 中的 native dylib 跑 replay：

```text
IANVS_CORE_LIB='/Users/robinfai/personal/ianvs/ianvs-terminal/example/build/macos/Build/Products/Debug/Ianvs Terminal Dev.app/Contents/Frameworks/libianvs_core.dylib' dart --packages=.dart_tool/package_config.json /private/tmp/replay_pet_cast.dart
```

结果：

```text
frames=175
graphicFrames=173
emptyAfterGraphic=0
uniqueRenderIds=[1,100]
assetIds=[49374,49375]
timedOut=false
seenExit=true
```

解释：

- `emptyAfterGraphic=0` 表示 replay 中没有出现“已经看到 graphics 后又突然输出空 graphics frame”的现象。
- `assetIds=[49374,49375]` 符合 Codex pet 更新过程中 image id 切换的场景。

### 2026-06-24 delete 语义复核

用户反馈退出 Codex 后 pet 应清理，复核重点从“完全没有空 graphics frame”调整为“空 graphics frame 必须有协议 delete 依据”。

当前使用 native debug dylib 跑同一份 cast：

```text
IANVS_CORE_LIB='/Users/robinfai/personal/ianvs/ianvs-terminal/native/core/target/debug/libianvs_core.dylib' dart --packages=.dart_tool/package_config.json /private/tmp/replay_pet_cast.dart > /private/tmp/replay_pet_cast_after.json
```

结果：

```text
frames=171
graphicFrames=137
emptyAfterGraphic=32
uniqueRenderIds=[1,113,118,132]
assetIds=[49374,49375]
timedOut=false
seenExit=true
```

解释：

- `emptyAfterGraphic=32` 不再按旧口径直接判失败；这些空图像输出对应 cast 中的显式 Kitty delete 或 Codex 退出后的清理状态。
- 4699-4712 行附近存在 `a=d,d=I,i=49374`，随后才重新 transmit/put `49374`，所以中间空图像是协议要求的删除状态。
- 4928 行附近存在 `a=d,d=I,i=49375`，这是换 pet/loading pet 过程中的显式删除。
- 5635 行附近存在 `a=d,d=I,i=49374`，随后进入 `Shutting down...` 和 shell prompt；图像保持清空是退出清理的正确结果。
- 5049-5635 行附近的动画/重绘帧持续携带 graphics，没有出现 replacement 中间态的无依据空图像。
- 回放脚本仍是真实 session 轮询，帧总数受后端合批影响；验收以 cast 行、delete 事件和 graphics 语义对应关系为准，不以帧数完全一致为准。

## Rust tests

已执行：

```text
cargo test --test session_test -- --test-threads=1
```

结果：

```text
104 passed; 0 failed
```

已执行：

```text
cargo test --lib -- --test-threads=1
```

结果：

```text
30 passed; 0 failed
```

已执行：

```text
cargo test --test vttest_regression_test -- --test-threads=1
```

结果：

```text
3 passed; 0 failed
```

相关专项测试覆盖：

- quiet delete 不因文本刷新消失。
- Codex 菜单刷新期间 pet 不消失。
- clear screen 后单帧空 graphics 被 deferral。
- chunked Kitty replacement 期间旧图保持可见。
- Kitty delete all 只删除 Kitty graphics，保留 iTerm2 inline image。
- Kitty z-index delete 能清理 pending clear hold，不让退出或显式删除后的图像残留。
- Codex shutdown 和 split replacement 的 session 测试使用 PTY 输入握手固定协议顺序，避免测试抢首帧造成随机超时。

2026-06-24 追加执行：

```text
cargo test --test session_test parser_terminal_kitty_delete -- --nocapture
cargo test --test session_test clear_screen_graphics_gap -- --nocapture
cargo test --test session_test clear_quiet_delete_and_moved_redraw -- --nocapture
cargo test --test session_test split_replacement_final_delete -- --nocapture
cargo test --no-default-features --features rust-only graphics::tests -- --nocapture
cargo test --test session_test -- --nocapture
cargo test --test session_test -- --test-threads=1 --nocapture
cargo build
```

结果：

```text
parser_terminal_kitty_delete: 2 passed
clear_screen_graphics_gap: passed
clear_quiet_delete_and_moved_redraw: passed
split_replacement_final_delete: 2 passed
graphics::tests: 47 passed
session_test parallel: 106 passed
session_test serial: 106 passed
cargo build: success
```

## Flutter package tests

已执行：

```text
flutter test packages/ianvs_terminal/test
```

结果：

```text
110 passed
```

覆盖范围包括：

- `TerminalFrameDiff.graphics` 解析。
- graphics cache 去重和失效。
- RGBA premultiply。
- viewport 渲染 resolved graphic placements。
- runtime controller frame merge。

## Static analysis

已执行：

```text
flutter analyze
```

结果：

```text
No issues found
```

## macOS debug build

已执行：

```text
flutter build macos --debug
```

工作目录：

```text
/Users/robinfai/personal/ianvs/ianvs-terminal/example
```

结果：

```text
Built build/macos/Build/Products/Debug/Ianvs Terminal Dev.app
```

产物：

```text
/Users/robinfai/personal/ianvs/ianvs-terminal/example/build/macos/Build/Products/Debug/Ianvs Terminal Dev.app
```

## Goal completion metadata

当前 goal 完成记录：

```text
objective: 不靠猜时间完成事件合并监听；需要合理的 Rust 计算、Dart 渲染，不中断不丢失
status: complete
tokensUsed: 6012990
timeUsedSeconds: 10142
```

人类可读耗时约 2 小时 49 分钟。

## 注意事项

- replay 脚本仍在 `/private/tmp`，尚未入库。
- 后续应将 replay 工具产品化，避免诊断知识只存在临时文件中。
- 每次 replay 前应确认当前 app bundle 加载的是新构建的 `libianvs_core.dylib`。
