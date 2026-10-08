import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import 'composer_pane.dart';

/// Keeps command presentation attached to the same native PTY as the raw view.
class CommandBlocksPane extends StatefulWidget {
  const CommandBlocksPane({
    super.key,
    required this.session,
    required this.viewport,
    required this.input,
    required this.terminalFocus,
    required this.active,
    required this.font,
    required this.onMeasuredCellSizeChanged,
    required this.child,
    required this.onOpenLinkTarget,
    this.onAskAi,
    this.onAttachBlocks,
    this.onAttachRange,
  });
  final ComposerPaneSession session;
  final TerminalViewportController viewport;
  final TerminalInputController input;
  final FocusNode terminalFocus;
  final bool active;
  final TerminalFontConfig font;
  final ValueChanged<Size> onMeasuredCellSizeChanged;
  final Widget child;
  final ValueChanged<TerminalLinkTarget> onOpenLinkTarget;
  final ValueChanged<CommandBlock>? onAskAi;
  final ValueChanged<List<CommandBlock>>? onAttachBlocks;
  final ValueChanged<CommandBlock>? onAttachRange;

  @override
  State<CommandBlocksPane> createState() => _CommandBlocksPaneState();
}

class _CommandBlocksPaneState extends State<CommandBlocksPane> {
  late final CommandBlockController _blocks;
  Timer? _refresh;
  bool _richOutput = false;
  bool _mainScreenApplication = false;
  TerminalFrameDiff? _lastFrame;
  ComposerOwnership? _lastOwnership;
  bool _lastEnabled = false;
  String? _readyLease;
  String? _readyText;
  int? _readyColumns;
  int? _readyRows;
  String? _seenSubmission;
  String? _revealSubmission;

  bool get _sessionAvailable => identical(
    widget.session.runtime.existingViewportFor(widget.session.sessionId),
    widget.viewport,
  );

  @override
  void initState() {
    super.initState();
    _blocks = widget.session.blocks;
    // Remounting an unresolved command is not another explicit submission.
    _seenSubmission = widget.session.controller.pendingSubmission?.id;
    widget.session.addListener(_changed);
    widget.session.controller.addListener(_changed);
    widget.viewport.addListener(_changed);
    widget.session.navigateBlocks = (delta) {
      if (!_showBlocks || _blocks.blocks.isEmpty) return false;
      _blocks.move(delta);
      return true;
    };
    _changed();
  }

