import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutterm_pty/flutterm_pty.dart';
import 'package:flutterm_terminal/flutterm_terminal.dart' as terminal;

import 'clipboard_client.dart';
import 'command_history.dart';
import 'fig_completion.dart';
import 'modern_input_controller.dart';
import 'saved_commands.dart';
import 'terminal_blocks.dart';
import 'terminal_settings.dart';

typedef PtyBackendFactory = PtySessionBackend Function();
typedef TerminalSessionConfigFactory =
    terminal.TerminalSessionConfig Function();

enum LocalShellStatus { starting, running, exited, failed }

class TerminalFindState {
  const TerminalFindState({
    this.query = '',
    this.matches = const <terminal.TerminalSearchMatch>[],
    this.activeIndex = -1,
    this.isOpen = false,
  });

  final String query;
  final List<terminal.TerminalSearchMatch> matches;
  final int activeIndex;
  final bool isOpen;

  int get displayIndex => matches.isEmpty ? 0 : activeIndex + 1;

  TerminalFindState copyWith({
    String? query,
    List<terminal.TerminalSearchMatch>? matches,
    int? activeIndex,
    bool? isOpen,
  }) {
    return TerminalFindState(
      query: query ?? this.query,
      matches: matches ?? this.matches,
      activeIndex: activeIndex ?? this.activeIndex,
      isOpen: isOpen ?? this.isOpen,
    );
  }
}

class LocalShellSessionController extends ChangeNotifier {
  LocalShellSessionController({
    required this.backendFactory,
    required this.clipboardClient,
    TerminalBlockSeedFactory? initialBlocksForSession,
    TerminalSessionConfigFactory? sessionConfigFactory,
    SavedCommandsController? savedCommandsController,
    FigCompletionRepository? completionRepository,
    Map<String, String> completionEnvironment = const <String, String>{},
  }) : _initialBlocksForSession = initialBlocksForSession,
       _sessionConfigFactory = sessionConfigFactory ?? _defaultSessionConfig {
    modernInputController = ModernInputController(
      submitCommand: _submitModernCommand,
    )..addListener(notifyListeners);
    blocksController = TerminalBlocksController(
      clipboardClient: clipboardClient,
      jumpToOffset: scrollViewportTo,
      reinputCommand: _reinputCommand,
    )..addListener(notifyListeners);
    commandHistoryController = CommandHistoryController(
      blocksController: blocksController,
      savedCommandsController: savedCommandsController,
      reinputCommand: _reinputCommand,
    )..addListener(notifyListeners);
    completionController = FigCompletionController(
      engine: FigCompletionEngine(
        repository: completionRepository ?? FigCompletionRepository.empty(),
      ),
      initialCwd: _defaultCwd(),
      environment: completionEnvironment,
    )..addListener(notifyListeners);
  }

  final PtyBackendFactory backendFactory;
  final ClipboardClient clipboardClient;
  final TerminalBlockSeedFactory? _initialBlocksForSession;
  final TerminalSessionConfigFactory _sessionConfigFactory;
  final terminal.SelectionController selectionController =
      terminal.SelectionController();
  late final ModernInputController modernInputController;
  late final TerminalBlocksController blocksController;
  late final CommandHistoryController commandHistoryController;
  late final FigCompletionController completionController;
  final List<terminal.TerminalViewportController> _retiredViewports =
      <terminal.TerminalViewportController>[];

  terminal.TerminalRuntimeController? _runtime;
  terminal.TerminalInputController? _inputController;
  terminal.TerminalViewportController _viewportController =
      terminal.TerminalViewportController();
  StreamSubscription<terminal.TerminalSessionEvent>? _eventsSubscription;

  LocalShellStatus _status = LocalShellStatus.starting;
  TerminalFindState _findState = const TerminalFindState();
  String? _sessionId;
  int? _exitCode;
  Object? _startupError;
  String? _windowTitle;
  Size? _lastViewportSize;
  Size? _lastMeasuredCellSize;
  int _startupRepaintAttempts = 0;
  bool _startupRepaintScheduled = false;
  int _nextBlockId = 0;
  _RunningShellBlock? _runningBlock;

  LocalShellStatus get status => _status;
  TerminalFindState get findState => _findState;
  String? get sessionId => _sessionId;
  int? get exitCode => _exitCode;
  Object? get startupError => _startupError;
  String? get windowTitle => _windowTitle;
  terminal.TerminalViewportController get viewportController =>
      _viewportController;
  terminal.TerminalInputController? get inputController => _inputController;
  bool get canAcceptInput => _status == LocalShellStatus.running;
  bool get canCopy => _inputController != null;
  bool get canPaste => canAcceptInput;
  bool get canRestart => _status != LocalShellStatus.starting;

