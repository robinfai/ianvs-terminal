import 'dart:async';

import 'package:app/features/ssh/ssh_auth_prompt.dart';
import 'package:app/features/terminal/terminal.dart' as terminal;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('serializes multiple keyboard-interactive OTP rounds', (
    tester,
  ) async {
    final presenter = SshAuthenticationPromptPresenter();
    final submitted = <({int challengeId, List<String> responses})>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () {
                unawaited(
                  presenter.enqueue(
                    context,
                    _event(
                      challengeId: 1,
                      name: 'Password verification',
                      prompt: 'Password:',
                    ),
                    ({required event, required responses, required cancel}) {
                      submitted.add((
                        challengeId: event.challengeId!,
                        responses: responses,
                      ));
                      return true;
                    },
                  ),
                );
                unawaited(
                  presenter.enqueue(
                    context,
                    _event(
                      challengeId: 2,
                      name: 'One-time password',
                      prompt: 'OTP code:',
                    ),
                    ({required event, required responses, required cancel}) {
                      submitted.add((
                        challengeId: event.challengeId!,
                        responses: responses,
                      ));
                      return true;
                    },
                  ),
                );
              },
              child: const Text('Authenticate'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Authenticate'));
    await tester.pumpAndSettle();
    expect(find.text('Password verification'), findsOneWidget);
    expect(find.text('Password:'), findsOneWidget);
    expect(find.text('Your response is hidden.'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('ssh-auth-dialog-content'))).width,
      greaterThanOrEqualTo(420),
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('ssh-auth-response-0')))
          .obscureText,
      isTrue,
    );

    await tester.enterText(
      find.byKey(const Key('ssh-auth-response-0')),
      'first-secret',
    );
    await tester.tap(find.byKey(const Key('ssh-auth-submit')));
    await tester.pumpAndSettle();
    expect(find.text('One-time password'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('ssh-auth-response-0')),
      '654321',
    );
    await tester.tap(find.byKey(const Key('ssh-auth-submit')));
    await tester.pumpAndSettle();

    expect(submitted.map((entry) => entry.challengeId), [1, 2]);
    expect(submitted[0].responses, ['first-secret']);
    expect(submitted[1].responses, ['654321']);
    expect(find.byKey(const Key('ssh-auth-prompt-dialog')), findsNothing);
  });

  testWidgets('session cancellation dismisses active and queued challenges', (
    tester,
  ) async {
    final presenter = SshAuthenticationPromptPresenter();
    var responseCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () {
                for (var challengeId = 1; challengeId <= 2; challengeId += 1) {
                  unawaited(
                    presenter.enqueue(
                      context,
                      _event(
                        challengeId: challengeId,
                        name: 'Challenge $challengeId',
                        prompt: 'Response:',
                      ),
                      ({required event, required responses, required cancel}) {
                        responseCount += 1;
                        return true;
                      },
                    ),
                  );
                }
              },
              child: const Text('Authenticate'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Authenticate'));
    await tester.pumpAndSettle();
    expect(find.text('Challenge 1'), findsOneWidget);

    presenter.cancelSession('session-1');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssh-auth-prompt-dialog')), findsNothing);
    expect(find.text('Challenge 2'), findsNothing);
    expect(responseCount, 0);
  });

  testWidgets('auth dialog fits narrow windows at high text scaling', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 560));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showDialog<List<String>>(
                context: context,
                builder: (_) => SshAuthenticationPromptDialog(
                  event: _event(
                    challengeId: 1,
                    name: 'Two-factor authentication challenge',
                    prompt: 'One-time password from authenticator:',
                  ),
                ),
              ),
              child: const Text('Show dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show dialog'));
    await tester.pumpAndSettle();

    final dialogRect = tester.getRect(
      find.byKey(const Key('ssh-auth-prompt-dialog')),
    );
    expect(dialogRect.left, greaterThanOrEqualTo(0));
    expect(dialogRect.right, lessThanOrEqualTo(320));
    expect(find.byKey(const Key('ssh-auth-submit')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

terminal.TerminalSessionSshAuthPromptEvent _event({
  required int challengeId,
  required String name,
  required String prompt,
}) {
  return terminal.TerminalSessionSshAuthPromptEvent(
    'session-1',
    rawPayload: <String, Object?>{
      'challenge_id': challengeId,
      'host': 'otp.example.test',
      'user': 'ianvs',
      'name': name,
      'instructions': 'Complete every challenge from the SSH server.',
      'prompts': <Object?>[
        <String, Object?>{'prompt': prompt, 'echo': false},
      ],
    },
  );
}
