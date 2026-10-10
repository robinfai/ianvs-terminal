# 桌面64条需求与当前实现逐项对照

核对日期：2026-10-10，起点`79db5115`，工作树尚未冻结。表中是源码及回归入口，不是完整PRD验收通过记录。所有Dn-Tnn正式证据仍为`not_run`。

源码/自动回归、真实原生操作、物理输入/辅助技术、真实模型分别记账。移动对照见[MOBILE_COMPARISON](MOBILE_COMPARISON.md)。

## D1

|需求|实现锚点|回归入口|当前实现／仍需执行|
|---|---|---|---|
|D1-R01 · 桌面壳与任务入口 · P1|[shell_screen_chrome_bar.dart](../../../../example/lib/features/shell/shell_screen_chrome_bar.dart)|[desktop_unified_chrome_test.dart](../../../../example/test/shell/desktop_unified_chrome_test.dart)|活动目标底栏、单层顶栏和真实白区 native drag 已补；1×/2×、英中与溢出回归已通过，完整原生场景待验。|
|D1-R02 · Block 情境操作与失败诊断 · P1|[command_blocks_pane.dart](../../../../example/lib/features/terminal_composer/command_blocks_pane.dart)|[terminal_ai_workspace_test.dart](../../../../example/test/ai/terminal_ai_workspace_test.dart)|诊断仅准备草稿和来源；原生零起始请求仍需采证。|
|D1-R03 · 选择上下文及来源冻结 · P0|[ai_models.dart](../../../../example/lib/features/ai/ai_models.dart)|[terminal_ai_evidence_versions_test.dart](../../../../example/test/ai/terminal_ai_evidence_versions_test.dart)|发送来源冻结；本轮补充要求也保留原 session/range。|
|D1-R04 · 单一可写入口与明确路由 · P0|[terminal_ai_controller.dart](../../../../example/lib/features/ai/terminal_ai_controller.dart)|[terminal_ai_deferred_recovery_test.dart](../../../../example/test/ai/terminal_ai_deferred_recovery_test.dart)|未知时保存尚未发送要求；检查回执不发送，显式继续才采用。|
|D1-R05 · 任务时间线与真实执行证据 · P1|[terminal_ai_workspace.dart](../../../../example/lib/features/ai/terminal_ai_workspace.dart)|[terminal_ai_citation_regression_test.dart](../../../../example/test/ai/terminal_ai_citation_regression_test.dart)|真实 Block 与 AI 消息分层；全流程原生结果待验。|
|D1-R06 · 桌面完整命令审阅 · P0|[terminal_ai_workspace.dart](../../../../example/lib/features/ai/terminal_ai_workspace.dart)|[terminal_ai_desktop_review_test.dart](../../../../example/test/ai/terminal_ai_desktop_review_test.dart)|本轮 pane 内完整审阅；旧 pane/target/revision 按钮失效。|
|D1-R07 · 编辑提案与审批版本 · P0|[terminal_ai_controller.dart](../../../../example/lib/features/ai/terminal_ai_controller.dart)|[terminal_ai_tasks_test.dart](../../../../example/test/ai/terminal_ai_tasks_test.dart)|本轮保留旧提案，新 revision 保存零执行。|
|D1-R08 · 提交、连点与执行回执 · P0|[terminal_ai_api_operations.dart](../../../../example/lib/features/ai/terminal_ai_api_operations.dart)|[api_operation_identity_test.dart](../../../../example/test/ai/api_operation_identity_test.dart)|本轮 API 重复 ID 返回原 receipt；冲突拒绝；ACP 原幂等保留。|
|D1-R09 · 只读观察终端 · P0|[shell_screen_ai_observer.dart](../../../../example/lib/features/shell/shell_screen_ai_observer.dart)|[terminal_ai_observer_test.dart](../../../../example/test/ai/terminal_ai_observer_test.dart)|只读观察零人工写；真实协议与输入来源计数仍需采证。|
|D1-R10 · 暂停、接管与中断分离 · P0|[terminal_ai_controller.dart](../../../../example/lib/features/ai/terminal_ai_controller.dart)|[terminal_ai_desktop_review_test.dart](../../../../example/test/ai/terminal_ai_desktop_review_test.dart)|统一收起/Esc；暂停、接管、中断分离。|
|D1-R11 · 未知回执与故障恢复 · P0|[terminal_ai_controller.dart](../../../../example/lib/features/ai/terminal_ai_controller.dart)|[terminal_ai_recovery_test.dart](../../../../example/test/ai/terminal_ai_recovery_test.dart)|新增结束跟进，未知记录保留；新任务不重放。|
|D1-R12 · 执行目标变化与目录推进 · P0|[terminal_ai_runtime.dart](../../../../example/lib/features/ai/terminal_ai_runtime.dart)|[terminal_ai_approval_scope_test.dart](../../../../example/test/ai/terminal_ai_approval_scope_test.dart)|既有 guard/lease；本轮覆盖异步批准期间目标失效。|
|D1-R13 · 任务、草稿与关闭生命周期 · P0|[shell_screen_close_protection.dart](../../../../example/lib/features/shell/shell_screen_close_protection.dart)|[shell_close_protection_test.dart](../../../../example/test/shell/shell_close_protection_test.dart)|已补风险关闭确认／复制／取消；录制等待后的目标、提案、草稿、附件与历史 unknown 重新核对，部分失败只清理真实已关 pane。|
|D1-R14 · 模型 API 的连接与错误状态 · P1|[ai_settings.dart](../../../../example/lib/features/ai/ai_settings.dart)|[terminal_ai_connections_test.dart](../../../../example/test/ai/terminal_ai_connections_test.dart)|API 配置/错误链已存在；新候选真实 API 待运行。|
|D1-R15 · 桌面 ACP 设置、恢复与权限 · P0|[acp_installation.dart](../../../../example/lib/features/ai/acp/acp_installation.dart)|[acp_installation_test.dart](../../../../example/test/ai/acp_installation_test.dart)|检测/手填/测试已有；Finder PATH 与真实恢复待复验。|
|D1-R16 · AI 与 Raw/TUI 的同会话闭环 · P0|[command_blocks_pane.dart](../../../../example/lib/features/terminal_composer/command_blocks_pane.dart)|[composer_acceptance_test.dart](../../../../example/integration_test/composer_acceptance_test.dart)|同 PTY Raw/TUI 回退已有；只读层几何需当前构建证明。|

