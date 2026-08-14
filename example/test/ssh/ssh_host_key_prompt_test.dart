import 'dart:async';

import 'package:app/features/ssh/ssh_auth_prompt.dart';
import 'package:app/features/terminal/terminal.dart' as terminal;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('unknown host shows a verifiable fingerprint before trust', (
    tester,
  ) async {
    final presenter = SshHostKeyPromptPresenter();
    final responses = <bool>[];
    final textInputMethods = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.textInput,
      (call) async {
        textInputMethods.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.textInput,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => unawaited(
                presenter.enqueue(context, _event(), ({
                  required event,
                  required accept,
                }) {
                  responses.add(accept);
                  return true;
                }),
              ),
              child: const Text('Connect'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(find.text('Trust this SSH host?'), findsOneWidget);
    expect(find.text('server.example.test:2222'), findsOneWidget);
    expect(find.text('ssh-ed25519'), findsOneWidget);
    expect(find.text('SHA256:verified-fingerprint'), findsOneWidget);
    expect(textInputMethods, contains('TextInput.hide'));

    await tester.tap(find.byKey(const Key('ssh-host-key-accept')));
    await tester.pumpAndSettle();
    expect(responses, <bool>[true]);
  });

  testWidgets('changed key warns and sends an explicit rejection', (
    tester,
  ) async {
    final presenter = SshHostKeyPromptPresenter();
    final responses = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => unawaited(
                presenter.enqueue(context, _event(reason: 'changed'), ({
                  required event,
                  required accept,
                }) {
                  responses.add(accept);
                  return true;
                }),
              ),
              child: const Text('Connect'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('SSH host key changed'), findsOneWidget);
    expect(find.text('Replace key and continue'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ssh-host-key-reject')));
    await tester.pumpAndSettle();
    expect(responses, <bool>[false]);
  });

  testWidgets('host-key dialog remains usable on a narrow scaled screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 560));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.8)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => SshHostKeyPromptDialog(event: _event()),
              ),
              child: const Text('Connect'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssh-host-key-accept')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

terminal.TerminalSessionSshHostKeyPromptEvent _event({
  String reason = 'unknown',
}) {
  return terminal.TerminalSessionSshHostKeyPromptEvent(
    'session-1',
    rawPayload: <String, Object?>{
      'challenge_id': 7,
      'host': 'server.example.test',
      'port': 2222,
      'reason': reason,
      'algorithm': 'ssh-ed25519',
      'fingerprint': 'SHA256:verified-fingerprint',
    },
  );
}
