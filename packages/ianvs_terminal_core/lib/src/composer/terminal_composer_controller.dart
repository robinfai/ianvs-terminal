import 'dart:async';

import 'package:flutter/widgets.dart';

import 'completion_models.dart';

enum ComposerOwnership { draft, ready, submitting, running, suspended, unknown }

enum ComposerSubmissionOutcome { accepted, rejected, unknown }

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
  int _contextRevision = 0;
  int _submissionSerial = 0;
  int _policyRevision = 0;
  bool _localSuggestions = false;
  bool _restoring = false;
  bool _disposed = false;
  bool _active = true;
  Timer? _timer;
  CompletionCancellation? _cancellation;
  CompletionQuery? _queued;
  bool _inFlight = false;
  CompletionBatch? _batch;
  String? _selectedId;
  String? _lease;
  String _contextKey = '';
  String _dialect = 'generic';
  String status = '';
  String cwd = '';
  ComposerOwnership ownership = ComposerOwnership.draft;
  ComposerSubmission? pendingSubmission;

  List<CompletionEdit> get items => _batch?.items ?? const [];
  int get selectedIndex =>
      items.indexWhere((item) => item.itemId == _selectedId);
  bool get loading => _inFlight && _cancellation?.isCancelled == false;
  bool get canRun =>
      _active &&
      ownership == ComposerOwnership.ready &&
      _lease != null &&
      submit != null &&
      editor.text.trim().isNotEmpty &&
      editor.value.composing.isCollapsed;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  String? get readyLease =>
      ownership == ComposerOwnership.ready ? _lease : null;
  bool get localSuggestions => _localSuggestions;

  void toggleLocalSuggestions() {
    _localSuggestions = !_localSuggestions;
    _policyRevision++;
    dismissCompletions();
    if (_active && editor.text.isNotEmpty) requestCompletions();
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
      if (!_restoring && _previous.composing.isCollapsed) {
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
    dismissCompletions(notify: false);
    if (_active && snapshot.canComplete && next.text.isNotEmpty) {
      _timer = Timer(debounce, requestCompletions);
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
    if (!active) dismissCompletions();
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
    if (!items.any((item) => item.itemId == _selectedId)) _selectedId = null;
    status = result.status == 'unsupported_context'
        ? 'unsupported_context'
        : '';
    notifyListeners();
  }

  void requestCompletions() {
    _timer?.cancel();
    final query = snapshot;
    if (_disposed ||
        !_active ||
        !query.canComplete ||
        ownership == ComposerOwnership.running ||
        ownership == ComposerOwnership.suspended ||
        ownership == ComposerOwnership.submitting) {
      return;
    }
    _cancellation?.cancel();
    _queued = query;
    if (!_inFlight) unawaited(_drain());
  }

  Future<void> _drain() async {
    _inFlight = true;
    while (!_disposed && _queued != null) {
      final query = _queued!;
      _queued = null;
      final cancellation = CompletionCancellation();
      _cancellation = cancellation;
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
        }
      } on Object {
        if (!_disposed &&
            !cancellation.isCancelled &&
            query.matches(snapshot)) {
          status = 'completion_unavailable';
          _batch = null;
        }
      } finally {
        cancellation.cancel();
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
    _selectedId =
        items[(index < 0
                ? (delta > 0 ? 0 : items.length - 1)
                : (index + delta) % items.length)]
            .itemId;
    notifyListeners();
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
    final text = editor.text;
    if (candidate.start < 0 ||
        candidate.end < candidate.start ||
        candidate.end > text.length ||
        !_boundary(text, candidate.start) ||
        !_boundary(text, candidate.end) ||
        candidate.newText.codeUnits.any(
          (c) => c < 32 || (c >= 127 && c <= 159),
        )) {
      return false;
    }
    final result = text.replaceRange(
      candidate.start,
      candidate.end,
      candidate.newText,
    );
    if (candidate.cursor < candidate.start ||
        candidate.cursor > candidate.start + candidate.newText.length ||
        !_boundary(result, candidate.cursor)) {
      return false;
    }
    editor.value = TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: candidate.cursor),
    );
    dismissCompletions();
    return true;
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
        if (editor.text == submission.query.value.text &&
            _editorRevision == submission.query.editorRevision) {
          editor.clear();
          _undo.clear();
          _redo.clear();
        }
        ownership = ComposerOwnership.running;
        status = '';
      case ComposerSubmissionOutcome.rejected:
        ownership = ComposerOwnership.draft;
        status = 'submission_rejected';
      case ComposerSubmissionOutcome.unknown:
        ownership = ComposerOwnership.unknown;
        status = 'unknown_outcome';
    }
    _lease = null;
    notifyListeners();
  }

  /// Explicit recovery never resubmits; the user must inspect the terminal.
  void recoverDraft() {
    final pending = pendingSubmission;
    if (pending == null) return;
    if (editor.text.isEmpty) editor.value = pending.query.value;
    pendingSubmission = null;
    ownership = ComposerOwnership.draft;
    status = '';
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
