import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'completion_models.dart';

enum ComposerOwnership { draft, ready, submitting, running, suspended, unknown }

enum ComposerSubmissionOutcome { accepted, rejected, unknown }

enum ComposerPrimaryAction { disabled, acceptHistory, acceptCompletion, run }

@immutable
final class ComposerSubmission {
  const ComposerSubmission({
    required this.id,
    required this.lease,
    required this.query,
  });
  final String id;
  final String lease;
  final CompletionQuery query;
}

typedef ComposerSubmit =
    Future<ComposerSubmissionOutcome> Function(ComposerSubmission submission);

typedef _CompletionRequest = ({
  CompletionQuery query,
  bool localSuggestions,
  bool fromTab,
  bool showMenu,
});

/// A pane-scoped local document. It deliberately has no terminal input sink.
final class TerminalComposerController extends ChangeNotifier {
  TerminalComposerController({
    required this.targetId,
    required this.provider,
    this.submit,
    String text = '',
    this.debounce = const Duration(milliseconds: 100),
  }) : sessionEpoch = ++_epochSeed,
       editor = TextEditingController(text: text) {
    editor.selection = TextSelection.collapsed(offset: text.length);
    _previous = editor.value;
    editor.addListener(_edited);
  }

  static int _epochSeed = 0;
  final int sessionEpoch;
  final String targetId;
  final CompletionProvider provider;
  final ComposerSubmit? submit;
  final Duration debounce;
  final TextEditingController editor;
  late TextEditingValue _previous;
  final List<TextEditingValue> _undo = [];
  final List<TextEditingValue> _redo = [];
  int _editorRevision = 0;
  int _selectionRevision = 0;
  int _selectionNavigationRevision = 0;
  int _contextRevision = 0;
  int _submissionSerial = 0;
  int _policyRevision = 0;
  bool _localSuggestions = false;
  bool _restoring = false;
  bool _disposed = false;
  bool _active = true;
  Timer? _timer;
  CompletionCancellation? _cancellation;
  _CompletionRequest? _queued;
  _CompletionRequest? _currentRequest;
  bool _inFlight = false;
  CompletionBatch? _batch;
  String? _selectedId;
  String? _lease;
  String _contextKey = '';
  String _dialect = 'generic';
  String _executionStatus = '';
  String _completionStatus = '';
  String cwd = '';
  ComposerOwnership ownership = ComposerOwnership.draft;
  ComposerSubmission? pendingSubmission;
  bool _completionMenuOpen = false;
  List<String> _history = const [];
  List<String> _historyItems = const [];
  TextEditingValue? _historyDraft;
  String? _selectedHistory;
  CompletionQuery? _dismissedInline;

  bool get completionMenuOpen => _completionMenuOpen && items.isNotEmpty;
  bool get historyOpen => _historyDraft != null;
  bool get canOpenHistory => _canSuggest && editor.value.composing.isCollapsed;
  bool get hasHistory => _history.isNotEmpty;
  List<String> get historyItems => _historyItems;
  int get historySelectedIndex => _historyItems.indexOf(_selectedHistory ?? '');
  String get historyFilter => editor.text;
  String get dialect => _dialect;

  /// Submission feedback survives editing and completion requests. An unknown
  /// transaction stays visible until explicitly recovered, even while polling.
  String get executionStatus => ownership == ComposerOwnership.unknown
      ? 'unknown_outcome'
      : _executionStatus;

  /// Transient feedback for the current document, separate from execution.
  String get completionStatus => _completionStatus;

  /// Compatibility for hosts displaying one feedback line. Submission results
  /// take precedence; writing a completion status cannot erase those results.
  String get status =>
      executionStatus.isNotEmpty ? executionStatus : completionStatus;
  set status(String value) {
    if (value == 'unknown_outcome' || value == 'submission_rejected') {
      _executionStatus = value;
    } else {
      _completionStatus = value;
    }
  }