## D2

|需求|实现锚点|回归入口|当前实现／仍需执行|
|---|---|---|---|
|D2-R01 · 键盘分发与主操作决策 · P0|[terminal_composer_view.dart](../../../../packages/ianvs_terminal/lib/src/composer/terminal_composer_view.dart)|[input_intent_test.dart](../../../../packages/ianvs_terminal/test/composer/input_intent_test.dart)|现有主动作与焦点分发；物理键/IME 原生验证另计。|
|D2-R02 · 多行编辑、粘贴与撤销 · P0|[terminal_composer_controller.dart](../../../../packages/ianvs_terminal/lib/src/composer/terminal_composer_controller.dart)|[composer_controller_redesign_test.dart](../../../../packages/ianvs_terminal/test/composer/composer_controller_redesign_test.dart)|本地编辑/撤销/预算已有；编辑不提交。|
|D2-R03 · 真实中文输入法优先 · P0|[terminal_composer_view.dart](../../../../packages/ianvs_terminal/lib/src/composer/terminal_composer_view.dart)|[composer_acceptance_test.dart](../../../../example/integration_test/composer_acceptance_test.dart)|人工 composing 值不代替真实拼音；物理候选确认未采证。|
|D2-R04 · 补全、详情与本地 I/O 授权 · P1|[composer_suggestions.dart](../../../../packages/ianvs_terminal/lib/src/composer/composer_suggestions.dart)|[composer_suggestions_test.dart](../../../../packages/ianvs_terminal/test/composer/composer_suggestions_test.dart)|既有窄/宽候选详情；不扩大本地 I/O 和 provider 范围。|
|D2-R05 · 历史与独立灰字 · P1|[terminal_composer_controller.dart](../../../../packages/ianvs_terminal/lib/src/composer/terminal_composer_controller.dart)|[composer_controller_redesign_test.dart](../../../../packages/ianvs_terminal/test/composer/composer_controller_redesign_test.dart)|历史/灰字/取消恢复已有；远端历史不得用本地伪装。|
|D2-R06 · Block 选择、键盘导航和复制 · P0|[command_blocks_view.dart](../../../../packages/ianvs_terminal/lib/src/terminal/command_blocks_view.dart)|[command_block_copy_test.dart](../../../../packages/ianvs_terminal/test/terminal/command_block_copy_test.dart)|块/文本选择及分页复制已有；四 pane 原生复制待验。|
|D2-R07 · 桌面 Block 高度和手动展开 · P1|[command_blocks_controls.dart](../../../../packages/ianvs_terminal/lib/src/terminal/command_blocks_controls.dart)|[command_blocks_test.dart](../../../../packages/ianvs_terminal/test/terminal/command_blocks_test.dart)|H/3 保留；本轮短窗摘要显示状态/退出码与详情。|
|D2-R08 · 滚轮、触摸板与双层滚动 · P1|[command_blocks_output.dart](../../../../packages/ianvs_terminal/lib/src/terminal/command_blocks_output.dart)|[command_block_scroll_ownership_test.dart](../../../../packages/ianvs_terminal/test/terminal/command_block_scroll_ownership_test.dart)|边界新手势、长手势跨块、DPR替换位置均先红后绿；物理惯性另验。|
|D2-R09 · 查找、过滤与原生阅读器 · P1|[command_blocks_view.dart](../../../../packages/ianvs_terminal/lib/src/terminal/command_blocks_view.dart)|[command_blocks_find_test.dart](../../../../packages/ianvs_terminal/test/terminal/command_blocks_find_test.dart)|本轮严格总量1000，显示单块200/总量限制；原生分页保留。|
|D2-R10 · 多 pane 焦点与执行隔离 · P0|[composer_pane.dart](../../../../example/lib/features/terminal_composer/composer_pane.dart)|[composer_pane_focus_test.dart](../../../../example/test/terminal_composer/composer_pane_focus_test.dart)|本轮 ready/运行 Block 仅向原有效 owner 聚焦。|
|D2-R11 · Tabs、拖放与关闭保护 · P0|[shell_screen_chrome_approval.dart](../../../../example/lib/features/shell/shell_screen_chrome_approval.dart)|[desktop_unified_chrome_test.dart](../../../../example/test/shell/desktop_unified_chrome_test.dart)|关闭保护及顶部／溢出／侧栏／折叠组待审入口已补；通知只定位原 pane，零提交回归通过；原生并发组合仍待。|
|D2-R12 · 窗口前后台与异步焦点 · P0|[composer_pane.dart](../../../../example/lib/features/terminal_composer/composer_pane.dart)|[composer_pane_focus_test.dart](../../../../example/test/terminal_composer/composer_pane_focus_test.dart)|本轮窗口／路由／焦点代际检查；另补完整及部分关闭不抢新 modal 焦点、TUI 晚到回调不切新任务；真实前后台待验。|
|D2-R13 · 窗口尺寸、缩放与多显示器 · P1|[terminal_composer_view.dart](../../../../packages/ianvs_terminal/lib/src/composer/terminal_composer_view.dart)|[composer_responsive_input_test.dart](../../../../packages/ianvs_terminal/test/composer/composer_responsive_input_test.dart)|约束布局已有；完整窗口/2×/真实多DPI矩阵待验。|
|D2-R14 · 鼠标情境菜单与可发现性 · P1|[command_blocks_controls.dart](../../../../packages/ianvs_terminal/lib/src/terminal/command_blocks_controls.dart)|[terminal_ai_desktop_review_test.dart](../../../../example/test/ai/terminal_ai_desktop_review_test.dart)|菜单/审阅独立焦点；首次点击仅激活窗口仍须原生实测。|
|D2-R15 · 证据检查器与只读并排 · P1|[command_block_reader.dart](../../../../packages/ianvs_terminal/lib/src/terminal/command_block_reader.dart)|[command_block_reader_host_test.dart](../../../../packages/ianvs_terminal/test/terminal/command_block_reader_host_test.dart)|当前窗格与600+360显式并排已实现；共享分页/选择、TUI不resize；同帧Composer门禁及当前owner恢复回归已通过。|
|D2-R16 · Raw/TUI/密码输入边界 · P0|[command_blocks_output.dart](../../../../packages/ianvs_terminal/lib/src/terminal/command_blocks_output.dart)|[command_block_input_lifecycle_test.dart](../../../../packages/ianvs_terminal/test/terminal/command_block_input_lifecycle_test.dart)|完成/挂起/移除后撤销旧粘贴；输出刷新不误取消。|

