import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'ai_api_client.dart';
import 'ai_models.dart';
import 'ai_settings.dart';

abstract interface class AiTerminalPort {
  Future<AiTerminalContext> readContext();
  Future<Map<String, Object?>> execute(
    AiAction action,
    AiTerminalContext expected,
    AiCancellation cancellation,
  );
  Stream<void> get userInput;
  void dispose();
}

enum AiPhase { idle, thinking, awaitingApproval, executing, failed }

class AiTranscriptEntry {
  const AiTranscriptEntry(this.role, this.text);
  final String role;
  final String text;
}

/// One conversation per PTY. Only [approve] can invoke a writing tool.
/// Inference cancellation, manual input and session guards revoke old proposals.
class TerminalAiController extends ChangeNotifier {
  TerminalAiController({
    required this.settings,
    required this.terminal,
    AiApi? api,
  }) : api = api ?? const AiApiClient() {
    _inputSubscription = terminal.userInput.listen((_) => takeOver());
    settings.addListener(_configurationChanged);
  }
  final AiSettingsController settings;
  final AiTerminalPort terminal;
  final AiApi api;
  late final StreamSubscription<void> _inputSubscription;
  final _messages = <Map<String, Object?>>[];
  final _transcript = <AiTranscriptEntry>[];
  List<AiTranscriptEntry> get transcript => List.unmodifiable(_transcript);
  AiPhase phase = AiPhase.idle;
  AiAction? pending;
  AiAction? _executingAction;
  AiTerminalContext? context;
  String? error;
  bool takenOver = false;
  bool _disposed = false;
  AiCancellation? _cancellation;
  int _steps = 0;
  bool get busy => phase == AiPhase.thinking || phase == AiPhase.executing;
  bool get canApprove => pending != null && phase == AiPhase.awaitingApproval;

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _configurationChanged() {
    // A proposal produced by a previous endpoint must not outlive that config.
    if (busy || pending != null) takeOver();
    _emit();
  }

  Future<void> refreshContext() async {
    try {
      final fresh = await terminal.readContext();
      if (!_disposed) context = fresh;
    } on Object catch (_) {
      if (!_disposed) error = 'session_unavailable';
    }
    _emit();
  }

  Future<void> ask(String input, {AiBlockContext? block}) async {
    final prompt = input.trim();
    if (_disposed || busy || prompt.isEmpty) return;
    if (prompt.length > 16000) {
      error = 'prompt_too_large';
      _emit();
      return;
    }
    await settings.loaded;
    if (_disposed) return;
    if (settings.configuration == null) {
      error = 'configuration';
      _emit();
      return;
    }
    _resolvePending('Superseded by a new user request. No input was sent.');
    _cancellation?.cancel();
    final cancellation = _cancellation = AiCancellation();
    takenOver = false;
    phase = AiPhase.thinking;
    error = null;
    _steps = 0;
    _emit();
    try {
      context = await terminal.readContext();
      cancellation.check();
      // Drop complete old turns, never a tool call without its result.
      if (_messages.length > 64 || jsonEncode(_messages).length > 192000) {
        _messages.clear();
      }
      _messages.add({
        'role': 'user',
        'content': jsonEncode({
          'request': prompt.startsWith('? ') ? prompt.substring(2) : prompt,
          'terminal_context': context!.toJson(),
          if (block != null) 'selected_block': block.toJson(),
        }),
      });
      _transcript.add(AiTranscriptEntry('user', prompt));
      if (_transcript.length > 100) {
        _transcript.removeRange(0, _transcript.length - 100);
      }
      await _infer(cancellation);
    } on Object catch (failure) {
      _fail(failure, cancellation);
    }
  }

  Future<void> correctLastCommand() async {
    await refreshContext();
    final block = context?.lastBlock;
    if (block == null || block.exitCode == null || block.exitCode == 0) {
      error = 'no_failed_command';
      _emit();
      return;
    }
    await ask(
      'Explain why this command failed and propose a corrected command. '
      '请解释这条命令失败的原因，并给出修正后的命令。',
      block: block,
    );
  }

