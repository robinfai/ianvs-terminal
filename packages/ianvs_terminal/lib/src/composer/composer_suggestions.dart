import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'completion_models.dart';
import 'terminal_composer_controller.dart';

/// Compact, keyboard-owned suggestion surfaces. Pointer hover changes the
/// selection without moving focus out of the editor.
class ComposerSuggestions extends StatelessWidget {
  const ComposerSuggestions({
    required this.model,
    required this.scroll,
    required this.chinese,
    required this.onAccepted,
    super.key,
  });

  final TerminalComposerController model;
  final ScrollController scroll;
  final bool chinese;
  final VoidCallback onAccepted;
  String tr(String en, String zh) => chinese ? zh : en;

  static double rowExtent(TextScaler scaler, {required bool inlineDetail}) =>
      math.max(
        32,
        12 +
            scaler.scale(13) * 1.4 +
            (inlineDetail ? scaler.scale(11) * 1.4 : 0),
      );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final colors = Theme.of(context).colorScheme;
      final scaler = MediaQuery.textScalerOf(context);
      final history = model.historyOpen;
      final split = !history && bounds.maxWidth >= scaler.scale(600);
      final selected = model.selectedIndex >= 0
          ? model.items[model.selectedIndex]
          : null;
      final count = history ? model.historyItems.length : model.items.length;
      final maxHeight = (MediaQuery.sizeOf(context).height * .36).clamp(
        120.0,
        320.0,
      );
      final footer = scaler.scale(11) * 1.4 + 16;
      final header = history ? scaler.scale(12) * 1.4 + 16 : 0.0;
      final extent = rowExtent(scaler, inlineDetail: !history && !split);
      final visibleRows = math.max(
        1,
        ((maxHeight - footer - header - 8) / extent).floor(),
      );
      final listHeight = math.max(1, math.min(count, visibleRows)) * extent;
      final list = _surface(
        context,
        SizedBox(
          height: count == 0
              ? math.min(maxHeight, 126 + scaler.scale(12))
              : listHeight + footer + header + 8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (history)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: 15,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tr('Command history', '命令历史'),
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: count == 0
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            tr('No matching commands', '没有匹配的历史命令'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        key: Key(
                          history
                              ? 'composer-history-list'
                              : 'composer-completion-list',
                        ),
                        controller: scroll,
                        padding: const EdgeInsets.all(4),
                        itemExtent: extent,
                        itemCount: count,
                        itemBuilder: (context, index) => history
                            ? _historyRow(context, index)
                            : _completionRow(
                                context,
                                model.items[index],
                                index,
                                !split,
                              ),
                      ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.outlineVariant)),
                ),
                child: Text(
                  scaler.scale(11) > 16
                      ? tr('↑ ↓   ⇥ accept   esc', '↑ ↓   ⇥ 采用   esc')
                      : tr(
                          '↑ ↓ navigate   ⇥ accept   esc close',
                          '↑ ↓ 选择   ⇥ 采用   esc 关闭',
                        ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      if (!split) return list;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(flex: 5, child: list),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: selected == null
                ? const SizedBox.shrink()
                : _surface(
                    context,
                    ConstrainedBox(
                      key: const Key('composer-completion-detail'),
                      constraints: BoxConstraints(maxHeight: maxHeight),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  _icon(selected),
                                  size: 16,
                                  color: colors.onSurfaceVariant,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _safe(selected.label),
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 13,
                                      height: 1.4,
                                      fontWeight: FontWeight.w600,
                                      color: colors.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (selected.detail.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                _safe(selected.detail),
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.5,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Text(
                              _kind(selected.kind),
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      );
    },
  );

  Widget _surface(BuildContext context, Widget child) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainer,
      elevation: 6,
      shadowColor: colors.shadow.withValues(alpha: .24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: child,
    );
  }

  Widget _completionRow(
    BuildContext context,
    CompletionEdit item,
    int index,
    bool detail,
  ) {
    final value = model.editor.value;
    final cursor = value.selection.extentOffset;
    final query =
        item.start >= 0 && item.start <= cursor && cursor <= value.text.length
        ? value.text
              .substring(item.start, cursor)
              .replaceAll(RegExp('["\']'), '')
        : '';
    return _row(
      context,
      selected: model.selectedIndex == index,
      label: _safe(item.label),
      query: query,
      detail: detail ? _safe(item.detail) : null,
      icon: _icon(item),
      type: _kind(item.kind),
      semantic:
          '${_safe(item.label)}, ${_safe(item.detail)}, ${index + 1}/${model.items.length}',
      onHover: () => model.highlightCompletion(item),
      onTap: () {
        if (model.accept(item)) onAccepted();
      },
    );
  }

  Widget _historyRow(BuildContext context, int index) {
    final command = model.historyItems[index];
    return _row(
      context,
      selected: model.historySelectedIndex == index,
      label: _safe(command.replaceAll('\n', ' ↵ ').replaceAll('\t', ' ')),
      query: model.historyFilter,
      icon: Icons.history_rounded,
      semantic: '$command, ${index + 1}/${model.historyItems.length}',
      onHover: () => model.highlightHistory(command),
      onTap: () {
        if (model.acceptHistory(command)) onAccepted();
      },
    );
  }

  Widget _row(
    BuildContext context, {
    required bool selected,
    required String label,
    required String query,
    required IconData icon,
    required String semantic,
    required VoidCallback onHover,
    required VoidCallback onTap,
    String? detail,
    String? type,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      label: semantic,
      child: ExcludeSemantics(
        child: MouseRegion(
          onEnter: (_) => onHover(),
          child: InkWell(
            canRequestFocus: false,
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? colors.secondaryContainer : null,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 15,
                    color: selected
                        ? colors.onSecondaryContainer
                        : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          _highlight(
                            label,
                            query,
                            selected
                                ? colors.onSecondaryContainer
                                : colors.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                        if (detail != null)
                          Text(
                            detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.4,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (type != null &&
                      MediaQuery.textScalerOf(context).scale(13) < 20) ...[
                    const SizedBox(width: 8),
                    Text(
                      type,
                      style: TextStyle(
                        fontSize: 10,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  TextSpan _highlight(String text, String query, Color color) {
    final words = query
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty);
    final positions = <int>{};
    for (final word in words) {
      for (final match in RegExp(
        RegExp.escape(word),
        caseSensitive: false,
      ).allMatches(text)) {
        positions.addAll(
          List.generate(match.end - match.start, (i) => match.start + i),
        );
      }
    }
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final grapheme in text.characters) {
      spans.add(
        TextSpan(
          text: grapheme,
          style: TextStyle(
            color: color,
            fontWeight: positions.contains(offset)
                ? FontWeight.w700
                : FontWeight.w400,
          ),
        ),
      );
      offset += grapheme.length;
    }
    return TextSpan(children: spans);
  }

  static String _safe(String text) =>
      text.replaceAll(RegExp(r'[\x00-\x1f\x7f-\x9f]'), '');
  IconData _icon(CompletionEdit item) => item.riskHint
      ? Icons.warning_amber_rounded
      : switch (item.kind) {
          'directory' || 'folder' => Icons.folder_outlined,
          'file' => Icons.insert_drive_file_outlined,
          'option' => Icons.flag_outlined,
          'alias' => Icons.shortcut_rounded,
          'script' => Icons.play_circle_outline_rounded,
          'command' || 'subcommand' => Icons.terminal_rounded,
          _ => Icons.code_rounded,
        };
  String _kind(String kind) => switch (kind) {
    'directory' || 'folder' => tr('Directory', '目录'),
    'file' => tr('File', '文件'),
    'option' => tr('Option', '选项'),
    'alias' => tr('Alias', '别名'),
    'script' => tr('Script', '脚本'),
    'command' || 'subcommand' => tr('Command', '命令'),
    _ => tr('Argument', '参数'),
  };
}
