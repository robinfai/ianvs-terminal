import 'package:app/features/ai/ai_approval.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/ai_settings_dialog.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';
import 'ai_approval_test.dart' show ControlledReviewer;
import 'terminal_ai_test.dart'
    show FakeApi, FakeTerminal, MemoryAiStore, commandReply;

void main() {
  testWidgets(
    'official settings expose approval and retain it when saving model',
    (tester) async {
      final store = MemoryAiStore(
        const AiConfiguration.official(
          model: 'selected',
          approvalMode: AiApprovalMode.manual,
        ),
      );
      final settings = AiSettingsController(store);
      addTearDown(settings.dispose);
      await settings.loaded;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 1200);
      addTearDown(tester.view.reset);
      await tester.pumpApp(
        AiSettingsDialog(settings: settings, onDone: (_) {}),
        platform: TargetPlatform.iOS,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-approval-mode')), findsOneWidget);
      expect(find.text('Confirm every command'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ai-approval-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Smart review').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('ai-save-official')));
      await tester.tap(find.byKey(const Key('ai-save-official')));
      await tester.pumpAndSettle();
      expect(store.value!.officialService, isTrue);
      expect(store.value!.approvalMode, AiApprovalMode.smart);
      expect(store.value!.model, 'selected');
      settings.updateGatewayConfiguration(
        const AiConfiguration(
          endpoint: 'https://gateway.example/v1/ai',
          apiKey: 'ephemeral',
          model: 'default',
        ),
      );
      expect(settings.configuration!.approvalMode, AiApprovalMode.smart);
      expect(settings.configuration!.apiKey, 'ephemeral');
      expect(store.value!.apiKey, isEmpty);
    },
  );
  test(
    'official smart review executes only the independently approved proposal',
    () async {
      final settings = AiSettingsController(
        MemoryAiStore(
          const AiConfiguration.official(approvalMode: AiApprovalMode.smart),
        ),
        gatewayConfiguration: const AiConfiguration(
          endpoint: 'https://gateway.example/v1/ai',
          apiKey: 'ephemeral',
          model: 'default',
        ),
      );
      await settings.loaded;
      final api = FakeApi()
        ..respond = (n) async =>
            n == 1 ? commandReply('ls -la') : const AiReply(text: 'Done');
      final terminal = FakeTerminal();
      final reviewer = ControlledReviewer()
        ..result.complete(
          const AiApprovalReview(automatic: true, reason: 'Scoped inspection.'),
        );
      final controller = TerminalAiController(
        settings: settings,
        api: api,
        terminal: terminal,
        reviewer: reviewer,
      );
      addTearDown(controller.dispose);
      addTearDown(settings.dispose);
      await controller.ask('List files');
      expect(reviewer.calls, 1);
      expect(terminal.writes, hasLength(1));
      expect(controller.phase, AiPhase.idle);
    },
  );
}