  Future<void> _infer(AiCancellation cancellation) async {
    while (true) {
      cancellation.check();
      if (++_steps > 24) throw const AiFailure('step_limit');
      phase = AiPhase.thinking;
      _emit();
      final configuration = settings.configuration;
      if (configuration == null) throw const AiFailure('configuration');
      final reply = await api.complete(configuration, [
        {'role': 'system', 'content': aiSystemPrompt},
        ..._messages,
      ], cancellation);
      cancellation.check();
      _messages.add(reply.toMessage());
      if (reply.text.trim().isNotEmpty) {
        _transcript.add(AiTranscriptEntry('assistant', reply.text));
      }
      final action = reply.action;
      if (action == null) {
        phase = AiPhase.idle;
        _emit();
        return;
      }
      if (action.kind == AiActionKind.readScreen) {
        pending = action;
        await Future<void>.delayed(const Duration(milliseconds: 200));
        cancellation.check();
        context = await terminal.readContext();
        cancellation.check();
        _messages.add(_toolResult(action, context!.toJson()));
        pending = null;
        continue;
      }
      // Bind approval to the context that actually informed inference. Reading
      // a fresh guard here could bless a command intended for a previous SSH hop.
      pending = action;
      phase = AiPhase.awaitingApproval;
      _emit();
      return;
    }
  }

  Future<void> approve() async {
    final action = pending;
    final expected = context;
    final cancellation = _cancellation;
    if (!canApprove ||
        action == null ||
        expected == null ||
        cancellation == null) {
      return;
    }
    pending = null;
    _executingAction = action;
    phase = AiPhase.executing;
    error = null;
    _emit();
    var resultRecorded = false;
    try {
      cancellation.check();
      final result = await terminal.execute(action, expected, cancellation);
      if (!identical(_executingAction, action)) return;
      _executingAction = null;
      // Preserve protocol history even if takeover happens during observation.
      _messages.add(_toolResult(action, result));
      resultRecorded = true;
      cancellation.check();
      _transcript.add(AiTranscriptEntry('tool', action.preview));
      context = await terminal.readContext();
      cancellation.check();
      await _infer(cancellation);
    } on Object catch (failure) {
      if (!resultRecorded && identical(_executingAction, action)) {
        _executingAction = null;
        _messages.add(
          _toolResult(action, {
            'error': failure is AiFailure ? failure.code : 'execution',
            'instruction':
                'Do not retry automatically. Input may have already been sent.',
          }),
        );
      }
      _fail(failure, cancellation);
    }
  }

  Map<String, Object?> _toolResult(
    AiAction action,
    Map<String, Object?> result,
  ) => {
    'role': 'tool',
    'tool_call_id': action.id,
    'content': jsonEncode(result),
  };

  void _resolvePending(String reason) {
    if (pending case final AiAction action) {
      _messages.add(_toolResult(action, {'cancelled': true, 'reason': reason}));
      pending = null;
    }
  }

  void reject() {
    if (!canApprove) return;
    _resolvePending('The user declined this action. No input was sent.');
    phase = AiPhase.idle;
    _emit();
  }

  void takeOver() {
    if (_disposed || (!busy && pending == null)) return;
    _cancellation?.cancel();
    _resolvePending('The user took over. Stop sending terminal input.');
    if (_executingAction case final AiAction action) {
      _messages.add(
        _toolResult(action, {
          'interrupted': true,
          'instruction':
              'Input may already have been sent. Inspect the current screen before continuing.',
        }),
      );
      _executingAction = null;
    }
    phase = AiPhase.idle;
    takenOver = true;
    error = null;
    _emit();
  }

  void _fail(Object failure, AiCancellation cancellation) {
    if (_disposed ||
        cancellation != _cancellation ||
        cancellation.isCancelled) {
      return;
    }
    error = failure is AiFailure ? failure.code : 'execution';
    _resolvePending('Observation failed. No additional input was sent.');
    phase = AiPhase.failed;
    _emit();
  }

  void clear() {
    takeOver();
    _messages.clear();
    _transcript.clear();
    error = null;
    takenOver = false;
    _emit();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancellation?.cancel();
    unawaited(_inputSubscription.cancel());
    settings.removeListener(_configurationChanged);
    terminal.dispose();
    super.dispose();
  }
}
