# flutterm example

这个目录只放 demo app。

它负责：

- tab
- 窗口壳和菜单
- profile 编辑与 defaults
- demo fixture
- 集成 smoke

它不负责：

- PTY FFI
- session runtime 定义
- viewport / 输入 / 选区的共享实现

这些共享能力统一来自：

- [packages/flutterm_pty/README.md](../packages/flutterm_pty/README.md)
- [packages/flutterm_terminal/README.md](../packages/flutterm_terminal/README.md)

## 常用命令

```bash
cd example
flutter analyze
flutter test
flutter run -d macos
```

当前 Flutter package 名仍为 `app`，只是为了兼容现有平台工程和 import 面。
