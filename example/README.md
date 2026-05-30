# Ianvs Terminal example

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

- [packages/ianvs_pty/README.md](../packages/ianvs_pty/README.md)
- [packages/ianvs_terminal/README.md](../packages/ianvs_terminal/README.md)

## 常用命令

```bash
cd example
flutter analyze
flutter test
flutter run -d macos
```

当前 Flutter package 名仍为 `app`，用于兼容现有 `package:app/...` import 面；macOS bundle/app identity 由 Runner project 的 Ianvs Terminal 元数据维护。