## D3

|需求|实现锚点|回归入口|当前实现／仍需执行|
|---|---|---|---|
|D3-R01 · 主题 tokens 盘点与映射 · P1|[app_theme.dart](../../../../example/lib/ui/foundation/app_theme.dart)|[app_theme_contract_test.dart](../../../../example/test/ui/app_theme_contract_test.dart)|主题映射见[TOKEN_MAP](TOKEN_MAP.md)；四模式目标色对检查已通过，原生场景仍待。|
|D3-R02 · 浅深色、ANSI与选区 · P1|[composer_theme.dart](../../../../packages/ianvs_terminal/lib/src/composer/composer_theme.dart)|[composer_theme_test.dart](../../../../packages/ianvs_terminal/test/composer/composer_theme_test.dart)|色对计算已有；当前原生 ANSI/选区/深浅/高对比场景待验。|
|D3-R03 · Command Block 桌面密度 · P1|[command_blocks_controls.dart](../../../../packages/ianvs_terminal/lib/src/terminal/command_blocks_controls.dart)|[command_blocks_test.dart](../../../../packages/ianvs_terminal/test/terminal/command_blocks_test.dart)|轻分隔/H3保留；本轮摘要明确真实状态。|
|D3-R04 · 三层 Composer Dock 视觉合同 · P1|[terminal_composer_view.dart](../../../../packages/ianvs_terminal/lib/src/composer/terminal_composer_view.dart)|[composer_responsive_input_test.dart](../../../../packages/ianvs_terminal/test/composer/composer_responsive_input_test.dart)|三层 Dock、长稿与暂停占位已有。|
|D3-R05 · AI 内容与执行事实分层 · P1|[terminal_ai_workspace.dart](../../../../example/lib/features/ai/terminal_ai_workspace.dart)|[terminal_ai_workspace_test.dart](../../../../example/test/ai/terminal_ai_workspace_test.dart)|正文/建议/执行结果分层；本轮补旧版本及结束跟进。|
|D3-R06 · 状态优先级与准确文案 · P0|[terminal_ai_workspace.dart](../../../../example/lib/features/ai/terminal_ai_workspace.dart)|[desktop_session_status_test.dart](../../../../example/test/shell/desktop_session_status_test.dart)|底栏同时保留断连/未知，不能用 ready 覆盖原结果。|
|D3-R07 · 字体、等宽与字形来源 · P1|[composer_theme.dart](../../../../packages/ianvs_terminal/lib/src/composer/composer_theme.dart)|[composer_acceptance_test.dart](../../../../example/integration_test/composer_acceptance_test.dart)|已有原生 iiii/WWWW 断言；当前构建字形/复制待跑。|
|D3-R08 · 桌面响应式与文字缩放 · P1|[terminal_ai_workspace.dart](../../../../example/lib/features/ai/terminal_ai_workspace.dart)|[terminal_ai_desktop_review_test.dart](../../../../example/test/ai/terminal_ai_desktop_review_test.dart)|本轮修矮窄 pane 2×；完整四尺寸与全部surface尚未完成。|
|D3-R09 · Hover、focus、pressed与disabled · P1|[composer_preview.dart](../../../../example/lib/ui/previews/composer_preview.dart)|[mobile_prd_component_previews_test.dart](../../../../example/test/ai/mobile_prd_component_previews_test.dart)|部分预览已存在；桌面全部 hover/focus/pressed/disabled 册待补。|
|D3-R10 · 中英本地化与长路径 · P1|[ai_strings.dart](../../../../example/lib/features/ai/ai_strings.dart)|[terminal_ai_deferred_recovery_test.dart](../../../../example/test/ai/terminal_ai_deferred_recovery_test.dart)|新文案有中英两套；长路径和所有状态漏译巡检待完成。|
|D3-R11 · 桌面可访问性与读序 · P1|[terminal_ai_workspace.dart](../../../../example/lib/features/ai/terminal_ai_workspace.dart)|[terminal_ai_accessibility_acceptance_test.dart](../../../../example/integration_test/terminal_ai_accessibility_acceptance_test.dart)|Semantics/键盘 fixture 不代替真实 VoiceOver/FKA。|
|D3-R12 · 动效、减少动画与稳定布局 · P1|[app_motion.dart](../../../../example/lib/ui/foundation/app_motion.dart)|[app_motion_test.dart](../../../../example/test/ui/app_motion_test.dart)|减少动画已有；真实系统设置与整页稳定性待验。|
|D3-R13 · 来源与证据检查器规范 · P0|[terminal_ai_workspace.dart](../../../../example/lib/features/ai/terminal_ai_workspace.dart)|[terminal_ai_evidence_versions_test.dart](../../../../example/test/ai/terminal_ai_evidence_versions_test.dart)|本轮 Chip 截断/淘汰标识，发送来源冻结，不借阅读改变目标。|
|D3-R14 · 底部状态栏与活动目标 · P0|[desktop_session_status.dart](../../../../example/lib/features/shell/widgets/desktop_session_status.dart)|[desktop_session_status_test.dart](../../../../example/test/shell/desktop_session_status_test.dart)|本轮新增活动目标/模式/owner/事实；未知数据核对中，详情只读。|
|D3-R15 · 命令菜单与快捷键可发现性 · P1|[shell_screen_state_command_actions.dart](../../../../example/lib/features/shell/shell_screen_state_command_actions.dart)|[shell_shortcut_bridge_test.dart](../../../../example/test/shell/shell_shortcut_bridge_test.dart)|沿用注册菜单/快捷键；用户定制映射帮助需原生核对。|
|D3-R16 · 视觉回归与组件状态册 · P1|[desktop_evidence_preview.dart](../../../../example/lib/ui/previews/desktop_evidence_preview.dart)|[desktop_evidence_preview_test.dart](../../../../example/test/ui/desktop_evidence_preview_test.dart)|新增Reader/底栏真实组件预览，浅深/高对比/2×和开关交互；当前原生before/after与完整状态册未齐。|

