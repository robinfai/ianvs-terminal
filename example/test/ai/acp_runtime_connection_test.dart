import 'dart:convert';

import 'package:app/features/ai/acp/acp_runtime_connection.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_acp_runtime/ianvs_acp_runtime.dart';

class FakeNative implements IanvsAcpNativeApi {
  final queued = <Map<String, Object?>>[];
  final requests = <String>[];
  Map<String, Object?>? decision;
  int sequence = 0;

  void emit(String type, Map<String, Object?> body) => queued.add({
    'schemaVersion': IanvsRuntimeEvent.supportedSchemaVersion,
    'sequence': ++sequence,
    'type': type,
    ...body,
  });

  @override
  int get ffiVersion => IanvsRustRuntime.expectedFfiVersion;
  @override
  Object createRuntime() => Object();
  @override
  String? pollEvents(
    Object runtime, {
    required int maxEvents,
    required int maxBytes,
    int timeoutMs = 0,
  }) {
    if (queued.isEmpty) return null;
    final result = jsonEncode({
      'events': [...queued],
      'hasMore': false,
    });
    queued.clear();
    return result;
  }

  @override
  bool prompt(
    Object runtime, {
    required String requestId,
    required String sessionId,
    required String text,
    List<Map<String, Object?>> attachments = const [],
  }) {
    requests.add(requestId);
    return true;
  }

  @override
  bool cancel(
    Object runtime, {
    required String requestId,
    required String sessionId,
  }) => true;
  @override
  bool respondPermission(
    Object runtime, {
    required String requestId,
    required Map<String, Object?> decision,
  }) {
    this.decision = {'requestId': requestId, ...decision};
    return true;
  }

  @override
  bool dispose(Object runtime) => true;
  @override
  void freeRuntime(Object runtime) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeNative native;
  late AcpRuntimeConnection connection;
  late List<Map<String, Object?>> updates;
  setUp(() {
    native = FakeNative();
    updates = [];
    connection = AcpRuntimeConnection(
      runtime: IanvsRustRuntime(
        native: native,
        pollInterval: const Duration(milliseconds: 1),
      ),
      onUpdate: updates.add,
      permissionOption: (_) => 'once',
    );
  });
  tearDown(() => connection.dispose());

  void completed(String id, {String reason = 'end_turn'}) =>
      native.emit('render_update', {
        'update': {
          'sessionId': 'session',
          'kind': 'turn_completed',
          'metadata': {
            'requestId': id,
            'stopReason': reason,
            'resultMeta': {
              'quota': {
                'model_usage': [
                  {'model': 'expected'},
                ],
              },
            },
          },
        },
      });

  test(
    'correlates completion and preserves quota independently of visible text',
    () async {
      final result = connection.prompt('session', 'hello');
      completed('unrelated');
      native.emit('render_update', {
        'update': {
          'sessionId': 'session',
          'kind': 'assistant_text',
          'text': 'hello',
        },
      });
      completed(native.requests.single);
      expect(await result, {
        'stopReason': 'end_turn',
        '_meta': {
          'quota': {
            'model_usage': [
              {'model': 'expected'},
            ],
          },
        },
      });
      expect(updates.single['text'], 'hello');
    },
  );

  test('cancel notification cannot complete the original prompt', () async {
    var settled = false;
    final result = connection.prompt('session', 'hello').then((value) {
      settled = true;
      return value;
    });
    connection.cancel('session');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(settled, isFalse);
    completed(native.requests.single, reason: 'cancelled');
    expect((await result)['stopReason'], 'cancelled');
  });

  test(
    'disconnect rejects pending work without fabricating completion',
    () async {
      final result = connection.prompt('session', 'hello');
      final check = expectLater(result, throwsA(isA<AiFailure>()));
      native.emit('status_changed', {'status': 'failed'});
      await check;
      expect(connection.closed, isTrue);
      expect(updates, isEmpty);
    },
  );

  test(
    'permission reply uses control request identity and offered choice',
    () async {
      native.emit('permission_request', {
        'request': {
          'requestId': 'permission-17',
          'sessionId': 'session',
          'toolCallId': 'tool',
          'rawInput': {'server': 'trail_terminal'},
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(native.decision, {
        'requestId': 'permission-17',
        'decision': 'selected',
        'optionId': 'once',
      });
    },
  );
}