  bool get canRecoverDraft =>
      !_disposed &&
      ownership == ComposerOwnership.unknown &&
      pendingSubmission != null &&
      editor.value.composing.isCollapsed;

  /// Explicit navigation/filtering requests that should reveal the selection.
  /// Pointer highlighting and background updates must not interrupt scrolling.
  int get selectionNavigationRevision => _selectionNavigationRevision;
  bool get _canSuggest =>
      !_disposed &&
      _active &&
      (ownership == ComposerOwnership.ready ||
          ownership == ComposerOwnership.draft);

  /// Newest first, per session, and never persisted by the editor. Hosts may
  /// supply the live shell's history, including commands entered through ZLE.
  void updateHistory(Iterable<String> commands) {
    if (_disposed) return;
    final unique = <String>{};
    var size = 0;
    for (final command in commands.take(200)) {
      if (command.trim().isEmpty ||
          command.startsWith(RegExp(r'\s')) ||
          command.length > 65536 ||
          command.codeUnits.any(
            (c) => (c < 32 && c != 10 && c != 9) || (c >= 127 && c <= 159),
          )) {
        continue;
      }
      if (size + command.length > 131072) break;
      if (unique.add(command)) size += command.length;
    }
    final next = unique.toList(growable: false);
    if (listEquals(next, _history)) return;
    _history = List.unmodifiable(next);
    if (historyOpen) _filterHistory();
    notifyListeners();
  }

  void openHistory() {
    if (!canOpenHistory) return;
    if (!historyOpen) _historyDraft = editor.value;
    dismissCompletions(notify: false);
    _filterHistory();
    _selectionNavigationRevision++;
    notifyListeners();
  }

  void toggleHistory() {
    if (_disposed || !_active || !editor.value.composing.isCollapsed) return;
    historyOpen ? dismissHistory() : openHistory();
  }

  void _filterHistory() {
    final words = editor.text.toLowerCase().trim().split(RegExp(r'\s+'));
    // Oldest above, newest nearest the input, so repeated Up goes back in time.
    _historyItems = List.unmodifiable(
      _history.reversed.where((command) {
        final text = command.toLowerCase();
        return words.every(text.contains);
      }),
    );
    if (!_historyItems.contains(_selectedHistory)) {
      _selectedHistory = _historyItems.isEmpty ? null : _historyItems.last;
    }
  }

  void selectHistory(int delta) {
    if (!historyOpen) {
      openHistory();
      return;
    }
    if (_historyItems.isEmpty) return;
    final next = historySelectedIndex + delta;
    if (next >= _historyItems.length) {
      dismissHistory();
      return;
    }
    _selectedHistory = _historyItems[next.clamp(0, _historyItems.length - 1)];
    _selectionNavigationRevision++;
    notifyListeners();
  }

  void highlightHistory(String command) {
    if (historyOpen &&
        _selectedHistory != command &&
        _historyItems.contains(command)) {
      _selectedHistory = command;
      notifyListeners();
    }
  }

  bool acceptHistory([String? command]) {
    final selected = command ?? _selectedHistory;
    if (!historyOpen ||
        !editor.value.composing.isCollapsed ||
        selected == null ||
        !_historyItems.contains(selected)) {
      return false;
    }
    dismissHistory(notify: false);
    editor.value = TextEditingValue(
      text: selected,
      selection: TextSelection.collapsed(offset: selected.length),
    );
    dismissCompletions(notify: false);
    _dismissedInline = snapshot;
    notifyListeners();
    return true;
  }

  void dismissHistory({bool notify = true}) {
    final draft = _historyDraft;
    if (draft == null) return;
    _restoring = true;
    editor.value = draft;
    _restoring = false;
    _historyDraft = null;
    _historyItems = const [];
    _selectedHistory = null;
    _dismissedInline = snapshot;
    if (notify) notifyListeners();
  }

