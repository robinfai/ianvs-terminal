Use case: precise-object-edit / design audit annotations
Asset type: evidence-based UI review board, not a redesign mockup.
Primary request: annotate the supplied current Trail Command Block screenshots with four verified design issues and concrete repairs. Use a spacious neutral white board with clear Chinese typography, fine warm-red numbered callouts, thin connector lines, and the original cool blue-grey screenshot palette. Arrange the three phone screenshots plus the short desktop screenshot as four numbered panels. Keep each screenshot's original proportions and content, including existing clipping. Place labels OUTSIDE the screenshots so the evidence stays visible. Do not invent controls, error stripes, phone bezels, or hidden content.
Input images in order:
1. Mobile landscape keyboard state, edit target. Mark the clipped top/bottom of the Composer outline and the tiny output fragment under the app header. Label: “01 横屏输入框被裁切” and “整改：单行紧凑输入布局，完整显示边框与执行按钮”.
2. Mobile output reader, edit target. Mark the tightly packed top back/title/more controls and inconsistent left edge of metadata/output. Label: “02 阅读页顶部过于贴边” and “整改：统一触控高度、标题留白和正文左边距”.
3. Mobile command list, edit target. Mark output starting at line 7 and the View all footer. Label: “03 末尾预览缺少范围说明” and “整改：明确标注末尾 6 行，保留查看全部入口”.
4. Short desktop state, edit target. Mark a compact command row's far-right controls lacking a more-actions menu. Label: “04 紧凑状态操作入口消失” and “整改：保留更多菜单，复制和过滤保持可发现”.
Title (verbatim): “Trail · Command Block 设计细节检查”
Footer (verbatim): “基于本轮真实组件截图 · 红色为审查标注，不进入产品界面”
Constraints: Preserve the source UI rather than drawing repaired UI. Callout arrows must land on the named components. This is an annotation sheet to guide code corrections; it must not imply that generated pixels are validation screenshots.

Built-in image_gen refinement 1:
Precise text-only correction to this existing design audit board. Preserve the entire board, screenshots, four-panel layout, callouts, typography and all other wording. Correct two inaccurate annotations only. In panel 02 replace the red annotation “返回、标题、更多按钮 间距过小，易误触” with “顶部留白不足，标题与控件过于贴边” (do not claim small touch targets, which have not failed tests). In panel 04 replace “紧凑行右侧仅显示状态和排序” with “紧凑行右侧仅显示状态和展开” because the second icon expands, it does not sort. Do not add any other claims. Keep the image as annotation, never redraw a fixed UI.

Built-in image_gen final refinement:
Edit this board in one tiny area only: the red note to the right of panel 04 in the lower-right quadrant. Delete its existing multi-line red note, including any occurrence of 排序, and replace the entire note with exactly these three red lines: 缺少更多操作菜单 / 复制、过滤等功能 / 缺少可见入口. Preserve the arrow pointing to the command row, every screenshot and every other word in all panels unchanged. Do not add or paraphrase any wording. This is a correction to an annotated audit board, not a UI redesign.

Selected output: annotated-review.png. Generated pixels are explanatory annotations only; the untouched before/ and after/ component captures remain the visual evidence.