## D4

|需求|实现锚点|回归入口|当前实现／仍需执行|
|---|---|---|---|
|D4-R01 · 真实本地 Shell 端到端 · P0|[verify_macos_app.sh](../../../../tools/verify_macos_app.sh)|[real_pty_acceptance_test.dart](../../../../example/integration_test/real_pty_acceptance_test.dart)|宿主macOS27.0.1；新候选原生完整构建/操作未完成。|
|D4-R02 · SSH、Bash/Zsh与多跳 · P0|[lib.rs](../../../../native/core/src/lib.rs)|[real_pty_acceptance_test.dart](../../../../example/integration_test/real_pty_acceptance_test.dart)|真实本地PTY/SSH及cwd、shell支持矩阵需独立记录。|
|D4-R03 · 真实模型 API 与错误注入 · P0|[ai_api_client.dart](../../../../example/lib/features/ai/ai_api_client.dart)|[terminal_ai_acceptance_test.dart](../../../../example/integration_test/terminal_ai_acceptance_test.dart)|真实API完整场景未新运行；mock和旧手机证据不能替代。|
|D4-R04 · 本地 ACP 的原生闭环 · P0|[terminal_ai_acp.dart](../../../../example/lib/features/ai/terminal_ai_acp.dart)|[terminal_ai_acp_design_test.dart](../../../../example/integration_test/terminal_ai_acp_design_test.dart)|真实ACP、返回模型、Finder PATH、恢复/权限待新验。|
|D4-R05 · Manual 与 Smart 审阅回归 · P0|[terminal_ai_approval.dart](../../../../example/lib/features/ai/terminal_ai_approval.dart)|[ai_approval_sensitivity_test.dart](../../../../example/test/ai/ai_approval_sensitivity_test.dart)|Manual/三档逻辑已有；真实两后端完整矩阵待完成。|
|D4-R06 · 重复、陈旧与竞争故障矩阵 · P0|[terminal_ai_runtime.dart](../../../../example/lib/features/ai/terminal_ai_runtime.dart)|[terminal_ai_input_recovery_test.dart](../../../../example/test/ai/terminal_ai_input_recovery_test.dart)|自动竞争/partial已有；五断点原生副作用证据未齐。|
|D4-R07 · 真实键盘、输入法和触摸板 · P0|[command_blocks_output.dart](../../../../packages/ianvs_terminal/lib/src/terminal/command_blocks_output.dart)|[command_block_scroll_ownership_test.dart](../../../../packages/ianvs_terminal/test/terminal/command_block_scroll_ownership_test.dart)|先修触摸板边界；真实IME/触摸板不能以事件注入代替。|
|D4-R08 · 多会话、分屏与长任务 · P0|[shell_screen_state_terminal_layout.dart](../../../../example/lib/features/shell/shell_screen_state_terminal_layout.dart)|[shell_ai_reconnect_test.dart](../../../../example/test/ai/shell_ai_reconnect_test.dart)|双pane回归不等于四pane原生组合；通知/拖放待验。|
|D4-R09 · 真实 TUI、密码与特殊输出 · P0|[composer_pane.dart](../../../../example/lib/features/terminal_composer/composer_pane.dart)|[composer_acceptance_test.dart](../../../../example/integration_test/composer_acceptance_test.dart)|当前构建vim/top/密码、几何及手动恢复待验。|
|D4-R10 · 断连、休眠与恢复 · P0|[terminal_ai_controller.dart](../../../../example/lib/features/ai/terminal_ai_controller.dart)|[terminal_ai_recovery_test.dart](../../../../example/test/ai/terminal_ai_recovery_test.dart)|本轮结束跟进/生命周期；桌面sleep/wake/重启须另验。|
|D4-R11 · 原生无障碍验收 · P1|[terminal_ai_workspace.dart](../../../../example/lib/features/ai/terminal_ai_workspace.dart)|[terminal_ai_accessibility_acceptance_test.dart](../../../../example/integration_test/terminal_ai_accessibility_acceptance_test.dart)|真实VoiceOver和Full Keyboard Access待完成。|
|D4-R12 · 原生 DPI、字体与多显示器 · P1|[terminal_viewport.dart](../../../../packages/ianvs_terminal/lib/src/terminal/terminal_viewport.dart)|[composer_acceptance_test.dart](../../../../example/integration_test/composer_acceptance_test.dart)|标准/高DPI、外接屏同场景证据未齐。|
|D4-R13 · 性能、内存与长输出 · P1|[bench_runner.dart](../../../../tools/bench/runner/bench_runner.dart)|[cat_log_benchmark_test.dart](../../../../example/test/benchmarks/cat_log_benchmark_test.dart)|按PRD采样profile帧/内存/长输出原始数据，不能目测替代。|
|D4-R14 · 构建、数据与回滚 · P0|[verify_flutter_terminal.sh](../../../../tools/verify_flutter_terminal.sh)|[apple_build_environment_contract_test.dart](../../../../test/apple_build_environment_contract_test.dart)|完整make verify及隔离签名/升级回滚未新运行。|
|D4-R15 · Linux／Windows 桌面验证边界 · P1|[APPLE_PLATFORM_COMPATIBILITY.md](../../../../docs/APPLE_PLATFORM_COMPATIBILITY.md)|[13_DESKTOP_PLATFORM_MATRIX.md](../../../../docs/product/desktop-block-ai-v1/13_DESKTOP_PLATFORM_MATRIX.md)|macOS主范围；Linux/Windows不从UI-only测试推断可交付。|
|D4-R16 · 最终 GitHub 可审查交付 · P0|[validate_evidence.py](../../../../docs/product/desktop-block-ai-v1/scripts/validate_evidence.py)|[test_validate_evidence.py](../../../../docs/product/desktop-block-ai-v1/scripts/test_validate_evidence.py)|validator46测试通过；64场景not_run；候选C未冻结。|
