import 'dart:async';

import 'package:app/features/ai/ai_api_client.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' show InputIntentChoice;

import '../helpers/pump_app.dart';
import 'terminal_ai_test.dart' show FakeTerminal, MemoryAiStore, commandReply;

class ControlledStreamingApi implements AiStreamingApi {
  final updates = <void Function(AiResponseUpdate)>[];
  final replies = <Completer<AiReply>>[];
  @override
  Future<AiReply> completeStreaming(
    AiConfiguration configuration,
    List<Map<String, Object?>> messages,
    AiCancellation cancellation,
    void Function(AiResponseUpdate) onUpdate,
  ) {
    updates.add(onUpdate);
    final reply = Completer<AiReply>();
    replies.add(reply);
    return reply.future; // Intentionally ignores cancellation to test the host.
  }

  @override
  Future<AiReply> complete(
    AiConfiguration configuration,
    List<Map<String, Object?>> messages,
    AiCancellation cancellation,
  ) => throw StateError('Expected real streaming entry point');
}

void main() {
  late AiSettingsController settings;
  late FakeTerminal terminal;
  late ControlledStreamingApi api;
  late TerminalAiController controller;
  setUp(() async {
    settings = AiSettingsController(MemoryAiStore());
    await settings.loaded;
    terminal = FakeTerminal();
    api = ControlledStreamingApi();
    controller = TerminalAiController(
      settings: settings,
      terminal: terminal,
      api: api,
    );
  });
  tearDown(() {
    controller.dispose();
    settings.dispose();
  });

  test(
    'cancelled deltas and completed tools cannot enter another task',
    () async {
      final old = controller.ask('first');
      await Future<void>.delayed(Duration.zero);
      api.updates[0](
        const AiResponseUpdate(AiResponseStage.generating, textDelta: 'old'),
      );
      controller.takeOver();
      expect(controller.generationCancelled, true);
      controller.newTask();
      final current = controller.ask('second');
      await Future<void>.delayed(Duration.zero);
      api.updates[1](
        const AiResponseUpdate(AiResponseStage.waitingForFirstToken),
      );
      api.updates[0](
        const AiResponseUpdate(AiResponseStage.generating, textDelta: 'late'),
      );
      api.replies[0].complete(commandReply('touch must-not-run'));
      await old;
      expect(controller.phase, AiPhase.waitingForFirstToken);
      expect(controller.transcript.map((e) => e.text), ['second']);
      expect(controller.pending, isNull);
      api.updates[1](
        const AiResponseUpdate(AiResponseStage.generating, textDelta: 'new'),
      );
      api.replies[1].complete(const AiReply(text: 'new'));
      await current;
      expect(controller.transcript.map((e) => e.text), ['second', 'new']);
      expect(controller.phase, AiPhase.idle);
      expect(terminal.writes, isEmpty);
    },
  );

  test(
    'manual command clears cancelled status and rejects the old reply',
    () async {
      final old = controller.ask('explain');
      await Future<void>.delayed(Duration.zero);
      controller.takeOver();
      expect(controller.generationCancelled, true);
      controller.chooseInputIntent(InputIntentChoice.command);
      await controller.runUserCommand('pwd');
      expect(controller.generationCancelled, false);
      expect(terminal.writes.single.command, 'pwd');
      api.updates.single(
        const AiResponseUpdate(AiResponseStage.generating, textDelta: 'late'),
      );
      api.replies.single.complete(commandReply('touch must-not-run'));
      await old;
      expect(controller.phase, AiPhase.idle);
      expect(controller.pending, isNull);
      expect(controller.transcript.any((entry) => entry.text == 'late'), false);
      expect(terminal.writes, hasLength(1));
    },
  );

  for (final reduced in [false, true]) {
    testWidgets(
      'phone renders request phases and partial text; reduced=$reduced',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.reset);
        await tester.pumpApp(
          MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 844),
              disableAnimations: reduced,
            ),
            child: TerminalAiWorkspace(
              controller: controller,
              onClose: () {},
              compactMobile: true,
            ),
          ),
          platform: TargetPlatform.iOS,
        );
        late Future<void> turn;
        await tester.runAsync(() async {
          turn = controller.ask('Explain');
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pump();
        await tester.pump();
        expect(controller.phase, AiPhase.connecting);
        expect(find.text('Connecting to model…'), findsOneWidget);
        api.updates[0](
          const AiResponseUpdate(AiResponseStage.waitingForFirstToken),
        );
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('Waiting for first token…'), findsOneWidget);
        api.updates[0](
          const AiResponseUpdate(
            AiResponseStage.generating,
            textDelta: 'Visible first chunk',
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('Generating…'), findsOneWidget);
        expect(controller.transcript.last.text, 'Visible first chunk');
        expect(find.byKey(const Key('ai-request-generating')), findsOneWidget);
        expect(
          find.byType(CircularProgressIndicator),
          reduced ? findsNothing : findsOneWidget,
        );
        controller.takeOver();
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          find.text('Generation cancelled · command is not interrupted'),
          findsOneWidget,
        );
        api.updates[0](
          const AiResponseUpdate(AiResponseStage.generating, textDelta: 'late'),
        );
        await tester.runAsync(() async {
          api.replies[0].complete(const AiReply(text: 'late complete'));
          await turn;
        });
        expect(controller.transcript.last.text, 'Visible first chunk');
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  }
}
