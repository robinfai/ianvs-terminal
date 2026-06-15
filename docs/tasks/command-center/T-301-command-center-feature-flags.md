# T-301 Command Center Feature Flags

## Goal

定义未来 Command Center feature flags 和本地配置入口，默认全部关闭。

## Scope

- 定义 Command Center 总开关和子能力开关。
- 将本地配置、开发覆盖和测试注入合成为只读 flag snapshot。
- 让后续 Search、History、Blocks、Command Bar、Context Chips 和 Review 入口共用同一份启用状态。

## Non-goals

- 不实现 Command Center UI。
- 不创建 command history、search index 或 block model。
- 不改变 terminal input 行为。
- 不新增 remote / SSH / SFTP / serial、cloud sync、协作或插件生态配置。
- 不把产品 UI 或 app-specific flag 类型下沉到 `packages/ianvs_terminal`。

## Files In Scope

- `example/lib/features/config/local_terminal_config_models.dart`
- `example/lib/features/config/local_terminal_config_loader.dart`
- `example/lib/features/command_center/command_center_feature_flags.dart`
- `example/test/config/local_terminal_config_models_test.dart`
- `example/test/command_center/command_center_feature_flags_test.dart`

## Functional Acceptance

- 默认配置不启用任何 Command Center UI、controller、repository 或索引。
- 总开关关闭时，所有子能力视为不可用。
- 子开关能分别表达 history/search、command blocks、command bar、context chips、review entrypoints 和 verification diagnostics。
- 测试可注入 flag snapshot，不依赖真实文件系统配置。
- 配置 schema 仍保持 local-only，不引入 remote 顶层字段。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/config/local_terminal_config_models_test.dart test/command_center/command_center_feature_flags_test.dart
```

## Manual QA

纯配置模型任务，不改变 runtime UI 或启动路径；无需人工 UI QA。

## Done When

- 后续任务可以通过同一 flag snapshot 判断能力是否启用。
- 默认关闭状态有测试覆盖。
- 配置 roundtrip 有测试覆盖。

## Risks / Follow-ups

- 配置字段命名需要稳定，避免后续 migration 反复改名。
- 如果未来需要灰度或实验覆盖，应扩展 flag snapshot，不让每个 widget 自行读取配置。