  void _changed() {
    // Capture before the refresh is coalesced: an accepted local submission
    // can clear pendingSubmission before the next output frame arrives.
    final submission = widget.session.controller.pendingSubmission;
    if (submission != null && submission.id != _seenSubmission) {
      _seenSubmission = submission.id;
      if (widget.active && widget.session.enabled) {
        _revealSubmission = submission.id;
      }
    }
    if (!widget.active ||
        !widget.session.enabled ||
        widget.session.controller.ownership == ComposerOwnership.draft) {
      _revealSubmission = null;
    }
    if (_refresh != null) return;
    _refresh = Timer(const Duration(milliseconds: 80), () {
      _refresh = null;
      if (!mounted || !_sessionAvailable) return;
      // Pair output attribution with current ownership. The 150 ms state
      // timer may still report the previous ready lease when this 80 ms
      // output callback observes an AI/native command's first bytes.
      if (widget.session.enabled && widget.active) {
        widget.session.refreshShellState();
      }
      final frame = widget.viewport.frame;
      // Keep graphics and protocol-specific widgets in the full renderer. The
      // flag is session-local because a graphic can leave the visible frame.
      _richOutput |=
          frame.graphics.isNotEmpty ||
          frame.inlineImages.isNotEmpty ||
          frame.sizedText.isNotEmpty ||
          frame.blocks.isNotEmpty ||
          frame.inlineButtons.isNotEmpty;
      final ownership = widget.session.controller.ownership;
      final commandActive =
          ownership == ComposerOwnership.running ||
          ownership == ComposerOwnership.submitting ||
          ownership == ComposerOwnership.suspended;
      if (!commandActive) {
        _mainScreenApplication = false;
      } else if (frame.modes.applicationCursor &&
          frame.modes.applicationKeypad &&
          frame.modes.hideCursor) {
        // procps top redraws the main buffer using application keys and a
        // hidden cursor, without entering the alternate screen. Keep the full
        // terminal until the command ends, including its visible-cursor input
        // prompts. Merely hiding a progress cursor does not activate this.
        _mainScreenApplication = true;
      }
      final fullScreen =
          frame.modes.alternateScreen ||
          frame.modes.mouseMode != 'off' ||
          _mainScreenApplication;
      final enabled = widget.session.enabled && widget.active;
      final previousBlock = _blocks.blocks.lastOrNull?.id;
      if (enabled &&
          (!identical(frame, _lastFrame) ||
              ownership != _lastOwnership ||
              enabled != _lastEnabled)) {
        _blocks.refresh();
      }
      if (_revealSubmission case final submissionId? when enabled) {
        final receipt = widget.session.runtime.composerRequest(
          widget.session.sessionId,
          'composer.receipt',
          {'submissionId': submissionId},
        );
        final blockId = receipt?['blockId'];
        if (receipt?['submissionId'] == submissionId &&
            receipt?['outcome'] == 'accepted' &&
            blockId is String &&
            _blocks.blocks.any((block) => block.id == blockId)) {
          _revealSubmission = null;
          // Reading old output remains stable for background/AI commands.
          // Only this explicit Composer submission reveals its correlated
          // block, which mounts the live input and transfers keyboard focus.
          // A fast command may already have returned focus to the editor.
          // Scroll without stealing it; a running block mounts liveFocus.
          _blocks.reveal(blockId, bottom: true, focus: false);
          // Starting execution leaves keyboard block navigation unselected;
          // the next Command+Up from the editor must still select the latest
          // block rather than skip it because revealing set activeId.
          _blocks.clearSelection();
        } else if (receipt?['outcome'] == 'rejected') {
          _revealSubmission = null;
        }
      }
      final lease = widget.session.controller.readyLease;
      // A decoded frame can lag behind the native ready receipt. Compare
      // native output with native ownership so a late rendering update is
      // not mistaken for new bytes outside a command.
      final live = enabled
          ? widget.session.runtime.liveScreen(widget.session.sessionId)
          : null;
      final text =
          live?['text'] as String? ??
          frame.rows.map((row) => row.text).join('\n');
      final columns = live?['columns'] as int? ?? frame.viewportCols;
      final rows = live?['rows'] as int? ?? frame.viewportRows;
      if (enabled &&
          _lastEnabled &&
          ownership == ComposerOwnership.ready &&
          _lastOwnership == ComposerOwnership.ready &&
          lease == _readyLease &&
          previousBlock == _blocks.blocks.lastOrNull?.id &&
          _readyText != null &&
          text != _readyText &&
          columns == _readyColumns &&
          rows == _readyRows &&
          frame.scrollbackOffset == _lastFrame?.scrollbackOffset) {
        // Unattributed bytes must remain visible. This shell protocol has no
        // prompt-end marker, so do not guess that a prompt redraw is a job's
        // output or silently omit it from the command-only projection.
        widget.session.updateOutput(
          fullScreen: fullScreen,
          richOutput: _richOutput,
          unattributedOutput: true,
        );
      }
      widget.session.updateOutput(
        fullScreen: fullScreen,
        richOutput: _richOutput,
      );
      _readyLease = lease;
      _readyText = text;
      _readyColumns = columns;
      _readyRows = rows;
      _lastFrame = frame;
      _lastOwnership = ownership;
      _lastEnabled = enabled;
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(CommandBlocksPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _changed();
  }

  @override
  void dispose() {
    _refresh?.cancel();
    widget.session.removeListener(_changed);
    widget.session.controller.removeListener(_changed);
    widget.viewport.removeListener(_changed);
    widget.session.navigateBlocks = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // An outgoing AnimatedSwitcher child may rebuild after native teardown.
    // Never mount its cached raw viewport with a disposed controller.
    if (!_sessionAvailable) return const SizedBox.shrink();
    final modes = widget.viewport.frame.modes;
    if (!_showBlocks) {
      return widget.child;
    }
    return TerminalCommandBlocksView(
      key: ValueKey('command-blocks-${widget.session.sessionId}'),
      controller: _blocks,
      chinese: Localizations.localeOf(context).languageCode == 'zh',
      liveInput: widget.active ? widget.input : null,
      liveFocus: widget.active ? widget.terminalFocus : null,
      liveModes: modes,
      font: widget.font,
      onMeasuredCellSizeChanged: widget.onMeasuredCellSizeChanged,
      onOpenLinkTarget: widget.onOpenLinkTarget,
      onAskAi: widget.onAskAi,
      onAttachBlocks: widget.onAttachBlocks,
      onAttachRange: widget.onAttachRange,
      onReturnToInput: widget.session.editorFocus.requestFocus,
      onReinput: (command) {
        widget.session.controller.editor.value = TextEditingValue(
          text: command,
          selection: TextSelection.collapsed(offset: command.length),
        );
        if (widget.session.controller.ownership == ComposerOwnership.ready) {
          widget.session.editorFocus.requestFocus();
        }
      },
    );
  }

  bool get _showBlocks {
    final modes = widget.viewport.frame.modes;
    final owner = widget.session.controller.ownership;
    return widget.session.enabled &&
        _blocks.available &&
        !_richOutput &&
        !_mainScreenApplication &&
        !modes.alternateScreen &&
        modes.mouseMode == 'off' &&
        (owner == ComposerOwnership.ready ||
            owner == ComposerOwnership.running ||
            owner == ComposerOwnership.submitting);
  }
}
