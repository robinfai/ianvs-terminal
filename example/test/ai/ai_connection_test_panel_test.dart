import 'dart:async';
import 'package:app/features/ai/ai_connection_test.dart';
import 'package:app/features/ai/ai_connection_test_panel.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const configuration = AiConfiguration.acp(
  agentCommand: '/node',
  agentArguments: [],
  model: 'test-model',
);
void main() {
  Future<void> mount(
    WidgetTester tester,
    AiConnectionTestController c, {
    Brightness brightness = Brightness.light,
    double width = 640,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildIanvsTerminalTheme(
          brightness,
          platform: TargetPlatform.macOS,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: width,
                child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: AiConnectionTestPanel(
                    controller: c,
                    onTest: () => c.start(configuration),
                    saved: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('running cancellation and persistent success with disclosure', (
    tester,
  ) async {
    final pending = <Completer<void>>[];
    final progress = <void Function(AiConnectionStage)>[];
    final c = AiConnectionTestController(
      runner: (_, _, stage) {
        progress.add(stage);
        final next = Completer<void>();
        pending.add(next);
        return next.future;
      },
    );
    await mount(tester, c);
    await tester.tap(find.byKey(const Key('ai-test-connection')));
    await tester.pump();
    expect(find.byKey(const Key('ai-cancel-test')), findsOneWidget);
    expect(find.text('Create session'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ai-cancel-test')));
    await tester.pumpAndSettle();
    expect(find.text('Test cancelled'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ai-test-connection')));
    await tester.pump();
    for (final stage in c.stages.skip(1)) {
      progress.last(stage);
    }
    pending.last.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-connection-ok')), findsOneWidget);
    expect(find.text('Create session'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    expect(find.byKey(const Key('ai-connection-ok')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ai-test-details')));
    await tester.pumpAndSettle();
    expect(find.text('Create session'), findsOneWidget);
    c.invalidate();
    await tester.pumpAndSettle();
    expect(find.text('Configuration changed. Test again.'), findsOneWidget);
    expect(find.byKey(const Key('ai-connection-ok')), findsNothing);
    pending.first.complete();
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  for (final brightness in Brightness.values) {
    testWidgets('failure and copy at narrow scaled layout $brightness', (
      tester,
    ) async {
      final c = AiConnectionTestController(
        runner: (_, _, stage) async {
          stage(AiConnectionStage.handshake);
          throw const AiFailure('acp_authentication');
        },
      );
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      await mount(tester, c, brightness: brightness, width: 360, scale: 1.5);
      c.start(configuration);
      await tester.pumpAndSettle();
      expect(find.text('Connection failed'), findsOneWidget);
      expect(find.text('Verify protocol'), findsOneWidget);
      final copy = find.byKey(const Key('ai-copy-test-diagnostics'));
      await tester.ensureVisible(copy);
      await tester.tap(copy);
      await tester.pumpAndSettle();
      expect(clipboard, contains('acp_authentication'));
      expect(clipboard, isNot(contains('/node')));
      expect(find.text('Copied'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
  }
}