  void start() {
    _disposeRuntime(closeSession: _sessionId != null);
    _retireViewport();
    _status = LocalShellStatus.starting;
    _sessionId = null;
    _exitCode = null;
    _startupError = null;
    _windowTitle = null;
    _findState = const TerminalFindState();
    selectionController.clear();
    _lastViewportSize = null;
    _lastMeasuredCellSize = null;
    _startupRepaintAttempts = 0;
    _startupRepaintScheduled = false;
    _nextBlockId = 0;
    _runningBlock = null;
    modernInputController.reset();
    completionController.close();
    blocksController.clear();
    commandHistoryController.reset();
    notifyListeners();

    try {
      final sessionConfig = _sessionConfigFactory();
      completionController.updateCwd(sessionConfig.launch.cwd ?? _defaultCwd());
      final runtime = terminal.TerminalRuntimeController(
        backend: backendFactory(),
        copyToClipboard: clipboardClient.writeText,
        readClipboard: clipboardClient.readText,
      );
      _runtime = runtime;
      _eventsSubscription = runtime.events.listen(_handleRuntimeEvent);
      final sessionId = runtime.createSession(sessionConfig);
      _sessionId = sessionId;
      _inputController = terminal.TerminalInputController(
        sessionId: sessionId,
        runtime: runtime,
        readFrame: () => _viewportController.frame,
        readSelection: _selectionText,
        copySelection: clipboardClient.writeText,
        readClipboard: clipboardClient.readText,
      );
      _status = LocalShellStatus.running;
      final seedBlocks =
          _initialBlocksForSession?.call(sessionId) ?? const <TerminalBlock>[];
      for (final block in seedBlocks) {
        blocksController.addBlock(
          block.sessionId == sessionId
              ? block
              : block.copyWith(sessionId: sessionId),
        );
      }
    } catch (error) {
      _disposeRuntime(closeSession: false);
      _startupError = error;
      _status = LocalShellStatus.failed;
    }

    notifyListeners();
  }

  void restart() {
    start();
  }

  void openFind() {
    _findState = _findState.copyWith(isOpen: true);
    notifyListeners();
  }

  void closeFind() {
    _findState = _findState.copyWith(isOpen: false);
    notifyListeners();
  }

  void updateFindQuery(String query) {
    final matches = _searchMatches(query);
    final activeIndex = matches.isEmpty ? -1 : 0;
    _findState = _findState.copyWith(
      query: query,
      matches: matches,
      activeIndex: activeIndex,
    );
    _activateMatch(activeIndex);
    notifyListeners();
  }

  void goToNextMatch() {
    final matches = _findState.matches;
    if (matches.isEmpty) {
      return;
    }
    final nextIndex = (_findState.activeIndex + 1) % matches.length;
    _findState = _findState.copyWith(activeIndex: nextIndex);
    _activateMatch(nextIndex);
    notifyListeners();
  }

  void goToPreviousMatch() {
    final matches = _findState.matches;
    if (matches.isEmpty) {
      return;
    }
    final nextIndex = _findState.activeIndex <= 0
        ? matches.length - 1
        : _findState.activeIndex - 1;
    _findState = _findState.copyWith(activeIndex: nextIndex);
    _activateMatch(nextIndex);
    notifyListeners();
  }

  Future<void> copySelection() async {
    await _inputController?.copySelection();
  }

  Future<void> pasteClipboard() async {
    final runtime = _runtime;
    final sessionId = _sessionId;
    if (!canAcceptInput || runtime == null || sessionId == null) {
      return;
    }
    final text = await clipboardClient.readText();
    if (text.isEmpty) {
      return;
    }
    if (modernInputController.state.effectiveMode ==
        ModernInputEffectiveMode.modern) {
      modernInputController.insertText(text);
      return;
    }
    runtime.sendInput(
      sessionId,
      terminal.TerminalInputController.clipboardPasteBytesFor(
        emulation: terminal.TerminalEmulation.xterm256,
        modes: _viewportController.frame.modes,
        text: text,
      ),
    );
  }

  Future<void> _submitModernCommand(String command) async {
    final runtime = _runtime;
    final sessionId = _sessionId;
    if (!canAcceptInput || runtime == null || sessionId == null) {
      return;
    }
    runtime.sendInput(
      sessionId,
      Uint8List.fromList(
        utf8.encode(command) + _enterBytesFor(_viewportController.frame.modes),
      ),
    );
  }

