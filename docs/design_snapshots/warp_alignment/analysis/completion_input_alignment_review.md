# Completion Input Alignment Review

本页重新约定 `04_completion_input.png` 的审图坐标系。此前的 `99%` contract 直接使用整图比例，容易把 Warp 的 sidebar / app chrome 偏移误判为 Ianvs terminal 内部布局。后续对齐以本页为准。

## Reference Images

- Warp original: `docs/design_snapshots/warp_alignment/warp_interaction/04_completion_input.png`
- Ianvs current: `docs/design_snapshots/warp_alignment/completion_input_layout.png`
- Warp annotated: `docs/design_snapshots/warp_alignment/analysis/04_completion_input_regions.svg`
- Ianvs annotated: `docs/design_snapshots/warp_alignment/analysis/completion_input_regions.svg`

## Coordinate System

Warp 原图大小为 `3456 x 1078`。

| Region | Global Rect | Decision |
| --- | ---: | --- |
| Warp app / tab chrome | `x=0, y=0, w=3456, h=71` | Excluded |
| Warp sidebar / conversation list | `x=0, y=71, w=501, h=1007` | Excluded |
| Warp terminal pane | `x=501, y=71, w=2955, h=1007` | Alignment source |

Ianvs 当前 golden 大小为 `1440 x 900`。rect contract 以 `terminal-pane-surface-1` 的 widget rect 作为 active terminal pane local surface，不再使用手工估算的全图候选值。

## Warp Functional Regions

以下 rect 为 Warp 原图全局坐标。

| Functional Region | Global Rect | Meaning |
| --- | ---: | --- |
| Empty terminal viewport | `x=501, y=71, w=2955, h=378` | 输入激活时默认 terminal 空态不作为视觉主体 |
| Active block band | `x=501, y=449, w=2955, h=406` | 横跨 terminal pane 全宽的当前 block 背景区 |
| Command / output body | `x=532, y=489, w=2680, h=326` | block 内部 command + output 内容主体 |
| Block actions | `x=3188, y=470, w=250, h=58` | 右上角 actions，绑定 block band |
| Command detection strip | `x=501, y=855, w=2955, h=59` | input 上方命令检测状态条 |
| Input editor system | `x=501, y=914, w=2955, h=164` | 底部轻量 editor 和相关 controls |
| Path / git / status chips | `x=532, y=1010, w=2690, h=45` | input 系统内的上下文 chips |

## Pane-Local Normalized Contract

以后 contract 不再直接比较全图 `x/y`，而是先转成 terminal pane-local ratio。

| Functional Region | Pane-Local Ratio Target |
| --- | ---: |
| Empty viewport top | `0.000` |
| Empty viewport height | `378 / 1007 = 0.375` |
| Block band left | `0.000` |
| Block band top | `(449 - 71) / 1007 = 0.375` |
| Block band width | `1.000` |
| Block band height | `406 / 1007 = 0.403` |
| Command/output body left | `(532 - 501) / 2955 = 0.010` |
| Command/output body top | `(489 - 71) / 1007 = 0.415` |
| Command/output body width | `2680 / 2955 = 0.907` |
| Command/output body height | `326 / 1007 = 0.324` |
| Actions right gap | `(3456 - 3438) / 2955 = 0.006` |
| Actions top | `(470 - 71) / 1007 = 0.396` |
| Detection top | `(855 - 71) / 1007 = 0.779` |
| Detection height | `59 / 1007 = 0.059` |
| Input top | `(914 - 71) / 1007 = 0.837` |
| Input height | `164 / 1007 = 0.163` |

## Ianvs Implementation Mapping

Ianvs 现在用 `terminal-pane-surface-1` 作为 active terminal pane local 坐标，不再手工估算 `x=0, y=106, w=1440, h=794`。

| Functional Region | Ianvs Key | Contract |
| --- | --- | --- |
| Active pane local surface | `terminal-pane-surface-1` | local coordinate origin |
| Active block band | `terminal-inline-block-row` | pane-local left / top / width / height |
| Command/output body | `terminal-inline-active-block-command-output-body` | pane-local left / top / width / height |
| Block actions | `terminal-inline-block-actions-button` | pane-local top and right gap |
| Command detection strip | `terminal-input-command-detection-strip` | pane-local top / height |
| Input editor system | `terminal-modern-input-bar` | pane-local top / height |
| Input editor | `terminal-modern-input-editor` | pane-local top sanity check |

## Implementation Status

- `completion input matches the pane-local pixel contract` now converts widget rects into `terminal-pane-surface-1` local ratios and asserts drift `<= 0.05`.
- Completion input mode treats the active block row as the first-class full-width block band.
- Command/output body is tested separately from the block band.
- Block actions are tested separately from the command/output body.
- Detection strip and input editor system remain full-width pane-local regions.
- `completion_input_layout.png` was regenerated after the pane-local layout change.

## Open Decisions

- Ianvs keeps top chrome visible in the golden, but all completion rect assertions are pane-local.
- Flutter golden keeps placeholder fonts for CI stability.
- Block hover/action color differences remain covered by `02_block_not_hover_click_actions.png` / `block_actions_layout.png`; `04_completion_input.png` only checks action placement.
