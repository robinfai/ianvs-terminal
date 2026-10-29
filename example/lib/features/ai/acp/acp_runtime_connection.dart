import 'dart:async';

import 'package:ianvs_acp_runtime/ianvs_acp_runtime.dart';

import '../ai_models.dart';

/// Correlates host operations with the shared runtime's authoritative results.
/// Each connection owns its subscription and pending operations: stale native
/// events can never resolve a replacement connection's requests.
class AcpRuntimeConnection {
  AcpRuntimeConnection({
    required this.onUpdate,
    required this.permissionOption,
    IanvsRustRuntime? runtime,
  }) : runtime = runtime ?? IanvsRustRuntime() {
    _subscription = this.runtime.events.listen(
      _receive,
      onError: (Object error) => _fail(const AiFailure('acp_disconnected')),
      onDone: () => _fail(const AiFailure('acp_disconnected')),
    );
  }

  final IanvsRustRuntime runtime;
  final void Function(Map<String, Object?>) onUpdate;
  final String? Function(Map<String, Object?>) permissionOption;
  late final StreamSubscription<IanvsRuntimeEvent> _subscription;
  final _pending = <String, Completer<Map<String, Object?>>>{};
  int _serial = 0;
  bool closed = false;
  Future<void>? _disposing;

  Future<Map<String, Object?>> start(void Function() launch) =>
      _request('ready', (_) => launch());

  Future<Map<String, Object?>> session({
    required String cwd,
    String? sessionId,
  }) => _request('session', (id) {
    if (sessionId == null) {
      runtime.createSession(requestId: id, cwd: cwd);
    } else {
      runtime.restoreSession(
        requestId: id,
        sessionId: sessionId,
        cwd: cwd,
        replayHistory: false,
      );
    }
  });

  Future<Map<String, Object?>> configure({
    required String sessionId,
    required String configId,
    required String value,
  }) => _request('config', (id) {
    runtime.setConfigOption(
      requestId: id,
      sessionId: sessionId,
      configId: configId,
      value: {'type': 'value_id', 'value': value},
    );
  });

  Future<Map<String, Object?>> prompt(String sessionId, String text) =>
      _request('prompt', (id) {
        runtime.prompt(requestId: id, sessionId: sessionId, text: text);
      }, timeout: const Duration(hours: 2));

  void cancel(String sessionId) {
    if (!closed) {
      runtime.cancel(requestId: 'cancel-${++_serial}', sessionId: sessionId);
    }
  }

  Future<Map<String, Object?>> _request(
    String kind,
    void Function(String) send, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (closed) throw const AiFailure('acp_disconnected');
    final id = kind == 'ready' ? 'ready' : '$kind-${++_serial}';
    final completion = Completer<Map<String, Object?>>();
    _pending[id] = completion;
    try {
      send(id);
      return await completion.future.timeout(
        timeout,
        onTimeout: () => throw const AiFailure('acp_timeout'),
      );
    } finally {
      _pending.remove(id);
    }
  }

  void _complete(Object? id, Map<String, Object?> result) {
    final pending = _pending.remove(id);
    if (pending != null && !pending.isCompleted) pending.complete(result);
  }

  void _receive(IanvsRuntimeEvent event) {
    if (closed) return;
    switch (event.type) {
      case IanvsRuntimeEventType.statusChanged:
        if (event.status == 'ready') {
          _complete('ready', _map(event.data['capabilities']));
        } else if ({
          'failed',
          'stopped',
          'disposed',
          'recovering',
        }.contains(event.status)) {
          _fail(const AiFailure('acp_disconnected'));
        }
      case IanvsRuntimeEventType.runtimeError:
        final error = AiFailure(
          event.errorCode?.contains('auth') == true
              ? 'acp_authentication'
              : 'acp_request',
        );
        final pending = _pending.remove(event.requestId);
        if (pending != null && !pending.isCompleted) {
          pending.completeError(error);
        }
        if (!event.recoverable || event.requestId == null) _fail(error);
      case IanvsRuntimeEventType.sessionUpdate:
        final update = event.update!;
        if ({
          'session_created',
          'session_restored',
          'config_changed',
        }.contains(update['kind'])) {
          _complete(update['requestId'], {
            ..._map(update['payload']),
            'sessionId': update['sessionId'],
          });
        }
      case IanvsRuntimeEventType.renderUpdate:
        final update = event.renderUpdate!;
        final metadata = _map(update['metadata']);
        if (update['kind'] == 'turn_completed') {
          _complete(metadata['requestId'], {
            'stopReason': metadata['stopReason'],
            '_meta': metadata['resultMeta'],
          });
        } else {
          onUpdate(update);
        }
      case IanvsRuntimeEventType.permissionRequest:
        final request = event.permissionRequest!;
        final option = permissionOption(request);
        runtime.respondPermission(
          requestId: request['requestId']! as String,
          decision: option == null
              ? {'decision': 'cancelled'}
              : {'decision': 'selected', 'optionId': option},
        );
      default:
        break;
    }
  }

  void _fail(AiFailure error) {
    closed = true;
    for (final completion in _pending.values) {
      if (!completion.isCompleted) completion.completeError(error);
    }
    _pending.clear();
  }

  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _fail(const AiFailure('acp_disconnected'));
    await _subscription.cancel();
    await runtime.dispose();
  }
}

Map<String, Object?> _map(Object? value) =>
    (value as Map? ?? const {}).cast<String, Object?>();
