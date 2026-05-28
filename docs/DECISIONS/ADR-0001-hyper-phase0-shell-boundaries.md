# ADR-0001: Hyper-inspired shell boundaries and protected terminal contracts

## Context

ianvs terminal 接下来要做一轮 Hyper-inspired UI 现代化，但当前仓库已经有一条稳定的 terminal 主链路：Flutter shell/UI + Rust PTY core + viewport render path。

如果不先明确 shell 层、session 层、viewport 层各自负责什么，后续 Phase 1A/1B 很容易把“视觉升级”顺手做成“输入/焦点/生命周期语义改动”，从而误伤现有稳定能力。

## Decision

### Layer ownership

| Layer | Current files | Owns | Allowed to mutate | Must not own |
| --- | --- | --- | --- | --- |
| Shell chrome | `example/lib/features/shell/shell_screen.dart`, `example/lib/features/profiles/` | 顶层布局、shell frame、tab/header 呈现、empty-state 呈现、顶层 action 入口 | 通过 `SessionController` 发起 session/profile 级 mutation；可保留当前对 active session 的最小 input/clipboard bridge 调用，但不应继续扩张这类直连 | PTY lifecycle policy、frame diff 生成、terminal selection 语义定义 |
| Session container | `example/lib/features/sessions/session_controller.dart`, `session_state.dart` | session lifecycle、tab 列表、active session、profile bootstrap、polling、viewport controller provisioning | create / activate / close session，profile defaults，resize orchestration，exit 事件处理 | 直接承担 shell chrome 视觉职责；改写 viewport 绘制细节 |
| Terminal interaction adapters | `example/lib/features/terminal/terminal_input_controller.dart`, `clipboard_bridge.dart`, `selection_controller.dart` | 键盘输入编码、复制粘贴桥接、选区文本提取 | 向 active session 发送 input；更新本地 selection 状态 | tab/session 生命周期；顶层 app action 路由 |
| Viewport renderer | `example/lib/features/terminal/terminal_viewport.dart`, `render_terminal_viewport.dart` | viewport focus 容器、pointer/scroll hit testing、frame diff 渲染 | viewport 内局部交互状态（focus、selection hit-test、scroll dispatch） | profile/session ownership、terminal state source of truth |
| Core boundary | `example/lib/ffi/ianvs_core.dart`, `native/core/src/*` | PTY、VT parsing、frame/event delivery、session runtime | core session create/write/resize/scroll/close | Flutter shell polish、tab hierarchy、empty-state UX |

### Observe vs mutate rules

1. Shell chrome 可以观察整个 `SessionState`，但 session metadata mutation 应优先通过 `SessionController`。
2. Shell chrome 当前已经存在两处对 active session 的直接桥接：
   - `Paste` 通过 `terminalCoreClientProvider.sendInput(...)`
   - viewport scroll 通过 `terminalCoreClientProvider.scrollViewport(...)`

   这两处视为当前仓库的既有例外，不在 Phase 0 强行重构；但后续实现不得继续增加新的 shell -> core 直连写路径，除非先证明 controller abstraction 不足。
3. Viewport/render 层可以发出 input / scroll / selection 相关局部 mutation，但不能拥有 tab/session 生命周期规则。
4. Rust/core 在 Phase 1-3 默认只作为稳定服务边界，不应因 shell polish 被改写。

## Protected terminal contracts

以下 contract 在 Hyper-inspired 早期阶段视为冻结边界。任何改动只要触碰这些行为，就必须以“回归保护未破坏”为完成条件，而不是仅凭视觉效果判断完成。

| Contract | Current owner(s) | Why protected | Existing evidence anchors |
| --- | --- | --- | --- |
| Terminal input path | `terminal_input_controller.dart`, `ianvs_core.dart`, `native/core` | shell polish 不得改变按键 -> bytes -> PTY 的主链路 | `example/test/terminal_input_controller_test.dart`, `example/test/ffi/ianvs_core_test.dart` |
| Selection semantics | `selection_controller.dart`, `render_terminal_viewport.dart` | 选区文本抽取和 block/linear 行为已形成用户可见语义 | `example/test/terminal/selection_controller_test.dart`, `example/test/widget_test.dart` |
| Copy/paste semantics | `clipboard_bridge.dart`, `terminal_input_controller.dart`, `shell_screen.dart` | clipboard 是高频路径，最容易被表层 UI 改动误伤 | `example/test/terminal_input_controller_test.dart`, `example/test/widget_test.dart` |
| Focus handoff after tab/session lifecycle changes | `session_controller.dart`, `shell_screen.dart`, `terminal_viewport.dart` | Hyper-like 表层升级不能引入“焦点去哪了”不确定性 | `example/test/sessions/session_controller_test.dart`, `example/test/widget_test.dart`, `example/integration_test/ianvs_smoke_test.dart` |
| Resize routing | `session_controller.dart`, `ianvs_core.dart` | shell frame 调整不能破坏 cols/rows/pixel size 路径 | `example/test/sessions/session_controller_test.dart`, `example/test/widget_test.dart`, `docs/TESTING.md` |
| Scroll routing | `render_terminal_viewport.dart`, `ianvs_core.dart` | shell polish 不得改变滚轮 -> viewport scroll 行为 | `example/test/terminal/render_terminal_viewport_test.dart`, `example/test/widget_test.dart` |
| PTY event delivery | `session_controller.dart`, `ianvs_core.dart`, `native/core` | exit / frame diff / event polling 是 session lifecycle 的底层契约 | `example/test/ffi/ianvs_core_test.dart`, `example/test/widget_test.dart`, `example/integration_test/ianvs_smoke_test.dart` |

## Consequences

- Phase 1A/1B 应优先落在 `example/lib/features/shell/` 与必要的 `example/lib/features/sessions/` 表层配合。
- 如果某个“看起来只是视觉优化”的方案需要修改 `native/core`、terminal selection 语义或 input path，默认应先视为超出 MVP 边界。
- 允许对 shell chrome 做明显的视觉现代化，但不允许借机引入新的 terminal 行为模型。

## Alternatives Considered

### 1. 直接把 shell、session、viewport 的边界留到实现时再判断

Rejected，因为这会让每个后续任务都重新解释“能不能碰 core / 能不能改 focus 规则”，导致 scope 漂移。

### 2. 在 Phase 0 就先重构 shell -> controller -> core 的全部调用路径

Rejected，因为这会把 Phase 0 从“定义目标和边界”扩成“先做架构整形”，不符合最小可逆 diff 原则。