  /// A preview suffix, never part of TextEditingValue, clipboard or submission.
  String get inlineSuggestion {
    final value = editor.value;
    if (!_canSuggest ||
        historyOpen ||
        completionMenuOpen ||
        !snapshot.canComplete ||
        value.text.isEmpty ||
        value.selection.end != value.text.length ||
        _dismissedInline?.matches(snapshot) == true) {
      return '';
    }
    for (final command in _history) {
      if (command.length > value.text.length &&
          command.startsWith(value.text)) {
        return command.substring(value.text.length);
      }
    }
    if (_batch?.query.matches(snapshot) != true) return '';
    for (final item in items) {
      final result = _completionValue(item);
      if (result != null &&
          result.selection.end == result.text.length &&
          result.text.startsWith(value.text) &&
          result.text.length > value.text.length) {
        return result.text.substring(value.text.length);
      }
    }
    return '';
  }

  bool acceptInline({bool partial = false}) {
    final suffix = inlineSuggestion;
    if (suffix.isEmpty) return false;
    final part = partial
        ? (RegExp(r'^\s*\S+\s*').firstMatch(suffix)?.group(0) ?? suffix)
        : suffix;
    final result = editor.text + part;
    editor.value = TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
    return true;
  }

  void dismissInline() {
    _dismissedInline = snapshot;
    notifyListeners();
  }

  List<CompletionEdit> get items => _batch?.items ?? const [];
  int get selectedIndex =>
      items.indexWhere((item) => item.itemId == _selectedId);
  bool get loading => _inFlight && _cancellation?.isCancelled == false;
  bool get canRun =>
      !_disposed &&
      _active &&
      ownership == ComposerOwnership.ready &&
      _lease != null &&
      submit != null &&
      !historyOpen &&
      editor.text.trim().isNotEmpty &&
      editor.value.composing.isCollapsed;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  String? get readyLease =>
      ownership == ComposerOwnership.ready ? _lease : null;
  bool get localSuggestions => _localSuggestions;

  /// A single decision for the primary button and Enter. Predictions are not
  /// included: accepting grey text remains a distinct, explicit edit action.
  ComposerPrimaryAction get primaryAction {
    if (_disposed ||
        !_active ||
        !editor.value.composing.isCollapsed ||
        ownership == ComposerOwnership.submitting ||
        ownership == ComposerOwnership.running ||
        ownership == ComposerOwnership.suspended) {
      return ComposerPrimaryAction.disabled;
    }
    if (historyOpen) {
      return historySelectedIndex >= 0
          ? ComposerPrimaryAction.acceptHistory
          : ComposerPrimaryAction.disabled;
    }
    if (selectedIndex >= 0) {
      return _batch?.query.matches(snapshot) == true && snapshot.canComplete
          ? ComposerPrimaryAction.acceptCompletion
          : ComposerPrimaryAction.disabled;
    }
    return canRun ? ComposerPrimaryAction.run : ComposerPrimaryAction.disabled;
  }

  bool get canPerformPrimaryAction =>
      primaryAction != ComposerPrimaryAction.disabled;

  Future<void> performPrimaryAction() async {
    switch (primaryAction) {
      case ComposerPrimaryAction.disabled:
        return;
      case ComposerPrimaryAction.acceptHistory:
        acceptHistory();
      case ComposerPrimaryAction.acceptCompletion:
        accept();
      case ComposerPrimaryAction.run:
        await run();
    }
  }

  /// Local IO is allowed only for the live request: automatic suggestions or
  /// an explicit Tab. A Tab never changes the session's automatic preference.
  bool allowsLocalSuggestions(CompletionCancellation cancellation) =>
      !_disposed &&
      _active &&
      identical(_cancellation, cancellation) &&
      !cancellation.isCancelled &&
      _currentRequest?.localSuggestions == true &&
      _currentRequest!.query.matches(snapshot) &&
      readyLease != null;

  void toggleLocalSuggestions() {
    _localSuggestions = !_localSuggestions;
    _policyRevision++;
    dismissCompletions();
    if (_active && editor.text.isNotEmpty) {
      _requestCompletions(fromTab: false, showMenu: _localSuggestions);
    }
  }

