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
