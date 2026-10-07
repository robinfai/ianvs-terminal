import 'dart:io';

import 'package:app/features/ai/acp/acp_rpc.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:flutter_test/flutter_test.dart';

String _dart() {
  var directory = File(Platform.resolvedExecutable).parent;
  for (var depth = 0; depth < 8; depth++) {
    final candidate = File('${directory.path}/dart-sdk/bin/dart');
    if (candidate.existsSync()) return candidate.path;
    directory = directory.parent;
  }
  return Platform.resolvedExecutable;
}

void main() {
  group('ACP process transport', () {
    late AcpRpc rpc;
    setUp(() async {
      rpc = AcpRpc(
        await Process.start(_dart(), ['test/fixtures/acp_rpc_agent.dart']),
        (_, _) {},
      );
    });
    tearDown(() => rpc.dispose());

    test('correlates replies that arrive out of order', () async {
      final first = rpc.request('reverse', {'value': 'first'});
      final second = rpc.request('reverse', {'value': 'second'});
      expect((await first)['value'], 'first');
      expect((await second)['value'], 'second');
    });

    test('denies unknown permission and host write callbacks', () async {
      final result = await rpc.request('callbacks', {});
      final replies = result['callbacks']! as List;
      expect((replies[0] as Map)['result'], {
        'outcome': {'outcome': 'cancelled'},
      });
      for (final reply in replies.skip(1)) {
        expect(((reply as Map)['error'] as Map)['code'], -32601);
      }
    });

    for (final method in ['malformed', 'invalid_result', 'disconnect']) {
      test('$method settles pending requests as disconnected', () async {
        await expectLater(
          rpc.request(method, {}, timeout: const Duration(seconds: 1)),
          throwsA(
            isA<AiFailure>().having((e) => e.code, 'code', 'acp_disconnected'),
          ),
        );
        expect(rpc.closed, isTrue);
      });
    }

    test('a timed-out request does not prevent later requests', () async {
      await expectLater(
        rpc.request('timeout', {}, timeout: const Duration(milliseconds: 50)),
        throwsA(isA<AiFailure>().having((e) => e.code, 'code', 'acp_timeout')),
      );
      expect(await rpc.request('ping', {}), isEmpty);
    });
  });
}