  Future<void> _reinputCommand(String command) async {
    if (!canAcceptInput) {
      return;
    }
    modernInputController.useModernInput();
    modernInputController.updateDraft(command);
  }

  void _handleShellHookEvent(terminal.TerminalSessionShellHookEvent event) {
    switch (event.hook) {
      case 'preexec':
        _startHookBlock(event.payload);
        break;
      case 'command_finished':
        _finishHookBlock(event.payload);
        break;
      case 'precmd':
        final pwd = event.payload['pwd'] as String?;
        if (pwd != null && pwd.trim().isNotEmpty) {
          completionController.updateCwd(pwd);
        }
        break;
      default:
        break;
    }
  }

  void _startHookBlock(Map<String, Object?> payload) {
    final sessionId = _sessionId;
    if (sessionId == null) {
      return;
    }
    final command = (payload['command'] as String?)?.trimRight();
    if (command == null || command.trim().isEmpty) {
      return;
    }
    if (_runningBlock != null) {
      _finishRunningBlock(TerminalBlockStatus.unknown);
    }

    final frame = _viewportController.frame;
    final cursorRow = frame.viewportStartRow + frame.cursor.row;
    _nextBlockId += 1;
    final blockId = '$sessionId-block-$_nextBlockId';
    blocksController.startBlock(
      id: blockId,
      sessionId: sessionId,
      commandText: command,
      scrollbackOffset: frame.scrollbackOffset,
    );
    _runningBlock = _RunningShellBlock(
      id: blockId,
      commandText: command,
      outputStartRow: cursorRow,
    );
  }

  void _finishHookBlock(Map<String, Object?> payload) {
    final exitCode = (payload['exit_code'] as num?)?.toInt();
    _finishRunningBlock(_blockStatusForExitCode(exitCode));
  }

  void _finishRunningBlock(TerminalBlockStatus status) {
    final runningBlock = _runningBlock;
    if (runningBlock == null) {
      return;
    }
    final outputText = _outputTextForBlock(runningBlock);
    if (outputText.isNotEmpty) {
      blocksController.updateBlockOutput(runningBlock.id, outputText);
    }
    blocksController.finishBlock(runningBlock.id, status: status);
    _runningBlock = null;
  }

  String _outputTextForBlock(_RunningShellBlock block) {
    final runtime = _runtime;
    final sessionId = _sessionId;
    if (runtime == null || sessionId == null) {
      return '';
    }
    final frame = _viewportController.frame;
    var outputStartRow = block.outputStartRow;
    final commandMatches = runtime.searchText(sessionId, block.commandText);
    if (commandMatches.isNotEmpty) {
      outputStartRow = commandMatches.last.row + 1;
    }
    return runtime.selectionText(
          sessionId,
          terminal.TerminalSelection(
            startRow: outputStartRow,
            startCol: 0,
            endRow: 1 << 30,
            endCol: frame.viewportCols,
          ),
          block: false,
        ) ??
        '';
  }

  TerminalBlockStatus _blockStatusForExitCode(int? exitCode) {
    if (exitCode == 0) {
      return TerminalBlockStatus.succeeded;
    }
    if (exitCode == 130) {
      return TerminalBlockStatus.interrupted;
    }
    if (exitCode == null) {
      return TerminalBlockStatus.unknown;
    }
    return TerminalBlockStatus.failed;
  }

  void resizeSession(
    Size viewportSize,
    double devicePixelRatio, {
    Size? measuredCellSize,
  }) {
    final runtime = _runtime;
    final sessionId = _sessionId;
    final viewportUnchanged = viewportSize == _lastViewportSize;
    final cellSizeUnchanged =
        measuredCellSize == null || measuredCellSize == _lastMeasuredCellSize;
    if (!canAcceptInput ||
        runtime == null ||
        sessionId == null ||
        (viewportUnchanged && cellSizeUnchanged)) {
      return;
    }
    _lastViewportSize = viewportSize;
    if (measuredCellSize != null) {
      _lastMeasuredCellSize = measuredCellSize;
      _viewportController.updateMeasuredCellSize(measuredCellSize);
      runtime.viewportFor(sessionId).updateMeasuredCellSize(measuredCellSize);
    }
    runtime.resizeSession(sessionId, viewportSize, devicePixelRatio);
  }

  void scrollViewport(int deltaLines) {
    final runtime = _runtime;
    final sessionId = _sessionId;
    if (runtime == null || sessionId == null) {
      return;
    }
    runtime.scrollViewport(sessionId, deltaLines);
  }

