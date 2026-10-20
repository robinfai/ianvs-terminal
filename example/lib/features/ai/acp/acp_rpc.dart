import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../ai_models.dart';

/// ACP v1 newline-delimited JSON-RPC. stdout is protocol, never a shell.
class AcpRpc {
  AcpRpc(this.process, this.onNotification, {this.permissionOption}) {
    _subscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_receive, onError: (_) => _fail(), onDone: _fail);
    _stderr = process.stderr.listen((_) {});
    unawaited(process.stdin.done.catchError((Object _) => _fail()));
    unawaited(process.exitCode.then((_) => _fail()));
  }

  final Process process;
  final void Function(String, Map<String, Object?>) onNotification;
  final String? Function(Map<String, Object?>)? permissionOption;
  late final StreamSubscription<String> _subscription;
  late final StreamSubscription<List<int>> _stderr;
  final _pending = <int, Completer<Map<String, Object?>>>{};
  int _serial = 0;
  bool closed = false;

  void _send(Map<String, Object?> message) {
    if (closed) throw const AiFailure('acp_disconnected');
    process.stdin.writeln(jsonEncode({'jsonrpc': '2.0', ...message}));
  }

  void notify(String method, Map<String, Object?> params) =>
      _send({'method': method, 'params': params});

  Future<Map<String, Object?>> request(
    String method,
    Map<String, Object?> params, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final id = ++_serial;
    final completion = Completer<Map<String, Object?>>();
    _pending[id] = completion;
    try {
      _send({'id': id, 'method': method, 'params': params});
      return await completion.future.timeout(
        timeout,
        onTimeout: () => throw const AiFailure('acp_timeout'),
      );
    } finally {
      _pending.remove(id);
    }
  }

  void _receive(String line) {
    try {
      if (line.length > 4 * 1024 * 1024) throw const FormatException();
      final message = (jsonDecode(line) as Map).cast<String, Object?>();
      final id = message['id'];
      final method = message['method'];
      if (method is String) {
        final params = (message['params'] as Map? ?? {})
            .cast<String, Object?>();
        if (id != null) {
          // Agent permission events cannot authorize host input.
          if (method == 'session/request_permission') {
            final option = permissionOption?.call(params);
            _send({
              'id': id,
              'result': {
                'outcome': option == null
                    ? {'outcome': 'cancelled'}
                    : {'outcome': 'selected', 'optionId': option},
              },
            });
          } else {
            _send({
              'id': id,
              'error': {
                'code': -32601,
                'message': 'Client capability unavailable',
              },
            });
          }
        } else {
          onNotification(method, params);
        }
        return;
      }
      final completion = _pending[id];
      if (completion == null) return;
      if (message['error'] case final Map<Object?, Object?> error) {
        completion.completeError(
          AiFailure(
            error['code'] == -32000 ? 'acp_authentication' : 'acp_request',
          ),
        );
      } else {
        completion.complete(
          (message['result'] as Map? ?? {}).cast<String, Object?>(),
        );
      }
      _pending.remove(id);
    } on Object {
      _fail();
    }
  }

  void _fail() {
    closed = true;
    for (final item in _pending.values) {
      if (!item.isCompleted) {
        item.completeError(const AiFailure('acp_disconnected'));
      }
    }
    _pending.clear();
  }

  Future<void> dispose() async {
    _fail();
    // The official adapter closes its owned app-server when stdin closes.
    try {
      await process.stdin.close();
    } on Object {
      /* Already disconnected. */
    }
    try {
      await process.exitCode.timeout(const Duration(seconds: 4));
    } on TimeoutException {
      process.kill();
    }
    await _subscription.cancel();
    await _stderr.cancel();
  }
}