  CompletionQuery get snapshot => CompletionQuery(
    sessionEpoch: sessionEpoch,
    targetId: targetId,
    contextRevision: _contextRevision,
    editorRevision: _editorRevision,
    selectionRevision: _selectionRevision,
    value: editor.value,
    dialect: _dialect,
    policyRevision: _policyRevision,
  );

  void _edited() {
    final next = editor.value;
    if (next == _previous) return;
    if (next.text != _previous.text) {
      _editorRevision++;
      if (!_restoring && !historyOpen && _previous.composing.isCollapsed) {
        _undo.add(_previous);
        if (_undo.length > 200) _undo.removeAt(0);
        _redo.clear();
      }
    }
    if (next.selection != _previous.selection ||
        next.composing != _previous.composing) {
      _selectionRevision++;
    }
    _previous = next;
    _completionStatus = '';
    dismissCompletions(notify: false);
    if (historyOpen) {
      _filterHistory();
      _selectionNavigationRevision++;
    } else if (_active && snapshot.canComplete && next.text.isNotEmpty) {
      _timer = Timer(
        debounce,
        () => _requestCompletions(fromTab: false, showMenu: _localSuggestions),
      );
    }
    notifyListeners();
  }

  /// Context comes from the bound session, never a process-wide cwd fallback.
  void updateShell({
    required String contextKey,
    required String cwd,
    required ComposerOwnership ownership,
    String? lease,
    String dialect = 'generic',
  }) {
    if (_disposed) return;
    final changed =
        _contextKey != contextKey || this.cwd != cwd || _dialect != dialect;
    if (!changed && this.ownership == ownership && _lease == lease) return;
    if (changed) {
      dismissHistory(notify: false);
      _contextRevision++;
      dismissCompletions(notify: false);
    }
    _contextKey = contextKey;
    this.cwd = cwd;
    _dialect = dialect;
    // A polling frame cannot unlock an in-flight or indeterminate transaction.
    if (this.ownership != ComposerOwnership.submitting &&
        this.ownership != ComposerOwnership.unknown) {
      this.ownership = ownership;
      _lease = lease;
    }
    notifyListeners();
  }

  void setActive(bool active) {
    if (_disposed) return;
    if (_active == active) return;
    _active = active;
    if (!active) {
      dismissHistory(notify: false);
      dismissCompletions();
    }
  }

  /// Providers may publish static candidates before optional IO completes.
  /// Every publication is checked against the entire current document identity.
  void publishCompletions(
    CompletionBatch result, {
    required CompletionCancellation cancellation,
  }) {
    if (_disposed ||
        !_active ||
        !identical(_cancellation, cancellation) ||
        cancellation.isCancelled ||
        !result.query.matches(snapshot)) {
      return;
    }
    _batch = result;
    _completionMenuOpen =
        _completionMenuOpen || _currentRequest?.showMenu == true;
    if (!items.any((item) => item.itemId == _selectedId)) _selectedId = null;
    _completionStatus = result.status == 'unsupported_context'
        ? 'unsupported_context'
        : '';
    notifyListeners();
  }

  void requestCompletions() =>
      _requestCompletions(fromTab: false, showMenu: true);

  /// Tab completes once or opens the final candidate list for selection.
  /// Ignore a second Tab while the first is still waiting on local IO.
  void completeOnTab() {
    if (historyOpen) {
      acceptHistory();
      return;
    }
    if (!_disposed &&
        _active &&
        editor.value.composing.isCollapsed &&
        editor.selection.isValid &&
        !editor.selection.isCollapsed) {
      _completionStatus = 'completion_selection';
      notifyListeners();
      return;
    }
    if (_disposed ||
        !_active ||
        !snapshot.canComplete ||
        ownership == ComposerOwnership.running ||
        ownership == ComposerOwnership.suspended ||
        ownership == ComposerOwnership.submitting ||
        _queued?.fromTab == true ||
        (loading && _currentRequest?.fromTab == true)) {
      return;
    }
    if (selectedIndex >= 0) {
      accept();
      return;
    }
    _requestCompletions(fromTab: true, showMenu: true);
  }