  void scrollViewportTo(int offset) {
    final runtime = _runtime;
    final sessionId = _sessionId;
    if (runtime == null || sessionId == null) {
      return;
    }
    runtime.scrollViewportTo(sessionId, offset);
  }

  List<terminal.TerminalSearchMatch> _searchMatches(String query) {
    if (query.isEmpty) {
      selectionController.clear();
      return const <terminal.TerminalSearchMatch>[];
    }

    final runtime = _runtime;
    final sessionId = _sessionId;
    if (canAcceptInput && runtime != null && sessionId != null) {
      return runtime.searchText(sessionId, query);
    }

    return _searchVisibleFrame(query);
  }

  List<terminal.TerminalSearchMatch> _searchVisibleFrame(String query) {
    final frame = _viewportController.frame;
    final matches = <terminal.TerminalSearchMatch>[];
    for (final row in frame.rows) {
      var start = 0;
      while (start <= row.text.length) {
        final index = row.text.indexOf(query, start);
        if (index < 0) {
          break;
        }
        matches.add(
          terminal.TerminalSearchMatch(
            row: frame.viewportStartRow + row.index,
            startCol: index,
            endCol: index + query.length,
            text: query,
            scrollbackOffset: frame.scrollbackOffset,
          ),
        );
        start = index + query.length;
      }
    }
    return matches;
  }

  void _activateMatch(int activeIndex) {
    if (activeIndex < 0 || activeIndex >= _findState.matches.length) {
      selectionController.clear();
      return;
    }

    final match = _findState.matches[activeIndex];
    final runtime = _runtime;
    final sessionId = _sessionId;
    if (canAcceptInput && runtime != null && sessionId != null) {
      runtime.scrollViewportTo(sessionId, match.scrollbackOffset);
    }
    selectionController.setSelection(
      terminal.TerminalSelection(
        startRow: match.row,
        startCol: match.startCol,
        endRow: match.row,
        endCol: match.endCol,
      ),
    );
  }

  String _selectionText() {
    final selection = selectionController.selection;
    if (selection == null) {
      return '';
    }
    final runtime = _runtime;
    final sessionId = _sessionId;
    if (canAcceptInput && runtime != null && sessionId != null) {
      final nativeSelection = runtime.selectionText(
        sessionId,
        selection,
        block: selectionController.isBlockSelection,
      );
      if (nativeSelection != null) {
        return nativeSelection;
      }
    }
    return selectionController.textForFrame(_viewportController.frame);
  }

  void _handleRuntimeEvent(terminal.TerminalSessionEvent event) {
    if (event.sessionId != _sessionId) {
      return;
    }
    switch (event) {
      case terminal.TerminalSessionFrameEvent(:final frame):
        final nextFrame = _frameWithRenderableDirtyRows(frame);
        _viewportController.updateFrame(nextFrame);
        modernInputController.updateAutoRawHintFromModes(nextFrame.modes);
        _requestStartupRepaintIfNeeded();
        final windowTitle = frame.windowTitle?.trim();
        if (windowTitle != null &&
            windowTitle.isNotEmpty &&
            windowTitle != _windowTitle) {
          _windowTitle = windowTitle;
          notifyListeners();
        }
        break;
      case terminal.TerminalSessionShellHookEvent():
        _handleShellHookEvent(event);
        break;
      case terminal.TerminalSessionExitEvent(:final exitCode):
        _finishRunningBlock(TerminalBlockStatus.unknown);
        _exitCode = exitCode;
        _status = LocalShellStatus.exited;
        notifyListeners();
        break;
    }
  }

  void _requestStartupRepaintIfNeeded() {
    final runtime = _runtime;
    final sessionId = _sessionId;
    if (_startupRepaintAttempts >= 1 ||
        _startupRepaintScheduled ||
        runtime == null ||
        sessionId == null ||
        !canAcceptInput) {
      return;
    }

    final frame = _viewportController.frame;
    if (!frame.cursor.visible || frame.cursor.col <= 0) {
      return;
    }
    final cursorRow = _rowForCursor(frame);
    if (cursorRow != null && cursorRow.text.trim().isNotEmpty) {
      return;
    }

    _startupRepaintAttempts += 1;
    _startupRepaintScheduled = true;
    scheduleMicrotask(() {
      _startupRepaintScheduled = false;
      if (_runtime != runtime || _sessionId != sessionId || !canAcceptInput) {
        return;
      }
      runtime.scrollViewportTo(
        sessionId,
        _viewportController.frame.scrollbackOffset,
      );
    });
  }

