import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/ffi/flutterm_core.dart';

import '../support/fake_core_bindings.dart';

void main() {
  test('terminal core client creates sessions and parses frame diffs', () {
    final bindings = FakeCoreBindings();
    final client = TerminalCoreClient(bindings);

    expect(client.ping(), 42);

    final sessionId = client.createSession(defaultTerminalProfile());
    final frame = client.takeFrameDiff(sessionId);

    expect(frame, isNotNull);
    expect(frame!.rows.single.text, 'flutterm ready');
    expect(client.pollEvents(sessionId).single.kind, 'started');

    client.closeSession(sessionId);
    expect(client.takeFrameDiff(sessionId), isNull);
  });
}