  void _requestCompletions({required bool fromTab, required bool showMenu}) {
    _timer?.cancel();
    final query = snapshot;
    if (_disposed ||
        !_active ||
        historyOpen ||
        !query.canComplete ||
        ownership == ComposerOwnership.running ||
        ownership == ComposerOwnership.suspended ||
        ownership == ComposerOwnership.submitting) {
      return;
    }
    _cancellation?.cancel();
    _completionStatus = '';
    _queued = (
      query: query,
      localSuggestions: _localSuggestions || fromTab,
      fromTab: fromTab,
      showMenu: showMenu,
    );
    if (!_inFlight) unawaited(_drain());
  }

  Future<void> _drain() async {
    _inFlight = true;
    while (!_disposed && _queued != null) {
      final request = _queued!;
      final query = request.query;
      _queued = null;
      final cancellation = CompletionCancellation();
      _cancellation = cancellation;
      _currentRequest = request;
      notifyListeners();
      try {
        final result = await provider(
          query,
          cancellation,
        ).timeout(const Duration(seconds: 2));
        if (!_disposed &&
            !cancellation.isCancelled &&
            query.matches(snapshot) &&
            result.query.matches(query)) {
          publishCompletions(result, cancellation: cancellation);
          // Incremental static results may still gain local alternatives. Only
          // the final result can justify accepting a unique match on Tab.
          if (request.fromTab &&
              !cancellation.isCancelled &&
              query.matches(snapshot)) {
            if (items.length == 1) {
              accept(items.single);
            } else if (items.isNotEmpty && selectedIndex < 0) {
              selectNext(1);
            } else if (items.isEmpty && result.status == 'ok') {
              _completionStatus = 'no_completions';
            }
          }
        }
      } on Object {
        if (!_disposed &&
            !cancellation.isCancelled &&
            query.matches(snapshot)) {
          _completionStatus = 'completion_unavailable';
          _batch = null;
        }
      } finally {
        cancellation.cancel();
        _currentRequest = null;
      }
    }
    _inFlight = false;
    if (!_disposed) notifyListeners();
  }

  void selectNext(int delta) {
    if (items.isEmpty) {
      requestCompletions();
      return;
    }
    final index = selectedIndex;
    _completionMenuOpen = true;
    _selectedId =
        items[(index < 0
                ? (delta > 0 ? 0 : items.length - 1)
                : (index + delta) % items.length)]
            .itemId;
    _selectionNavigationRevision++;
    notifyListeners();
  }

  void highlightCompletion(CompletionEdit item) {
    if (_batch?.query.matches(snapshot) == true &&
        (_selectedId != item.itemId || !_completionMenuOpen) &&
        items.contains(item)) {
      _selectedId = item.itemId;
      _completionMenuOpen = true;
      notifyListeners();
    }
  }

  bool accept([CompletionEdit? edit]) {
    final batch = _batch;
    final candidate =
        edit ?? (selectedIndex >= 0 ? items[selectedIndex] : null);
    if (batch == null ||
        candidate == null ||
        !batch.items.contains(candidate) ||
        !batch.query.matches(snapshot) ||
        !snapshot.canComplete) {
      return false;
    }
    final result = _completionValue(candidate);
    if (result == null) return false;
    editor.value = result;
    dismissCompletions();
    return true;
  }

