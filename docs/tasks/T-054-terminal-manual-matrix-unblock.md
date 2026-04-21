# T-054 Terminal Manual Matrix Unblock

## Goal

解除当前 terminal 手工矩阵的主要执行阻塞，让真实 GUI smoke 与 VT220 手工验证至少能在一台标准开发机稳定运行。

## Scope

- `docs/TESTING.md`
- `docs/KNOWN_ISSUES.md`
- `docs/tasks/T-054-terminal-manual-matrix-unblock.md`

## Non-goals

- 不修改 terminal 产品逻辑
- 不修改 Rust core / FFI / frame schema
- 不在本任务里执行完整 VT220 / prompt / trackpad / DPI 矩阵
- 不把 `HardwareKeyboard` 问题顺手混进 terminal 功能任务

## Functional Acceptance

- `flutter run -d macos` 的前置台 / 可交互路径有明确状态：
  - 要么可用于真实 GUI smoke
  - 要么被明确记录为环境 blocker，并附复现步骤与具体错误文本
- `vttest` 的前置条件被明确写出，至少能指导一台标准开发机准备 VT220 手工矩阵
- 若再次出现 `HardwareKeyboard` 重复 `KeyDownEvent` 断言，必须单开独立排障任务

## Verification Commands

```bash
cd /Users/robinfai/personal/flutterm
command -v vttest || true

cd /Users/robinfai/personal/flutterm/app
flutter test integration_test/flutterm_smoke_test.dart
flutter run -d macos
```

## Manual QA

1. 运行 `flutter run -d macos`，记录 app 是否可前置到真实可交互桌面
2. 若失败，记录绝对日期、错误文本与是否仍可附着 Dart VM Service
3. 检查当前机器是否安装 `vttest`；若没有，记录标准准备路径或阻塞条件
4. 若运行期间复现 `HardwareKeyboard` 重复 `KeyDownEvent`，记录最小复现并拆出新任务

## Done When

- 手工矩阵的主要执行阻塞有明确状态，不再停留在口头结论
- `docs/TESTING.md` / `docs/KNOWN_ISSUES.md` 与最新环境证据一致
- VT220 手工矩阵已经具备可准备、可执行的前置说明

## Risks / Follow-ups

- 某些阻塞可能属于当前运行环境，而不是仓库本身；如果确认如此，文档必须明确标注环境范围
- 本任务完成后，完整兼容性矩阵仍留给 `T-055`
