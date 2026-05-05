import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutterm_pty/flutterm_pty.dart';
import 'package:flutterm_terminal/flutterm_terminal.dart' as terminal;

import 'clipboard_client.dart';
import 'command_history.dart';
import 'fig_completion.dart';
import 'modern_input_controller.dart';
import 'platform_paths.dart';
import 'saved_commands.dart';
import 'session_launch.dart';
import 'session_metadata.dart';
import 'shell_hook_pty_backend_adapter.dart';
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
    List<TerminalBlock> initialBlocks = const <TerminalBlock>[],
    TerminalBlockSeedFactory? initialBlocksForSession,
    TerminalSessionConfigFactory? sessionConfigFactory,
    String? initialCwd,
    String? startupCommand,
    SavedCommandsController? savedCommandsController,
    FigCompletionRepository? completionRepository,
    Map<String, String> completionEnvironment = const <String, String>{},
    TerminalSessionMetadata sessionMetadata = const TerminalSessionMetadata(),
    TerminalSessionLaunchProfile sessionLaunchProfile =
        const TerminalSessionLaunchProfile.localShell(),
  }) : _initialBlocks = List<TerminalBlock>.unmodifiable(initialBlocks),
       _initialBlocksForSession = initialBlocksForSession,
       _sessionConfigFactory = sessionConfigFactory ?? _defaultSessionConfig,
       _initialCwd = _normalizeInitialCwd(initialCwd),
       _startupCommand = _normalizeStartupCommand(startupCommand),
       _sessionMetadata = sessionMetadata,
       _sessionLaunchProfile = sessionLaunchProfile {
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
      initialCwd: _initialCwd,
      environment: completionEnvironment,
    )..addListener(notifyListeners);
  }

  final PtyBackendFactory backendFactory;
  final ClipboardClient clipboardClient;
  final List<TerminalBlock> _initialBlocks;
  final TerminalBlockSeedFactory? _initialBlocksForSession;
  final TerminalSessionConfigFactory _sessionConfigFactory;
  final String _initialCwd;
  String? _startupCommand;
  TerminalSessionMetadata _sessionMetadata;
  TerminalSessionLaunchProfile _sessionLaunchProfile;
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
  StreamSubscription<ShellHookEvent>? _shellHookSubscription;
  ShellHookPtyBackendAdapter? _shellHookBackend;

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
  String? get startupCommand => _startupCommand;
  TerminalSessionMetadata get sessionMetadata => _sessionMetadata;
  TerminalSessionLaunchProfile get sessionLaunchProfile =>
      _sessionLaunchProfile;
  terminal.TerminalViewportController get viewportController =>
      _viewportController;
  terminal.TerminalInputController? get inputController => _inputController;
  bool get canAcceptInput => _status == LocalShellStatus.running;
  bool get canCopy => _inputController != null;
  bool get canPaste => canAcceptInput;
  bool get canRestart => _status != LocalShellStatus.starting;
  bool get isViewedBlockRunning {
    final viewedBlock = blocksController.activeBlock;
    return viewedBlock == null || viewedBlock.isRunning;
  }
  bool get isViewedBlockCompleted => !isViewedBlockRunning;
  bool get canUseRawTerminalForViewedBlock =>
      canAcceptInput &&
      (isViewedBlockRunning || blocksController.hasRunningBlock);
  bool get canWriteToPtyFromViewedBlock => canAcceptInput;

  void updateStartupCommand(String? value) {
    final nextCommand = _normalizeStartupCommand(value);
    if (nextCommand == _startupCommand) {
      return;
    }
    _startupCommand = nextCommand;
    notifyListeners();
  }

  void updateSessionMetadata(TerminalSessionMetadata value) {
    if (value == _sessionMetadata) {
      return;
    }
    _sessionMetadata = value;
    notifyListeners();
  }

  void updateSessionLaunchProfile(TerminalSessionLaunchProfile value) {
    if (value == _sessionLaunchProfile) {
      return;
    }
    _sessionLaunchProfile = value;
    notifyListeners();
  }

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
      final backend = ShellHookPtyBackendAdapter.wrap(backendFactory());
      _shellHookBackend = backend;
      _shellHookSubscription = backend.shellHooks.listen(_handleShellHookEvent);
      final runtime = terminal.TerminalRuntimeController(
        backend: backend,
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
      final seedBlocks = _initialBlocks.isNotEmpty
          ? _initialBlocks
          : _initialBlocksForSession?.call(sessionId) ??
                const <TerminalBlock>[];
      for (final block in seedBlocks) {
        blocksController.addBlock(
          block.sessionId == sessionId
              ? block
              : block.copyWith(sessionId: sessionId),
        );
      }
      _runStartupCommandIfConfigured();
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
    if (!_prepareForRawTerminalInteraction()) {
      modernInputController.useModernInput();
      modernInputController.clearAutoRawHint();
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

  TerminalSessionAuditSnapshot buildAuditSnapshot({
    DateTime? exportedAt,
    TerminalSessionMetadata? metadata,
  }) {
    return buildTerminalSessionAuditSnapshot(
      metadata: metadata ?? _sessionMetadata,
      blocks: blocksController.blocks,
      exportedAt: exportedAt,
    );
  }

  Future<void> _submitModernCommand(String command) async {
    if (!canWriteToPtyFromViewedBlock || !_prepareForPtyWrite()) {
      return;
    }
    _sendCommand(command);
  }

  void _sendCommand(String command) {
    final runtime = _runtime;
    final sessionId = _sessionId;
    if (runtime == null || sessionId == null) {
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

  bool prepareForRawTerminalInteraction() {
    return _prepareForRawTerminalInteraction();
  }

  bool _prepareForPtyWrite() {
    if (!canAcceptInput) {
      return false;
    }
    if (isViewedBlockRunning) {
      return true;
    }
    if (blocksController.hasRunningBlock) {
      return blocksController.selectLatestRunningBlock();
    }
    return true;
  }

  bool _prepareForRawTerminalInteraction() {
    if (!canAcceptInput) {
      return false;
    }
    if (isViewedBlockRunning) {
      return true;
    }
    return blocksController.selectLatestRunningBlock();
  }

  void _handleShellHookEvent(ShellHookEvent event) {
    if (event.sessionId != _sessionId) {
      return;
    }
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
      outputStartRow: cursorRow + 1,
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
    blocksController.finishBlock(
      runningBlock.id,
      status: status,
      recordedAt: DateTime.now().toUtc().toIso8601String(),
      targetEnvironment: _sessionMetadata.auditTargetEnvironment,
    );
    _runningBlock = null;
  }

  String _outputTextForBlock(_RunningShellBlock block) {
    final runtime = _runtime;
    final sessionId = _sessionId;
    if (runtime == null || sessionId == null) {
      return '';
    }
    final frame = _viewportController.frame;
    return runtime.selectionText(
          sessionId,
          terminal.TerminalSelection(
            startRow: block.outputStartRow,
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
    if (runtime != null && sessionId != null) {
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
    if (runtime != null && sessionId != null) {
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
    if (runtime != null && sessionId != null) {
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
    if (event is terminal.TerminalSessionFrameEvent) {
      final frame = event.frame;
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
      return;
    }
    if (event is terminal.TerminalSessionExitEvent) {
      _finishRunningBlock(_blockStatusForExitCode(event.exitCode));
      _exitCode = event.exitCode;
      _status = LocalShellStatus.exited;
      notifyListeners();
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
    _shellHookSubscription?.cancel();
    _shellHookSubscription = null;
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
    _shellHookBackend?.dispose();
    _shellHookBackend = null;
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

  void _runStartupCommandIfConfigured() {
    final command = _startupCommand;
    if (command == null || !canAcceptInput) {
      return;
    }
    _sendCommand(command);
  }
}

String? _normalizeStartupCommand(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return value.trimRight();
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
  return defaultUserHomePath();
}

String _normalizeInitialCwd(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    return _defaultCwd();
  }
  return normalized;
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
