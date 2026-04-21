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

## Current Status

`2026-04-21` 本机复跑结果：

- `flutter test integration_test/flutterm_smoke_test.dart`: `pass`
- `flutter run -d macos`: `blocked`
  - app 可构建
  - Dart VM Service 可附着
  - 运行器仍打印 `Failed to foreground app; open returned 1`
  - 60 秒内未进入可确认的真实前置台交互状态
- `command -v vttest`: `blocked`
  - 当前机器未安装 `vttest`
  - `brew info vttest` 已确认标准准备路径可用：`brew install vttest`
- `HardwareKeyboard` 重复 `KeyDownEvent`：`blocked`
  - 这次复跑未再次触发
  - 由于 app 未前置到真实交互桌面，暂时不能视为风险收敛

基于这轮结果，`T-054` 在当前机器上只能完成 blocker 归属确认；`T-055` 应迁移到一台标准交互式 macOS 开发机执行。

## Done When

- 手工矩阵的主要执行阻塞有明确状态，不再停留在口头结论
- `docs/TESTING.md` / `docs/KNOWN_ISSUES.md` 与最新环境证据一致
- VT220 手工矩阵已经具备可准备、可执行的前置说明

## Risks / Follow-ups

- 某些阻塞可能属于当前运行环境，而不是仓库本身；如果确认如此，文档必须明确标注环境范围
- 本任务完成后，完整兼容性矩阵仍留给 `T-055`