  TextEditingValue? _completionValue(CompletionEdit candidate) {
    final text = editor.text;
    if (candidate.start < 0 ||
        candidate.end < candidate.start ||
        candidate.end > text.length ||
        !_boundary(text, candidate.start) ||
        !_boundary(text, candidate.end) ||
        candidate.newText.codeUnits.any(
          (c) => c < 32 || (c >= 127 && c <= 159),
        )) {
      return null;
    }
    final result = text.replaceRange(
      candidate.start,
      candidate.end,
      candidate.newText,
    );
    if (candidate.cursor < candidate.start ||
        candidate.cursor > candidate.start + candidate.newText.length ||
        !_boundary(result, candidate.cursor)) {
      return null;
    }
    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: candidate.cursor),
    );
  }

  static bool _boundary(String text, int offset) {
    var index = 0;
    for (final grapheme in text.characters) {
      if (index == offset) return true;
      index += grapheme.length;
    }
    return index == offset;
  }

  void dismissCompletions({bool notify = true}) {
    _timer?.cancel();
    _cancellation?.cancel();
    _queued = null;
    _batch = null;
    _selectedId = null;
    _completionMenuOpen = false;
    _completionStatus = '';
    if (notify && !_disposed) notifyListeners();
  }

  void insertNewline() {
    final value = editor.value;
    if (!value.composing.isCollapsed) return;
    final range = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    editor.value = TextEditingValue(
      text: value.text.replaceRange(range.start, range.end, '\n'),
      selection: TextSelection.collapsed(offset: range.start + 1),
    );
  }

  void undo() => _restore(_undo, _redo);
  void redo() => _restore(_redo, _undo);

  /// Clears only this local draft and remains undoable. A history filter is
  /// cancelled first so undo restores the draft, not a temporary search string.
  void clearDraft() {
    if (_disposed || !_active || !editor.value.composing.isCollapsed) return;
    dismissHistory(notify: false);
    dismissCompletions(notify: false);
    _completionStatus = '';
    editor.clear();
    notifyListeners();
  }

  void _restore(List<TextEditingValue> from, List<TextEditingValue> to) {
    if (from.isEmpty || !editor.value.composing.isCollapsed) return;
    to.add(editor.value);
    _restoring = true;
    editor.value = from.removeLast();
    _restoring = false;
  }

  Future<void> run() async {
    if (!canRun || _disposed) return;
    final submission = ComposerSubmission(
      id: '$sessionEpoch-${++_submissionSerial}',
      lease: _lease!,
      query: snapshot,
    );
    pendingSubmission = submission;
    _executionStatus = '';
    _completionStatus = '';
    ownership = ComposerOwnership.submitting;
    dismissCompletions();
    ComposerSubmissionOutcome outcome;
    try {
      outcome = await submit!(submission).timeout(const Duration(seconds: 3));
    } on Object {
      outcome = ComposerSubmissionOutcome.unknown;
    }
    if (_disposed) return;
    switch (outcome) {
      case ComposerSubmissionOutcome.accepted:
        pendingSubmission = null;
        updateHistory([submission.query.value.text, ..._history]);
        if (editor.text == submission.query.value.text &&
            _editorRevision == submission.query.editorRevision) {
          editor.clear();
          _undo.clear();
          _redo.clear();
        }
        ownership = ComposerOwnership.running;
      case ComposerSubmissionOutcome.rejected:
        pendingSubmission = null;
        ownership = ComposerOwnership.draft;
        _executionStatus = 'submission_rejected';
      case ComposerSubmissionOutcome.unknown:
        ownership = ComposerOwnership.unknown;
        _executionStatus = 'unknown_outcome';
    }
    _lease = null;
    notifyListeners();
  }

  /// Explicit recovery never resubmits; the user must inspect the terminal.
  void recoverDraft() {
    if (!canRecoverDraft) return;
    final pending = pendingSubmission!;
    if (editor.text.isEmpty) editor.value = pending.query.value;
    pendingSubmission = null;
    _lease = null;
    ownership = ComposerOwnership.draft;
    _executionStatus = '';
    _completionStatus = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _cancellation?.cancel();
    _queued = null;
    editor.removeListener(_edited);
    editor.dispose();
    super.dispose();
  }
}
