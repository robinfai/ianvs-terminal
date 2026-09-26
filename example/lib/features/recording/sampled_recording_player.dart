import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;

import '../../platform/clipboard_bridge.dart';
import '../../ui/app_ui.dart';
import '../terminal/terminal_input_controller.dart';
import '../terminal/terminal_viewport.dart' show TerminalViewport;
import 'replay_viewport_layout.dart';
import 'sampled_replay_controller.dart';
import 'sampled_replay_surface.dart';

class SampledRecordingPlayer extends StatefulWidget {
  const SampledRecordingPlayer({
    super.key,
    required this.recording,
    required this.onClose,
    required this.colors,
    this.initialPosition = Duration.zero,
    this.font = const terminal.TerminalFontConfig(),
    this.cursor = const terminal.TerminalCursorConfig(),
  });
  final terminal.SampledRecordingFile recording;
  final VoidCallback onClose;
  final Duration initialPosition;
  final terminal.TerminalViewportColors colors;
  final terminal.TerminalFontConfig font;
  final terminal.TerminalCursorConfig cursor;
  @override
  State<SampledRecordingPlayer> createState() => _SampledRecordingPlayerState();
}

class _SampledRecordingPlayerState extends State<SampledRecordingPlayer> {
  late final SampledReplayController _replay;
  final terminal.SelectionController _selection =
      terminal.SelectionController();
  final FocusNode _focus = FocusNode(debugLabel: 'sampled-recording-replay');
  late final TerminalInputController _input;
  Size _cellSize = terminal.terminalFallbackCellSize;

  @override
  void initState() {
    super.initState();
    _replay = SampledReplayController(widget.recording);
    _replay.viewport.addListener(_selection.clear);
    _input = TerminalInputController(
      sessionId: 'recording',
      runtime: const _ReadOnlySink(),
      readFrame: () => _replay.viewport.frame,
      readSelection: () => _selection.textForFrame(_replay.viewport.frame),
      copySelection: (text) => ClipboardBridge.copyWithFeedback(context, text),
      readClipboard: () async => '',
      readOnly: () => true,
    );
    unawaited(_replay.initialize(position: widget.initialPosition));
  }

  @override
  void dispose() {
    _replay.viewport.removeListener(_selection.clear);
    _replay.dispose();
    _selection.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
    },
    child: ListenableBuilder(
      listenable: _replay,
      builder: (context, _) {
        final frame = _replay.viewport.frame;
        final tokens = context.appTheme;
        return SampledReplaySurface(
          title: widget.recording.info.title,
          duration: _replay.duration,
          position: _replay.position,
          playing: _replay.playing,
          loading: _replay.loading,
          speed: _replay.speed,
          interrupted:
              widget.recording.info.completion !=
              terminal.SampledRecordingCompletion.finished,
          error: _replay.error,
          timelineError: _replay.timelineError,
          timelineLoading: _replay.timelineLoading,
          commands: [
            for (final event in _replay.events)
              SampledReplayCommand(
                label:
                    event.command ??
                    switch (event.kind) {
                      terminal.SampledTimelineKind.hookUnavailable =>
                        context.l10n.sampledHookUnavailable,
                      terminal.SampledTimelineKind.hookAvailable =>
                        context.l10n.sampledHookAvailable,
                      _ => event.hostname ?? event.cwd ?? event.contextId,
                    },
                detail: [
                  if (event.kind == terminal.SampledTimelineKind.commandStarted)
                    context.l10n.sampledCommandStarted,
                  if (event.exitCode != null)
                    context.l10n.sampledCommandExit(event.exitCode!),
                  if (event.hostname != null) event.hostname!,
                  if (event.cwd != null) event.cwd!,
                ].join(' · '),
                offset: event.offset,
              ),
          ],
          onToggle: () => _replay.playing ? _replay.pause() : _replay.play(),
          onSeek: (position) => unawaited(_replay.seek(position)),
          onSpeed: _replay.setSpeed,
          onCopy: () => unawaited(
            ClipboardBridge.copyWithFeedback(
              context,
              frame.rows.map((row) => row.text).join('\n'),
            ),
          ),
          onClose: widget.onClose,
          onFirstPage: () => unawaited(_replay.firstPage()),
          onPreviousPage: _replay.hasPreviousPage
              ? () => unawaited(_replay.previousPage())
              : null,
          onNextPage: _replay.hasNextPage
              ? () => unawaited(_replay.nextPage())
              : null,
          viewport: ReplayViewportFit(
            recordedViewportSize: frame.viewportRows > 0
                ? Size(
                    frame.viewportCols * _cellSize.width + 24,
                    frame.viewportRows * _cellSize.height + 24,
                  )
                : null,
            child: ReplayViewportFrame(
              backgroundColor: widget.colors.canvasBackground,
              borderRadius: BorderRadius.circular(tokens.radius.lg),
              child: TerminalViewport(
                key: const Key('recording-replay-viewport'),
                controller: _replay.viewport,
                selectionController: _selection,
                inputController: _input,
                focusNode: _focus,
                contentPadding: const EdgeInsets.all(12),
                colors: widget.colors,
                font: widget.font,
                cursor: widget.cursor,
                altClickMovesCursor: false,
                useFrameDefaultColors: true,
                graphicsCache: _replay.graphics,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
                inlineButtonEnabled: (_) => false,
                onMeasuredCellSizeChanged: (size) {
                  if (mounted && size != _cellSize) {
                    setState(() => _cellSize = size);
                  }
                },
              ),
            ),
          ),
        );
      },
    ),
  );
}

final class _ReadOnlySink implements terminal.TerminalInputSink {
  const _ReadOnlySink();
  @override
  void sendInput(String sessionId, Uint8List bytes) {}
}
