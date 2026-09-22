# Compatibility Evidence Boundaries

当前缺陷和待办只维护在 [KNOWN_ISSUES](../KNOWN_ISSUES.md)。本页说明如何解读兼容性证据，
不保存历史通过记录或重复维护产品风险清单。

- 存在 parser 或单元测试不等于真实 app、外部终端或每一种宿主已经通过验证。
- macOS 与 iOS 已有 app runner；Linux/Windows native 构建或特定 CI 测试不代表存在对应 app runner。
- 外部 `vttest`、SSH fixture、系统权限或设备缺失时，应明确标记该次检查未执行。
- 截断 transcript 的 resize 不能还原已经丢弃的历史；session diagnostics 通过
  [Diagnostic Event v1](../protocols/DIAGNOSTIC_EVENT_V1.md) 暴露 transcript/replay 计数。
- Kitty POSIX shared-memory 需要宿主支持；严格验证使用 `IANVS_REQUIRE_POSIX_SHM_TESTS=1`。
- 字体、DPI、IME 和实体输入设备按 [人工检查表](MANUAL_VERIFICATION.md) 执行。
- 性能结果需带宿主与构建信息，不能由一次本机通过推断所有机器的性能。

测试位置见 [Test Assets](TEST_ASSET_INVENTORY.md)，能力归属见 [Capability Matrix](CAPABILITY_MATRIX.md)。
