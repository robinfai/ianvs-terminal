import 'dart:async';
import 'package:app/features/ai/ai_connection_test.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/ai_settings_dialog.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'terminal_ai_test.dart' show MemoryAiStore;

void main() {
  testWidgets(
    'settings cancel unlocks fields and changed configuration invalidates success',
    (tester) async {
      final store = MemoryAiStore(
        const AiConfiguration.acp(
          agentCommand: '/node',
          agentArguments: [],
          model: 'test-model',
        ),
      );
      final settings = AiSettingsController(store);
      await settings.loaded;
      addTearDown(settings.dispose);
      final pending = <Completer<void>>[];
      final progress = <void Function(AiConnectionStage)>[];
      final tokens = <AiCancellation>[];
      await tester.binding.setSurfaceSize(const Size(1398, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(
            Brightness.light,
            platform: TargetPlatform.macOS,
          ),
          home: AiSettingsDialog(
            settings: settings,
            connectionTestRunner: (_, token, stage) {
              tokens.add(token);
              progress.add(stage);
              final result = Completer<void>();
              pending.add(result);
              return result.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.byKey(const Key('ai-test-connection'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ai-save-settings')))
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<TextField>(find.byKey(const Key('ai-model'))).enabled,
        isFalse,
      );
      await tester.ensureVisible(find.byKey(const Key('ai-cancel-test')));
      await tester.tap(find.byKey(const Key('ai-cancel-test')));
      await tester.pumpAndSettle();
      expect(tokens.first.isCancelled, isTrue);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ai-save-settings')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(button);
      await tester.pump();
      for (final stage in AiConnectionStage.values.take(5).skip(1)) {
        progress.last(stage);
      }
      pending.last.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-connection-ok')), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(const Key('ai-connection-ok')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('ai-model')),
        'changed-model',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-connection-ok')), findsNothing);
      expect(find.text('Configuration changed. Test again.'), findsOneWidget);
      expect(store.value!.model, 'test-model');
      pending.first.complete();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
