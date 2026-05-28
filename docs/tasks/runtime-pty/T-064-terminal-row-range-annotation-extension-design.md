# T-064 Terminal Row-Range Annotation Extension Design

## Goal

先把 `TerminalViewport` / `RenderTerminalViewport` 的 row-range 渲染扩展点
定义清楚，让后续实现 terminal 内 block 分隔时不再临场决定接口和约束。

## Scope

- 定义 absolute scrollback row range 的公共模型。
- 定义 annotation 在 viewport / render-layer 的挂载点、绘制顺序和布局回报。
- 定义 annotation 与 selection、search、copy、dirty-range、row cache 的边界。
- 产出一份可直接照做的 candidate API，供后续 renderer 实现任务使用。

## Non-goals

- 不在本任务里落 divider、gutter、sticky header 或 hover action 的可见 UI。
- 不把 Ianvs Terminal 的产品文案、状态文案或 block toolbar 直接塞进
  ianvs terminal 公共层。
- 不修改 `native/core` frame schema，也不要求 backend 直接理解 block。
- 不改变现有 selection、search、copy、hyperlink hit-test 语义。

## Files In Scope

- `docs/tasks/runtime-pty/T-064-terminal-row-range-annotation-extension-design.md`
- `packages/ianvs_terminal/lib/src/terminal/terminal_viewport.dart`
- `packages/ianvs_terminal/lib/src/terminal/render_terminal_viewport.dart`
- `packages/ianvs_terminal/lib/src/terminal/terminal_models.dart`
- `packages/ianvs_terminal/test/`

## Candidate API

- 新增 `TerminalRowRangeAnnotationController extends ChangeNotifier`
  - 持有不可变 `annotations`
  - 持有最新可见布局快照 `visibleLayouts`
- 新增 `TerminalRowRangeAnnotation`
  - `id`
  - `startAbsoluteRow`
  - `endAbsoluteRowExclusive`
  - `kind`
  - `style`
  - `metadata`
- `kind` 固定只定义四类：
  - `background`
  - `gutter`
  - `divider`
  - `anchor`
- `TerminalViewport` 新增可选 `annotationController`
- `RenderTerminalViewport` 负责两件事：
  - 绘制 `background / gutter / divider`
  - 计算 `anchor` 的可见 rect，并回写到 `visibleLayouts`

## Functional Acceptance

- 绝对行号语义固定为 scrollback absolute row，不使用 viewport row index
  做外部 API。
- 可见行映射固定基于当前 frame 的 `scrollbackOffset` 和 `viewportRows`
  计算，annotation 不得直接改写 `TerminalFrameDiff`。
- 绘制顺序固定为：
  - canvas background
  - annotation `background / gutter / divider`
  - terminal text / hyperlink visuals
  - selection highlight
  - cursor
- `anchor` 只产出几何信息，不在 render object 内承接点击、hover 或 gesture。
  后续产品侧 overlay action 必须挂在 render object 外面。
- annotation 更新不能污染 backend `dirty_ranges` 语义；render 层要用独立的
  annotation version / overlap 判断来决定哪些可见行需要重绘。
- row visual cache 的失效规则必须明确包含：
  - annotation 覆盖区变化
  - annotation style 变化
  - viewport scroll 导致可见 absolute row 变化
- `selectionText`、本地选区拖拽、search 跳转、copy 结果、hyperlink 打开
  在有 annotation 时保持现有行为。
- 本任务文档必须写清后续实现至少要覆盖的测试：
  - 部分可见 range 的 top/bottom clip
  - row cache 只重绘受 annotation 影响的行
  - selection/search/copy 在 annotation 存在时不回归
  - anchor rect 随 scrollback 和 resize 正确更新

## Verification Commands

参考 [TESTING.md](../../TESTING.md)。后续实现这份设计时，验证至少包括：

```bash
cd packages/ianvs_terminal
flutter test
```

```bash
cd example
flutter test
```

## Manual QA

1. 在带 annotation 的 viewport 中上下滚动，确认只在可见 absolute row
   上出现背景、gutter 或 divider。
2. 让一个 range 同时经历“完全可见、顶部裁切、底部裁切、完全离开视口”
   四种状态，确认 `visibleLayouts` 的 rect 和 clipped 状态正确。
3. 在 annotation 覆盖区做 selection、copy、search 跳转和 hyperlink 打开，
   确认行为和没有 annotation 时一致。
4. 用 overlay anchor 场景验证：render object 只回报几何，不自己处理点击。

## Done When

- 任务文档已经给出可实现的 candidate API 和固定约束。
- 后续 renderer 实现不需要再决定 absolute row 语义、绘制顺序或 cache 失效边界。
- 文档明确禁止把 Ianvs Terminal 的具体 UI 直接写成 ianvs terminal 公共 API。
- 设计验收项已经足够具体，后续实现者不需要补问接口和测试标准。

## Risks / Follow-ups

- 如果未来需要“render object 内直接处理 hover / click”，那是新任务，
  不要在本设计上偷偷扩大范围。
- sticky header 若需要跨 viewport 内容区固定显示，也应另开 focused task，
  不和这份 row-range annotation 设计混做一轮。
