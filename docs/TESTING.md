# flutterm Testing

这份文档集中维护标准验证命令和人工 smoke 流程。任务文档里的 `Verification Commands` 应当优先引用这里，而不是每次重新发明。

## 默认命令

### Flutter

```bash
cd /Users/robinfai/personal/flutterm/app
flutter analyze
flutter test
flutter test integration_test/flutterm_smoke_test.dart
```

### Rust

```bash
cd /Users/robinfai/personal/flutterm/native/core
cargo fmt --check
cargo test
```

### 运行应用

```bash
cd /Users/robinfai/personal/flutterm/app
flutter run -d macos
```

## 按改动类型选择命令

### 只改 Flutter UI 或状态层

至少执行：

- `flutter analyze`
- `flutter test`

如果本次改动涉及应用启动路径、tab 管理或可见主界面冒烟，追加：

- `flutter test integration_test/flutterm_smoke_test.dart`

### 改 Rust core 或 FFI

至少执行：

- `cargo fmt --check`
- `cargo test`
- 相关 Flutter 侧测试

### 改 terminal 主链路、输入、滚动、viewport

必须执行：

- `cargo fmt --check`
- `cargo test`
- `flutter analyze`
- `flutter test`
- `flutter test integration_test/flutterm_smoke_test.dart`
- `flutter run -d macos`

## 自动化 Smoke

当前最小自动化 GUI 冒烟命令：

```bash
cd /Users/robinfai/personal/flutterm/app
flutter test integration_test/flutterm_smoke_test.dart
```

当前覆盖范围：

- 应用启动
- 主 terminal UI 渲染
- 新建 tab
- 关闭非激活 tab 焦点保持
- 关闭激活 tab 焦点迁移
- shell `exit` 后最后一个 tab 回到空状态
- 关闭最后一个 tab 后进入 empty-state
- shell `exit` 后最后一个 tab 回到 empty-state
- 从 empty-state 通过 `New Tab` 恢复
- shell `exit` 后回到 empty-state 再通过 `New Tab` 恢复
- 恢复后再次关闭并重新回到 empty-state
- `Paste` 按钮写入 active session
- `Paste` 按钮空剪贴板 no-op
- `Paste` 按钮保留多行文本换行
- `Copy` 按钮写入系统剪贴板
- `Copy` 按钮空选区 no-op
- `Copy` 按钮保留多行选区换行
- `Copy` 按钮保留反向多行选区换行
- `Copy` 按钮对越界多行选区安全裁剪
- 滚轮事件 -> core scroll 调用
- scroll 后 frame diff 驱动的可见内容 repaint
- 布局尺寸变化 -> core resize 调用
- resize 后 frame diff 驱动的可见内容 repaint
- Rust core 交互式 PTY 输入 -> 输出最小往返
- Flutter 侧 FFI -> PTY -> 输出最小往返
- Flutter 侧 FFI -> PTY 多命令往返
- Flutter 侧 FFI -> PTY 长输出后继续交互
- Flutter 侧 FFI -> PTY 在不同 prompt 配置下保持交互
- Flutter 侧真实 shell `exit` 事件传播
- shell `exit` 后活动 tab 焦点迁移
- 多行选区文本提取语义（换行、反向拖选、裁剪、非对称列范围）

当前未覆盖：

- 真正的矩形 / block selection 语义
- 更复杂的 clipboard / selection 组合语义

## 手工 Smoke Checklist

只要改动影响 terminal 主链路，就至少做一轮手工检查：

1. 启动应用
2. 打开一个本地 shell tab
3. 输入 `pwd`
4. 输入 `echo hello`
5. 输入 `ls`
6. 复制一段文本并粘贴回 terminal
7. 向上滚动查看 scrollback
8. 拖动鼠标进行线性选择
9. 调整窗口大小，确认内容和光标不乱
10. 打开多个 tab 并切换

## 高风险改动附加检查

以下改动应追加更细的人工验证：

- 输入事件映射
- selection / clipboard
- resize
- frame diff 结构
- PTY 生命周期
- profile 持久化

建议额外检查：

- 快速切换 tab
- 连续输入多行命令
- 高输出命令后 GUI 是否仍可交互
- shell 退出后的状态是否正确更新

## 结果记录要求

最终汇报里至少要说明：

- 运行了哪些命令
- 是否做了手工 smoke
- 有哪些未覆盖或未验证的风险
