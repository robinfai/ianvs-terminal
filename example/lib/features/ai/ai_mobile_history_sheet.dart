import 'package:flutter/material.dart';

import '../../ui/app_ui.dart';
import 'terminal_ai_controller.dart';

/// A navigation surface only. Selecting history never submits model requests.
class AiMobileHistorySheet extends StatefulWidget {
  const AiMobileHistorySheet({required this.controller, super.key});
  final TerminalAiController controller;

  @override
  State<AiMobileHistorySheet> createState() => _AiMobileHistorySheetState();
}

class _AiMobileHistorySheetState extends State<AiMobileHistorySheet> {
  final _search = TextEditingController();
  String _query = '';
  String t(String en, String zh) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final tasks = controller.tasks.toList();
        final positions = {
          for (var i = 0; i < tasks.length; i++) tasks[i].id: i,
        };
        tasks.sort((a, b) {
          if (a.id == b.id) return 0;
          if (a.id == controller.taskId) return -1;
          if (b.id == controller.taskId) return 1;
          final recent = b.visitOrder.compareTo(a.visitOrder);
          return recent != 0
              ? recent
              : positions[a.id]!.compareTo(positions[b.id]!);
        });
        final visible = tasks
            .where(
              (task) =>
                  '${task.title} ${task.preview} ${task.draft} ${task.commandName}'
                      .toLowerCase()
                      .contains(_query),
            )
            .toList();
        final current = visible
            .where((task) => task.id == controller.taskId)
            .toList();
        final recent = visible
            .where((task) => task.id != controller.taskId)
            .toList();
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 300;
            return Material(
              color: context.groupedBackground,
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    if (!compact) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.outlineVariant,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 48,
                        child: NavigationToolbar(
                          centerMiddle: true,
                          leading: PopupMenuButton<String>(
                            tooltip: t('More actions', '更多操作'),
                            onSelected: (action) =>
                                Navigator.of(context).pop(action),
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'mobile:details',
                                child: Text(t('Details and controls', '详情与控制')),
                              ),
                              PopupMenuItem(
                                value: 'mobile:observe',
                                key: const Key('ai-observe-terminal'),
                                child: Text(
                                  t('View terminal (read-only)', '只读查看终端'),
                                ),
                              ),
                            ],
                            icon: const Icon(Icons.more_horiz),
                          ),
                          middle: Text(
                            t('Conversations', '历史会话'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          trailing: IconButton(
                            tooltip: t('Close', '关闭'),
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      child: Row(
                        children: [
                          Expanded(child: _searchField()),
                          if (compact)
                            IconButton(
                              tooltip: t('Close', '关闭'),
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: visible.isEmpty
                          ? Center(
                              child: Text(
                                t('No matching conversations', '没有匹配的会话'),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : ListView(
                              key: const Key('ai-history-list'),
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                              children: [
                                if (_query.isNotEmpty)
                                  AppGroupedSection(
                                    title: t('Search results', '搜索结果'),
                                    separated: true,
                                    children: [
                                      for (final task in visible)
                                        _conversation(
                                          task,
                                          task.id == controller.taskId,
                                        ),
                                    ],
                                  )
                                else ...[
                                  if (current.isNotEmpty)
                                    AppGroupedSection(
                                      title: t('Current conversation', '当前会话'),
                                      children: [
                                        _conversation(current.first, true),
                                      ],
                                    ),
                                  if (current.isNotEmpty && recent.isNotEmpty)
                                    const SizedBox(height: 24),
                                  if (recent.isNotEmpty)
                                    AppGroupedSection(
                                      title: t('Recent conversations', '最近会话'),
                                      separated: true,
                                      children: [
                                        for (final task in recent)
                                          _conversation(task, false),
                                      ],
                                    ),
                                ],
                              ],
                            ),
                    ),
                    if (!compact)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                        child: FilledButton.icon(
                          key: const Key('ai-new-task'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(160, 48),
                            shape: const StadiumBorder(),
                          ),
                          onPressed:
                              !controller.hasUnresolvedSubmission ||
                                  controller.followUpEnded
                              ? () => Navigator.of(context).pop('mobile:new')
                              : null,
                          icon: const Icon(Icons.edit_square, size: 20),
                          label: Text(t('New conversation', '新建会话')),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _searchField() {
    final theme = Theme.of(context);
    return TextField(
      key: const Key('ai-history-search'),
      controller: _search,
      autocorrect: false,
      textInputAction: TextInputAction.search,
      onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
      decoration: InputDecoration(
        hintText: t('Search conversations', '搜索会话'),
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: t('Clear search', '清除搜索'),
                onPressed: () {
                  _search.clear();
                  setState(() => _query = '');
                },
                icon: const Icon(Icons.cancel_outlined),
              ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: context.appTheme.spacing.md,
          vertical: context.appTheme.spacing.sm,
        ),
        constraints: const BoxConstraints(minHeight: 44),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(context.appTheme.radius.lg),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _conversation(AiTaskSummary task, bool selected) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final spacing = context.appTheme.spacing;
    final title = task.title.isNotEmpty
        ? task.title
        : task.commandName.isNotEmpty
        ? task.commandName
        : task.draft.isNotEmpty
        ? t('Draft', '草稿')
        : t('New conversation', '新会话');
    final preview = task.preview.isNotEmpty ? task.preview : task.draft;
    final status = task.hasUnresolvedSubmission
        ? t('Needs review', '待核对')
        : task.phase == AiPhase.failed
        ? t('Failed', '失败')
        : task.phase == AiPhase.awaitingApproval
        ? t('Awaiting approval', '待审批')
        : null;
    final attention =
        task.hasUnresolvedSubmission || task.phase == AiPhase.failed;
    return Semantics(
      selected: selected,
      child: Material(
        color: context.groupedSurface,
        borderRadius: BorderRadius.circular(context.appTheme.radius.lg),
        child: InkWell(
          key: ValueKey('ai-mobile-task-${task.id}'),
          borderRadius: BorderRadius.circular(context.appTheme.radius.lg),
          onTap: () => Navigator.of(context).pop(task.id),
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: EdgeInsets.symmetric(
              horizontal: spacing.lg,
              vertical: spacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 17,
                        ),
                      ),
                    ),
                    if (selected)
                      Padding(
                        padding: EdgeInsets.only(left: spacing.sm),
                        child: Icon(
                          Icons.check,
                          size: 20,
                          color: colors.primary,
                        ),
                      ),
                  ],
                ),
                if (preview.isNotEmpty && preview != title) ...[
                  SizedBox(height: spacing.xs),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 15,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
                if (status != null)
                  Padding(
                    padding: EdgeInsets.only(top: spacing.sm),
                    child: Text(
                      status,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: attention
                            ? colors.error
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
