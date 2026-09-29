import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'completion_models.dart';
import 'composer_icons.dart';
import 'composer_theme.dart';
import 'terminal_composer_controller.dart';

/// Results remain keyboard-owned; pointer scrolling never reveals a selection.
class ComposerSuggestions extends StatelessWidget {
  const ComposerSuggestions({
    required this.model,
    required this.scroll,
    required this.chinese,
    required this.onAccepted,
    this.onClosed,
    this.maxHeight = 320,
    super.key,
  });

  final TerminalComposerController model;
  final ScrollController scroll;
  final bool chinese;
  final VoidCallback onAccepted;
  final VoidCallback? onClosed;
  final double maxHeight;
  String tr(String en, String zh) => chinese ? zh : en;

  static double rowExtent(
    TextScaler scaler, {
    required bool inlineDetail,
    ComposerTheme? tokens,
  }) => math.max(
    34,
    14 +
        (scaler.scale(tokens?.resultStyle.fontSize ?? 14) *
                (tokens?.resultStyle.height ?? 1.4))
            .ceilToDouble() +
        (inlineDetail
            ? (scaler.scale(tokens?.statusStyle.fontSize ?? 12) *
                      (tokens?.statusStyle.height ?? 1.4))
                  .ceilToDouble()
            : 0),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      if (maxHeight <= 0) return const SizedBox.shrink();
      final tokens = ComposerTheme.of(context);
      final scaler = MediaQuery.textScalerOf(context);
      final history = model.historyOpen;
      final split = !history && bounds.maxWidth >= scaler.scale(600);
      final selected = model.selectedIndex >= 0
          ? model.items[model.selectedIndex]
          : null;
      final count = history ? model.historyItems.length : model.items.length;
      final extent = rowExtent(
        scaler,
        inlineDetail: !history && !split,
        tokens: tokens,
      );
      final available = maxHeight.clamp(0.0, 320.0);
      var footer = math.max(tokens.controlHeight, scaler.scale(12) * 1.4 + 8);
      var header = history ? math.max(32.0, scaler.scale(12) * 1.4 + 12) : 0.0;
      // Short windows prioritize a usable result row over redundant chrome.
      if (available < extent + header + footer + 8) header = 0;
      if (available < extent + footer + 8) footer = 0;
      final desired = count == 0
          ? scaler.scale(12) * 3 + 32 + header + footer
          : count * extent + 8 + header + footer;
      final panelHeight = math.min(available, desired);
      final listHeight = math.max(0.0, panelHeight - header - footer);
      final list = _surface(
        tokens,
        SizedBox(
          height: panelHeight,
          child: Column(
            children: [
              if (header > 0)
                SizedBox(
                  height: header,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Icon(
                          ComposerIcons.history,
                          size: 16,
                          color: tokens.muted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tr('Command history', '命令历史'),
                            style: tokens.contextStyle,
                          ),
                        ),
                        Text('$count', style: tokens.metadataStyle),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: count == 0
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          model.hasHistory
                              ? tr(
                                  'No matching commands. Try a different filter.',
                                  '没有匹配的历史命令，请调整筛选内容。',
                                )
                              : tr(
                                  'No command history in this session yet.',
                                  '当前会话还没有命令历史。',
                                ),
                          textAlign: TextAlign.center,
                          style: tokens.statusStyle,
                        ),
                      )
                    : ScrollConfiguration(
                        behavior: ScrollConfiguration.of(
                          context,
                        ).copyWith(scrollbars: false),
                        child: Scrollbar(
                          controller: scroll,
                          thumbVisibility: count * extent + 8 > listHeight,
                          child: ListView.builder(
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
                      ),
              ),
              if (footer > 0)
                Container(
                  height: footer,
                  padding: const EdgeInsets.only(left: 12, right: 4),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: tokens.divider)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          count == 0
                              ? tr('Esc restore draft', 'Esc 恢复草稿')
                              : bounds.maxWidth < scaler.scale(400)
                              ? tr('↑ ↓ select · Tab accept', '↑ ↓ 选择 · Tab 采用')
                              : tr(
                                  '↑ ↓ select   Tab accept   Esc close',
                                  '↑ ↓ 选择   Tab 采用   Esc 关闭',
                                ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tokens.metadataStyle,
                        ),
                      ),
                      if (!split && selected != null)
                        TextButton(
                          key: const Key('composer-completion-detail-action'),
                          style: TextButton.styleFrom(
                            textStyle: tokens.actionStyle,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () => _showDetails(context, selected),
                          child: Text(tr('Details', '详情')),
                        ),
                      IconButton(
                        key: const Key('composer-menu-close'),
                        tooltip: history
                            ? tr(
                                'Close history and restore draft · Esc',
                                '关闭历史并恢复草稿 · Esc',
                              )
                            : tr('Close completions · Esc', '关闭补全 · Esc'),
                        icon: Icon(
                          ComposerIcons.close,
                          size: 16,
                          color: tokens.muted,
                          semanticLabel: history
                              ? tr(
                                  'Close history and restore draft',
                                  '关闭历史并恢复草稿',
                                )
                              : tr('Close completions', '关闭补全'),
                        ),
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints.tightFor(
                          width: tokens.controlHeight,
                          height: footer,
                        ),
                        onPressed: () {
                          history
                              ? model.dismissHistory()
                              : model.dismissCompletions();
                          onClosed?.call();
                        },
                      ),
                    ],
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
                    tokens,
                    SizedBox(
                      key: const Key('composer-completion-detail'),
                      height: panelHeight,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(14),
                        child: _details(tokens, selected),
                      ),
                    ),
                  ),
          ),
        ],
      );
    },
  );

  Widget _surface(ComposerTheme tokens, Widget child) => Material(
    color: tokens.popover,
    elevation: tokens.highContrast ? 0 : 4,
    shadowColor: tokens.shadow,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(ComposerTheme.popoverRadius),
      side: BorderSide(color: tokens.border, width: tokens.borderWidth),
    ),
    child: child,
  );

  Widget _details(ComposerTheme tokens, CompletionEdit item) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ComposerIcons.forKind(item.kind), size: 16, color: tokens.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _safe(item.label),
              style: tokens.resultStyle.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      if (item.detail.isNotEmpty) ...[
        const SizedBox(height: 10),
        SelectableText(_safe(item.detail), style: tokens.statusStyle),
      ],
      const SizedBox(height: 10),
      Text(_kind(item.kind), style: tokens.metadataStyle),
      if (item.riskHint) ...[
        const SizedBox(height: 8),
        Text(
          tr('Review the expanded command before running.', '执行前请确认展开后的命令。'),
          style: tokens.statusStyle.copyWith(color: tokens.error),
        ),
      ],
    ],
  );

  Future<void> _showDetails(BuildContext context, CompletionEdit item) async {
    final tokens = ComposerTheme.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Completion details', '补全详情')),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(child: _details(tokens, item)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Done', '完成')),
          ),
        ],
      ),
    );
    onClosed?.call();
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
      icon: ComposerIcons.forKind(item.kind),
      type: _kind(item.kind),
      riskHint: item.riskHint,
      semantic:
          '${_safe(item.label)}, ${_kind(item.kind)}, ${_safe(item.detail)}, ${index + 1}/${model.items.length}',
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
      icon: ComposerIcons.history,
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
    bool riskHint = false,
  }) {
    final tokens = ComposerTheme.of(context);
    final color = selected ? tokens.onSelection : tokens.foreground;
    return Semantics(
      selected: selected,
      button: true,
      label: semantic,
      onTap: onTap,
      child: ExcludeSemantics(
        child: MouseRegion(
          // Enter is also emitted when a row moves under a stationary pointer.
          // Only actual pointer movement changes selection, never scroll position.
          onHover: (_) => onHover(),
          child: Tooltip(
            message: [
              label,
              if (detail != null && detail.isNotEmpty) detail,
              ?type,
            ].join('\n'),
            child: InkWell(
              canRequestFocus: false,
              hoverColor: tokens.hover,
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: selected ? tokens.selection : null,
                  borderRadius: BorderRadius.circular(ComposerTheme.rowRadius),
                  border: selected && tokens.highContrast
                      ? Border(
                          left: BorderSide(color: tokens.onSelection, width: 3),
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: ComposerTheme.rowIconSize,
                      color: selected ? tokens.onSelection : tokens.muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            _highlight(label, query, color),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tokens.resultStyle,
                          ),
                          if (detail != null)
                            Text(
                              detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tokens.statusStyle,
                            ),
                        ],
                      ),
                    ),
                    if (riskHint) ...[
                      const SizedBox(width: 6),
                      Tooltip(
                        message: tr('Review before running', '执行前确认命令'),
                        child: Icon(
                          ComposerIcons.unknown,
                          size: 16,
                          color: tokens.error,
                        ),
                      ),
                    ],
                    if (type != null &&
                        MediaQuery.textScalerOf(context).scale(13) < 20) ...[
                      const SizedBox(width: 8),
                      Text(type, style: tokens.metadataStyle),
                    ],
                  ],
                ),
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
  String _kind(String kind) => switch (kind) {
    'directory' || 'folder' => tr('Directory', '目录'),
    'file' => tr('File', '文件'),
    'option' => tr('Option', '选项'),
    'alias' => tr('Alias', '别名'),
    'script' => tr('Script', '脚本'),
    'command' => tr('Command', '命令'),
    'subcommand' => tr('Subcommand', '子命令'),
    _ => tr('Argument', '参数'),
  };
}
