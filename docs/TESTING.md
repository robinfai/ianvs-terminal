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

当前未覆盖：

- 真实 PTY 命令执行
- 复制 / 粘贴系统交互
- 滚动 / resize / 选区细节

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
