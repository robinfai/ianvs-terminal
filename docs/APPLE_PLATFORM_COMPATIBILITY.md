# Apple 平台兼容性要求

macOS 和 iOS 默认仅要求兼容最近 **4 个已正式发布的大版本**。范围包含最新正式
大版本及之前三个正式大版本，按实际发布时间排序；不按版本号减 3，beta 和 RC
不计入。除非产品需求另有明确说明，不为窗口之外的系统新增兼容代码或验收要求。

## 当前基线

核对日期：2026-09-20。

| 平台 | 支持的大版本（从旧到新） | 最低部署版本 |
| --- | --- | --- |
| macOS | 14、15、26、27 | 14.0 |
| iOS | 17、18、26、27 | 17.0 |

依据：[Apple 2026-09-14 正式发布公告](https://www.apple.com/newsroom/2026/09/major-updates-for-apples-software-platforms-are-now-available/)。
Apple 的版本号存在跳号，不能据数字推导不存在的版本。各大版本以其最新可用
维护版本作为日常验收环境；最低部署版本是安装下限。macOS 的通用包继续包含
Apple silicon 和 Intel；Intel 只适用于该窗口内 Apple 本身支持的系统版本。

## 工程和验收规则

- `example/macos/Runner.xcodeproj/project.pbxproj` 的所有构建配置使用 macOS 14.0，
  `example/macos/TrailSparkle/Package.swift` 保持一致；应用 `LSMinimumSystemVersion`
  取自部署目标，更新清单读取实际构建产物的值。
- `example/ios/Runner.xcodeproj/project.pbxproj` 的所有构建配置使用 iOS 17.0。
- 新增系统 API 必须在窗口内可用，或有可用性判断及回退。依赖不能意外提高
  最低系统要求。无需追改第三方依赖内部更低的最低部署版本。
- 发布前覆盖窗口中最旧和最新系统的关键路径，并对中间两个大版本做回归抽查。
  macOS 包括启动、终端输入、保存、退出与更新；iOS 包括启动、连接、输入、
  键盘与前后台恢复。记录真实设备/模拟器系统版本及未覆盖项。
- 工程声明的支持范围不等于四个版本均已实测通过；CI 构建成功也不能代替全部
  系统版本的运行验收。

## 滚动更新

Apple 发布下一个正式大版本后，在下一次发布准备时核对官方发布记录，加入新
版本、移出最旧版本，并通过同一个 PR 更新本文、README、Xcode 部署目标、
相关 Swift Package 及发布说明。检查实际产物的最低系统版本，明确记录验证
范围。SDK 和构建机的版本可高于最低部署版本，不应据构建机版本推导兼容范围。

## Xcode 27 的多架构校验兼容

2026-09-30 在 macOS 27.0.1、Xcode 27.0（27A266a）、Flutter 3.44.0 上确认：
`make build-macos` 会在 `release_unpack_macos` 阶段失败。Flutter 调用
`lipo <binary> -verify_arch arm64 x86_64` 时，Xcode 27 返回
`-verify_arch requires exactly one input file`；同一文件分别校验两种架构均成功。
因此 Flutter 报出的“缺少架构”不能据此判断为框架损坏。

上游问题与修复：[flutter/flutter#188346](https://github.com/flutter/flutter/issues/188346)、
[flutter/flutter#188625](https://github.com/flutter/flutter/pull/188625)。
当前项目在 macOS Flutter Prepare 和 Assemble 阶段通过 `tools/apple_toolchain/lipo`
将该调用拆为逐个架构校验；其他 lipo 操作直接交给当前选定的 Xcode。发布脚本也逐个校验
架构，继续要求 Apple silicon 和 Intel 通用包。此适配不修改全局 Flutter SDK。
以后升级到包含上游修复的 Flutter 版本并验证通用包构建后，可移除 Prepare 和 Assemble
阶段的 PATH 适配及对应脚本。

本次验证在上述 macOS 27.0.1 环境完成：`make build-macos` 成功，开发签名检查和
Rust 原生库 `dlopen` 检查通过；应用内 11 个 Mach-O 二进制均含 `arm64` 与 `x86_64`，
最低系统版本仍为 14.0。`python3 -m unittest discover -s tools/release -p 'test_*.py'`
的 14 项测试，以及 `dart test test/apple_build_environment_contract_test.dart` 的
12 项测试通过。本次未执行应用界面验收或其他 macOS 版本的运行验证。
