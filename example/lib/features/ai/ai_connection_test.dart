import 'dart:async';

import 'package:flutter/foundation.dart';

import 'acp/agent_backend.dart';
import 'ai_models.dart';

export 'acp/agent_backend.dart' show AiConnectionStage;

enum AiConnectionTestStatus {
  idle,
  running,
  success,
  failed,
  timedOut,
  cancelled,
}

typedef AiConnectionTestRunner =
    Future<void> Function(
      AiConfiguration configuration,
      AiCancellation cancellation,
      ValueChanged<AiConnectionStage> onStage,
    );

/// A bounded settings check, independent of the long-lived task deadline.
/// Attempt identity prevents late callbacks from replacing a newer result.
class AiConnectionTestController extends ChangeNotifier {
  AiConnectionTestController({
    required this.runner,
    this.limit = const Duration(seconds: 60),
  });

  final AiConnectionTestRunner runner;
  final Duration limit;
  AiConnectionTestStatus status = AiConnectionTestStatus.idle;
  AiConnectionStage? stage;
  final completed = <AiConnectionStage, Duration>{};
  List<AiConnectionStage> stages = const [];
  Duration elapsed = Duration.zero;
  String? error;
  String model = '';
  AiBackendKind? backend;
  bool stale = false;
  final _clock = Stopwatch();
  Duration _stageStart = Duration.zero;
  Timer? _ticker;
  Timer? _deadline;
  AiCancellation? _cancellation;
  int _attempt = 0;
  bool _disposed = false;
  bool get running => status == AiConnectionTestStatus.running;
  bool get hasResult => status != AiConnectionTestStatus.idle;

  void start(AiConfiguration configuration) {
    if (_disposed || running) return;
    final attempt = ++_attempt;
    final cancellation = _cancellation = AiCancellation();
    status = AiConnectionTestStatus.running;
    stale = false;
    error = null;
    backend = configuration.backend;
    model = configuration.model;
    stages = backend == AiBackendKind.acp
        ? const [
            AiConnectionStage.launch,
            AiConnectionStage.handshake,
            AiConnectionStage.session,
            AiConnectionStage.model,
            AiConnectionStage.reply,
          ]
        : const [AiConnectionStage.request];
    stage = stages.first;
    completed.clear();
    elapsed = _stageStart = Duration.zero;
    _clock
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsed = _clock.elapsed;
      notifyListeners();
    });
    _deadline = Timer(limit, () {
      if (_current(attempt)) {
        _finish(AiConnectionTestStatus.timedOut, code: 'timeout');
        cancellation.cancel();
      }
    });
    notifyListeners();
    unawaited(_execute(configuration, cancellation, attempt));
  }

  bool _current(int attempt) => !_disposed && attempt == _attempt && running;

  Future<void> _execute(
    AiConfiguration configuration,
    AiCancellation cancellation,
    int attempt,
  ) async {
    try {
      await runner(configuration, cancellation, (next) {
        if (!_current(attempt) || next == stage || !stages.contains(next)) {
          return;
        }
        if (stages.indexOf(next) <= stages.indexOf(stage!)) return;
        elapsed = _clock.elapsed;
        completed[stage!] = elapsed - _stageStart;
        _stageStart = elapsed;
        stage = next;
        notifyListeners();
      });
      if (_current(attempt)) _finish(AiConnectionTestStatus.success);
    } on Object catch (failure) {
      if (!_current(attempt)) return;
      final code = failure is AiFailure ? failure.code : 'connection';
      _finish(
        {'timeout', 'acp_timeout'}.contains(code)
            ? AiConnectionTestStatus.timedOut
            : AiConnectionTestStatus.failed,
        code: _safeError(code),
      );
      cancellation.cancel();
    }
  }

  void _finish(AiConnectionTestStatus result, {String? code}) {
    _ticker?.cancel();
    _deadline?.cancel();
    _clock.stop();
    elapsed = _clock.elapsed;
    if (result == AiConnectionTestStatus.success && stage != null) {
      completed[stage!] = elapsed - _stageStart;
    }
    status = result;
    error = code;
    notifyListeners();
  }

  void cancel() {
    if (!running) return;
    _finish(AiConnectionTestStatus.cancelled);
    _cancellation?.cancel();
  }

  void invalidate() {
    if (!hasResult || stale) return;
    cancel();
    stale = true;
    notifyListeners();
  }

  /// Deliberately excludes credentials, paths, arguments and remote output.
  String diagnostics() => [
    'Trail connection test',
    'backend: ${backend?.name}',
    'result: ${status.name}',
    'configuration_changed: $stale',
    'elapsed_ms: ${elapsed.inMilliseconds}',
    'limit_ms: ${limit.inMilliseconds}',
    'stage: ${stage?.name}',
    if (error != null) 'error: $error',
    for (final item in stages)
      '${item.name}: ${completed.containsKey(item)
          ? '${completed[item]!.inMilliseconds} ms'
          : item == stage
          ? status.name
          : 'not_run'}',
  ].join('\n');

  @override
  void dispose() {
    _disposed = true;
    _attempt++;
    _ticker?.cancel();
    _deadline?.cancel();
    _cancellation?.cancel();
    _clock.stop();
    super.dispose();
  }
}

String _safeError(String code) =>
    const {
      'timeout',
      'acp_timeout',
      'configuration',
      'acp_authentication',
      'acp_capability',
      'acp_model',
      'acp_request',
      'acp_disconnected',
      'authentication',
      'response_format',
      'empty_response',
      'response_too_large',
      'quota',
      'forbidden',
      'http',
      'rate_limit',
      'network',
      'read_only',
      'connection',
    }.contains(code)
    ? code
    : 'connection';
