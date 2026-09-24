# ADR-0001: Shell、session 与 terminal 的边界

## Context

应用壳层的布局与样式会持续变化，但输入、焦点、选区和 PTY 生命周期需要保持稳定。
当前模块归属以 [ARCHITECTURE](../ARCHITECTURE.md) 为准。

## Decision

| 层 | 当前实现 | 职责 |
| --- | --- | --- |
| App shell | [shell](../../example/lib/features/shell/) | 窗口、tab/pane 展示、菜单和产品动作入口 |
| App session | [SessionController](../../example/lib/features/sessions/session_controller.dart) | Profile、session 生命周期、active pane 和产品策略 |
| Terminal runtime | [ianvs_terminal](../../packages/ianvs_terminal/lib/src/) | 输入编码、选区、刷新、viewport 与协议事件适配 |
| PTY boundary | [ianvs_pty](../../packages/ianvs_pty/lib/src/) | 当前 FFI ABI、版本化会话与资产传输 |
| Native core | [native/core](../../native/core/src/) | PTY/SSH、VT 解析、frame diff、事件和原生状态 |

App 通过 session/runtime API 发起输入和生命周期操作。终端包不拥有 profile 编辑器、
窗口与菜单；系统剪贴板由 app 注入。Viewport 负责局部焦点、命中和绘制，不拥有 tab 生命周期。
原生层不依赖 Flutter 壳层样式。Standalone 包由 canonical 源生成，不维护第二套协议。

## Consequences

壳层修改需要保持输入字节、复制粘贴、选区、焦点切换、resize、scroll 和退出行为。
涉及 terminal/runtime 边界时，按 [TESTING](../TESTING.md) 选择相关回归；不能用视觉结果
代替终端行为验证。

当前检查入口包括 [输入测试](../../packages/ianvs_terminal/test/terminal_input_controller_test.dart)、
[运行时测试](../../packages/ianvs_terminal/test/terminal_runtime_controller_test.dart)、
[SessionController 测试](../../example/test/sessions/session_controller_test.dart) 和
[真实 PTY 验收](../../example/integration_test/real_pty_acceptance_test.dart)。

## Alternatives Considered

将共享终端逻辑留在 app 壳层会重复协议与状态所有权；为了视觉改动修改底层协议会放大回归范围。
两者均不作为当前实现方式。
