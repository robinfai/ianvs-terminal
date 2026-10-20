import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../../platform/clipboard_bridge.dart';
import '../../ui/app_ui.dart';

/// A projection of the current terminal, with no capability to write to a PTY.
///
/// The host keeps its original viewport mounted at the original geometry.
/// This view cannot resize it, focus its editor, paste, or activate inline
/// terminal actions. Scrolling and copying only read the existing output.
class TerminalAiObserver extends StatefulWidget {
  const TerminalAiObserver({
    required this.sessionId,
    required this.targetLabel,
    required this.viewport,
    required this.onScrollLines,
    required this.onScrollToOffset,
    required this.onTakeOver,
    this.onBack,
    this.autofocus = false,
    this.font = const TerminalFontConfig(),
    this.colors,
    this.graphicsCache,
    this.readSelectionText,
    super.key,
  });

  final String sessionId;
  final String targetLabel;
  final TerminalViewportController viewport;
  final ValueChanged<int> onScrollLines;
  final ValueChanged<int> onScrollToOffset;
  final VoidCallback? onTakeOver;
  final VoidCallback? onBack;
  final bool autofocus;
  final TerminalFontConfig font;
  final TerminalViewportColors? colors;
  final TerminalGraphicsCache? graphicsCache;
  final String? Function(TerminalSelection selection, {required bool block})?
  readSelectionText;

  @override
  State<TerminalAiObserver> createState() => _TerminalAiObserverState();
}

class _TerminalAiObserverState extends State<TerminalAiObserver> {
  final _selection = SelectionController();
  final _focus = FocusNode(debugLabel: 'Read-only terminal observer');

  @override
  void initState() {
    super.initState();
    if (widget.autofocus) _requestFocus();
  }

  void _requestFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.autofocus) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _selection.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TerminalAiObserver oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Explicit navigation owns hardware shortcuts. A passive wide-screen
    // projection must leave the AI draft's focus and IME selection untouched.
    if (widget.autofocus && !oldWidget.autofocus) _requestFocus();
    if (oldWidget.sessionId != widget.sessionId ||
        oldWidget.viewport != widget.viewport) {
      _selection.clear();
    }
  }

  String t(String en, String zh) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  String _selectedText() {
    final selection = _selection.selection;
    if (selection == null) return '';
    final text = widget.readSelectionText?.call(
      selection,
      block: _selection.isBlockSelection,
    );
    if (text?.isNotEmpty == true) return text!;
    final frame = widget.viewport.frame;
    // A cross-page selection must never silently copy only the visible rows.
    if (frame.viewportRowForSourceRow(selection.startRow) == null ||
        frame.viewportRowForSourceRow(selection.endRow) == null) {
      return '';
    }
    return _selection.textForFrame(frame);
  }

  KeyEventResult _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    if (_selection.selection != null) {
      _selection.clear();
    } else {
      widget.onBack?.call();
    }
    return KeyEventResult.handled;
  }

  Future<void> _showTarget() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t('Observed terminal', '正在观察的终端')),
      content: SelectableText(widget.targetLabel),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('Done', '完成')),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    final input = TerminalInputController(
      sessionId: widget.sessionId,
      // Deliberately not the session's runtime, including protocol/focus input.
      runtime: const _ObserverSink(),
      readFrame: () => widget.viewport.frame,
      readSelection: _selectedText,
      copySelection: (text) => ClipboardBridge.copyWithFeedback(context, text),
      readClipboard: () async => '',
    );
    return ColoredBox(
      key: ValueKey('ai-terminal-observer-${widget.sessionId}'),
      color: palette.panel,
      child: Column(
        children: [
          Row(
            children: [
              if (widget.onBack != null)
                IconButton(
                  key: const Key('ai-observer-back'),
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  onPressed: widget.onBack,
                  tooltip: t('Return to task', '返回任务'),
                  icon: const Icon(Icons.arrow_back),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    t('Terminal · Read only', '终端 · 只读'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ),
              IconButton(
                key: const Key('ai-observer-target'),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                tooltip: t('Terminal target details', '终端目标详情'),
                onPressed: _showTarget,
                icon: const Icon(Icons.info_outline),
              ),
              Tooltip(
                message: widget.onTakeOver == null
                    ? t('This session is disconnected', '此会话已断开')
                    : t('Pause AI and take over input', '暂停 AI 并接管输入'),
                child: TextButton(
                  key: const Key('ai-observer-take-over'),
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  onPressed: widget.onTakeOver,
                  child: Text(t('Take over', '人工接管')),
                ),
              ),
            ],
          ),
          Expanded(
            child: TerminalViewport(
              key: const Key('ai-observer-viewport'),
              controller: widget.viewport,
              selectionController: _selection,
              inputController: input,
              focusNode: _focus,
              readOnly: true,
              autofocus: widget.autofocus,
              altClickMovesCursor: false,
              useFrameDefaultColors: false,
              colors: widget.colors,
              font: widget.font,
              graphicsCache: widget.graphicsCache,
              onScrollLines: widget.onScrollLines,
              onScrollToOffset: widget.onScrollToOffset,
              onHostKeyEvent: _handleKey,
              // No onMeasuredCellSizeChanged or action callbacks: observing
              // cannot resize the shell or acquire an indirect write path.
            ),
          ),
        ],
      ),
    );
  }
}

final class _ObserverSink implements TerminalInputSink {
  const _ObserverSink();

  @override
  void sendInput(String sessionId, Uint8List bytes) {}
}