  terminal.TerminalRow? _rowForCursor(terminal.TerminalFrameDiff frame) {
    for (final row in frame.rows) {
      if (row.index == frame.cursor.row) {
        return row;
      }
    }
    return null;
  }

  void _retireViewport() {
    _retiredViewports.add(_viewportController);
    _viewportController = terminal.TerminalViewportController();
  }

  void _disposeRuntime({required bool closeSession}) {
    final runtime = _runtime;
    final sessionId = _sessionId;
    _eventsSubscription?.cancel();
    _eventsSubscription = null;
    if (runtime != null && closeSession && sessionId != null) {
      try {
        runtime.closeSession(sessionId);
      } catch (_) {
        // The native process may already have exited; restart should still move on.
      }
    }
    runtime?.dispose();
    _runtime = null;
    _inputController = null;
  }

  @override
  void dispose() {
    _disposeRuntime(closeSession: _sessionId != null);
    modernInputController.removeListener(notifyListeners);
    modernInputController.dispose();
    completionController.removeListener(notifyListeners);
    completionController.dispose();
    commandHistoryController.removeListener(notifyListeners);
    commandHistoryController.dispose();
    blocksController.removeListener(notifyListeners);
    blocksController.dispose();
    selectionController.dispose();
    _viewportController.dispose();
    for (final viewport in _retiredViewports) {
      viewport.dispose();
    }
    super.dispose();
  }
}

terminal.TerminalFrameDiff _frameWithRenderableDirtyRows(
  terminal.TerminalFrameDiff frame,
) {
  if (frame.frameKind != terminal.TerminalFrameKind.delta ||
      frame.rows.isEmpty ||
      frame.viewportRows <= 0) {
    return frame;
  }

  final dirtyRows = <int>{};
  for (final range in frame.dirtyRanges) {
    final start = range.start.clamp(0, frame.viewportRows).toInt();
    final end = range.end.clamp(start, frame.viewportRows).toInt();
    for (var row = start; row < end; row += 1) {
      dirtyRows.add(row);
    }
  }
  for (final row in frame.rows) {
    if (row.index >= 0 && row.index < frame.viewportRows) {
      dirtyRows.add(row.index);
    }
  }

  final nextDirtyRanges = _dirtyRangesForRows(dirtyRows);
  if (_sameDirtyRanges(frame.dirtyRanges, nextDirtyRanges)) {
    return frame;
  }

  return terminal.TerminalFrameDiff(
    frameKind: frame.frameKind,
    rows: frame.rows,
    cursor: frame.cursor,
    selection: frame.selection,
    viewportRows: frame.viewportRows,
    viewportCols: frame.viewportCols,
    dirtyRanges: nextDirtyRanges,
    scrollbackOffset: frame.scrollbackOffset,
    scrollbackMaxOffset: frame.scrollbackMaxOffset,
    viewportStartRow: frame.viewportStartRow,
    viewportRowShift: frame.viewportRowShift,
    modes: frame.modes,
    windowTitle: frame.windowTitle,
    windowIconName: frame.windowIconName,
    hyperlinks: frame.hyperlinks,
  );
}

List<terminal.TerminalDirtyRange> _dirtyRangesForRows(Set<int> rows) {
  if (rows.isEmpty) {
    return const <terminal.TerminalDirtyRange>[];
  }
  final sortedRows = rows.toList()..sort();
  final ranges = <terminal.TerminalDirtyRange>[];
  var start = sortedRows.first;
  var end = start + 1;
  for (final row in sortedRows.skip(1)) {
    if (row == end) {
      end += 1;
      continue;
    }
    ranges.add(terminal.TerminalDirtyRange(start: start, end: end));
    start = row;
    end = row + 1;
  }
  ranges.add(terminal.TerminalDirtyRange(start: start, end: end));
  return ranges;
}

bool _sameDirtyRanges(
  List<terminal.TerminalDirtyRange> left,
  List<terminal.TerminalDirtyRange> right,
) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index].start != right[index].start ||
        left[index].end != right[index].end) {
      return false;
    }
  }
  return true;
}

List<int> _enterBytesFor(terminal.TerminalFrameModes modes) {
  return ascii.encode(modes.lineFeedNewLineMode ? '\r\n' : '\r');
}

terminal.TerminalSessionConfig _defaultSessionConfig() {
  return TerminalSettings.defaults().toSessionConfig();
}

String _defaultCwd() {
  return Platform.environment['HOME'] ?? Directory.current.path;
}

class _RunningShellBlock {
  const _RunningShellBlock({
    required this.id,
    required this.commandText,
    required this.outputStartRow,
  });

  final String id;
  final String commandText;
  final int outputStartRow;
}
