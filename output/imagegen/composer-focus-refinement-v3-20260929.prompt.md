# Composer focus refinement V3

Mode: built-in image_gen. Visual design preview, not an application code change.

## Focus treatment

- Pure-white surface in both states.
- Remove the blue perimeter and blue-tinted focused surface.
- Use a slightly stronger neutral outline, subtle elevation, blue insertion caret, and a short underline inside the input area.
- Preserve existing controls, ordering, and empty-command disabled execute button.

## Shell-ready meaning

The existing status is derived from ComposerOwnership.ready and rendered as “就绪” in packages/ianvs_terminal/lib/src/composer/terminal_composer_view.dart. The host maps the runtime composer.state result into that state in example/lib/features/terminal_composer/composer_pane.dart.

It indicates the shell can accept a command through Composer. It is independent of input focus, does not mean the previous command succeeded, and does not by itself enable execution of an empty draft.

The design uses “Shell 就绪” and a quiet status dot to clarify the meaning and avoid success-check styling.

## Final prompt

Use case: precise-object-edit
Asset type: revised desktop terminal composer interaction-state comparison.
Input image: the attached V2 board is the edit target. Preserve its two-row comparison composition and its existing UI elements.
Primary request: Redesign the FOCUSED state again. The previous full bright-blue perimeter and pale-blue flooded card were rejected. Create a more restrained, intentional focus treatment with pure-white surfaces and a localized input accent. Also clarify the independent Shell-ready status.
Composition and invariants:
- Keep the same wide canvas and two stacked cards, labelled "默认状态" on top and "聚焦状态" below.
- Preserve the existing positions, proportions, spacing, Chinese typography, header, path, selected command capsule, history, enabled suggestion switch, ellipsis, helper, and disabled execute button.
- The cards must remain clear, crisp native desktop UI screenshots on a plain white presentation background.
- Both cards represent an empty command and a shell that is ready; focus must NOT affect the ready state or enable the execute button.
Shared refinements:
- Both card surfaces are perfectly pure white #FFFFFF. No blue wash, gray wash, frosted glass, paper texture or gradient.
- Keep the far-left outer pane divider unobtrusive, a pale neutral hairline #E4EAF0 in both states.
- Replace the upper-right "就绪" wording with "Shell 就绪" in BOTH cards to make its meaning explicit. Replace the prominent green check-circle with a tiny unobtrusive blue-gray status dot #7A8CA0. The status label is smaller, regular weight, neutral dark blue-gray #627187. No green success styling. It communicates availability, not command success.
- Preserve the existing bright-blue small command icon, selected pale-blue command capsule, and blue filled enabled auto-suggest switch exactly. Keep these colors and controls stable between states.
Default card:
- Pure-white surface, very fine neutral pale outline #E0E6ED, essentially flat.
- No caret and no local input underline.
Focused card, key redesign:
- REMOVE the saturated blue outline on all four sides completely.
- REMOVE the pale-blue interior and REMOVE any external blue glow.
- Pure-white surface stays identical in color to the default card.
- Use a restrained thin neutral outline #C6D0DC and a tiny, soft colorless lift underneath the card, very subtle shadow, no muddy haze.
- Show a thin crisp blue text insertion caret #347FDD immediately before "输入命令…".
- Add ONE short, thin blue focus rule INSIDE THE INPUT AREA: about 100 logical pixels wide and 2 logical pixels high, rounded ends, aligned with the placeholder's left edge and positioned about 12 logical pixels below the input text. This blue rule is a localized active-input underline, NOT a full-width line and NOT an accent around the whole card. It must sit in the generous gap between placeholder and toolbar, without shifting any existing element. No line at the outer card bottom, no centered handle or progress bar.
- The placeholder can have a slightly firmer neutral text color #65758A, but no text-size or weight change.
Keep exact content (apart from the stated Shell-ready wording change): "Local Shell · zsh", "/Users/robinfai", "Shell 就绪", "输入命令…", "命令", "历史", "自动建议", "…", "Tab 补全 · ⇧ Enter 换行", "执行".
Avoid: full blue focus box, colored flooded background, gradients, glow, green success indicator, heavy border, oversized shadow, extra icons or text, extra controls, changed layout, enabled execute button, grain, blur, watermark.
